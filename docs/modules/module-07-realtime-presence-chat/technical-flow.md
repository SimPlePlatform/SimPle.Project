# Technical Flow - Module 07: Real-Time Presence, Lobby Updates & Chat

## Summary
Module 7 replaces three mocks at once: hard-coded `status: 'online'` presence dots, a static lobby-chat
placeholder, and a 2-second poll standing in for live lobby updates. All three now run over one authenticated
SignalR connection, backed by real, persisted, moderation-ready chat. The module is built around one hard
fact about SignalR that the whole design answers to: a connection's identity is decided once at handshake
and never automatically re-checked, so every subscribe, send, and delete re-reads current membership,
suspension, and block state rather than trusting who connected. It deliberately does not claim more than a
single backend instance can honestly support — presence and connection state live in memory, correct for
one process only — and it does not claim exactly-once delivery: a lost or duplicated hint costs one
redundant, safely re-authorized snapshot fetch, never a wrong one.

## Problem Solved
Before this module, `Sidebar`, `Topbar`, `SettingsPage`, `DashboardPage`, and `FriendsPage` all rendered a
literal `'online'` string for every user, regardless of whether that user was actually connected.
`ChatPanel.tsx` was a static mock with canned messages and a composer that sent nowhere. `LobbyPage.tsx`
(Module 6) only saw a teammate join, leave, or ready-up on its own 2-second poll or a manual refresh. Module
7 makes all three real: presence is composed live from actual SignalR connections and the existing
Module 2/3 visibility and block rules; lobby chat is a persisted aggregate with a 30-day retention window and
a moderation-hold seam left empty for Module 12; and lobby state changes push a thin, revision-carrying hint
that tells the client to re-fetch Module 6's existing authorized snapshot rather than pushing lobby state
itself over the wire.

## Architecture Overview
```
Browser
  |-- RealtimeConnectionProvider (SignalR client; gated on useAuth().status === 'authenticated';
  |     automatic reconnect 0s / 2s / 10s / 30s, explicit Retry after that)
  |     `-- /hubs/realtime  (RealtimeHub; HttpOnly access_token cookie; exact-origin allowlist)
  |           SubscribeLobby / UnsubscribeLobby / SendLobbyMessage / ReportActivity
  |-- ChatPanel.tsx (composer <textarea>, REST history + realtime reconcile, stable message-id keys)
  |     `-- GET /api/chat/lobbies/{lobbyId}/messages , DELETE /api/chat/messages/{messageId}
  |-- Sidebar / Topbar / SettingsPage / DashboardPage / FriendsPage / LobbyPage's SeatCard
  |     `-- usePresence(userId) -> PresenceChanged events (absent while unknown, never defaults to "online")
  `-- GameRoomPage.tsx match ChatPanel -> made visibly unavailable (NullMatchScopeAuthorizer, Module 8 seam)

RealtimeHub  --authorize-->  IRealtimeScopeAuthorizer
                               LobbyScopeAuthorizer  (Subscribe / Send / Delete; re-reads ILobbyRepository,
                               User.IsAccountSuspended(), IFriendRepository.IsBlockedInEitherDirectionAsync
                               on every call -- never a cached prior result)
                               NullMatchScopeAuthorizer -> Realtime.ScopeNotAvailable (Module 8 seam)
             --delivery-->   IRealtimeNotifier / RealtimeNotifier
                               (Clients.Users(recipientIds), block-filtered; never Clients.Group(...) for chat)
             --presence-->   IPresenceRegistry (in-memory only; Max precedence; 5-connection cap per user;
                               5-min Away / 10s-debounced Offline; 1-per-60s activity throttle)

ChatController (REST)  -->  ChatService (single send/delete/history authorization path, shared with the hub)
                               |-- ChatBodyNormalizer   (NFC, CRLF/CR -> LF, 1-1000 Unicode scalars)
                               |-- ChatProfanityFilter  (versioned deny-list; message not stored on a hit)
                               |-- GetDeliverableRecipientsAsync / FilterBlockedSendersAsync (block-aware,
                               |     applied identically on the realtime send path and the REST history path)
                               `-- ChatRepository --> PostgreSQL
                                     chat_messages / chat_message_holds / outbox_handler_activations

LobbiesService (Module 6)  --additive LobbyReadinessChangedV1-->  OutboxMessage
OutboxDispatcherWorker  --eager ActivateAllHandlersAsync-->  LobbyRealtimeHandler
                               (per-handler watermark row; suppresses every event that predates the
                                handler's first activation; collapses repeated same-revision events into
                                one LobbyChanged; emits ResyncRequired on a detected gap)
ChatRetentionSweeper (batched, hold-aware, PostgreSQL row locking) --> chat_messages / chat_message_holds
```

## Backend Flow
`RealtimeHub` is the single entry point for presence, lobby delivery, and chat send/subscribe. On connect,
`OnConnectedAsync` acquires a connection-limit lease (5 per user) inside a `try`/`catch` that releases the
lease if anything later in the method faults — the fix for **M07-002**, a connection-leak finding from the
backend security review. `CloseOnAuthenticationExpiration = true` is set on the hub options so a token
expiring mid-connection closes the socket automatically; separately, logout, logout-all, revoke-session, and
delete-account each call `IRealtimeConnectionCloser` to proactively close every connection mapped to the
affected user or session, rather than waiting for token expiry. Every `SubscribeLobby`, `SendLobbyMessage`,
and the REST `DELETE` route funnel through `IRealtimeScopeAuthorizer`/`ChatService`, which re-read
`ILobbyRepository`, `User.IsAccountSuspended()`, and `IFriendRepository.IsBlockedInEitherDirectionAsync`
fresh on every call — the connection's identity is never trusted as still-valid just because it was valid
at handshake.

`ChatService` is deliberately the **only** place send/delete/history authorization logic lives; both
`RealtimeHub.SendLobbyMessage` and `ChatController`'s REST routes call into it rather than duplicating
checks, which is why fixing **M07-001** (unfiltered group broadcast let a blocked co-member see chat) and
later finding **M07-008** (the REST history route had no equivalent block filter) were both one-line changes
in `ChatService`/`ChatRepository`, not two divergent implementations to keep in sync. Presence is tracked
entirely in memory by `IPresenceRegistry`: each user's aggregate status is the `Max` of every connection's
individual precedence (`Offline=0 < Away=1 < Online=2 < InLobby=3 < Playing=4`), so one idle browser tab and
one active match tab for the same user correctly report `Playing`, not `Away`.

Lobby state changes reach connected clients through the existing Module 6 outbox, extended additively with a
new `LobbyReadinessChangedV1` message type — no migration was needed for this, since it reuses Module 6's
outbox table and existing idempotency uniqueness index. `LobbyRealtimeHandler` consumes these messages and
turns them into a thin `LobbyChanged { revision, changeType }` hint (never the lobby state itself) sent to
the lobby's subscriber group. A real bug was found and fixed here during the M07-B2 backend session: the
outbox dispatcher activated each handler's watermark **lazily**, on its first `HandleAsync` call, which
meant a handler that had never yet processed a message would treat its very first delivery as "since the
beginning of time" and could replay the lobby's entire historical event backlog. The fix adds
`ActivateAllHandlersAsync`, called eagerly at dispatcher startup, so every handler's watermark is captured
once, at boot, before any message is dispatched — not on first use. This fix touched
`OutboxDispatcherWorker.cs`, which sits outside Module 7's declared file-ownership boundary; it is recorded
as an explicit, flagged exception (see Design Tradeoffs, D3) rather than a silent scope creep.

Two more backend changes round out the module: `AuthService.LogoutAsync` was changed to revoke the caller's
full session family, not just the current session token, closing a real gap where a logged-out user's
already-open realtime connection would otherwise survive logout until natural token expiry (an approved
Module 1 behavior change, agreed in planning before implementation — see Design Tradeoffs, R4); and the dead
placeholder notifier interfaces plus the orphaned `DirectMessage` value of the `ChatScope` enum (never
persisted, never referenced by a live code path) were deleted, with a reference/search test asserting no
remaining dependency before removal.

## Frontend Flow
- Existing UI reused: `LobbyPage.tsx`'s chat placeholder (already gated behind
  `lobby.dependencyReadiness.chat` since Module 6), `Avatar`'s `status`/`showPresence` props, and
  `presenceColor()`/`presenceDotClass()` in `src/lib/utils.ts` — none of these needed new markup, only real
  data instead of literals.
- Frontend integration points: new `features/realtime/` (`RealtimeConnectionProvider.tsx`, `usePresence`
  hook), new `features/chat/` (`chatApi.ts`, `types.ts`), rewritten `components/lobby/ChatPanel.tsx`,
  `features/lobby/LobbyPage.tsx`'s `SeatCard` (previously never called `usePresence` at all — found and
  fixed during the M07-F1 frontend session), `features/room/GameRoomPage.tsx` (match chat made visibly
  unavailable, its mock send removed), `features/landing/LandingPage.tsx` (copy no longer promises direct
  messages), and removal of every hard-coded `status: 'online'` literal in `Sidebar.tsx`, `Topbar.tsx`,
  `SettingsPage.tsx`, `DashboardPage.tsx`, `FriendsPage.tsx`.
- Visual changes made: the chat composer changed from a single-line `<input>` to a visually compatible
  `<textarea>` — the one approved visual change, needed so Shift+Enter can insert a literal newline while
  Enter still sends (an IME composition event never triggers an accidental send).

## Database/Domain Model Changes
- Additive migration `20260717001316_AddChatAndRealtimeActivation`, verified against a real local
  PostgreSQL instance (not SQLite/in-memory), adding three new tables — no existing table is altered or
  dropped:
  - `chat_messages` — `Id`, `LobbyId`, `SenderId`, `Body`, `Deleted`, `ClientCommandId`, `CreatedAt`,
    `SchemaVersion`, with the unique index `ux_chat_messages_sender_command` on `(SenderId,
    ClientCommandId)` enforcing idempotent send at the database level, not just in application code.
  - `chat_message_holds` — ships empty this module; the schema exists so Module 12 can write a hold without
    Module 7 needing to change again, but nothing in Module 7 ever inserts into it.
  - `outbox_handler_activations` — `HandlerName` (primary key), `ActivatedAtUtc`,
    `WatermarkOccurredAtUtc`, `WatermarkEventId`, backing the eager-activation watermark fix described above.
- No presence or connection data is persisted anywhere; it is process-memory only by design, which is also
  the source of the module's single-instance boundary (see Design Tradeoffs, D5).

## API Contract
- Backend/API/Swagger alignment: the two REST routes are documented via `[SwaggerOperation]` on
  `ChatController.cs`, verified by the passing `Swagger_DescribesChatHistoryAndDeleteRoutes` test; hub
  methods are not representable in Swagger/OpenAPI and are documented directly in `api-reference.md` and the
  approved spec instead.
- Frontend/API integration alignment: `node scripts/check-contract-drift.mjs` reports **DRIFT=0** — 87
  backend routes, 72 unique frontend calls, 0 unresolved mismatches (an interim in-session check during the
  M07-B2 backend slice, before the frontend caller for chat history existed, had reported 71 unique frontend
  calls against the same 87 backend routes; the number moved to 72 once the frontend slice added that call,
  and has stayed there through the frontend and verification sessions).
- Full endpoint-by-endpoint detail, DTO shapes, and the error catalogue live in `api-reference.md`.

## Validation And Error Handling
Chat body validation is centralized in `ChatBodyNormalizer` (NFC normalization, CRLF/CR to LF, 1-1000
Unicode scalar values, other control characters rejected) so the hub path and the REST path can never
diverge on what counts as a valid message. A profanity match returns `Chat.ProfanityRejected` as an ordinary
validation error — the message is never persisted, and this is deliberately not treated as a security event,
since the deny-list is a moderation aid, not an access control (see Design Tradeoffs, D2 and the M07-004 Info
finding). `Chat.MessageExpired` (`409`) is returned if a delete or hold request targets a message that has
already aged past the retention window or is otherwise gone — an honest error rather than a silently wrong
success. `Chat.NotFound` never distinguishes "does not exist" from "exists but you cannot see it," matching
the same privacy-safe convention Module 6 already uses for lobbies. Rate-limit rejections
(`RateLimit.Exceeded`) always carry a `Retry-After`/`retryAfterUtc` so a well-behaved client can back off
correctly instead of hot-looping.

## Authorization And Security Decisions
The central decision this module makes is treating SignalR's cached-handshake-principal behavior as a real
threat rather than an implementation detail to work around later. Three independent mechanisms close it, and
the `--security=asvs-lite` review's own methodology was to verify none of the three alone would have been
sufficient: `CloseOnAuthenticationExpiration` only handles natural token expiry, not an active
revoke/suspend/logout, which is why proactive closure via `IRealtimeConnectionCloser` exists separately; and
even both of those together still leave a window between a membership/block change and the next natural
disconnect, which is why every subscribe/send/delete rechecks current state rather than relying on either
closure mechanism to eventually catch up. The review found and the team fixed two Medium findings
(**M07-001** unfiltered chat broadcast, **M07-008** the same gap on the REST history route) and two Low
findings (**M07-002** connection-lease leak, **M07-003** missing-`Origin` bypass), with zero unwaived
Critical/High findings across both the backend and post-frontend review phases. Three Info findings remain
open, non-blocking, and explicitly deferred rather than hidden: the intentionally simple profanity filter
(**M07-004**, Module 12's moderation pipeline is the real backstop), thinner-than-ideal positive
security-event logging (**M07-006**), and the out-of-scope `OutboxDispatcherWorker` fix that was
sanity-checked but not deep-reviewed (**M07-007**). Full finding-by-finding detail, including exact file/line
evidence and the verifying test for each, lives in
`SimPle.Project/docs/security/audits/module-07-realtime-presence-chat.md`, which this document does not
duplicate.

Separately from the security findings themselves, the module's **process** evidence has a gap worth stating
plainly here rather than only in the README: the formal ordered stage-checkpoint chain
(`docs/ai-workflow/evidence/checkpoints/module-07-realtime-presence-chat/index.json`) has only the
`planning` stage registered. The backend security-review stage ran on Sonnet 5 instead of the
manifest-routed Opus for that assurance-sensitive stage, and every later stage inherited the same
"cannot chain onto a missing prior index" condition as a result. The project owner explicitly **waived**
backfilling that chain for Module 7 — the security, frontend-security, and verification checkpoint files
themselves exist, are internally valid, and record real, passing evidence; only their ordered registration in
`index.json` is missing. `releaseEligible` stays **false** regardless of the waiver, pending Module 14's
CI/container/staging foundation. See `testing-report.md`'s Final Status for the complete framing.

## Realtime/Socket.IO Flow If Applicable
**Connection and reconnect.** The client connects with `withAutomaticReconnect([0, 2000, 10000, 30000])` —
an immediate retry, then 2s, 10s, 30s, after which the client falls back to a manual "Reconnect" affordance
rather than retrying forever silently. Each successful (re)connect receives a fresh `Connected { serverEpoch
}` event; because the epoch is generated once per server process (`Guid.NewGuid()` at hub construction), a
backend restart is always observably a new epoch to a reconnecting client, never something the client has to
guess at.

```
Connection state machine (client-observed):

  [Disconnected] --connect()--> [Connecting]
  [Connecting] --success--> [Connected: fresh epoch, snapshot fetch]
  [Connecting] --failure--> [Reconnecting: wait 0s]
  [Connected] --transport drop--> [Reconnecting: wait 0s]
  [Reconnecting: wait 0s]  --retry fails--> [Reconnecting: wait 2s]
  [Reconnecting: wait 2s]  --retry fails--> [Reconnecting: wait 10s]
  [Reconnecting: wait 10s] --retry fails--> [Reconnecting: wait 30s]
  [Reconnecting: wait 30s] --retry fails--> [Disconnected: manual "Reconnect" shown]
  [Reconnecting: *]        --retry succeeds--> [Connected: compare epoch]
       epoch unchanged  -> resume; re-subscribe each previously-subscribed lobby, compare revision
       epoch changed    -> full resync: re-subscribe, re-fetch every open lobby's authorized snapshot
```

**Presence precedence.** A user's displayed status is the `Max` over every one of their live connections'
individual states, ordinally `Offline=0 < Away=1 < Online=2 < InLobby=3 < Playing=4`. A connection moves to
`Away` after 5 minutes without a `ReportActivity` call or qualifying client interaction, and to effectively
`Offline` (from other users' point of view) 10 seconds after its last connection closes — a short debounce so
a page refresh or a momentary network blip does not flash a friend's dot to gray and back. `ReportActivity`
itself grants no authorization and is rate-limited to once per 60 seconds per connection; a forged or
excessive call can, at worst, keep a status pinned at `Online` a little longer than honest — never grant
access to anything.

**Delivery guarantee and resync.** The system is explicitly **at-least-once**, never exactly-once, and is
designed so that is safe: `LobbyChanged` is a thin hint carrying only a `revision` and `changeType`, never
lobby state itself, so a duplicate hint just triggers one redundant (fully re-authorized) re-fetch of Module
6's existing snapshot endpoint, and a **missed** hint is caught the moment the client's locally-tracked
revision falls behind what a later hint reports, or explicitly via `ResyncRequired` if the server-side
watermark detects a gap it cannot bridge (e.g. a slow consumer or a dispatcher restart mid-stream). Chat
messages use client-side deduplication keyed on the message id (present identically whether the message
arrived via `ChatMessageCreated` or via a REST history re-fetch after reconnect), so a message delivered
twice renders once.

**Retention/hold race.** The 30-day retention sweep and a future Module 12 moderation hold both touch the
same `chat_messages` rows, so the cleanup path uses a single atomic delete guarded by PostgreSQL row-level
locking (`FOR UPDATE SKIP LOCKED`) rather than a check-then-delete window that a concurrent hold-write could
race. `ChatRetentionHoldRaceTests`, run against a real Postgres instance (not an in-memory substitute),
exercises this directly.

## State Management If Applicable
`RealtimeConnectionProvider` (React context) owns the single SignalR connection for the whole authenticated
app shell, mounted once and torn down on logout/logout-all; `usePresence(userId)` subscribes to
`PresenceChanged` events scoped to the ids a given screen actually renders, defaulting to "unknown" (never
"online") until a real event arrives. `ChatPanel.tsx` keeps its own local reconciliation state: an initial
REST history page, then a live append/dedupe/delete-tombstone reducer fed by `ChatMessageCreated` /
`ChatMessageDeleted`, keyed by stable message id for React list rendering (fixing a real defect found in
development where array-index keys caused message flicker on reconnect-driven re-fetches).

## Edge Cases Handled
- A duplicate `SendLobbyMessage` retry (same `clientCommandId`) returns the original message rather than
  creating a second one, backed by a real database unique constraint.
- A blocked user's messages are excluded from both the realtime delivery path and the REST history path
  identically (M07-001 and M07-008 closed the same gap on both paths).
- A membership/suspension/block change takes effect on the **next** subscribe/send/delete call, not only on
  the next natural reconnect — closing the cached-principal gap described above.
- A lobby closing or expiring now correctly releases every stranded `LobbyMember` row (see the domain bug
  below), instead of permanently blocking those players from rejoining any lobby.
- A missing or duplicated `LobbyChanged` hint self-heals via revision comparison or an explicit
  `ResyncRequired`, never silently leaving a client's view stale.
- A too-frequent `ReportActivity` call is silently ignored rather than erroring, since it grants no
  authorization in the first place.
- **Domain bug found and fixed during live verification:** `Lobby.CloseInternal` and `Lobby.TryExpire` never
  released `LobbyMember.State`, so a member of a closed or expired lobby was permanently stuck in a joined
  state and could never rejoin any lobby again. Fixed with a new `Lobby.ReleaseAllJoinedMembers(nowUtc)`
  domain method, called from both close and expire paths. A follow-on bug in
  `LobbyRealtimeHandler`'s `LobbyClosed` case (referencing a nonexistent `JoinedMembers` property instead of
  `Members`) was found and fixed in the same pass.
- **Two accessibility defects found and fixed during live verification:** `LobbyPage.tsx` was missing a page
  `<h1>`, and `ChatPanel.tsx`'s placeholder text failed color-contrast — both caught by the shared axe
  accessibility fixture in the live-stack E2E run and fixed before the spec passed.

## Design Tradeoffs
- **R1 — Greenfield deletion, not migration, for dead placeholder code.** The pre-existing placeholder
  notifier interfaces and the orphaned `DirectMessage` enum value had no live callers and nothing persisted
  under them, so they were deleted outright rather than deprecated in place, with a reference/search test
  proving no remaining dependency before removal.
- **R2 — `ChatScope` keeps only `Lobby` and `Match`.** Removing `DirectMessage` now, while the surface is
  still small, avoids carrying a value with no real implementation into later modules where more code would
  come to depend on its absence being handled somewhere.
- **R3 — `LobbyReadinessChangedV1` added additively to Module 6's existing outbox**, rather than a new
  outbox table or a schema change to Module 6's. No migration was needed for this change; it reuses Module
  6's existing idempotency uniqueness index as-is.
- **R4 — `AuthService.LogoutAsync` now revokes the full session family**, an approved Module 1 behavior
  change agreed during planning: a live realtime connection surviving a user's own logout until natural
  token expiry is a real, user-visible gap that a closed *new* connection alone cannot fix, since the *old*
  connection was never told to close.
- **D1 — The cached-principal defense is three independent, jointly-necessary mechanisms, not one.**
  `CloseOnAuthenticationExpiration`, proactive closure on logout/revoke/suspend, and a per-method recheck
  each cover a different gap the others leave open; the security review's methodology explicitly verified
  each one was individually necessary rather than assuming defense-in-depth made the exact boundaries
  unimportant.
- **D2 — Profanity filtering is a moderation aid, not an access control (M07-004).** A simple versioned
  deny-list is intentionally cheap and bypassable by obfuscation; the real backstop is Module 12's manual
  moderation pipeline, which this module's `ChatMessageHold` table exists to support without a future schema
  change.
- **D3 — The `OutboxDispatcherWorker` eager-activation fix is a flagged ownership-boundary exception.** The
  watermark-replay bug (see Backend Flow) could only be fixed correctly in the dispatcher itself, which sits
  outside Module 7's declared file ownership. It was made, tested, and disclosed rather than worked around
  with a narrower but uglier fix inside Module 7's own files — and it is recorded as sanity-checked only, not
  deep-reviewed, in the security disposition (**M07-007**).
- **D4 — Positive security-event logging is intentionally partial for now (M07-006).** Connection-limit
  rejection and resync/gap events are logged; origin rejection and per-message rate/profanity rejection are
  not yet. This was recorded as an open, non-blocking Info finding rather than silently left unmentioned.
- **D5 — Single-instance operation is a hard scope boundary, not a tuning knob.** Presence and connection
  state are process-memory only; a second backend instance would each maintain its own, inconsistent view of
  who is online and which lobby groups exist. A Redis or Azure SignalR backplane is deferred, not implied to
  already work at smaller scale. MessagePack was not adopted for the hub protocol (JSON only, matching every
  other endpoint in the app), and no dedicated "show online status" user setting was built — presence
  visibility already composes from the existing Module 2/3 profile-visibility and block rules, and adding a
  separate toggle was judged to be new product scope, not part of this module's brief.

## Files Changed And Why
Backend: `Hubs/RealtimeHub.cs` (new hub, connect/subscribe/send/activity), `Realtime/IRealtimeScopeAuthorizer.cs`
+ `LobbyScopeAuthorizer.cs` + `NullMatchScopeAuthorizer.cs` (per-call re-authorization), `Realtime/
IPresenceRegistry.cs` + implementation (in-memory precedence aggregation), `Realtime/IRealtimeConnectionCloser.cs`
(proactive close on logout/revoke/suspend/delete), `Chat/ChatMessage.cs`, `Chat/ChatMessageHold.cs`, `Chat/
ChatService.cs`, `Chat/ChatBodyNormalizer.cs`, `Chat/ChatProfanityFilter.cs`, `Chat/ChatRepository.cs`,
`Controllers/ChatController.cs`, `Realtime/LobbyRealtimeHandler.cs` (outbox consumer, plus its
`JoinedMembers`→`Members` fix), `Realtime/OutboxHandlerActivation.cs` + the eager-activation change in
`OutboxDispatcherWorker.cs` (flagged exception, see D3), `Domain/Lobby.cs`
(`ReleaseAllJoinedMembers`), `AuthService.cs` (`LogoutAsync` session-family revoke), the migration
`20260717001316_AddChatAndRealtimeActivation`, and deletion of the dead placeholder notifier interfaces and
the `DirectMessage` enum value. Frontend: `features/realtime/RealtimeConnectionProvider.tsx` +
`usePresence.ts` (new), `features/chat/chatApi.ts` + `types.ts` (new), `components/lobby/ChatPanel.tsx`
(rewritten), `features/lobby/LobbyPage.tsx` (`SeatCard` presence wiring — previously never called
`usePresence` at all), `features/room/GameRoomPage.tsx` (match chat made visibly unavailable),
`features/landing/LandingPage.tsx` (copy correction), `Sidebar.tsx`/`Topbar.tsx`/`SettingsPage.tsx`/
`DashboardPage.tsx`/`FriendsPage.tsx` (mock presence literals removed), plus the fix for two ESLint errors
found in `RealtimeConnectionProvider.tsx` during the frontend session, and the two accessibility fixes
(`LobbyPage.tsx`'s missing `<h1>`, `ChatPanel.tsx`'s placeholder contrast) found during live verification.

## How To Read The Implementation
Start with the approved spec (`docs/specs/module-07-realtime-presence-chat-spec.md`) for the full contract
and domain invariants, then read `RealtimeHub.cs` for the connection/method surface, then
`LobbyScopeAuthorizer.cs` and `ChatService.cs` together for the shared authorization path, then
`LobbyRealtimeHandler.cs` for how Module 6's outbox becomes a `LobbyChanged` hint. On the frontend, start at
`RealtimeConnectionProvider.tsx` for connection lifecycle and reconnect handling, then `ChatPanel.tsx` for
the REST-plus-realtime reconciliation pattern every presence-consuming screen follows in miniature via
`usePresence`.

## Future Improvements / Deferred Items

| Item | Deferred to | Why |
|------|-------------|-----|
| Match-scope chat and live updates | Module 8 | `NullMatchScopeAuthorizer` returns `Realtime.ScopeNotAvailable` until Module 8 supplies a real match-scope adapter on the same typed contract |
| Moderation evidence copy, 2-year retention domain | Module 12 | `ChatMessageHold` schema ships empty this module; Module 7 never writes to it |
| Live suspension enforcement trigger | Module 12 | `User.IsAccountSuspended()` is checked everywhere already; nothing yet calls `User.Suspend()` in a live path |
| Redis / Azure SignalR backplane, distributed presence, multi-instance operation | Future infra module | Hard Phase 1 scope boundary — presence/connection state is process-memory only by design |
| MessagePack hub protocol | Not planned | JSON kept for consistency with every other endpoint; revisit only if profiling shows a real need |
| Dedicated "show online status" user setting | Not in this module's brief | Presence visibility already composes from existing Module 2/3 profile-visibility and block rules |
| Positive security-event logging depth (origin rejection, rate/profanity rejects) | Non-blocking, open | **M07-006**, Info severity, recorded rather than silently left out |
| `OutboxDispatcherWorker` eager-activation fix — deep review | Non-blocking, open | **M07-007**, sanity-checked only during this module; crosses Module 7's declared file ownership |
| E2E spec self-cleanup of its own test lobby | Before Module 14 CI | P2, owner-tracked; not a blocker to this module's local completion |
| One-off release of the real `mohannad` account's pre-existing orphaned lobby-membership row | Owner-authorized, local-dev-only | Scoped fix, explicitly authorized but not yet executed as of this evidence; not part of this module's shipped code |
| Formal ordered stage-checkpoint chain backfill | Waived for Module 7 | Owner-waived process gap (root cause: backend security stage ran on Sonnet 5, not the manifest-routed Opus); functional evidence is real and passing regardless |
| Hosted CI, container build, staging deployment | Module 14 | `releaseEligible` stays `false` until Module 14's CI/container/staging foundation exists |

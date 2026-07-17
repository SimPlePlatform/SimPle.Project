# API Reference - Module 07: Real-Time Presence, Lobby Updates & Chat

## Overview
- Existing UI reused: `LobbyPage.tsx`'s chat placeholder (already gated on `lobby.dependencyReadiness.chat`
  since Module 6), `Avatar`'s `status`/`showPresence` props, `presenceColor()`/`presenceDotClass()`
  (`src/lib/utils.ts`) — all already correct, previously fed literal mock values. The one approved visual
  change: the chat composer `<input>` becomes a visually compatible `<textarea>`.
- Frontend integration points: new `features/realtime/` (SignalR connection provider, `usePresence` hook),
  new `features/chat/` (`chatApi.ts`, `types.ts`), `components/lobby/ChatPanel.tsx` (rewritten), `features/
  lobby/LobbyPage.tsx` (`SeatCard` presence wiring), `features/room/GameRoomPage.tsx` (match chat made
  visibly unavailable, mock send removed), `features/landing/LandingPage.tsx` (DM-promising copy
  corrected), and de-mocking of hard-coded `status:'online'` literals in `Sidebar.tsx`, `Topbar.tsx`,
  `SettingsPage.tsx`, `DashboardPage.tsx`, `FriendsPage.tsx`.
- Existing database impact: additive only. Three new tables: `chat_messages`, `chat_message_holds`,
  `outbox_handler_activations`. No existing Module 1-6 table is altered or dropped. Presence, connection
  maps, and ephemeral versions add no schema — they are in-memory only, correct for the single supported
  backend instance.

## Base Route / Route Group
Realtime hub: `/hubs/realtime`, source of truth `SimPLe.Backend/src/SimPle.Api/Hubs/RealtimeHub.cs`. REST
chat: `/api/chat`, source of truth `SimPLe.Backend/src/SimPle.Api/Controllers/ChatController.cs`.
Authentication for both is the existing HttpOnly `access_token` cookie (`credentials: 'include'`); the hub
deliberately does **not** accept a bearer query-string token, sidestepping the documented ASP.NET Core risk
of that token being logged in request URLs at `Info` level. Every state-changing REST call additionally
requires the shared CSRF header, consistent with every other controller in the app.

## Authentication And Authorization Requirements
Every hub method and every REST route requires a signed-in session (`[Authorize]`); `IUserIdProvider` →
`SubjectUserIdProvider` maps the JWT `sub` claim (stable, globally unique), never a body/route-supplied
value. The load-bearing rule this module is built around: SignalR "captures the authenticated user when a
connection is established and caches it for the lifetime of the connection" and does not automatically
revalidate it. Three independent, jointly-required mechanisms close that gap — none is sufficient alone:
`CloseOnAuthenticationExpiration = true` closes a connection on token expiry; logout, logout-all,
revoke-session, and delete-account **proactively close** the mapped connections via
`IRealtimeConnectionCloser`; and **every** subscribe/send/delete/reconnect **rechecks** scope, suspension,
and block against current owner data through `IRealtimeScopeAuthorizer` — never the principal cached at
handshake. `LobbyScopeAuthorizer` re-reads `ILobbyRepository`, `User.IsAccountSuspended()`, and
`IFriendRepository.IsBlockedInEitherDirectionAsync` on every call. Match scope is registered as
`NullMatchScopeAuthorizer`, which returns `realtime.scope_not_available` until Module 8 supplies a real
adapter. SignalR groups are a delivery optimization only — never an authorization mechanism or a membership
store. The handshake's `Origin` header is validated against an exact allowlist as a coarse anti-CSWSH gate
layered **under** this per-method authorization, not a substitute for it (the header is client-controlled
and can be faked).

## Endpoint Summary Table

| # | Method | Path | Purpose | Auth | Notes |
|---|--------|------|---------|------|-------|
| 1 | HUB CONNECT | `/hubs/realtime` | Establish the authenticated realtime connection | Required (cookie) | Exact-origin allowlist; 6th concurrent connection for one user rejected; `Connected` event carries the server epoch |
| 2 | HUB INVOKE | `SubscribeLobby(Guid lobbyId)` | Join a lobby's delivery group and get its current revision | Required | Privacy-safe `Lobbies.NotFound`-equivalent scope rejection for a non-member; ack carries revision so the client snapshots immediately |
| 3 | HUB INVOKE | `UnsubscribeLobby(Guid lobbyId)` | Leave a lobby's delivery group | Required | No response payload |
| 4 | HUB INVOKE | `SendLobbyMessage(Guid lobbyId, string body, Guid clientCommandId)` | Send a lobby chat message | Required | Duplicate `clientCommandId` returns the original message; 16 KiB receive cap; 5/5s + 20/min rate limit; profanity filter |
| 5 | HUB INVOKE | `ReportActivity()` | Signal foreground activity (prevents Away) | Required | Throttled to 1/60s; grants no authorization; may be forged without security impact |
| 6 | GET | `/api/chat/lobbies/{lobbyId}/messages` | Authorized chat history, cursor-paginated | Required | `limit` default 30, cap 50; block-aware (`FilterBlockedSendersAsync`) |
| 7 | DELETE | `/api/chat/messages/{messageId}` | Delete the caller's own message (tombstone) | Required + CSRF | Author-only; id never reused; fans out `ChatMessageDeleted` |

## Endpoints

### HUB CONNECT /hubs/realtime
- Purpose: establish the one authenticated realtime connection a browser session uses for presence, lobby
  updates, and chat.
- Request parameters: none (the HttpOnly `access_token` cookie is sent automatically by the browser).
- Request body: not applicable (SignalR negotiate + WebSocket/transport upgrade).
- Validation rules: handshake `Origin` must be in the exact configured allowlist (`Realtime:AllowedOrigins`)
  — a missing `Origin` header is rejected identically to a present-but-unlisted one; a 6th concurrent
  connection for the same user is rejected with `Realtime.ConnectionLimit`; `MaximumReceiveMessageSize`/
  `ApplicationMaxBufferSize` are set to 16 KiB and never disabled; `MaximumParallelInvocationsPerClient == 1`
  is the ASP.NET Core default, asserted by a config test rather than set explicitly.
- Success response: the connection opens; `OnConnectedAsync` immediately sends the `Connected` event
  carrying the current server epoch (`Guid.NewGuid()`, generated once per process — a restart is therefore
  always a new epoch by construction).
- Error responses: `403 Realtime.OriginRejected` (missing or unlisted `Origin`), `Realtime.ConnectionLimit`
  (6th connection), connection refused for an anonymous/stale/revoked session.
- Authorization behavior: caller must hold a valid, unexpired session cookie; the connection closes
  immediately via `CloseOnAuthenticationExpiration` if the token expires while open, and is proactively
  closed by `IRealtimeConnectionCloser` on logout/logout-all/revoke-session/delete-account.
- Rate limiting / abuse notes: 5 connections per user (`IRealtimeRateLimiter.TryAcquireConnection`); coarse
  IP limits protect unauthenticated handshake abuse without making a shared-network IP the only key.
- Swagger/OpenAPI notes: not applicable — SignalR hub endpoints are not represented in Swagger/OpenAPI.
- Backend/API/Swagger alignment: not applicable (see above); verified by direct read of `RealtimeHub.cs`
  and `RealtimeOriginValidationMiddleware.cs`.
- Frontend/API integration alignment: `features/realtime/RealtimeConnectionProvider.tsx`, gated on
  `useAuth().status === 'authenticated'`, torn down on `logout`/`logoutAll`.
- Example request: SignalR client `HubConnectionBuilder().withUrl('/hubs/realtime', { withCredentials: true
  }).withAutomaticReconnect([0, 2000, 10000, 30000]).build()`.
- Example response: `Connected` event, payload `{ serverEpoch: "<guid>" }`.

### HUB INVOKE SubscribeLobby(Guid lobbyId)
- Purpose: join a lobby's delivery group and receive its current revision so the client can snapshot
  immediately.
- Request parameters: `lobbyId` (client passes lobby ids only — never a group name or a lobby join code).
- Request body: not applicable (hub method argument).
- Validation rules: `IRealtimeScopeAuthorizer.AuthorizeAsync(RealtimeAction.Subscribe, ...)` re-reads current
  lobby membership/privacy, caller suspension, and block state — never a cached prior result.
- Success response: `SubscribeLobbyResultDto { int Revision }` — the ack itself carries the revision, so no
  `ResyncRequired` round-trip is needed just to learn it; the client then calls the existing `GET
  /api/lobbies/{lobbyId}` (Module 6) to fetch the authorized snapshot.
- Error responses: the same privacy-safe not-found/forbidden outcome as `GET /api/lobbies/{lobbyId}` for a
  non-member/private lobby; match-scope subscribe returns `Realtime.ScopeNotAvailable` until Module 8
  registers its adapter.
- Authorization behavior: current lobby member, or any signed-in user for a `Public` lobby (matching Module
  6's `GET /api/lobbies/{lobbyId}` visibility) — re-checked on every call, not cached from a prior
  subscribe.
- Rate limiting / abuse notes: bound by the single-concurrent-invocation-per-connection default.
- Swagger/OpenAPI notes: not applicable — hub method, not a REST route.
- Backend/API/Swagger alignment: not applicable; verified by direct read of `RealtimeHub.cs`/
  `LobbyScopeAuthorizer.cs`.
- Frontend/API integration alignment: `features/realtime/RealtimeConnectionProvider.tsx`'s subscribe
  effect, invoked from `LobbyPage.tsx` on mount.
- Example request: `connection.invoke('SubscribeLobby', lobbyId)`.
- Example response: `{ revision: 7 }`.

### HUB INVOKE UnsubscribeLobby(Guid lobbyId)
- Purpose: leave a lobby's delivery group (e.g. navigating away from `/lobby/[lobbyId]`).
- Request parameters: `lobbyId`.
- Request body: not applicable.
- Validation rules: none beyond an authenticated connection; unsubscribing from a group the caller was
  never subscribed to is a no-op, not an error.
- Success response: no payload.
- Error responses: none beyond standard connection-level failures.
- Authorization behavior: any authenticated caller for their own subscription state.
- Rate limiting / abuse notes: bound by the single-concurrent-invocation-per-connection default.
- Swagger/OpenAPI notes: not applicable.
- Backend/API/Swagger alignment: not applicable; verified by direct read of `RealtimeHub.cs`.
- Frontend/API integration alignment: `RealtimeConnectionProvider.tsx`'s unmount/cleanup path.
- Example request: `connection.invoke('UnsubscribeLobby', lobbyId)`.
- Example response: none.

### HUB INVOKE SendLobbyMessage(Guid lobbyId, string body, Guid clientCommandId)
- Purpose: send a lobby chat message.
- Request parameters: `lobbyId`, `body`, `clientCommandId` (client-generated UUID idempotency key).
- Request body: not applicable (hub method arguments).
- Validation rules: `ChatBodyNormalizer` enforces NFC normalization, CRLF/CR→LF, trimmed outer Unicode
  whitespace, LF allowed, other C0/C1 controls rejected, 1-1000 Unicode scalar values; the versioned
  deny-list profanity filter rejects a match before persistence (message is not stored, sender is told
  why); `ChatService` is the sole send-authorization path shared by hub and REST, re-checking scope,
  suspension, and block via `LobbyScopeAuthorizer` before persisting. A duplicate `clientCommandId` for the
  same sender returns the **original** message (backed by the real database unique index
  `ux_chat_messages_sender_command` on `(SenderId, ClientCommandId)`, not an app-level guard alone).
- Success response: `SendLobbyMessageResultDto { ChatMessageDto Message }`; fans out `ChatMessageCreated` to
  an explicit, block-filtered recipient list (`Clients.Users(...)`, never a raw group broadcast for chat).
- Error responses: `Chat.InvalidBody` (normalization/length/control-character failure), `Chat.ProfanityRejected`
  (deny-list match, a normal validation error, not a security event), `Realtime.PayloadTooLarge` (>16 KiB
  receive), `RateLimit.Exceeded` with `Retry-After` (5/5s burst, 20/min sustained), the same scope-rejection
  outcome as `SubscribeLobby` if membership/block/suspension state has changed.
- Authorization behavior: sender only; recipient list is computed per-send by `ChatService
  .GetDeliverableRecipientsAsync` — currently-joined lobby members, always including the sender's own other
  connections, excluding any member with a block relationship in either direction with the sender.
- Rate limiting / abuse notes: `matchmaking`-style per-user `IRealtimeRateLimiter` (hub invocations are
  **not** covered by ASP.NET Core's HTTP-scoped `AddRateLimiter`, so this is purpose-built); repeated
  profanity triggers by the same sender feed the existing abuse rate-limit counters rather than a separate
  penalty system.
- Swagger/OpenAPI notes: not applicable — hub method.
- Backend/API/Swagger alignment: not applicable; verified by direct read of `ChatService.cs`/`RealtimeHub.cs`.
- Frontend/API integration alignment: `chatApi.ts`'s send path, invoked from `ChatPanel.tsx`'s composer
  (Enter sends, Shift+Enter inserts LF, IME composition never submits accidentally).
- Example request: `connection.invoke('SendLobbyMessage', lobbyId, "gg, well played\nsee you next round",
  clientCommandId)`.
- Example response: `{ message: { id: "<uuid>", lobbyId: "<uuid>", sender: {...}, body: "gg, well
  played\nsee you next round", deleted: false, createdAt: "<ISO-8601>", schemaVersion: 1 } }`.

### HUB INVOKE ReportActivity()
- Purpose: signal foreground activity so aggregated presence does not fall to `Away`.
- Request parameters: none.
- Request body: not applicable.
- Validation rules: accepted at most once per 60 seconds per connection; a rejected (too-frequent) signal
  mutates nothing.
- Success response: no payload; on acceptance, resets the connection's last-activity timestamp used by the
  Away/Offline state machine.
- Error responses: none — a too-frequent call is silently ignored, not an error.
- Authorization behavior: grants no authorization of any kind and **may be forged without security impact**
  — it only ever prevents a presence-state transition, never a permission decision.
- Rate limiting / abuse notes: 1 accepted call per 60 seconds per connection.
- Swagger/OpenAPI notes: not applicable.
- Backend/API/Swagger alignment: not applicable; verified by direct read of the presence registry.
- Frontend/API integration alignment: a periodic foreground-activity ping from `RealtimeConnectionProvider.tsx`.
- Example request: `connection.invoke('ReportActivity')`.
- Example response: none.

### GET /api/chat/lobbies/{lobbyId}/messages
- Purpose: authorized chat history for a lobby, used on `ChatPanel` mount, reconnect resync, and scrollback
  pagination.
- Request parameters (query): `cursor` (opaque, `(createdAt,id)`-encoded), `direction` (`before` default —
  scrollback; `after` — reconnect repair), `limit` (default 30, cap 50).
- Request body: none.
- Validation rules: `limit` bounded 1-50; malformed cursor rejected; block-aware — `ChatService
  .FilterBlockedSendersAsync` excludes any row from a sender the caller has blocked or is blocked by (the
  actor's own messages are always visible); the pagination cursor is computed from the **unfiltered** rows,
  so filtering a blocked sender's row cannot corrupt cursor position or silently under-fill a page.
- Success response: `200` page of `ChatMessageDto`, ordered `(createdAt, id)`.
- Error responses: `404 Chat.NotFound` (lobby missing or not visible to the viewer — existence is never
  disclosed), `400 Validation.Failed` (out-of-range `limit`), `429 RateLimit.Exceeded`.
- Authorization behavior: caller must be authorized for the lobby (current member, or any signed-in user for
  a `Public` lobby, matching Module 6's visibility rule); re-checked on every request.
- Rate limiting / abuse notes: standard read-path rate limiting; no dedicated abuse surface beyond the
  general per-user limits.
- Swagger/OpenAPI notes: documented via `[SwaggerOperation]` on `ChatController.cs`; verified by the passing
  `Swagger_DescribesChatHistoryAndDeleteRoutes` test rather than a self-reported `OperationId` string here.
- Backend/API/Swagger alignment: `ChatController.cs` → `ChatService.GetHistoryAsync`.
- Frontend/API integration alignment: `chatApi.getHistory()`, `ChatPanel.tsx`.
- Example request: `GET /api/chat/lobbies/3f9a.../messages?limit=30`
- Example response: `{ "items": [ { "id": "...", "lobbyId": "3f9a...", "sender": {...}, "body": "gg",
  "deleted": false, "createdAt": "<ISO-8601>", "schemaVersion": 1 } ], "nextCursor": null }`

### DELETE /api/chat/messages/{messageId}
- Purpose: author deletes their own message, producing a tombstone.
- Request parameters: `messageId` (route).
- Request body: none.
- Validation rules: author-only; the message body is not cleared on disk (it may still be needed by a
  Module 12 evidence copy within the 30-day retention window) but the **read path** returns `body: null,
  deleted: true` — the body never leaves the server again once deleted; the id is never reused.
- Success response: `204 No Content`; fans out `ChatMessageDeleted { messageId, deletedAtUtc }` to the same
  block-filtered recipient list as a send.
- Error responses: `404 Chat.NotFound` (missing or not visible — existence never disclosed), `403
  Chat.Forbidden` (caller is not the message's author), `409 Chat.MessageExpired` (an active Module 12 hold
  or already-cleaned-up message — see the retention/hold race in `technical-flow.md`).
- Authorization behavior: author only, re-checked against current data, not a cached ownership claim.
- Rate limiting / abuse notes: standard write-path rate limiting.
- Swagger/OpenAPI notes: documented via `[SwaggerOperation]` on `ChatController.cs`; verified by
  `Swagger_DescribesChatHistoryAndDeleteRoutes`.
- Backend/API/Swagger alignment: `ChatController.cs` → `ChatService.DeleteAsync`.
- Frontend/API integration alignment: `chatApi.deleteMessage()`, `ChatPanel.tsx`'s delete action.
- Example request: `DELETE /api/chat/messages/7c2b...`
- Example response: `204` empty body.

## Data Models / DTOs

```typescript
ChatScope = 'Lobby' | 'Match'; // no 'DirectMessage' — the legacy enum value was removed this module

RealtimeEnvelope = {
  schemaVersion: number; eventId: string; serverUtc: string; scope: 'lobby' | 'match' | 'user'; scopeId: string;
}

ChatSenderDto = // shared M3 player-identity contract
  | { kind: 'visible'; userId: string; username: string; displayName: string; avatarUrl: string | null }
  | { kind: 'tombstone' }; // deleted, blocked, or hidden sender — no profile link, no username leak

ChatMessageDto = {
  id: string; lobbyId: string; sender: ChatSenderDto; body: string | null; deleted: boolean;
  createdAt: string; // ISO 8601
  schemaVersion: number;
}

SubscribeLobbyResultDto = { revision: number; }
SendLobbyMessageResultDto = { message: ChatMessageDto; }

// Server -> client hub events (IRealtimeClient), each envelope-wrapped per RealtimeEnvelope above
LobbyChangedPayload = { revision: number; changeType: string; } // thin hint, carries no lobby state
PresenceChangedPayload = { userId: string; status: PresenceStatus; serverEpoch: string; userVersion: number; }
ChatMessageCreatedPayload = ChatMessageDto;
ChatMessageDeletedPayload = { messageId: string; deletedAtUtc: string; }
AccessRevokedPayload = { reason: 'lobby.membership_removed' | 'lobby.closed' | 'auth.session_revoked' |
  'auth.suspended' | 'social.blocked'; }
ResyncRequiredPayload = { reason: 'gap' | 'slow_consumer'; currentRevision: number | null; }
ConnectedPayload = { serverEpoch: string; }

PresenceStatus = 'Offline' | 'Away' | 'Online' | 'InLobby' | 'Playing'; // ordinal = precedence, aggregated via Max

CursorPage<T> = { items: T[]; nextCursor: string | null; }
```

## Error Format
Envelope: `{ error: { code, message, retryAfterUtc? } }` (`ApiErrorResponse`/`MapError`, same convention as
every other controller). Detailed hub exceptions never reach clients — `EnableDetailedErrors` is
development/test only.

| Code | HTTP / Hub | Meaning |
|------|------|---------|
| `Realtime.ScopeNotAvailable` | hub error | Match scope — until M8 registers its adapter |
| `Realtime.ConnectionLimit` | hub error | 6th concurrent connection for one user |
| `Realtime.OriginRejected` | 403 (handshake) | Handshake `Origin` missing or not in the exact allowlist |
| `Realtime.PayloadTooLarge` | hub error | Receive > 16 KiB |
| `Chat.NotFound` | 404 | Message/lobby absent **or** not visible to the viewer — existence never disclosed |
| `Chat.Forbidden` | 403 | Not the author on delete |
| `Chat.InvalidBody` | 400 | Failed normalization/length/control-character rules |
| `Chat.ProfanityRejected` | 400 | Deny-list match — a normal validation error, not a security event; message not stored |
| `Chat.MessageExpired` | 409 | Delete/hold requested on a message that already aged out — M12's honest answer, not silent evidence loss |
| `RateLimit.Exceeded` | 429 | With `Retry-After` + `retryAfterUtc` |

## Security Considerations
Every hub method and REST route requires a session; the actor is always the `sub` claim, never a
body/route-supplied id. The cached-principal problem — SignalR's own documented behavior of not
revalidating identity after handshake — is closed with all three required mechanisms
(`CloseOnAuthenticationExpiration`, proactive close on logout/revoke/suspend, and a per-method recheck of
scope/suspension/block against current data), independently verified by the `--security=asvs-lite` review
rather than merely asserted. Chat idempotency is a real database unique constraint
(`ux_chat_messages_sender_command`), not an app-level guard alone. The retention/hold race (Module 12's
future evidence copy vs. the 30-day cleanup sweep) is closed by a single atomic CTE-based delete with row
locking, not a check-then-act window. Size and rate caps (16 KiB receive/buffer, 5 connections/user, 5
messages/5s + 20/min) are configured and never disabled.

The `--security=asvs-lite` review
(`SimPle.Project/docs/security/audits/module-07-realtime-presence-chat.md`) covered a backend phase and a
post-frontend phase and found **zero unwaived Critical/High findings** in either. Two Medium findings were
identified and fixed: **M07-001**, lobby chat delivered as an unfiltered per-lobby group broadcast so a
blocked co-member still received chat (fixed — delivery is now an explicit, block-filtered recipient list,
`Clients.Users(...)`, never `Clients.Group(...)`, for chat); and **M07-008**, the REST chat-history endpoint
had no block filtering at all, an asymmetry with the already-fixed realtime path (fixed via
`FilterBlockedSendersAsync`). Two Low findings were also fixed: **M07-002**, a connection/presence-slot leak
if `OnConnectedAsync` faults after acquiring its lease (fixed with a release-on-failure `try`/`catch`); and
**M07-003**, a request with no `Origin` header bypassing the allowlist (fixed — a missing header is now
rejected identically to a present-but-unlisted one). Three Info findings remain open and non-blocking: the
deny-list profanity filter is intentionally simple and bypassable by obfuscation, by design, backed by
Module 12's manual moderation pipeline (**M07-004**); positive security-event logging is thinner than the
brief's full list — connection-limit rejection and resync/gap events are logged, origin rejection and
per-message rate/profanity rejects are not yet (**M07-006**); and an out-of-scope `OutboxDispatcherWorker`
fix made during backend development was sanity-checked only, not deep-reviewed, since it crosses this
module's declared ownership boundary (**M07-007**, see `technical-flow.md`'s Design Tradeoffs). A fourth
Info item, output encoding, was independently confirmed **passing** in the post-frontend phase, not left
open: chat bodies render as auto-escaped JSX text with no `dangerouslySetInnerHTML` and no auto-linking.

The module's formal ordered stage-checkpoint chain (`docs/ai-workflow/evidence/checkpoints/module-07-realtime-presence-chat/index.json`)
carries only the `planning` stage — a process/tooling gap, not a functional one. The backend security-review
stage ran on Sonnet 5 rather than the manifest-routed Opus for that assurance-sensitive stage, so it could
not be formally chained in, and every later stage inherited the same "cannot chain onto a missing prior
index" condition. The project owner explicitly waived backfilling that chain for this module; the
underlying security, frontend-security, and verification checkpoint files themselves exist as valid,
independently readable evidence of real, passing results. See `testing-report.md`'s Final Status for full
detail.

## Related Tests
Backend: full unit suite **962/962** passed, 0 failed (`docs/ai-workflow/evidence/operations/module-07-realtime-presence-chat/operations.json`);
an earlier point in the same working session (before the verification-stage domain-bug fix) recorded
**955/955** unit + **400/400** integration, including the real-PostgreSQL `ChatRetentionHoldRaceTests` suite
(5/5, independently re-run in isolation) proving the moderation-hold-vs-cleanup race never silently loses
evidence. Security-phase regression tests: 24/24 unit + 18/18 integration after the M07-008 fix (0
regressions). Frontend: `npx vitest run` **264/264** passing across 26 test files; `npx tsc --noEmit` and
`npm run lint` both clean; `node scripts/check-contract-drift.mjs` reports **DRIFT=0** (87 backend routes, 72
unique frontend calls). Live E2E: `module-07-realtime-chat.spec.ts` passed **1/1** against a live local stack
(real Postgres + backend :5147 + frontend :3000, no mocks) — two authenticated contexts, live presence, a
multiline chat message seen exactly once on both sides, a disconnect/mutate/reconnect convergence, and the
shared axe accessibility fixture reporting zero violations. Full detail, including test-count provenance
across sessions, in `testing-report.md`.

## Last Verified Command
Backend (verification session): `dotnet build SimPLe.Backend/SimPle.sln` (0 errors, 0 warnings), `dotnet
test SimPLe.Backend/SimPle.sln --no-build` (294 passed, 0 failed, 107 Testcontainers-gated integration tests
skipped in that pass), `node scripts/check-contract-drift.mjs` (`DRIFT=0`). Operations gate (same session):
`dotnet test SimPLe.Backend/SimPle.sln` (full unit suite, 962/962 passed). Frontend (M07-F1 session): `npx
tsc --noEmit -p tsconfig.json` (clean), `npx eslint ... --max-warnings=0` (clean), `npx vitest run` (264/264),
`npm run build` (clean, 19 routes). Live E2E: `node scripts/run-module-e2e.mjs --modules 7` against local
backend `:5147` + frontend `:3000` + real PostgreSQL — 1 passed, after two resolved attempts blocked by stale
test-account lobby state (see `testing-report.md`).

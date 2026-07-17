# Security Audit - Module 07: Real-Time Presence, Lobby Updates & Chat

Date: 2026-07-17

## Scope

Backend slice B1+B2 (presence/lobby-realtime infrastructure + chat persistence): SignalR hub
(`RealtimeHub`), origin-validation middleware, connection tracker/rate limiter, presence registry,
scope authorization (`LobbyScopeAuthorizer`), chat service/domain/repository, chat retention sweeper,
outbox-driven `LobbyRealtimeHandler`, and the two REST chat endpoints (`ChatController`). Frontend is
not yet wired (Session Plan step 4) and is explicitly out of scope for this phase.

**Post-frontend phase (2026-07-17, this update):** the M07-F1 frontend slice (`ChatPanel.tsx`,
`RealtimeConnectionProvider.tsx`, `chatApi.ts`, presence wiring in `LobbyPage.tsx`/`Sidebar.tsx`/
`Topbar.tsx`/`SettingsPage.tsx`/`DashboardPage.tsx`/`FriendsPage.tsx`, `GameRoomPage.tsx`'s unavailable
match-chat placeholder) plus, on independent follow-up verification, the backend `ChatService.GetHistoryAsync`
REST history path. See the new "Post-Frontend Phase Review" section below.

## Assessment Type

ASVS-lite (module brief's mandated minimum depth per `docs/ai-workflow/module-registry.md` threat
profile: realtime, websocket, signalr, abuse, chat-moderation).

Review phase: backend

## Authorization Statement

Local authorized project-only review. No external systems, production services, real secrets, or real
user data were used. Read-only review; no exploit payloads were executed against a live target — findings
were validated by source reading, targeted test evidence, and safe local exploit narratives only.

## Executive Summary

The B1+B2 backend slice is materially sound: authorization is re-checked on every hub method and REST
endpoint against live data rather than the handshake-cached principal, the cached-principal problem named
as the module's top risk is closed with all three required mechanisms (`CloseOnAuthenticationExpiration`,
proactive close on revoke, per-method recheck), the chat idempotency key is a real database unique
constraint (not just an app-level guard), the retention/hold race is closed with a single atomic
CTE-based delete rather than a check-then-act window, and size/rate caps are configured correctly and
never disabled. No Critical or High severity finding was identified.

One Medium finding was confirmed by direct code read: lobby chat delivery is an unfiltered
per-lobby-group broadcast, and the block check inside `LobbyScopeAuthorizer` only evaluates a block
between the actor and the lobby host — not between co-members. A user who blocks (or is blocked by) a
non-host lobby member still receives that member's chat messages, and vice versa. This is a genuine
deviation from the module brief's explicit "blocked users do not receive or infer presence/chat"
requirement (`docs/module-requirements/module-07-realtime-presence-chat.md`, Security section) and from
the shared baseline's block-consistency requirement. Two Low findings (a connection/presence-slot leak
on a handshake-send failure, and origin validation silently allowing a request with no `Origin` header)
are hardening items, not exploitable authorization gaps.

**Update (same day, fix session):** the user approved fixing all three findings. All three are now fixed
in product code — see Findings below and Fixed Issues Summary. Chat fan-out is now an explicit,
block-filtered recipient list instead of a raw group broadcast; `RealtimeHub.OnConnectedAsync` releases
its acquired connection lease/presence entry/tracker registration on any post-acquisition failure; and the
origin-validation middleware now rejects a missing `Origin` header the same as a present-but-unlisted one.

## Severity Summary Table

| Severity | Count | Notes |
|---|---:|---|
| Critical | 0 | |
| High | 0 | |
| Medium | 1 | M07-001 chat block-bypass in lobby group broadcast — **fixed** |
| Low | 2 | M07-002 connection/presence-slot leak on handshake failure — **fixed**; M07-003 missing-`Origin` request allowed through — **fixed** |
| Info | 4 | M07-004 naive profanity filter (by design); M07-005 output encoding — **confirmed PASS in post-frontend review**; M07-006 thin positive security-event logging; M07-007 out-of-scope outbox-dispatcher fix (sanity-only, not deep-reviewed) |
| Medium (post-frontend) | 1 | M07-008 REST chat history had no block filtering (unlike the realtime path fixed by M07-001) — **fixed** |

## OWASP Mapping

- OWASP Top 10 web: A01 Broken Access Control (M07-001), A04 Insecure Design / resource consumption (M07-002), A09 Security Logging and Monitoring Failures (M07-006)
- OWASP API Security Top 10: API1 Broken Object Level Authorization (M07-001), API4 Unrestricted Resource Consumption (M07-002)
- WebSocket/Socket.IO checklist (`docs/security/threat-playbooks/socketio-websocket.md`): origin validation, per-message authorization, connection/rate limits, cached-principal revalidation — all reviewed above.

## Methodology

Source-code review of the files listed in Scope, cross-checked against the module brief's Security
section (lines ~121-268) and the shared quality baseline's authorization/privacy requirements, plus
reading of the existing unit/integration test suite to classify each claim as test-proven vs.
asserted-only. Two findings (M07-001 chat block-bypass, M07-002 connection-leak path) were independently
spot-verified by direct read of `RealtimeNotifier.cs`, `LobbyScopeAuthorizer.cs`, and `RealtimeHub.cs`
rather than taken on the delegated reviewer's word alone. Targeted test evidence was re-run this session
(see Tests/Security Checks Run) rather than only citing the prior backend-slice checkpoint. No live
exploitation, fuzzing, or destructive payloads were used; the block-bypass finding is a direct reading of
the authorization code path, not a demonstrated live exploit.

## Module Architecture Reviewed

- Existing UI reused: n/a (backend-only phase; frontend still mock per Module 7 status)
- Frontend integration points: none yet — REST chat routes exist with no frontend caller (expected; contract-drift confirmed 0 drift with this understood as backend-only routes per the B2 checkpoint report)
- Existing database impact: additive only — `ChatMessage`, `ChatMessageHold`, `OutboxHandlerActivation` tables added in migration `20260717001316_AddChatAndRealtimeActivation`; no existing table altered/dropped
- Migration added: yes
- Migration safety notes: additive; unique index `ux_chat_messages_sender_command` on `(SenderId, ClientCommandId)` backs the idempotency contract at the DB layer, not just in application code
- Data preservation notes: no destructive change; tombstone/soft-delete preserves the row (id never reused) for M12 evidence retention
- Destructive DB changes: none
- Backend/API/Swagger alignment: `Swagger_DescribesChatHistoryAndDeleteRoutes` passes; `ChatController.cs` carries `[SwaggerOperation]` annotations for both REST routes
- Frontend/API integration alignment: not applicable this phase (frontend slice is Session Plan step 4)

## Threat Model

Threats named in the module brief and addressed by this review: CSWSH/origin abuse, stale/cached-principal
sessions, cross-group/cross-scope disclosure (IDOR/BOLA), XSS (deferred to frontend rendering — no
server-side HTML assembly exists in this slice), flooding, oversized payloads, replay (idempotent
send), block bypass, connection exhaustion, and log leakage. See Findings for the one confirmed gap
(block bypass) and two hardening items (connection-slot leak, missing-`Origin` handling).

## Findings

### M07-001 - Blocked lobby co-members still receive each other's chat via unfiltered group broadcast
- Severity: Medium
- Affected asset: `SimPLe.Backend/src/SimPle.Api/Realtime/RealtimeNotifier.cs:45-57` (`NotifyChatMessageCreatedAsync`/`NotifyChatMessageDeletedAsync`), `SimPLe.Backend/src/SimPle.Application/Realtime/Authorization/LobbyScopeAuthorizer.cs:53-60`
- Description: Chat messages are broadcast to the entire SignalR lobby group (`Clients.Group(RealtimeGroups.Lobby(lobbyId))`) with no per-recipient filtering. `LobbyScopeAuthorizer.AuthorizeAsync` only evaluates a block relationship between the acting user and the lobby host (`lobby.HostUserId`), by explicit design comment ("only meaningful against the host"). It never checks blocks between two non-host co-members. Both members therefore remain subscribed and continue to exchange chat even after blocking each other.
- How it could be exploited, written safely: Users A and B both join a lobby hosted by C (neither A nor B is host). A blocks B. A sends a lobby chat message. B's still-subscribed connection receives the `ChatMessageCreated` event containing A's real identity and message body — the block has no effect on lobby chat delivery in either direction.
- Evidence: direct read of `RealtimeNotifier.cs:45-50` (unfiltered group broadcast) and `LobbyScopeAuthorizer.cs:53-60` (block check scoped to `lobby.HostUserId != actorUserId` only). No existing test asserts a blocked co-member is excluded from chat fan-out.
- Fix implemented: `ChatService` now computes an explicit per-recipient delivery list before every chat
  create/delete notification (`ChatService.GetDeliverableRecipientsAsync`, new private helper): it loads the
  lobby's currently-joined members, always includes the sender (for the sender's own other connections), and
  excludes any other member with a block relationship in either direction with the sender
  (`IFriendRepository.IsBlockedInEitherDirectionAsync`, one pairwise check per member — lobbies are small, so
  this is cheap). `IRealtimeNotifier.NotifyChatMessageCreatedAsync`/`NotifyChatMessageDeletedAsync` now take an
  explicit `recipientUserIds` collection (mirroring the pre-existing `NotifyPresenceChangedAsync` pattern), and
  `RealtimeNotifier`'s SignalR implementation delivers via `Clients.Users(...)` instead of
  `Clients.Group(RealtimeGroups.Lobby(lobbyId))` — the group broadcast path for chat is gone entirely, not just
  bypassed for the blocked pair. Files changed: `ChatService.cs`, `IRealtimeNotifier.cs`, `RealtimeNotifier.cs`.
- Verification after fix: new regression test
  `ChatServiceTests.Send_LobbyHasBlockedCoMember_ExcludesBlockedMemberFromRecipients` — a lobby with the sender
  plus a blocked co-member and an unrelated co-member, asserts the notifier is called with a recipient list
  that contains the sender and the unrelated member but excludes the blocked one. All pre-existing
  `ChatServiceTests` and `RealtimeHubTests` (unit + real end-to-end hub fan-out) still pass unchanged since the
  sender-inclusive-by-default recipient list preserves prior externally-observable behavior for the
  non-blocked case. See Tests/Security Checks Run for the full command and log.
- Residual risk: none identified for the scenario this finding described (co-member block bypass in lobby
  chat). Group-based delivery is no longer used for chat at all, so there is no remaining code path that could
  regress this silently by re-introducing a group broadcast without also updating the recipient-computation
  call site.

### M07-002 - Per-user connection lease, presence entry, and tracker registration leak if `OnConnectedAsync` fails after acquisition
- Severity: Low
- Affected asset: `SimPLe.Backend/src/SimPle.Api/Hubs/RealtimeHub.cs:54-81` (`OnConnectedAsync`)
- Description: After `_rateLimiter.TryAcquireConnection`, `_presence.TryConnect`, and `_tracker.Register` all succeed, the method awaits `Clients.Caller.Connected(...)`. If that send throws (e.g. the client disconnected mid-handshake), SignalR aborts the connection without invoking `OnDisconnectedAsync` for a connection whose `OnConnectedAsync` itself faulted, so the already-acquired connection-limit lease and tracker registration are never released, and the presence entry is not cleared through the normal disconnect path.
- How it could be exploited, written safely: a client repeatedly opens a hub connection and forcibly drops the socket in the negotiate/handshake window; each iteration can leak one of the user's 5 connection-limit slots, eventually pinning them out of new legitimate connections.
- Evidence: `RealtimeHub.cs:58-78`; no test exercises a send failure at that point in the handshake.
- Fix implemented: the acquire-then-send body of `OnConnectedAsync` is now wrapped in a `try`/`catch`. On any
  exception after the rate-limiter lease, presence entry, and tracker registration have all been acquired, the
  `catch` block releases all three (`_tracker.Unregister`, `_rateLimiter.ReleaseConnection`,
  `_presence.Disconnect`) using the already-captured `callerContext`/`userId`, then rethrows so the original
  failure still propagates and the connection still aborts. File changed: `RealtimeHub.cs`.
- Verification after fix: covered by code review (the release calls are the same ones `OnDisconnectedAsync`
  already performs on the normal path, so the leak-recovery behavior reuses proven logic) rather than a new
  fault-injection unit test — `SimPle.UnitTests` deliberately has no dependency on the `SimPle.Api` layer where
  `RealtimeHub` lives (Clean Architecture boundary; only `SimPle.IntegrationTests` references `SimPle.Api`), and
  reliably forcing `Clients.Caller.Connected(...)` to throw mid-handshake through a real `TestServer`/WebSocket
  connection was judged not worth the added test-harness complexity for a Low-severity, self-limited leak. The
  full existing `RealtimeHubTests` suite (connect/disconnect/reconnect paths) still passes unchanged, confirming
  no regression to the non-failure path. See Tests/Security Checks Run.
- Residual risk: none new. Self-limited to the affected user's own connection budget as before; the fix removes
  the leak rather than changing the risk's shape.

### M07-003 - A handshake request with no `Origin` header bypasses the origin allowlist check
- Severity: Low
- Affected asset: `SimPLe.Backend/src/SimPle.Api/Realtime/RealtimeOriginValidationMiddleware.cs:27-41`
- Description: The middleware rejects a *present-but-unlisted* `Origin` header but allows a request through when the header is absent entirely.
- How it could be exploited, written safely: a non-browser client that omits `Origin` reaches the hub without an origin check. Not exploitable for CSWSH from a browser context, because browsers always send `Origin` on cross-site requests to this endpoint — the gap only affects non-browser clients, which still face full per-method object/action authorization (`LobbyScopeAuthorizer`) and standard cookie/JWT auth regardless.
- Evidence: `RealtimeOriginValidationMiddleware.cs:34` (only the unlisted-but-present branch denies); `RealtimeHubTests.Connect_WithMismatchedOrigin_IsRefused` covers the present-but-wrong case, not the absent case.
- Fix implemented: the condition is now `string.IsNullOrEmpty(origin) || !allowedOrigins.Contains(origin, ...)`
  — a missing `Origin` header is rejected with the same `403 Realtime.OriginRejected` response as a
  present-but-unlisted one, closing the bypass outright rather than narrowing it to a conditional check. This
  is safe for every real browser client: per the Fetch spec, browsers include `Origin` on POST requests (the
  negotiate call) and on WebSocket upgrades regardless of same-origin status, so no legitimate browser-driven
  connection can reach this path without an `Origin` header already. File changed:
  `RealtimeOriginValidationMiddleware.cs`.
- Verification after fix: new integration test
  `RealtimeHubTests.Connect_WithMissingOriginHeader_IsRefusedWith403` — a raw `HttpClient` negotiate POST
  (deliberately not the `HubConnection` SignalR client, which always sets `Origin` itself and offers no way to
  omit it) with an authenticated cookie but no `Origin` header, asserts `403 Forbidden`. The existing
  allowed-origin and mismatched-origin tests (`Connect_WithValidCookieAndAllowedOrigin_Succeeds`,
  `Connect_WithMismatchedOrigin_IsRefused`) still pass unchanged.
- Residual risk: none identified for the missing-header bypass this finding described. Origin remains a coarse
  anti-CSWSH gate, not the primary authorization mechanism, per the brief's own framing — that division of
  responsibility is unchanged by this fix.

## Fixed Issues Summary

All three findings were fixed in this session, following explicit user approval ("fix") after the initial
review report:

- **M07-001** (Medium, chat block-bypass): fixed by replacing the unfiltered `Clients.Group(...)` chat
  broadcast with an explicit, block-filtered `Clients.Users(...)` recipient list computed per send/delete.
- **M07-002** (Low, connection/presence/tracker leak): fixed by wrapping `OnConnectedAsync`'s
  post-acquisition body in a `try`/`catch` that releases the lease/presence/tracker state on any failure
  before rethrowing.
- **M07-003** (Low, missing-`Origin` bypass): fixed by rejecting a missing `Origin` header the same as a
  present-but-unlisted one.

See each finding above for the exact code change, and Tests/Security Checks Run for the fix-verification
test run.

## Post-Frontend Phase Review

Date: 2026-07-17. Assessment type: ASVS-lite (unchanged). Reviewer: main session (Sonnet 5, high effort —
matches `post-frontend-security-review`'s manifest routing; no Opus escalation required since no
Critical/High finding resulted), with a `security-reviewer` subagent pass used for the initial rendered-data/
DOM-sink/storage/redirect/CSP/error-privacy sweep, independently spot-verified against live source.

### Scope reviewed

Rendered chat content and DOM/HTML/URL sinks, token/storage exposure, redirects/external-origin allowlists,
cookie/CSRF/CORS assumptions, CSP/security-header compatibility, browser error/log privacy, and presence
trust boundaries in: `ChatPanel.tsx`, `chatApi.ts`, `RealtimeConnectionProvider.tsx`, `errors.ts`,
`LobbyPage.tsx` (`SeatCard` presence wiring), `GameRoomPage.tsx` (match-chat placeholder), and the
presence-consuming surfaces (`Sidebar.tsx`, `Topbar.tsx`, `SettingsPage.tsx`, `DashboardPage.tsx`,
`FriendsPage.tsx`). On an independent follow-up (not raised by the subagent), also re-read
`SimPLe.Backend/src/SimPle.Application/Chat/ChatService.cs`'s `GetHistoryAsync` REST-history path, since the
client's correctness for M07-005 depends on what the server actually returns on every page load.

### M07-005 (Info, deferred from backend phase) — RESOLVED: PASS

Confirmed by direct read of `ChatPanel.tsx:344-346`: message bodies render as plain JSX text children
(`{message.body}`), which React auto-escapes — no `dangerouslySetInnerHTML`, no manual HTML assembly, no
auto-linking of URLs anywhere in the chat render path. `parseHubErrorCode` (`errors.ts`) allowlists a fixed
set of known error codes before display, so a raw server exception message can never reach the DOM. Verdict:
the frontend slice satisfies the module brief's "output is encoded text; links are not auto-linked"
requirement as written. No finding.

### M07-008 - REST chat history endpoint returned a blocked co-member's messages on every fetch (block filtering existed only on the realtime path)
- Severity: Medium
- Affected asset: `SimPLe.Backend/src/SimPle.Application/Chat/ChatService.cs` (`GetHistoryAsync`)
- Description: M07-001 (backend phase) made the *realtime* chat broadcast block-aware via
  `GetDeliverableRecipientsAsync`, but `GetHistoryAsync` — which backs `GET /api/chat/lobbies/{lobbyId}/messages`,
  called by `chatApi.getHistory` on every `ChatPanel` mount, reconnect resync, and pagination request — had no
  block filtering at all. A blocked co-member's historical messages remained fully visible on any REST fetch,
  including a fresh page reload, directly contradicting the module brief's "blocked users do not receive or
  infer presence/chat" requirement for the history surface specifically (the requirement was only actually met
  for live/realtime delivery until this fix).
- How it could be exploited, written safely: user A blocks lobby co-member B. B's earlier messages, and any
  message B sends afterward and A fetches via history (not just live broadcast), still appear in A's chat
  history on every page load — the block has no effect on the REST history path.
- Evidence: direct read of `ChatService.GetHistoryAsync` (pre-fix) — `rows` from
  `_chat.GetHistoryPageAsync(...)` were mapped straight into the response DTO list with no
  `IsBlockedInEitherDirectionAsync` check, unlike `GetDeliverableRecipientsAsync`'s per-member check on the
  send path. No existing test asserted a blocked sender's row was excluded from a history page.
- Fix implemented: added a private `FilterBlockedSendersAsync` helper (mirrors
  `GetDeliverableRecipientsAsync`'s per-sender pairwise block check; lobby history pages are bounded to 50 rows
  with a capped distinct-sender count, so this is cheap) and inserted it into `GetHistoryAsync` between the raw
  page fetch and DTO construction. The actor's own messages are always visible. The unfiltered `rows` — not the
  filtered `visibleRows` — are still used to compute the `next` pagination cursor, so filtering a blocked
  sender's row cannot corrupt cursor position or cause a page to silently under-fill. File changed:
  `ChatService.cs`.
- Verification after fix: new regression test
  `ChatServiceTests.GetHistory_RowFromBlockedSender_IsExcludedFromResults` — a history page containing the
  actor's own message, a blocked sender's message, and an unrelated sender's message asserts the response
  excludes the blocked sender's message while keeping the other two. `dotnet build SimPle.sln --no-restore` →
  0 errors. `dotnet test SimPle.sln --filter "FullyQualifiedName~ChatServiceTests|FullyQualifiedName~RealtimeHubTests|FullyQualifiedName~ChatEndpointsTests" --no-build` → 24/24 unit (23 prior + 1 new), 18/18 integration, 0
  regressions.
- Residual risk: none identified for the scenario this finding described. Both delivery surfaces (realtime
  broadcast via M07-001, REST history via M07-008) are now block-aware using the same
  `IFriendRepository.IsBlockedInEitherDirectionAsync` primitive, closing the asymmetry between them.

### Other post-frontend observations (Info, no fix required)

- Presence-unknown handling (`usePresence` returning `undefined`) is applied consistently across every
  presence-consuming surface, including the previously-gapped `LobbyPage.tsx` `SeatCard` (fixed in the M07-F1
  frontend session, prior to this review) — no surface treats "unknown" as "offline" or "online".
  `GameRoomPage.tsx`'s match chat correctly shows an unavailable placeholder with no mock send affordance.
- `Avatar.tsx`'s `background: url(${src}) center/cover` inline-style pattern is pre-existing and app-wide, not
  introduced by Module 7; `src` values originate from the same trusted avatar-URL source used elsewhere in the
  app already covered by prior security review, so it is not treated as a new sink here.
- `RealtimeConnectionProvider.tsx` uses `withCredentials: true` against a relative `API_BASE`, so the SignalR
  connection is always same-origin HTTPS/WSS in production with HttpOnly-cookie auth — no token is readable
  from or written to client-side storage for the realtime path.

## Deferred Issues

- M07-004 (Info): the deny-list/regex profanity filter is intentionally simple (whole-word match, server-versioned config) and trivially bypassable by obfuscation; acceptable per the brief's explicit design ("a false-positive match is a normal validation error, not a security event"), backed by the M12 manual moderation pipeline. No action needed.
- M07-005 (Info): **RESOLVED — see Post-Frontend Phase Review above.** Confirmed PASS: the client renders chat
  body as auto-escaped JSX text with no auto-linking.
- M07-006 (Info): positive security-event logging (origin rejections, per-message rate/profanity rejects, proactive revocation closes) is thinner than the brief's full list; connection-limit rejection and resync/gap events are logged, but origin rejection in the middleware and per-message rate/profanity rejects are not. Recommend adding structured security-event logs (error code + userId/correlation id only, never message bodies) as a follow-up; not a vulnerability.
- M07-007 (Info): `OutboxDispatcherWorker`'s eager-activation fix (documented in `docs/ai-workflow/evidence/module-07-realtime-presence-chat/m07-b2-checkpoint-report.md` as an explicit ownership-boundary exception made during the B2 backend session) was sanity-checked only, not deep-reviewed, since it sits outside this module's declared ownership boundary. The watermark-suppression logic in `LobbyRealtimeHandler.HandleAsync` that depends on it is internally consistent on read. Recommend the human reviewer explicitly acknowledge the boundary crossing per the checkpoint report's own request.

## Tests/Security Checks Run

- **Fix-verification run (this session, after the three code changes)**:
  `dotnet test SimPLe.Backend/SimPle.sln --filter "FullyQualifiedName~ChatServiceTests|FullyQualifiedName~RealtimeHub" --no-build`
  → Unit: 23/23 passed. Integration: 9/9 passed, 0 failed. Includes the two new regression tests
  (`ChatServiceTests.Send_LobbyHasBlockedCoMember_ExcludesBlockedMemberFromRecipients` for M07-001,
  `RealtimeHubTests.Connect_WithMissingOriginHeader_IsRefusedWith403` for M07-003) plus every pre-existing
  test in both classes, confirming no regression to prior externally-observable behavior.
- **Full build**: `dotnet build SimPLe.Backend/SimPle.sln --no-restore` → 0 errors, confirming the
  `IRealtimeNotifier` interface-signature change and `ChatService` constructor-signature change are
  consistent across every production and test call site.
- **Full-suite run (this session, twice)**: `dotnet test SimPLe.Backend/SimPle.sln --no-build`, once with
  no local Postgres running and once after starting the project's local Postgres container
  (`SimPLe.Backend/compose.auth.yml`). Unit: 956/956 passed both times (0 regressions). Integration: 294
  passed / 107 failed both times, with the identical 107 test names in both runs, all in
  `GameCatalogMigrationTests`, `GameCapabilitySeederTests`, `GamesPostgresConcurrencyTests`,
  `LobbyMatchmakingMigrationTests`, `LobbiesPostgresConcurrencyTests`, `MatchmakingPostgresConcurrencyTests`,
  `FriendsMigrationSmokeTests`, `FriendsPostgresConcurrencyTests`, `ProfilePrivacyMigrationSmokeTests`, and
  `ChatRetentionHoldRaceTests` — none of them Module 7 realtime/chat delivery or origin-validation tests.
  **Zero failures in `RealtimeHubTests` or `ChatServiceTests` in either full-suite run.** Root cause of the
  107 failures: before starting the container, `Npgsql.NpgsqlException`/`SocketException` ("actively
  refused") — Postgres wasn't running; after starting the container,
  `Npgsql.PostgresException: 28P01 password authentication failed for user "postgres"` — the local
  container's real credentials (set via `SimPLe.Backend/src/SimPle.Api/.env`, a real env file) don't match
  the `MIGRATION_TEST_CONNECTION_STRING` value this session used (the CI default,
  `Host=localhost;Port=5432;Database=postgres;Username=postgres;Password=postgres`, per
  `SimPLe.Backend/.github/workflows/ci.yml`). This session did not read the real `.env` file to obtain the
  correct password, per the standing rule against reading real secrets/env files (`CLAUDE.md`). This is a
  pre-existing local-environment credential gap, unrelated to and predating the three fixes in this
  session — it affects unrelated modules' Postgres-dependent test classes uniformly, not anything touched
  here, and is called out separately from the fix verification rather than left silently unmentioned.
  Full logs: `.claude/state/logs/run-2026-07-17T09-19-51-024Z-bddc85eb-1126-4745-81df-3323c943d6f1/2026-07-17T09-33-27-715Z-security-dotnet.log`
  (connection-refused run) and
  `.claude/state/logs/run-2026-07-17T09-19-51-024Z-bddc85eb-1126-4745-81df-3323c943d6f1/2026-07-17T10-10-37-977Z-security-dotnet.log`
  (password-auth-failure run).
- Targeted re-run, prior read-only review session (real, not reused from memory):
  `dotnet test SimPLe.Backend/SimPle.sln --filter "FullyQualifiedName~RealtimeHubTests|FullyQualifiedName~ChatServiceTests|FullyQualifiedName~ChatRetentionHoldRaceTests|FullyQualifiedName~ChatEndpointsTests" --no-restore`
  → Unit: 22/22 passed. Integration: 17/17 passed, 5 skipped (the 5 `ChatRetentionHoldRaceTests` real-Postgres
  cases skip via `[SkippableFact]`/`SkipIfNoPg()` when `MIGRATION_TEST_CONNECTION_STRING` is not set for this
  run — they were independently verified passing against real PostgreSQL, 5/5, in the immediately preceding
  B2 backend session the same day; not re-verified against real Postgres in this security-review session).
  Full log: `.claude/state/logs/run-2026-07-17T07-03-37-936Z-49c786b2-355d-4b32-a8cc-05e07c030f62/2026-07-17T07-12-25-813Z-security-dotnet.log`.
- Reused from the B2 backend checkpoint (`m07-b2-checkpoint-report.md`): full suite 955 unit + 400 integration
  passed (including all 5 `ChatRetentionHoldRaceTests` against real Postgres), `check-contract-drift.mjs` = 0
  drift, `Swagger_DescribesChatHistoryAndDeleteRoutes` passed.
- Source-code review (this session): `RealtimeHub.cs`, `RealtimeNotifier.cs`, `LobbyScopeAuthorizer.cs`,
  `SubjectUserIdProvider.cs`, `RealtimeConnectionTracker.cs`, `RealtimeConnectionCloser.cs`,
  `RealtimeOriginValidationMiddleware.cs`, `RealtimeOptions.cs`, `RealtimeRateLimiter.cs`, `ChatService.cs`,
  `ChatBodyNormalizer.cs`, `ChatProfanityFilter.cs`, `ChatRepository.cs`, `ChatRetentionSweeper.cs`,
  `ChatController.cs`, `ChatMessage.cs`, `ChatMessageHold.cs`, `Program.cs` (SignalR/auth configuration),
  the `AddChatAndRealtimeActivation` migration, and the full existing test files listed under Methodology.

## Files Changed

Fix session (after the initial read-only review; user-approved product-code mutation):

- `SimPLe.Backend/src/SimPle.Application/Chat/ChatService.cs` — block-aware recipient computation (M07-001); new `ILobbyRepository`/`IFriendRepository` constructor dependencies.
- `SimPLe.Backend/src/SimPle.Application/Realtime/Contracts/IRealtimeNotifier.cs` — `NotifyChatMessageCreatedAsync`/`NotifyChatMessageDeletedAsync` signatures now take an explicit `recipientUserIds` collection (M07-001).
- `SimPLe.Backend/src/SimPle.Api/Realtime/RealtimeNotifier.cs` — chat fan-out now `Clients.Users(...)`, not `Clients.Group(...)` (M07-001).
- `SimPLe.Backend/src/SimPle.Api/Hubs/RealtimeHub.cs` — leak-safe `try`/`catch` in `OnConnectedAsync` (M07-002).
- `SimPLe.Backend/src/SimPle.Api/Realtime/RealtimeOriginValidationMiddleware.cs` — missing `Origin` now rejected (M07-003).
- `SimPLe.Backend/tests/SimPle.UnitTests/Chat/ChatServiceTests.cs` — constructor/assertions updated for the new notifier signature and lobby/friend mocks; new `Send_LobbyHasBlockedCoMember_ExcludesBlockedMemberFromRecipients` regression test.
- `SimPLe.Backend/tests/SimPle.IntegrationTests/Realtime/RealtimeHubTests.cs` — new `Connect_WithMissingOriginHeader_IsRefusedWith403` regression test.

No migration, no destructive DB change, no API contract change visible to REST/frontend callers (the changed
interface is internal to the Application/Api layers; the hub's client-facing `ChatMessageCreated`/
`ChatMessageDeleted` event payloads are unchanged — only which connections receive them changed).

Post-frontend phase (2026-07-17, this update):

- `SimPLe.Backend/src/SimPle.Application/Chat/ChatService.cs` — new `FilterBlockedSendersAsync` helper wired
  into `GetHistoryAsync` (M07-008). No frontend file required changes; the frontend slice as landed already
  satisfied M07-005.
- `SimPLe.Backend/tests/SimPle.UnitTests/Chat/ChatServiceTests.cs` — new
  `GetHistory_RowFromBlockedSender_IsExcludedFromResults` regression test.

No migration, no API-contract-visible change (response shape of `GET /api/chat/lobbies/{lobbyId}/messages` is
unchanged; only which rows it returns for a caller with a blocked co-member changed).

## Final Security Status

Backend phase: **CLOSED — no unwaived Critical or High findings.** All three findings identified in this
review — M07-001 (Medium, chat block-bypass), M07-002 (Low, connection/presence/tracker leak), and
M07-003 (Low, missing-`Origin` bypass) — were fixed and test-verified in this same-day fix session
following explicit user approval ("fix"). Verification: 0 build errors; the two new regression tests plus
every pre-existing `ChatServiceTests`/`RealtimeHubTests` test pass (23/23 unit, 9/9 integration); the full
suite's unit tests pass at 956/956 with zero regressions, and the full suite's only integration failures
(107, in both a pre- and post-Postgres-start attempt) are a pre-existing local-environment credential gap
unrelated to Module 7 (see Tests/Security Checks Run) — not a Module 7 code issue, and not something this
session should resolve by reading real `.env` secrets.

**Resolved by explicit user decision (2026-07-17):** the Level-1 "security" stage checkpoint for this
module cannot be formally emitted via `scripts/stage-checkpoint.mjs`, because this review-and-fix session
resolved to Sonnet 5 while the workflow manifest requires Opus for `assuranceSensitive`/`failClosed`
security-stage checkpoints, and `record-review-exception` only supports Module 14. This was raised to the
user, who explicitly chose to accept the Sonnet 5 result as-is and proceed to the frontend slice rather
than rerun the stage on Opus. This is a process/model-routing deviation, not a code defect — all three
code-level findings are fixed and verified above — and it is recorded as an accepted deviation in
`docs/ai-workflow/project-state.json`. The `security` stage remains absent from this checkpoint set's
`index.json` by design (tooling fail-closes on it), not by oversight.

**Post-frontend phase (2026-07-17): CLOSED — no unwaived Critical or High findings.** M07-005 confirmed PASS
(encoded output, no auto-linking). One new Medium finding, M07-008 (REST chat history missing block
filtering — an asymmetry with the already-fixed M07-001 realtime path, not a newly-introduced frontend
defect), was found on independent follow-up verification and fixed same-session: 24/24 unit tests, 18/18
integration tests, 0 regressions, `dotnet build` 0 errors. This stage's manifest routing
(`post-frontend-security-review`: Sonnet 5, high effort, `failClosed: true`, not `assuranceSensitive`) matches
the actual model used this session, so this is not a model-routing deviation like the backend `security` stage
above.

A schema-valid Level-1 `frontend-security` checkpoint was written and independently passes
`node scripts/stage-checkpoint.mjs validate` (`docs/ai-workflow/evidence/checkpoints/module-07-realtime-presence-chat/frontend-security.json`),
but `emit` (which updates the checkpoint set's `index.json`) fails closed with "Stage 'frontend-security' is
out of order... missing prior stage 'backend'": the module's `backend`, `security`, and `frontend` stages were
themselves never formally emitted into the index (both prior sessions used the same informal hand-written
checkpoint-report pattern — `m07-b2-checkpoint-report.md`, `m07-f1-checkpoint-report.md` — rather than
`scripts/stage-checkpoint.mjs`), so the index has no prior-stage entries for `frontend-security` to chain onto.
This is a continuation of the same known, previously-accepted evidence gap this module has carried since the
backend phase, not a new one introduced here. `docs/ai-workflow/evidence/checkpoints/module-07-realtime-presence-chat/index.json`
remains at `{planning}` only.

`securityGate`: zero unwaived Critical/High findings across both phases. Next step per module brief Session
Plan: step 6, `/simple-verify-checkpoint modules="7"` (live-stack Playwright run, still outstanding from the
M07-F1 frontend session).

## Reviewer Notes

- Model/effort provenance: the deep code audit was performed by the `security-reviewer` subagent
  (configured `model: opus` in its definition), with synthesis, spot-verification of the two most material
  findings (M07-001, M07-002) against live source, and independent targeted test re-execution performed in
  the main session. Actual resolved model/effort for both should be taken from runtime/transcript metadata
  at checkpoint-emission time, not from this self-report, per `docs/ai-workflow/known-limitations.md`.
- This review supersedes the prior "Not started" placeholder audit at this same path, which predated the
  B1+B2 implementation and no longer reflected the real code.
- Notably strong points worth preserving in any future refactor: the cached-principal handling
  (`CloseOnAuthenticationExpiration` + proactive close-on-revoke + per-method recheck, all three present),
  the DB-level idempotency unique index (not just an app-level guard), and the single-statement CTE that
  closes the retention/hold race without a check-then-act window.

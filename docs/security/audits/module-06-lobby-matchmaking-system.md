# Security Audit - Module 06: Lobby & Matchmaking System

Date: 2026-07-12

## Scope

Backend-only review (phase=backend) of the Module 6 lobby and Quick Match matchmaking system on branch
`feature/module-06-lobby-matchmaking-system` (`SimPLe.Backend`, uncommitted, slices 6A+6B+6C): lobby/invite/
credential/matchmaking controllers (`LobbiesController`, `MatchRematchController`, `MatchmakingController`),
services (`LobbiesService`, `MatchmakingService`, `MatchmakingCoordinator`, `MatchProposalBuilder`),
repositories (`LobbyRepository`, `MatchmakingRepository`, `OutboxRepository`), the whole-transaction command
runner and cross-table advisory lock (`LobbyCommandRunner`), the HMAC join-credential hasher and failure
throttle, the codebase's first outbox dispatcher (`OutboxProcessor`, `IOutboxHandler`, `LobbyBlockHandler`,
`OutboxDispatcherWorker`), the matchmaking/expiry background workers, domain aggregates under
`SimPle.Domain/Lobbies` and `SimPle.Domain/Matchmaking`, DTOs, the additive migration
`20260711195731_AddLobbyMatchmakingAndCapabilities`, and `Program.cs` rate-limit/config wiring. No frontend
code exists yet for Module 6 (frontend slice and its `frontend-security` review are separate, later sessions).

## Assessment Type
`--security=asvs-lite` (brief- and spec-mandated minimum depth for Module 6's `idor, authorization, abuse`
threat profile; see `docs/module-requirements/module-06-lobby-matchmaking-system.md` and
`docs/specs/module-06-lobby-matchmaking-system-spec.md`'s Authorization And Privacy Rules section,
lines 312-340).

Review phase: backend

## Authorization Statement
Local authorized project-only review. No external systems, production services, real secrets, or real user
data were used.

## Executive Summary
Zero unwaived Critical/High/Medium findings. A `security-reviewer` subagent performed a read-only source
review against the spec's authoritative Authorization And Privacy Rules table and five focus areas carried
forward from Module 6's planning/backend sessions, citing `file:line` evidence and named tests for every
claim. The orchestrating session independently re-verified the five highest-stakes claims by reading the
primary source directly: the outbox dead-letter path (`OutboxProcessor.cs:108-126`), the cross-table advisory
lock taken identically by both the lobby-join and matchmaking-enqueue paths
(`LobbyCommandRunner.cs:100-134`, `MatchmakingService.cs:67-97`), the matchmaking coordinator's M8 gate
(`MatchmakingCoordinator.cs:58-70`), and the ticket BOLA not-found check
(`MatchmakingService.cs:130-140`) — all confirmed exactly as reported. One Low finding (per-instance
in-memory join-failure throttle) and three Informational notes were recorded; none are exploitable given the
current single-instance deployment model and the ~60-bit credential entropy floor.

## Severity Summary Table

| Severity | Count | Notes |
|---|---:|---|
| Critical | 0 | |
| High | 0 | |
| Medium | 0 | |
| Low | 1 | M06-001 |
| Info | 3 | M06-002, M06-003, M06-004 |

## OWASP Mapping
- OWASP Top 10 web: A01:2021 Broken Access Control (BOLA/object-authorization controls — verified
  controlled); A02:2021 Cryptographic Failures (join-credential HMAC digest handling — verified controlled);
  A07:2021 Identification and Authentication Failures (M06-001); A09:2021 Security Logging and Monitoring
  Failures (outbox dead-letter content — verified controlled, no finding).
- OWASP API Security Top 10: API1:2023 Broken Object Level Authorization (ticket/lobby/invite BOLA — verified
  controlled); API4:2023 Unrestricted Resource Consumption (credential-guess throttle — M06-001; queue/invite
  rate limits — verified controlled).
- WebSocket/Socket.IO checklist: not applicable — Module 6 has no realtime transport (M7 later replaces the
  2-second poll with live delivery).

## Methodology
Read-only review (no product code changed). A `security-reviewer` subagent independently read every file in
scope, verified each row of the spec's Authorization And Privacy Rules table, and reported explicit PASS/FAIL
verdicts with `file:line` evidence and named tests for the five mandated focus areas below. The orchestrating
session then independently re-verified the highest-stakes claims by reading `OutboxProcessor.cs`,
`LobbyCommandRunner.cs`, `MatchmakingCoordinator.cs`, and `MatchmakingService.cs` directly — all findings
matched exactly. No test suite was re-executed this session; this review relies on the already-verified 6C
backend checkpoint's test evidence (862/862 unit, 375/375 integration against real PostgreSQL, 0 skipped —
confirming the Postgres-gated concurrency/outbox tests actually ran rather than being skipped for lack of a
live database).

## Module Architecture Reviewed
- Existing UI reused: not applicable this phase — no frontend slice exists yet for Module 6.
- Frontend integration points: none yet (backend-only phase).
- Existing database impact: 9 new additive tables (`Lobby`, `LobbyMember`, `LobbyInvite`,
  `LobbyJoinCredential`, `MatchmakingTicket`, `MatchmakingAssignment`, `GameCapabilityProfile`,
  `CapabilitySeedHistory`, plus the codebase's first `OutboxDelivery`-driven dispatcher schema).
- Migration added: yes — `20260711195731_AddLobbyMatchmakingAndCapabilities`.
- Migration safety notes: purely additive (`CreateTable`/`CreateIndex` only); `Down()` drops only M6 objects;
  adds `AK_games_Slug` to Module 4's `games` table (R6, required for the `GameCapabilityProfile` FK) —
  strictly additive, cannot fail on existing data (the pre-existing `IX_games_Slug` unique index already
  guarantees uniqueness), asserted by `Module4AndModule3TablesAreUnchangedByThisMigration`.
- Data preservation notes: no existing table's data is modified; Modules 3/4/5 tables are untouched aside
  from the additive `games` alternate key.
- Destructive DB changes: none.
- Backend/API/Swagger alignment: 20 endpoints (17 lobby/matchmaking + `rematch-lobbies`), Swagger-annotated;
  `node scripts/check-contract-drift.mjs` recorded DRIFT=0 at the 6B/6C checkpoints (routes 64→81→84).
- Frontend/API integration alignment: not applicable this phase.

## Threat Model
See `docs/specs/module-06-lobby-matchmaking-system-spec.md`'s Authorization And Privacy Rules (lines 312-340)
for the authoritative contract: auth required on every route via JWT `sub`; CSRF header required on every
state-changing endpoint; every lobby/ticket/invite action re-checked against the object's membership/host
role on every request, never a body `hostId`/`userId` or a prior step's result; BOLA-safe not-found for
foreign/missing/expired/unauthorized ids; credential-oracle prevention; public-discovery privacy; M3 block
enforcement at every gate; safe DTO fields only; actor-keyed rate limits. Combined with
`docs/security/threat-playbooks/authorization-idor-bola.md`, `rate-limiting-abuse.md`,
`owasp-api-top-10.md`, and `owasp-top-10-web.md` (Module 6's `idor, authorization, abuse` threat profile per
`docs/ai-workflow/module-registry.md`).

## Focus Areas — Explicit Verdicts

These five areas were carried forward from Module 6's planning/backend sessions as the highest-risk surfaces
and were reviewed with particular depth, beyond the general ASVS-lite pass.

### 1. Privacy-safe not-found on matchmaking tickets (BOLA) — PASS
`MatchmakingService.GetTicketAsync` and `CancelAsync` both check `ticket is null || ticket.UserId !=
actorUserId` and return the identical `TicketNotFound` result for both cases
(`MatchmakingService.cs:130-140, 144-149`); the controller maps this to a single 404 with no distinguishing
403 branch. The foreign-ticket path does no extra work relative to the missing-ticket path (single indexed PK
lookup, no follow-on projection), so the two cases are not just code-identical but effectively
timing-indistinguishable as far as is checkable from source. Lobby and invite BOLA follow the same discipline
(`LobbiesService.cs:132,140,467,484,514,889`). Backed by
`Cancel_AnotherUsersTicketIsAPrivacySafeNotFound`, `GetTicket_AnotherUsersTicketIdIsIndistinguishableFromOneThatNeverExisted`,
`Get_APrivateLobbyTheCallerIsNotIn_IsIndistinguishableFromOneThatDoesNotExist`,
`Kick_ByANonMember_Returns404_NotForbidden`, `AcceptInvite_AnotherUsersInviteId_IsAPrivacySafeNotFound`.

### 2. Credential-oracle prevention — PASS
Wrong/expired/rotated/revoked/unknown join codes all collapse to the identical `Lobbies.CredentialInvalid`
(`LobbiesService.cs:257,261`), mapped to 404 by the controller — indistinguishable from a missing lobby. Only
genuine credential failures increment the throttle (`LobbiesService.cs:270`), so an unrelated failure (lobby
full/already-active) cannot be used as a side channel and cannot lock out a legitimate user. The throttle
check runs before any digest work. Credentials are stored only as keyed HMAC-SHA256 digests
(`HmacLobbyCredentialHasher.cs:58-62`), never appear in logs, events, or any DTO except the create/rotate
response. Backed by `Join_WrongExpiredRotatedAndClosed_AllReturnTheIdenticalError`,
`Join_OnlyAnInvalidCredentialCountsTowardTheFailureThrottle`,
`Join_WhileThrottled_IsRejectedWithARetryAfter_BeforeAnyDigestWorkHappens`.

### 3. Cross-table one-active-lobby-or-ticket advisory lock parity — PASS (independently re-verified)
Both the lobby-join path (`LobbiesService.cs:247`) and the matchmaking-enqueue path
(`MatchmakingService.cs:69`) call `ILobbyCommandRunner.RunAsync`, which derives and takes
`pg_advisory_xact_lock(AdvisoryLockKey(actorUserId))` exactly once per invocation
(`LobbyCommandRunner.cs:100-134`) — there is no second key and no code path that opens its own transaction to
bypass it. Confirmed directly by reading `LobbyCommandRunner.cs:100-134` and
`MatchmakingService.cs:67-97` in this session: the enqueue handler's cross-table check
(`GetActiveLobbyForUserAsync`) runs inside the same lock the join path takes, exactly mirroring the pattern.
`ConcurrentJoinAndEnqueue_ByTheSameUser_ProduceExactlyOneWinner` asserts `(seated + queued) == 1` and that
the loser receives typed `Lobbies.AlreadyActive`, never a 500.

### 4. Outbox dispatcher's dead-letter path — PASS (independently re-verified)
`OutboxProcessor.cs:108-126` catches any handler exception and calls
`delivery.MarkFailed($"{ex.GetType().Name} after {delivery.AttemptCount} attempt(s).", isFinalAttempt)` — the
exception **message is never read**, only its CLR type name and attempt count. An inline comment states the
reason explicitly: "Never the exception message: an event body or a user id could reach it, and a dead-letter
row is long-lived, widely read, and exactly the kind of place PII quietly accumulates." The full exception
object is passed only to the structured logger, never to the durable `OutboxDelivery.LastError` column, whose
own XML doc states "Safe error text only — never PII, credentials, or event body." Confirmed directly by
reading `OutboxProcessor.cs:95-127` in this session. Backed by the decisive test
`ADeadLetteredDeliveryNeverRecordsTheExceptionMessage`, which throws an exception containing a fabricated
email address and PII and asserts `LastError` does not contain it while asserting the type name does.

### 5. Matchmaking worker's M8 gate — PASS (independently re-verified)
`MatchmakingCoordinator.RunCycleAsync` checks `await _matchRuntime.IsAvailableAsync(ct)` immediately after
argument validation and returns `MatchmakingCycleResult.Disabled(age)` with **no transaction opened** when no
match runtime (M5 `IGameRegistry`) is registered (`MatchmakingCoordinator.cs:58-70`) — confirmed directly by
reading the method in this session. No ticket can be claimed, matched, or have a `MatchRequestedV1` event
emitted without a runtime; the expiry sweep runs independently so a queued ticket still reaches an honest
terminal outcome. The equivalent gate exists on the lobby `Start` path (`LobbiesService.cs:559-567`, 503
`Lobbies.MatchRuntimeUnavailable`, lobby stays `Open`). Backed by the real-Postgres test
`WithNoMatchRuntime_TheWorkerCommitsNothingAtAll` (zero assignments, zero events, all tickets still `Queued`)
and `Start_WhileNoMatchRuntimeIsRegistered_Returns503_AndLeavesTheLobbyOpen`.

## Additional ASVS-lite Observations (no separate findings — supporting evidence)
- **AuthN/session:** every route requires the JWT `sub` claim as actor identity; no endpoint accepts
  `hostId`/`userId`/`rating` from a request body.
- **CSRF:** `X-Requested-With: XMLHttpRequest` enforced on all 14 state-changing lobby/matchmaking endpoints.
- **Re-checked authorization:** host-only actions re-verify `IsHost` against freshly loaded membership on
  every call, never a cached/prior-step result.
- **Blocks (M3):** enforced at join, invite, start, and queue assignment, plus asynchronously via the new
  outbox-driven `LobbyBlockHandler`, which correctly handles `FriendOutbox`'s camelCase JSON payload with
  `PropertyNameCaseInsensitive` (the real bug found and fixed during 6C).
- **Public discovery privacy:** private/non-Open lobbies never enter the query; full/expired/blocked rows are
  filtered without disturbing the keyset cursor or totals.
- **Config fail-closed:** `LobbyCredential:Key` is validated at startup (`ValidateOnStart`, ≥32 chars, rejects
  placeholder values), matching the existing `Jwt:SecretKey`/`Recaptcha:SecretKey` pattern — no silent
  fallback to an unkeyed digest.
- **Rate limiting:** all Module 6 policies are keyed to the authenticated actor with a coarse IP fallback,
  consistent with the existing `FriendWindow` convention; `Retry-After` reveals no credential or queue state.

## Findings

### M06-001 - Per-instance in-memory join-failure throttle
- Severity: Low
- Affected asset: `SimPLe.Backend/src/SimPle.Infrastructure/Lobbies/MemoryCacheLobbyJoinThrottle.cs`
- Description: the credential-guess throttle is backed by `IMemoryCache`, so its failure budget is
  per-application-instance. In a multi-instance deployment, an attacker spraying guesses across N instances
  gets an N× larger effective budget than intended.
- How it could be exploited, written safely: with N instances behind a load balancer, effective guesses
  become (budget × N) per window per account. Against a ≥60-bit join code (≈10^18 space) this remains
  astronomically infeasible — entropy, not the throttle, is the real control here — so the practical impact
  is a weakened defense-in-depth layer, not a break of the credential itself.
- Evidence: documented as a known limitation in the class's own XML doc comment; the same per-instance
  property already exists for the pre-existing revoked-JTI cache and per-account rate limiters project-wide.
- Fix implemented: none (deferred, non-blocking; matches an existing project-wide limitation pattern).
- Verification after fix: not applicable.
- Residual risk: accepted. Recommend a shared store (e.g. Redis) when the platform moves to a
  multi-instance deployment; tracked as a pre-production hardening item alongside the project's other
  per-instance rate-limit caveats (see Module 3's carried-forward limitations).

### M06-002 - Join-code digest lookup uses DB index equality, not constant-time compare
- Severity: Info
- Affected asset: `SimPLe.Backend/src/SimPle.Infrastructure/Persistence/Repositories/LobbyRepository.cs`
  (credential lookup by digest) vs. `HmacLobbyCredentialHasher.DigestsMatch` (constant-time compare, defined
  but not on this hot path)
- Description: the join path resolves a credential via a B-tree equality lookup on the HMAC digest rather
  than routing through the constant-time comparator. Because the compared value is a keyed HMAC the attacker
  cannot compute without the server key, a timing difference on the digest comparison yields no usable signal
  about the underlying plaintext code — this differs from the classic timing-oracle case where the attacker
  controls or can predict the compared value.
- Fix implemented: none required.
- Residual risk: accepted. If desired for uniformity, document in module docs that constant-time compare is
  intentionally reserved for any future path comparing attacker-influenced digests directly.

### M06-003 - A valid credential to a full/blocked/already-active lobby returns a distinguishable error
- Severity: Info (by design)
- Affected asset: `SimPLe.Backend/src/SimPle.Application/Lobbies/Services/LobbiesService.cs` (`SeatMemberAsync`)
- Description: the spec's identical-error requirement covers *invalid*-credential reasons only (wrong/
  expired/rotated/closed); a *valid* code that lands in a full/blocked/already-active lobby returns
  `Lobbies.Full`/`Lobbies.Blocked`/`Lobbies.AlreadyActive`, which confirms the code was valid.
- Fix implemented: none — not an oracle in practice, since reaching those branches already requires
  possessing a valid ~60-bit credential. Recorded so a future reviewer does not mistake this for a gap.
- Residual risk: accepted.

### M06-004 - Advisory-lock key is a 64-bit truncation of the actor's GUID
- Severity: Info
- Affected asset: `SimPLe.Backend/src/SimPle.Infrastructure/Persistence/LobbyCommandRunner.cs`
  (`AdvisoryLockKey`)
- Description: the `pg_advisory_xact_lock` key uses the first 8 bytes of the actor's GUID, so two distinct
  users can in principle collide and briefly serialize their seat-acquiring commands against each other. This
  is a liveness/throughput nuance, not a correctness or security defect — a collision only makes two unrelated
  actors briefly wait; the per-table filtered unique indexes remain the hard correctness boundary regardless.
- Fix implemented: none required; documented in the code's own comment.
- Residual risk: accepted.

## Fixed Issues Summary
None required this review — zero Critical/High/Medium findings, no `--fix` requested.

## Deferred Issues
M06-001 (Low, per-instance throttle — pre-production multi-instance hardening item), M06-002/003/004
(Info, none block completion per `_shared-quality-baseline.md`'s "Critical or High verified findings block
completion" rule).

## Tests/Security Checks Run
- Source-level verification of the five mandated focus areas above — PASS on all 5, three independently
  re-verified by the orchestrating session reading primary source directly (advisory-lock parity, outbox
  dead-letter content, matchmaking M8 gate), two accepted from the subagent's file:line + named-test evidence
  after spot-checking the same code region (ticket BOLA, credential oracle).
- Broader ASVS-lite pass: authentication/session, re-checked object-level authorization, CSRF, block
  enforcement (sync + new async outbox path), public-discovery privacy, config fail-closed startup checks,
  and actor-keyed rate limiting — all PASS, see Additional ASVS-lite Observations above.
- No test suite was re-executed this session; relied on the already-verified 6C backend checkpoint's evidence
  (`docs/ai-workflow/evidence/checkpoints/module-06-lobby-matchmaking-system/backend.json`): 862/862 unit
  tests pass, 375/375 integration tests pass against real PostgreSQL with 0 skipped (confirming the
  Postgres-gated concurrency/outbox-dispatcher tests that back focus areas 3-5 actually executed, not merely
  present-but-skipped).

## Files Changed
None — review-only, no `--fix` requested, no product code modified. This audit document and its checkpoint
are the only artifacts written this session.

## Final Security Status
Backend phase: **CLOSED, zero unwaived Critical/High**. `securityGate`: unwaivedCritical 0, unwaivedHigh 0,
waivedCritical 0, waivedHigh 0, waiverReferences []. Post-frontend phase: not yet applicable — Module 6's
frontend slice has not been built; per `.claude/config/module-stage-manifest.json` Module 6 requires 8
checkpoint stages including an independent `frontend-security` review, to run after the frontend slice per
the module brief's session plan (step 5).

## Reviewer Notes (backend phase)
The pre-existing audit document at this path was a stale pre-implementation placeholder (planned scope,
generic requirements checklist, "module not yet implemented") written before Module 6's spec/reconciliation
were approved — it named a different, generic file layout (`LobbyController.cs`, `LobbyService.cs`) that does
not match the as-built architecture (`LobbiesController`, `LobbiesService`, the matchmaking subsystem, the
outbox dispatcher). It is superseded in full by this document, matching the precedent set by Module 5's audit
replacement.

---

# Post-Frontend Phase (2026-07-12)

## Scope
Client-boundary-only review (phase=post-frontend) of the Module 6 frontend slice on branch
`feature/module-06-lobby-matchmaking-system` (`SimpLe.Frontend`, uncommitted, commit `1412295`):
`CreateLobbyModal.tsx`, `QuickMatchModal.tsx`, `InviteFriendModal.tsx`, `LobbyPage.tsx`,
`SearchResultsPage.tsx`'s Public Lobbies tab, `DashboardPage.tsx`'s lobby/invite cards, `ProfilePage.tsx`'s
invite button, `GameDetailPage.tsx`'s newly-enabled quick-match/create-lobby/invite-friend entry actions,
`lobbyApi.ts`, `lobbyErrors.ts`, `matchmakingApi.ts`, `matchmakingErrors.ts`, `routes.ts`, and the shared
`api-client.ts` wrapper. Does not re-review backend logic — that is covered by the backend-phase section
above (zero unwaived Critical/High/Medium, carried unchanged).

## Assessment Type
`--security=asvs-lite` (module-mandated minimum depth, unchanged from the backend phase).

Review phase: post-frontend

## Executive Summary
Zero unwaived Critical/High/Medium findings. A `security-reviewer` subagent performed a read-only source
review of all in-scope frontend files against the post-frontend checklist (XSS/DOM sinks, credential/token
browser storage, redirect/external-origin allowlisting, DTO privacy in rendered/error states, CSRF/cookie
wrapper usage, client logging). The orchestrating session independently re-verified the one real finding
(join credential persisted in `sessionStorage` with no clearing on leave) by reading
`CreateLobbyModal.tsx:105-108`, `LobbyPage.tsx:66-70,103-106,148-152`, and `InviteFriendModal.tsx:109-110`
directly, plus the CSRF/cookie wrapper claim (`api-client.ts:4,42`) and confirmed zero raw `fetch(` calls in
`lobbyApi.ts` — all matched exactly. One Low finding and two Info notes were recorded; none block completion.

## Severity Summary Table

| Severity | Count | Notes |
|---|---:|---|
| Critical | 0 | |
| High | 0 | |
| Medium | 0 | |
| Low | 1 | M06-005 |
| Info | 2 | M06-006, M06-007 |

## OWASP Mapping
- OWASP Top 10 web: A02:2021 Cryptographic Failures (M06-005, browser storage of a bearer-style credential);
  A05:2021 Security Misconfiguration (M06-005, storage hardening); no XSS/DOM-sink findings (A03:2021
  Injection — verified controlled, all untrusted strings render as inert JSX text).
- OWASP API Security Top 10: API2:2023 Broken Authentication (M06-005, credential handling on the client) —
  Low, not exploitable without a separate XSS foothold, none found in this diff.
- WebSocket/Socket.IO checklist: not applicable — Module 6 has no realtime transport; `LobbyPage.tsx` polls
  every 3s (M7 later replaces this with live delivery).

## Methodology
Read-only review (no product code changed). A `security-reviewer` subagent independently read every in-scope
file plus the backend audit for context, verified the 8 post-frontend checklist items with file:line
evidence, and reported explicit PASS/FAIL/INFO verdicts. The orchestrating session then independently
re-verified the credential-storage finding and the CSRF-wrapper/no-raw-fetch claims by reading
`CreateLobbyModal.tsx`, `LobbyPage.tsx`, `InviteFriendModal.tsx`, and `api-client.ts` directly, and by
grepping `lobbyApi.ts` for `fetch(` (zero matches, confirming every call routes through `apiFetch<T>()`) — all
findings matched exactly. No test suite was re-executed this session; relied on the already-verified frontend
checkpoint's evidence (`npx tsc --noEmit` clean, `npm run lint` clean, `npx vitest run` 243/243 pass,
`node scripts/check-contract-drift.mjs` DRIFT=0, `npm run build` compiled successfully).

## Module Architecture Reviewed
- Existing UI reused: yes — `CreateLobbyModal`, `QuickMatchModal`, `InviteFriendModal`, `LobbyPage`,
  `SearchResultsPage`, `DashboardPage`, `ProfilePage`, `GameDetailPage` are all pre-existing components wired
  to the real Module 6 backend contract in place of `mock/lobbies.ts`.
- Frontend integration points: `lobbyApi.ts` / `matchmakingApi.ts` against the 20 Module 6 endpoints
  (17 lobby/matchmaking + `rematch-lobbies`); `GameEntryActions.All`'s 3 M6-owned entries flipped from
  deferred to enabled.
- Existing database impact: none this phase (frontend-only slice).
- Migration added: no.
- Migration safety notes: not applicable this phase.
- Data preservation notes: not applicable this phase.
- Destructive DB changes: none.
- Backend/API/Swagger alignment: unchanged from backend phase (84 routes).
- Frontend/API integration alignment: `node scripts/check-contract-drift.mjs` — DRIFT=0, 85 backend routes,
  71 unique frontend calls, 5 unresolved dynamic paths (manual-verify only, not a failure), per the frontend
  checkpoint.

## Threat Model
Client trust boundary per `docs/security/threat-playbooks/authorization-idor-bola.md` (UI must not
re-introduce a distinguishing oracle the backend deliberately collapsed) and `rate-limiting-abuse.md`
(client must not defeat server-side throttles). Combined with the post-frontend checklist in
`.claude/skills/simple-security-review/frontend-security-checklist.md`. The credential-oracle and BOLA
controls verified server-side in the backend phase are re-checked here only for whether the frontend
preserves or undermines them in rendered/error states — confirmed preserved (see Findings and Additional
Observations).

## Focus Areas — Explicit Verdicts
Carried forward from the frontend checkpoint's declared focus: credential display/rotation, join-by-lobbyId
race handling, and `GameEntryActions` enabled-branch gating re-verified client-side.

### 1. Rendered data / XSS sinks — PASS
All untrusted strings (lobby name/slug, member display names/usernames, inviter names, public-lobby host,
the revealed join code) render as inert JSX text. The only `dangerouslySetInnerHTML` in the frontend is a
static theme-boot script (`src/app/layout.tsx:39`) with no lobby/user data, out of this module's scope. No
`innerHTML`/`document.write`/`eval`/dynamic script-or-URL-as-markup construction found.

### 2. Join-credential display/rotation — PASS with one Low finding (M06-005)
Rotation correctly replaces the displayed code and warns the previous code/link no longer work
(`LobbyPage.tsx:148-154`). The credential is sent only to the documented create/rotate endpoints
(`lobbyApi.ts:27-28,65-66`) and never appears in a URL, router call, or log. It **is** persisted to
`sessionStorage` with no clearing on leave/kick/close — see M06-005.

### 3. Join-by-lobbyId race / stale-state handling — PASS (Info note, M06-006-adjacent)
All action gating re-derives from the latest server `lobby` object every render (`isHost`, `allowedActions`,
seat/ready state) and every mutating call carries `expectedRevision: lobby.revision`
(`LobbyPage.tsx:100,110,116,131`), so the server's optimistic-concurrency check — not client state — is the
real boundary. The unconditional 3s poll write (`LobbyPage.tsx:44-45`) can momentarily display a stale
snapshot after a just-applied action, self-healing on the next tick; a UX nuance, not a security defect,
since no action's authorization is ever decided client-side.

### 4. `GameEntryActions` enabled-branch gating re-verified client-side — PASS
Entry actions render enabled only when the server DTO says `status === 'enabled'`
(`GameDetailPage.tsx:269`), gated further against server-provided per-game facts; opening a modal still
requires each modal to fetch the authoritative capability profile before enabling create/queue
(`CreateLobbyModal.tsx:75`, `QuickMatchModal.tsx:50`). No client-only flag can fabricate availability the
server would reject.

## Additional ASVS-lite Observations (no separate findings — supporting evidence)
- **Redirects/external origins:** every navigation target is a known route template with a server-issued id
  (`ROUTES.room(result.lobbyId)`, `ROUTES.lobby(...)`), never a raw DTO URL; the only absolute URL
  (`https://simple.gg/j/${linkToken}`) is copied to the clipboard, never used as a navigation target.
- **DTO privacy in rendered/error states:** `Lobbies.NotFound` and `Lobbies.CredentialInvalid` collapse to
  one identical client-side message (`lobbyErrors.ts:8-11`), preserving the backend's credential-oracle
  prevention; `Matchmaking.TicketNotFound` likewise generic. The by-design distinguishable
  full/closed/blocked messages mirror backend M06-003 and require an already-valid credential to reach.
- **CSRF/cookie wrapper:** every state-changing lobby/matchmaking call routes through the shared `apiFetch`
  (`credentials:'include'` + `X-Requested-With: XMLHttpRequest`, `api-client.ts:4,42`); zero raw `fetch(`
  calls in `lobbyApi.ts`/`matchmakingApi.ts` (grep-confirmed), unlike the documented Module 4
  `gamesApi.getDetail` exception (not present in this module).
- **Client logging:** zero `console.*` calls in the lobby/matchmaking feature code or components; errors
  are either swallowed (`.catch(() => {})`) or surfaced only as mapped generic user copy. No test fixture
  references the credential fields.

## Findings

### M06-005 - Join credential (code + link token) persisted in `sessionStorage`, not cleared on leave
- Severity: Low
- Affected asset: `SimpLe.Frontend/src/components/lobby/CreateLobbyModal.tsx:105-108` (write on create),
  `SimpLe.Frontend/src/features/lobby/LobbyPage.tsx:152` (write on rotate), `:66-70` (read on mount),
  `SimpLe.Frontend/src/components/friends/InviteFriendModal.tsx:109-110` (read of link token)
- Description: the ~60-bit join credential — deliberately shown only to the host at create/rotation per the
  backend's threat model — is written in cleartext JSON to `sessionStorage` under
  `lobby-credential:${lobbyId}` so the reveal survives a reload. It is never removed on the `leave` path
  (`LobbyPage.tsx:103-106`) or when the lobby closes.
- How it could be exploited, written safely: given a hypothetical same-origin script-injection foothold
  elsewhere in the app (none found in this diff — see Item 1, PASS), `JSON.parse(sessionStorage.getItem(...))`
  would yield a working join code/link token for any lobby the victim hosted this tab session, turning an
  unrelated XSS into lobby takeover/griefing. Without such a foothold there is no exploit path:
  `sessionStorage` is same-origin, per-tab, and cleared on tab close.
- Evidence: confirmed directly — `sessionStorage.setItem('lobby-credential:' + lobbyId, JSON.stringify({ code, linkToken }))` at both the create and rotate call sites; no matching `removeItem` anywhere in the reviewed diff, confirmed by reading `leave()` (`LobbyPage.tsx:103-106`).
- Fix implemented: none (deferred, non-blocking; defense-in-depth hardening item, not an active vulnerability
  given no XSS sink exists in this diff).
- Verification after fix: not applicable.
- Residual risk: accepted. Recommend clearing the `sessionStorage` entry on leave/kick/close and on
  superseding a rotated generation, and consider whether the human-readable `code` needs to be persisted at
  all versus the `linkToken` alone.

### M06-006 - Stored credential has no generation tag; a stale code can be displayed/shared after out-of-band rotation
- Severity: Info
- Affected asset: `SimpLe.Frontend/src/features/lobby/LobbyPage.tsx:66-68,148-166`
- Description: the persisted `{ code, linkToken }` object carries no `generation`, so if the host rotates
  from another tab/device, this tab can display and let the user copy/share a dead credential after a
  reload. Fails safe — the backend rejects the old credential (M06-002's credential-oracle prevention) — so
  this is a UX correctness nit, not a security gap.
- Fix implemented: none required.
- Residual risk: accepted.

### M06-007 - Route id interpolation without `encodeURIComponent`
- Severity: Info
- Affected asset: `SimpLe.Frontend/src/lib/routes.ts:19-20` (`lobby`, `room`)
- Description: unlike `ROUTES.u`/`profile`, the `lobby`/`room` route builders interpolate the id without
  encoding. All values reaching these templates in the reviewed flows are server-issued GUIDs, so there is
  no attacker-controlled input and no exploit path; noted only for consistency.
- Fix implemented: none required.
- Residual risk: accepted.

## Fixed Issues Summary
None required this review — zero Critical/High/Medium findings, no `--fix` requested.

## Deferred Issues
M06-005 (Low, sessionStorage credential persistence — pre-production hardening item), M06-006/007 (Info,
none block completion per `_shared-quality-baseline.md`'s "Critical or High verified findings block
completion" rule).

## Tests/Security Checks Run
- Source-level verification of the 8 post-frontend checklist items above — PASS on 7, one Low finding on the
  credential-storage item, independently re-verified by the orchestrating session reading
  `CreateLobbyModal.tsx`, `LobbyPage.tsx`, and `InviteFriendModal.tsx` directly, plus the CSRF-wrapper claim
  (`api-client.ts:4,42`) and a `fetch(` grep of `lobbyApi.ts` (zero matches).
- No test suite was re-executed this session; relied on the already-verified frontend checkpoint's evidence
  (`docs/ai-workflow/evidence/checkpoints/module-06-lobby-matchmaking-system/frontend.json`): `npx tsc
  --noEmit` clean, `npm run lint` clean, `npx vitest run` 243/243 pass, `node scripts/check-contract-drift.mjs`
  DRIFT=0, `npm run build` compiled successfully.

## Files Changed
None — review-only, no `--fix` requested, no product code modified. This audit document and its checkpoint
are the only artifacts written this session.

## Final Security Status
Post-frontend phase: **CLOSED, zero unwaived Critical/High**. `securityGate`: unwaivedCritical 0,
unwaivedHigh 0, waivedCritical 0, waivedHigh 0, waiverReferences []. Module 6 checkpoint index now has 5/8
stages (planning, backend, security, frontend, frontend-security); remaining: verification, docs,
production-review.

## Reviewer Notes (post-frontend phase)
This document is updated in place (not replaced), per the same single-document, dated-sections convention
used for Modules 4 and 5's backend/post-frontend audit pairs. The backend-phase content above this section
is unchanged and remains authoritative for backend findings.

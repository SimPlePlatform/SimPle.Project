# Security Audit - Module 3: Friends & Social Graph

Date: 2026-07-05 (backend re-audit); **frontend scope added 2026-07-06**; **M03-006/M03-007 fixed 2026-07-06**
(this pass)

## Scope

Backend security review of the **reconciled** Module 3 implementation (planning + Sub-sessions A/B/C,
2026-07-05/06) on branch `feature/module-03-friends-social-graph`. The prior 2026-06-29 audit described the
pre-reconciliation code (14 endpoints, `403` IDOR, `friend-request`/`friend-block` limiters, `Friends.Blocked`
400, offset paging, level/ELO in DTOs) and is now stale; this audit replaces it against the current source.

**Backend source reviewed:**
- `SimPle.Api/Controllers/FriendsController.cs` (16 endpoints, `[Authorize]`, CSRF, per-endpoint rate-limit attributes, `MapError`)
- `SimPle.Api/Program.cs` (rate-limiter policies `friend-send` / `friend-discovery` / `friend-suggestions` / `friend-block`; `OnRejected`; middleware order)
- `SimPle.Application/Friends/Services/FriendsService.cs`
- `SimPle.Application/Friends/Outbox/FriendOutbox.cs`
- `SimPle.Application/Friends/DTOs/*.cs` (12 DTOs incl. `DiscoveryResultDto`, `SendFriendRequestResult`, `BlockUserResult`)
- `SimPle.Application/Friends/Validators/*.cs`
- `SimPle.Infrastructure/Persistence/Repositories/FriendRepository.cs`
- `SimPle.Domain/Friends/*.cs`, `SimPle.Domain/Outbox/*.cs`
- Migrations `20260627154911_AddFriendsAndBlocks`, `20260705120243_HardenFriendsSocialGraph`

**Frontend source reviewed (this pass, 2026-07-06, `--scope=frontend`, `--security=asvs-lite`, `--fix` not
requested):**
- `SimpLe.Frontend/src/features/friends/friendsApi.ts`, `types.ts`, `friendsErrors.ts`
- `SimpLe.Frontend/src/features/friends/FriendsPage.tsx`, `AddFriendModal.tsx`, `FriendSummaryContext.tsx`
- `SimpLe.Frontend/src/lib/api-client.ts` (`apiFetch` — CSRF header, credential/cookie handling, `ApiError` shape)
- Consumers: `SimpLe.Frontend/src/components/layout/Sidebar.tsx`, `AppShell.tsx`,
  `SimpLe.Frontend/src/features/dashboard/DashboardPage.tsx`,
  `SimpLe.Frontend/src/components/friends/InviteFriendModal.tsx`,
  `SimpLe.Frontend/src/features/settings/SettingsPage.tsx` (privacy tab + block-list panel),
  `SimpLe.Frontend/src/features/profile/ProfilePage.tsx` (friend count display only)
- Vitest suites: `friendsApi.test.ts`, `FriendsPage.test.tsx`, `DashboardFriends.test.tsx`,
  `SidebarFriendBadge.test.tsx`, `FriendSummaryContext.test.tsx`

**Threat playbook:** `docs/security/threat-playbooks/friends-social-graph.md` (profile tags: idor, bola, privacy, abuse).
**Spec / contract:** `docs/specs/module-03-friends-social-graph-spec.md`;
`SimPle.Project/docs/modules/module-03-friends-social-graph/api-reference.md`.

`--fix` was **not** requested for the backend or frontend review passes above — those two passes changed no
product code. **A follow-up `--fix` pass (2026-07-06, same session) closed both open findings** — see "Fixed
Issues Summary" below.

## Assessment Type

ASVS-lite (mandatory minimum for this module; not downgraded). Not a white-box pentest.

## Authorization Statement

Local authorized project-only review. No external systems, production services, real secrets, or real user data were used. The NuGet advisory scan queried the public advisory database only.

## Executive Summary

The reconciled backend is well-hardened against the module's threat profile. All 16 endpoints require
authentication; all 9 state-changing endpoints require the CSRF header; every object-level-authorization denial
(accept/decline/cancel/remove/dismiss on an id the caller does not own) returns an **identical `Profile.NotVisible`
404**, eliminating the enumeration/existence oracle that a `403` would create (R8). Discovery is written to do the
same membership/visibility work whether or not the account exists, removing a timing side-channel (verified on
real Postgres in Sub-session C). Blocks are bidirectional and re-checked at accept time; block+unfriend and the
transactional outbox commit as a single unit of work with minimum-id (redacted) payloads. Per-account fixed-window
rate limiters sit in the correct `Authentication → RateLimiter → Authorization` order and emit `Retry-After`.

**No Critical or High production findings.** The one **Low** finding (M03-007) and one **Medium** finding
(M03-006) are both **fixed** (2026-07-06, see "Fixed Issues Summary"). The prior Low (M03-001) is **resolved on
the Module 3 surface** by R8. Two High NuGet advisories exist only in the **test toolchain** (`System.Net.Http` /
`System.Text.RegularExpressions` 4.3.0, transitive) and are not shipped to production.

**Frontend addendum (2026-07-06):** the frontend is a thin logic/integration layer over the hardened backend and
introduces **no new Critical/High/Medium/Low findings**. Every mutation goes through the shared `apiFetch()`
wrapper, which attaches the CSRF header (`X-Requested-With`) on every non-GET call and sends `credentials:
'include'` — there is no fetch call in the friends feature that bypasses this wrapper. Request bodies are built
from an explicit allow-list (`{ targetUserId }`, `{ targetUserId, idempotencyKey }`, `{ friendRequestPrivacy }`)
constructed from literals and server-issued ids (never a client-editable object spread), so the frontend cannot be
used to smuggle server-owned fields (`state`, `requesterId`, `domainVersion`, etc.) — consistent with the backend's
allow-list binding. `Profile.NotVisible` 404s are handled generically everywhere (`friendsErrorMessage` →
"User not found.") with no branch that reveals *why* a target is hidden, so the UI does not reintroduce the
enumeration oracle the backend closed. `Friends.RequestCooldown` / `RateLimit.Exceeded` correctly surface
`retryAfterUtc` via `formatRetryAfter()` without exposing raw internals. No `console.*`, `localStorage`,
`sessionStorage`, or `dangerouslySetInnerHTML` usage exists anywhere in the friends feature. `FriendSummaryContext`
correctly clears cached counts when auth status leaves `authenticated`, so no stale-session data can leak across a
logout. **M03-007 was not amplified by the frontend even before the fix:** `FriendsPage.handleBlock` never read
the identity fields back out of `BlockUserResult` — it renders only the pre-known `confirmAction.displayName`
captured before the call. The backend fix (2026-07-06) removed those fields from `BlockUserResult` entirely, and
the frontend `BlockUserResult` type was updated to match (`blockedUserId`/`blockedAt` only) — `handleBlock`
required no logic change since it never depended on the removed fields. `InviteFriendModal`'s "send invite"
action is fully mocked (no backend call; deferred to M6/M8/M9 per
the module registry) and only reads the caller's own friends list, so it has no live authorization surface yet.
Targeted vitest run: **61/61 passed** across the five friends-related suites, including numerous privacy-safe-404
assertions across discovery, dismiss, and block/accept/decline/cancel flows. `npm run lint` clean.

## Severity Summary Table

| Severity | Count | Notes |
|---|---:|---|
| Critical | 0 | |
| High | 0 | 2 transitive High advisories in the **test toolchain only** — informational, not deployed |
| Medium | 0 | M03-006 — no audit logging — **fixed 2026-07-06** |
| Low | 0 | M03-007 — block endpoint identity-card disclosure — **fixed 2026-07-06** |
| Info | 5 | see Deferred Issues / Reviewer Notes |

## OWASP Mapping

- **OWASP Top 10 web:** A01 Broken Access Control (BOLA/IDOR guards, block precedence, privacy gates); A04 Insecure Design (abuse throttles, cooldowns, atomic state machine); A05 Security Misconfiguration (rate-limiter registration + middleware order); A09 Security Logging & Monitoring Failures (M03-006, **fixed**).
- **OWASP API Security Top 10:** API1 Broken Object Level Authorization (accept/decline/cancel/remove/settings/unblock all actor-scoped → 404); API2 Broken Authentication (`[Authorize]` + JWT `sub`); API3 Broken Object Property Level Authorization (minimal DTOs; mass-assignment-safe request bodies; **M03-007 fixed**); API4 Unrestricted Resource Consumption (keyset paging bounds + per-account rate limits; secondary caps deferred); API6/API7 (privacy-safe error surface); API8 Security Misconfiguration.
- WebSocket/Socket.IO checklist: not applicable (no realtime surface in Module 3; presence/notifications deferred to M7/M11).

## Methodology

Authorized static code review of controller, application service, repository, DTOs, validators, domain entities,
outbox builder, EF configurations, migrations, and rate-limiter configuration; DTO field inspection for
over-exposure; authorization/ownership tracing per endpoint; block-precedence and privacy-gate tracing; error-code
→ HTTP-status mapping review; and a public NuGet advisory scan. Concurrency/atomicity and timing-parity claims are
corroborated by the Sub-session C real-Postgres evidence recorded in the backend checkpoint
(`docs/ai-workflow/evidence/checkpoints/module-03-friends-social-graph/backend.json`); this review did not re-run
the disposable-Postgres suite.

## Module Architecture Reviewed

- **Existing UI reused:** yes — the dirty `ui`-branch Module 3 frontend was reconciled to the realigned contract
  (logic/integration only); visual design preserved, no redesign.
- **Frontend integration points:** cursor-paged lists (`CursorPage<T>`), outcome discriminators (201 vs 200 on
  send/block), safe discovery (`AddFriendModal`), suggestion dismiss (optimistic + rollback), cooldown/rate-limit
  `Retry-After` surfacing, and the friend-summary badge (`Sidebar`/`DashboardPage`) — per `api-reference.md`.
- **Existing database impact:** additive. Two forward-only migrations; `HardenFriendsSocialGraph` adds columns with defaults, 3 tables (outbox message/delivery, dismissed suggestion), unordered-pair + keyset + outbox-idempotency indexes, a no-self-dismissal CHECK, and an idempotent legacy backfill.
- **Migration added:** yes (`20260705120243_HardenFriendsSocialGraph`, in addition to `20260627154911_AddFriendsAndBlocks`).
- **Migration safety notes:** forward-only, additive; snapshot consistent (`has-pending-model-changes` = none per backend checkpoint). `Down()` drops current Module 3 tables — back up before any production rollback.
- **Data preservation notes:** legacy social rows backfilled idempotently; no destructive data operation in the up path.
- **Destructive DB changes:** none.
- **Backend/API/Swagger alignment:** every endpoint carries `SwaggerOperation` + `ProducesResponseType`; `api-reference.md` realigned 2026-07-06.
- **Frontend/API integration alignment:** confirmed for this pass — `check-contract-drift.mjs` reported DRIFT=0
  at the frontend-slice checkpoint (2026-07-06); no client-side trust of server-owned fields found in this review.

## Threat Model

Primary risks for a social graph (per playbook): accepting requests not addressed to you, cross-user
cancel/remove, block bypass, private-relationship leakage, request flooding, and graph/account enumeration.
Controls mapped below. Trust boundary is the authenticated JWT `sub`; every mutation and read is scoped to it.
The outbox is an internal producer for M11 (notifications) and must not carry profile snapshots or block reasons.

**Attack scenarios considered**

| Scenario | Verdict |
|---|---|
| Accept/decline a request you are not the addressee of (guessed id) | `f.AddresseeId != actorId` → identical `Profile.NotVisible` 404 |
| Cancel a request you did not send | `f.RequesterId != actorId` → 404 |
| Remove / mutate an A–C edge you are not party to | `GetEdgeAsync(actorId, other)` only matches edges where actor is a party → 404 |
| Unblock / read a block you did not create | `GetBlockAsync(actorId, …)` scoped to `BlockerId == actorId` |
| Read another user's settings | `GetSettingsAsync(actorId)` uses JWT sub only |
| Send to a private / blocked / suspended / nonexistent target | Identical `Profile.NotVisible` 404 (no distinction) |
| Enumerate accounts by discovery response **timing** | Symmetric work via `probeId = Guid.Empty`; timing parity verified on real PG (Sub-session C) |
| Enumerate accounts by discovery **outcome** | Ineligible (private/Off/blocked/FoF-with-0-mutual/nonexistent) → identical 404 |
| Send to a user who blocked you, then accept after a late block | Bidirectional block check at **send and accept**; committed block wins the accept-vs-block race (xmin) |
| Duplicate / reverse-direction request race | Unordered-pair unique index → `23505` convergence; reverse pending → atomic cross-accept |
| Self-request / self-block | Service check + DB CHECK (`ck_no_self_friendship` / `ck_no_self_block`) |
| Re-request flooding after decline/cancel | Requester cooldown (decline 7d / cancel 24h) → `Friends.RequestCooldown` 409 + `Retry-After` |
| Request/block flooding | Per-account fixed-window limiters (send 10/min, block 20/min, discovery 30/min, suggestions 30/min) |
| Mass assignment via request body | Bodies are `{TargetUserId}` / `{FriendRequestPrivacy}` only |
| SQL injection | All EF/LINQ, parameterized; only static migration DDL |
| Outbox leaks profile/PII to notification consumer | Payloads carry ids only (relationshipId/requesterId/addresseeId, blockId/blocker/blocked) |
| Block endpoint reveals a private user's identity card by GUID | **Fixed (M03-007)** — `BlockUserResult` no longer carries any target identity field |
| Frontend bypasses CSRF header or sends server-owned fields (`state`, `requesterId`, `domainVersion`) on a mutation | Not possible — every mutation routes through `apiFetch()`, which always attaches the CSRF header on non-GET calls; request bodies are hand-built allow-lists, not object spreads of server DTOs |
| Frontend re-exposes *why* a target is hidden (private vs blocked vs nonexistent) beyond the backend's identical 404 | Not possible — `friendsErrorMessage()` maps every `Profile.NotVisible` to the same "User not found." with no branch on hidden reason |
| Frontend amplifies M03-007 by rendering the block response's identity card for an otherwise-hidden target | Not possible — `handleBlock` never reads `BlockUserResult`'s card fields; UI shows only the pre-known display name captured before the call |
| Stale friend/summary counts persist in the UI across a logout/login as a different user | Not possible — `FriendSummaryContext` clears `summary`/`error` and stops loading when `useAuth().status` leaves `authenticated` |

## Findings

### M03-007 - Block endpoint echoes target identity card, bypassing the Private-visibility and block-precedence gates
- **Severity:** Low
- **Status:** **Fixed (2026-07-06)**
- **ASVS ref / OWASP:** V4.2 object-level property authorization; API3 / A01
- **Affected asset:** `POST /api/friends/blocks` → `FriendsService.BlockUserAsync` (previously returned `BlockUserResult` containing a full `BlockDto`: username, displayName, initials, color, presigned avatarUrl).
- **Description:** Every other identity-bearing endpoint (`Discover`, `SendFriendRequest`) returns `Profile.NotVisible` 404 for a target that is Private (and not a friend), suspended, or that has blocked the caller. `BlockUserAsync` performed only `GetByIdAsync(targetUserId)` + self-check, then returned the target's identity card for **any** existing user id — including a Private-profile user or a user who has blocked the caller. The Private-visibility gate and block-precedence that protect identity elsewhere were not applied on this path.
- **How it could be exploited, written safely:** An authenticated caller who already holds a target's user **GUID** (v4, non-enumerable) could `POST /api/friends/blocks` and read back the target's current username/displayName/avatar even if that user is Private or has blocked the caller — then immediately `DELETE` the block. This let a blocked party harvest the blocker's current identity card, partially defeating the protective intent of the block. It also distinguished an existing id (201/200 + card) from a nonexistent id (404), a user-existence oracle — negligible on its own given GUIDs are non-enumerable.
- **Evidence (pre-fix):** `FriendsService.cs` `BlockUserAsync` (built `dto` from `target` before any visibility/block gate); `BlockUserResult`/`BlockDto` carried the identity fields; contrast `DiscoverByUsernameAsync` and `SendFriendRequestAsync`, which gate on `Visibility == Private` and `IsBlockedInEitherDirectionAsync` → 404.
- **Fix implemented (Option A from the original recommendation):** `BlockUserResult` (`SimPle.Application/Friends/DTOs/BlockUserResult.cs`) now carries only `Outcome`, `BlockedUserId`, `BlockedAt` — no identity fields at all. `FriendsService.BlockUserAsync` no longer builds an identity-card DTO for this path (`BuildBlockDtoAsync` removed as dead code); `GET /api/friends/blocks` (the caller's own block list) is unaffected and still returns the full `BlockDto` since that is the caller's own data, not a leak. Frontend `BlockUserResult` type updated to match; `FriendsPage.handleBlock` required no change since it never read the removed fields.
- **Verification after fix:** New integration test `BlockUser_PrivateTarget_ResponseDoesNotExposeIdentityCard` (`FriendEndpointsTests.cs`) blocks a Private-visibility target and asserts the 201 response body contains `blockedUserId` but not the target's username/displayName or any `blockedUsername`/`blockedDisplayName`/`blockedAvatarUrl` field. Full backend `dotnet build` green; targeted `dotnet test` — UnitTests (Friends) 68/0, IntegrationTests (Friends) 63/0 (includes the new test and all pre-existing block/unblock tests, unaffected). Frontend `npx tsc --noEmit` clean, targeted `vitest` 81/0 across 7 friends-related suites, `npm run lint` clean, `check-contract-drift.mjs` DRIFT=0.
- **Residual risk:** None — the identity-card disclosure vector is closed. (The existing-vs-nonexistent-id timing/outcome distinction remains, as already accepted as Info-level in Deferred Issues; GUIDs are non-enumerable.)

### M03-006 - No security audit logging for friend/block/unfriend actions
- **Severity:** Medium
- **Status:** **Fixed (2026-07-06)**
- **ASVS ref / OWASP:** V7.2 log security events; A09
- **Affected asset:** `FriendsService` (previously no `ILogger` dependency; no security event emitted for send/accept/decline/cancel/remove/block/unblock).
- **Description:** Abuse patterns (block harassment, serial unfriending, request flooding across rate windows) left no application-level security event trail and could not be investigated retroactively. Rate limiting mitigates real-time abuse but not forensics.
- **How it could be exploited, written safely:** An abuser operating within per-account rate limits (e.g., mass-blocking many accounts over time) left no queryable security-event record for later moderation.
- **Evidence (pre-fix):** `FriendsService` constructor took `IFriendRepository`, `IUserRepository`, `IFileStorageService`, `IOptions<StorageOptions>` — no logger/audit sink. The reconciled outbox is an **integration** event stream for M11, not a security/audit log.
- **Fix implemented:** `FriendsService` now takes an `ILogger<FriendsService>` (DI-resolved; no registration change needed) and emits structured `Security: ...` log lines — the exact convention already established in Module 1's `AuthService` (e.g. `"Security: Login success. UserId={UserId} Ip={Ip}"`), applied here rather than inventing new cross-cutting infrastructure. Logged transitions: friend request sent (new + reactivated-after-cooldown-expiry), cross-request accepted (via send), request accepted, request declined, request cancelled, friend removed, user blocked, user unblocked. Idempotent no-op repeats (e.g. re-sending to an already-pending target) are intentionally not logged to avoid noise — only actual state transitions are. This closes the audit-trail gap using the platform's existing logging pipeline (whatever sink/aggregator already ingests `ILogger` output for Module 1) rather than a new sink, consistent with "no new cross-cutting infrastructure without approval."
- **Verification after fix:** Full backend `dotnet build` green; targeted `dotnet test` — UnitTests (Friends) 68/0, IntegrationTests (Friends) 63/0 (all pass with the new `ILogger` dependency injected via `NullLogger<FriendsService>.Instance` in unit tests).
- **Residual risk:** None for Module 3's own actions. Cross-module correlation/alerting on these log lines (e.g. a SIEM query or an admin-facing audit view) is a separate, larger platform capability and remains out of scope here, same as it is for Module 1/2's existing `Security:` log lines.

### M03-001 - Block-existence inference on the friend-request surface (carried) - RESOLVED on the Module 3 surface
- **Severity:** Info (was Low)
- **Status:** Resolved on Module 3 endpoints by reconciliation R8.
- **Description:** Previously, sending to a user who had blocked you returned `Friends.Blocked` 400, letting a caller infer a block. The reconciled send path now returns an **identical `Profile.NotVisible` 404** for blocked, Private-non-friend, suspended, and nonexistent targets, so the friend-request surface no longer distinguishes a block from any other invisibility. Residual inference exists only on the **Module 2** profile-view surface (`Profile.Blocked`), which is out of Module 3 scope; carry the direction-neutrality acceptance note into the Module 2 audit/spec.
- **Residual risk:** Info.

## Fixed Issues Summary

Both open findings from the 2026-07-05/06 review were fixed in a same-session follow-up pass (2026-07-06):

| ID | Severity | Fix | Verification |
|---|---|---|---|
| M03-007 | Low | `BlockUserResult` stripped to `Outcome`/`BlockedUserId`/`BlockedAt` — no target identity fields on the block-response path, regardless of the target's visibility. | New integration test `BlockUser_PrivateTarget_ResponseDoesNotExposeIdentityCard`; full targeted backend + frontend suites green (see below). |
| M03-006 | Medium | `FriendsService` now logs `Security: ...` events for send/cross-accept/accept/decline/cancel/remove/block/unblock, using the same `ILogger` convention already established in Module 1's `AuthService`. | Full targeted backend suites green with the new constructor dependency wired through DI and test doubles. |

No Critical/High findings existed, so this pass closes the module's full findings list to zero.

## Deferred Issues

| ID / Item | Severity | Owner | Rationale |
|---|---|---|---|
| Secondary rate caps: send 3/day/account-target, discovery 120/hour/IP | Info | Later slice | Per-account windows are enforced; the daily per-pair cap needs a durable per-pair counter and the per-IP discovery cap needs a chained global limiter. Tracked in `api-reference.md` "Rate Limiting" and the backend checkpoint. |
| No rate limit on GET list endpoints (summary/friends/requests/blocks/settings) | Info | Later slice / platform | Keyset paging (limit ≤ 50) bounds response size but not call frequency; a platform-wide limiter should cover reads before production. |
| Test-toolchain transitive High advisories (`System.Net.Http` 4.3.0, `System.Text.RegularExpressions` 4.3.0) | Info | Test hygiene | Present only in `SimPle.UnitTests` / `SimPle.IntegrationTests`; not shipped. Pin/upgrade the transitive graph opportunistically. |
| User-existence oracle via block/dismiss (200/204 vs 404 keyed by GUID) | Info | Accepted | GUIDs are non-enumerable; negligible. |

## Tests/Security Checks Run

```bash
# 1. NuGet advisory scan (2026-07-05, backend pass)
dotnet list SimPLe.Backend/SimPle.sln package --vulnerable --include-transitive
#   Production projects (Api, Application, Domain, Infrastructure, Shared): no vulnerable packages
#   SimPle.UnitTests / SimPle.IntegrationTests (transitive, test-only):
#     System.Net.Http 4.3.0            High  GHSA-7jgj-8wvc-jh57
#     System.Text.RegularExpressions 4.3.0 High GHSA-cmhx-cq75-c4mj

# 2. Module-requirements structural gate (2026-07-05)
node scripts/validate-module-requirements.mjs        # exit 0 (Modules 3-14 pass)

# 3. Frontend targeted vitest (this pass, 2026-07-06)
npx vitest run src/__tests__/friendsApi.test.ts src/__tests__/FriendsPage.test.tsx \
  src/__tests__/DashboardFriends.test.tsx src/__tests__/SidebarFriendBadge.test.tsx \
  src/__tests__/FriendSummaryContext.test.tsx
#   Test Files  5 passed (5)  |  Tests  61 passed (61)

# 4. Frontend lint (this pass, 2026-07-06)
npm run lint --prefix SimpLe.Frontend                 # clean, no errors

# 5. M03-006/M03-007 fix verification (2026-07-06, same session, --fix)
dotnet build SimPLe.Backend/SimPle.sln                                        # Build succeeded, 0 errors
dotnet test SimPLe.Backend/tests/SimPle.UnitTests/... --filter Friends        # 68/0/0
dotnet test SimPLe.Backend/tests/SimPle.IntegrationTests/... --filter FriendEndpointsTests   # 63/0/0
npx tsc --noEmit --prefix SimpLe.Frontend                                     # clean
npx vitest run <7 friends-related suites> --prefix SimpLe.Frontend            # 81/0
npm run lint --prefix SimpLe.Frontend                                        # clean
node scripts/check-contract-drift.mjs                                        # DRIFT=0
```

Corroborating backend-stage evidence (Sub-session C, not re-run here — see
`docs/ai-workflow/evidence/checkpoints/module-03-friends-social-graph/backend.json`):
UnitTests **273/0/0**; IntegrationTests **187/0/0** with `MIGRATION_TEST_CONNECTION_STRING` set (0 skipped),
including 8 disposable-Postgres concurrency/atomicity tests + 10 migration smoke tests proving xmin no-500,
`23505` cross-send convergence, atomic outbox commit/rollback, block atomicity, expression-uniqueness/self-CHECK/
5-role cascade, and keyset index usage under `enable_seqscan=off`.

Corroborating frontend-stage evidence (frontend slice, not re-run here — see
`docs/ai-workflow/evidence/checkpoints/module-03-friends-social-graph/frontend.json`): `tsc --noEmit` clean on
production `src/**`, `check-contract-drift.mjs` DRIFT=0, full targeted vitest 96/0 across 7 suites at slice time.

## Files Changed

- `SimPle.Project/docs/security/audits/module-03-friends-social-graph.md` (this audit — re-authored for the
  reconciled backend on 2026-07-05; frontend scope added 2026-07-06; M03-006/M03-007 fix pass 2026-07-06).
- `SimPle.Project/docs/modules/module-03-friends-social-graph/api-reference.md` (`BlockUserResult` shape,
  security considerations).
- `SimPLe.Backend/src/SimPle.Application/Friends/DTOs/BlockUserResult.cs` (M03-007 — minimal shape).
- `SimPLe.Backend/src/SimPle.Application/Friends/Services/FriendsService.cs` (M03-007 — stopped building the
  identity-card DTO on the block path, removed dead `BuildBlockDtoAsync`; M03-006 — added `ILogger<FriendsService>`
  + `Security: ...` log lines on send/accept/decline/cancel/remove/block/unblock).
- `SimPLe.Backend/tests/SimPle.UnitTests/Friends/FriendsServiceTests.cs` (constructor updated for the new
  `ILogger` dependency, via `NullLogger<FriendsService>.Instance`).
- `SimPLe.Backend/tests/SimPle.IntegrationTests/Friends/FriendEndpointsTests.cs` (new regression test for
  M03-007).
- `SimpLe.Frontend/src/features/friends/types.ts` (`BlockUserResult` type updated to match the minimal shape).
- `SimpLe.Frontend/src/__tests__/friendsApi.test.ts` (fixture/assertion updated to match).

## Final Security Status

- **Critical / High (production):** none. Frontend review introduced **zero new findings** at any severity.
- **Open:** none. **Fixed:** M03-007 (Low, backend `POST /api/friends/blocks`) and M03-006 (Medium, backend
  audit logging) — both closed 2026-07-06 (see "Fixed Issues Summary").
- **Blocks module completion?** No — there is nothing outstanding. No Critical/High findings ever existed, and
  the two non-blocking findings are now fixed rather than merely dispositioned.
- **Backend security review:** complete. **Frontend security review:** complete (2026-07-06, `--scope=frontend`,
  asvs-lite) — no new Critical/High/Medium/Low findings.
- **Module 3 overall security-ready:** **Yes** — unconditional. Zero open findings at any severity.

## Reviewer Notes

**For a non-specialist reviewer:** Module 3 decides who can befriend, block, or discover whom. The two risks
that matter most are "can user A do something that belongs to user B?" (authorization) and "does the graph leak
private information?" (privacy).

1. **Everything is scoped to the signed-in user** via the JWT, never the request body or URL. Trying to act on
   someone else's request/edge/block returns the same generic "not found" as if it never existed — so you can't
   even confirm the target exists.
2. **Discovery can't be used to fish for accounts by timing or error message** — the code deliberately does the
   same work for a real and a fake username, and returns the same 404 for anyone you're not allowed to see.
3. **Blocking is mutual and atomic** — if A blocks B, neither can request the other, any existing friendship is
   ended in the same database transaction, and a late accept loses to a committed block.
4. **Abuse is throttled** — per-account limits on sending, blocking, discovery, and suggestions, plus a cooldown
   before you can re-request someone who declined or whom you cancelled.
5. **One Low finding (M03-007), fixed 2026-07-06:** the *block* endpoint used to hand back the blocked user's
   public name/avatar even for otherwise-hidden accounts. It needed a known internal id (not guessable) and only
   exposed public card fields, but it was inconsistent with every other endpoint — fixed by returning a minimal
   block response (`outcome`, `blockedUserId`, `blockedAt`) with no identity fields.
6. **One Medium finding (M03-006), fixed 2026-07-06:** friend/block actions weren't written to a security log, so
   abuse couldn't have been investigated after the fact. Same gap as Modules 1–2; closed by adding the same
   `ILogger` + `Security: ...` structured logging convention `AuthService` already uses, to every state-changing
   action in `FriendsService`.
7. **Dependencies:** production code has no known-vulnerable packages; two advisories exist only in test tooling.
8. **Frontend addendum (2026-07-06):** the friends UI is a thin client over the backend above — it doesn't add its
   own authorization logic, so there was nothing new to break. The review confirmed it can't be used to smuggle
   server-owned fields, doesn't leak *why* a target is hidden, and clears cached friend counts on logout. The one
   open backend finding (M03-007) isn't made worse by the UI, since the block screen never displays the extra
   identity fields the backend response happens to include.

# Testing Report - Module 03: Friends & Social Graph

## Test Strategy

Backend logic, invariants, and DB constraints are covered by xUnit unit tests, in-memory integration tests,
and a provider-real-PostgreSQL suite run against a disposable `postgres:16-alpine` container. Frontend wiring
is covered by Vitest (component + API-client tests). A two-user Playwright E2E spec exercises the live local
stack end-to-end. Date: 2026-07-06 (reconciled backend/frontend contract; supersedes the 2026-06-29
pre-reconciliation report).

## Coverage Target

90%+ meaningful module coverage (advisory).

## Coverage Result

Backend: **UnitTests 273/0/0**, **IntegrationTests 187/0/0** (0 skipped, `MIGRATION_TEST_CONNECTION_STRING`
set), covering every transition, repeat/idempotent outcome, actor check, 401/404/409/429 mapping, privacy
matrix, cooldown boundary, dismissal, cursor validation, and outbox payload redaction. A statement/branch
coverage percentage was not re-collected after the reconciliation (Sub-sessions A/B/C changed the contract
surface enough that the pre-reconciliation 2026-06-29 percentages are stale and are not repeated here);
`dotnet test SimPLe.Backend/SimPle.sln --collect:"XPlat Code Coverage"` is the command to regenerate them.
Frontend: `npx vitest run` on the 7 reconciled friends suites passed **96/0**; a project-wide coverage run
was not part of this reconciliation slice.

## Commands Run

```bash
# Backend
dotnet test tests/SimPle.UnitTests/SimPle.UnitTests.csproj                    # 273/0/0
dotnet test tests/SimPle.IntegrationTests/SimPle.IntegrationTests.csproj      # in-memory, part of 187/0/0
docker run -d --name simple-pg-verify -p 5544:5432 postgres:16-alpine
MIGRATION_TEST_CONNECTION_STRING=... dotnet test tests/SimPle.IntegrationTests  # real Postgres, 187/0/0
docker rm -f simple-pg-verify

# Frontend
cd SimpLe.Frontend
npx tsc --noEmit               # production src/** clean
npm run lint                   # clean
npx vitest run                 # 7 reconciled friends suites, 96/0
node scripts/check-contract-drift.mjs   # DRIFT=0

# E2E (module verification checkpoint)
node scripts/check-contract-drift.mjs   # DRIFT=0; 54 backend routes, 48 unique frontend calls
dotnet ef database update --project SimPle.Infrastructure --startup-project SimPle.Api
npx playwright test tests/e2e/module-03-friends.spec.ts   # 1/1 passed, 10.2s
```

## Unit Tests

`FriendsServiceTests.cs` rewritten for the reconciled contract (~65 tests): send outcomes and privacy matrix,
cooldown gating, accept/decline/cancel/remove with BOLA-404 + idempotency, block/unblock, discovery visibility
and timing parity, suggestion dismissal, cursor validation, and outbox payload redaction. Combined with the
rest of the backend unit suite: **273/0/0**.

## Integration Tests

In-memory `FriendEndpointsTests.cs` reconciled to the new contract: all former 403 branches now assert 404
`Profile.NotVisible`; duplicate/reverse/already-accepted/already-blocked all assert 200 outcomes; offset paging
tests replaced with keyset-cursor tests including invalid-cursor 400; new tests added for discovery
(200/404/400), dismiss (idempotent + suppression), cooldown (409 + `Retry-After`), and BOLA on a guessed id.
Real-Postgres: new `FriendsPostgresConcurrencyTests.cs` (8 tests) plus existing `FriendsMigrationSmokeTests.cs`
(10 tests) run against a disposable `postgres:16-alpine` container — proving `xmin` stale-update →
`ConcurrencyConflict` (never 500), unordered-pair `23505` cross-send convergence to exactly one accepted edge,
atomic outbox staging/rollback with the aggregate, accept-vs-block and remove-vs-block races resolving for the
committed block, expression-uniqueness/self-CHECK(23514)/cascade, migration apply + legacy backfill, keyset +
mutual-count SQL translation, and an `EXPLAIN` proof that the incoming-requests keyset query uses the intended
index (no seq scan). Combined total: **IntegrationTests 187/0/0**, 0 skipped.

Frontend: `friendsApi.test.ts` and 6 other reconciled component/integration suites — **96 passed / 0 failed**
across 7 files.

## Security/Authorization Tests

Ownership/BOLA paths are exercised at both the unit level (privacy matrix, guessed-id 404) and on real
Postgres (timing parity between "hidden" and "never existed" branches). Backend authorization is enforced
server-side; full findings are in the security audit
(`SimPle.Project/docs/security/audits/module-03-friends-social-graph.md`) — no Critical/High production
findings; open items **M03-006** (Medium, deferred — no audit-event logging) and **M03-007** (Low — block
endpoint echoes target identity card) remain to disposition before the module is declared complete. The prior
Low finding M03-001 (block response leaking direction via a 403) is resolved on the Module 3 surface.

## Frontend Tests If Applicable

- Existing UI reused: yes (Sidebar, FriendsPage, Settings, Dashboard, profile).
- Frontend integration points tested: `friendsApi`, `friendsErrors`, `FriendSummaryContext`, badge, modals,
  safe discovery, suggestion dismiss.
- Visual changes made: deferred buttons rendered `disabled`; "Online" tab hidden; `@username` shown in the
  slot previously used for level/ELO (per approved R5 list).

## Realtime Tests If Applicable

Not applicable — realtime deferred to Module 7.

## Database/Migration Checks

- Existing database impact: additive (`Friendship` extended, `Block`, `UserFriendSettings`,
  `DismissedFriendSuggestion`, `OutboxMessage`, `OutboxDelivery`).
- Migration added: yes — forward-only corrective migration `20260705120243_HardenFriendsSocialGraph`.
- Migration safety notes: expression-unique unordered-pair index, `xmin` concurrency, CHECK constraints,
  cascade FKs, and the idempotent legacy-history backfill are all verified on real PostgreSQL 16 (Sub-session
  C, 2026-07-06, 18 real-Postgres tests, 0 failures, 0 skips). EF InMemory does not enforce any of these and
  was not used as evidence for them.
- Data preservation notes: no existing data altered.
- Destructive DB changes: none.

## Backend/API/Swagger Alignment

Controller carries Swagger annotations; endpoints/DTOs match `api-reference.md` (realigned 2026-07-06).

## Frontend/API Integration Alignment

`friendsApi.ts` matches documented routes/verbs; `node scripts/check-contract-drift.mjs` reports **DRIFT = 0**
(54 backend routes, 48 unique frontend calls, 5 dynamic paths noted, 0 unresolved mismatches).

## Edge Cases Tested

Self-action, exact repeat, reverse/cross-send convergence, cooldown direction and boundary, simultaneous send,
accept-vs-decline/cancel/block, remove-vs-block, stale `xmin`, privacy change with a pending request, guessed
request id, hidden mutuals, malformed/forged/expired cursor, discovery timing parity across
nonexistent/private/blocked/deleted/suspended targets, suggestion dismissal repeat/expiry, state reset on modal
reopen, debounce, concurrent-search guard, stale-response suppression, load-more, and optimistic dismiss with
rollback.

## Bugs Found During Testing

One test-only bug in the reconciled discovery test (`friendsApi` discover-404 case asserted a double API call
against a single mock) — a test defect, not an application defect. The Playwright E2E run also surfaced that
`module-03-friends.spec.ts` and `smoke.spec.ts` were never actually runnable before this checkpoint: the login
form hard-requires a reCAPTCHA token and the frontend had no test bypass.

## Fixes Made After Test Failures

Fixed the discovery test's double-call assertion. Added an env-gated dev/test-only seam in
`RecaptchaCheckbox.tsx` (`NEXT_PUBLIC_E2E_CAPTCHA_BYPASS`, pairs with the backend's existing
`Recaptcha:DevBypassToken`; both unset in production, so inert there) so the E2E suite can sign in. Corrected
copied-from-`smoke.spec.ts` selector bugs in `module-03-friends.spec.ts` (login inputs by autocomplete
attribute, exact "Sign in" submit button, `.first()` on toasts that legitimately render twice).

## Remaining Untested/Deferred Items

- Statement/branch coverage percentages were not re-collected after the reconciliation; the pre-reconciliation
  numbers are stale and not repeated here (see Coverage Result).
- `scripts/run-module-e2e.mjs` fails on Windows (`spawnSync npm.cmd EINVAL`); the E2E run for this checkpoint
  invoked Playwright directly to bypass it. Fixing the runner to spawn with `shell:true` on win32 is deferred.
- No automated E2E seed/reset fixture exists yet: preconditions (email-verified test accounts, clean
  friend-graph tables) were seeded/truncated manually between runs.
- E2E proves the happy path only (discover → send → accept → both list → block → both lose it → block
  precedence non-disclosure); it is not a production-readiness or full-correctness guarantee.
- Manual-only browser checks (responsive collapse below 900px, keyboard reachability of the More menu, focus
  trap/restore in AddFriendModal, `aria-expanded` on Manage, no-console-error sweep) remain unverified beyond
  the automated Playwright path.
- `mock/friends.ts` retained (still imported by lobby/game surfaces); deletion deferred to Module 5/7.
- Secondary rate caps (send 3/day/account-target; discovery 120/hr/IP) remain deferred — need a durable
  per-pair counter / chained global limiter.
- Open security items to disposition before Module 3 is declared complete: **M03-006** (Medium, deferred) and
  **M03-007** (Low).

## Final Status

Backend (273/0/0 unit, 187/0/0 integration incl. 18 real-Postgres tests), security review (no Critical/High
production findings), frontend (96/0 vitest, DRIFT=0), and the module E2E checkpoint (Playwright
`module-03-friends.spec.ts`, 1/1 passed against a live local stack) are all green. This is locally verified,
not deployed. Production review, disposition of M03-006/M03-007, and validated final evidence remain before
Module 3 is declared complete.

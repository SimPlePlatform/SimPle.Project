# Testing Report - Module 03: Friends & Social Graph

> Revision 2. Backend/frontend automated suites cover the full revision-2 contract (people search, canonical
> profile navigation, viewer-context, friend/mutual-friend drill-downs) and are green. The expanded
> multi-user Playwright scenario (`module-03-friends.spec.ts`) has been **executed against a live seeded
> local stack and passed (1/1, 25.7s)** — see `docs/ai-workflow/evidence/checkpoints/
> module-03-friends-social-graph/verification.json`. Two real product-code bugs surfaced and were fixed
> during that run (a `Cursor.cs` pagination defect and a `ProtectedRoute`/route-group gap for anonymous
> public-profile access); both are detailed below and are already re-verified.

## Test Strategy

Backend logic, invariants, and DB constraints are covered by xUnit unit tests, in-memory integration tests,
and a provider-real-PostgreSQL suite run against a disposable `postgres:16-alpine` container. Frontend
wiring is covered by Vitest (component + API-client tests). A two-user Playwright E2E spec already proved
the revision-1 happy path on a live local stack; an expanded A/B/C/anonymous Playwright spec for revision 2
was written, then executed and passed against a live local stack (real backend + frontend + real Postgres).
Dates: 2026-07-09 (backend 2A/2B, frontend 4A/4B), 2026-07-10 (live E2E verification, then security-fix
re-verification).

## Coverage Target

90%+ meaningful module coverage (advisory).

## Coverage Result

Backend: **UnitTests 321/321**, **IntegrationTests 224/224** (0 skipped, real PostgreSQL) — covering every
revision-1 transition plus revision-2's people search, viewer-context derivation, friend/mutual-friend
drill-down privacy filtering, send-cap durability, and the two new migrations. A statement/branch coverage
percentage was not collected this revision; `dotnet test SimPLe.Backend/SimPle.sln --collect:"XPlat Code
Coverage"` remains the command to regenerate one. Frontend: `npx vitest run` **188/188** passing across all
reconciled suites (revision-1 + revision-2); a project-wide coverage run was not part of this slice.

## Commands Run

```bash
# Backend (2026-07-09)
dotnet build SimPle.sln
dotnet test tests/SimPle.UnitTests/SimPle.UnitTests.csproj                              # 321/0/0
dotnet test tests/SimPle.IntegrationTests --filter PeopleEndpointsTests|ProfileEndpointsTests  # in-memory, 70/0/0
MIGRATION_TEST_CONNECTION_STRING=... dotnet test --filter FriendsMigrationSmokeTests    # real Postgres, 15/0/0
MIGRATION_TEST_CONNECTION_STRING=... dotnet test --filter FriendsPostgresConcurrencyTests  # real Postgres, 11/0/0
MIGRATION_TEST_CONNECTION_STRING=... dotnet test tests/SimPle.IntegrationTests          # real Postgres, full suite, 224/0/0, 0 skipped
dotnet build src/SimPle.Api/SimPle.Api.csproj                                           # Swagger/OpenAPI XML-doc check

# Frontend (2026-07-09)
cd SimpLe.Frontend
npx tsc --noEmit -p tsconfig.json      # clean
npm run lint                           # clean (incl. react-hooks/set-state-in-effect fix in PeopleSearchCombobox)
npm run test                           # vitest run, 188/188
node scripts/check-contract-drift.mjs  # DRIFT=0 (58 backend routes, 49 resolved frontend calls)

# Live E2E verification (2026-07-10, run-2026-07-09T16-12-20-678Z-50e0bc0a-...)
node tests/e2e/seed-b-friends.mjs                                            # one-time seed, ~8-9 min (auth-register rate limit)
npx playwright test tests/e2e/module-03-friends.spec.ts --project=chromium  # full A/B/C/anonymous scenario, live backend :5147 + frontend :3000 + real Postgres — 1 passed, 25.7s
node scripts/check-contract-drift.mjs                                        # re-run, DRIFT=0 (58/49)
dotnet build SimPle.sln                                                      # after the Cursor.cs fix below
npx tsc --noEmit -p tsconfig.json                                            # after the (public) route-group restructuring below

# Security-fix verification (2026-07-10)
dotnet build src/SimPle.Api/SimPle.Api.csproj
dotnet test tests/SimPle.UnitTests --filter "FullyQualifiedName~Friends|FullyQualifiedName~People|FullyQualifiedName~Profile"  # 202/202
npx playwright test tests/e2e/module-03-friends.spec.ts --project=chromium   # targeted live re-run against real Postgres, validating the corrected count queries only
curl smoke test of GET /api/profile/{username} anonymous vs authenticated Cache-Control/Vary headers
```

## Unit Tests

Backend combined total **321/0/0**, including `PeopleServiceTests.cs` (search ranking, exclusion rules,
cursor binding) and `ProfileServiceTests.cs` (viewer-context state derivation for all six
`relationshipState` values, visible-count computation) added this revision, plus the existing
`FriendsServiceTests.cs` extended for the three-field settings shape and the send-cap. Frontend:
`friendsApi.test.ts`, `friendsErrors.test.ts`, `AddFriendModal.test.tsx`, `FriendsPage.test.tsx`,
`DashboardFriends.test.tsx`, `InviteFriendModal.test.tsx`, `SettingsPrivacy.test.tsx`, and the new
`ProfileFriendCount.test.tsx` — combined with the rest of the reconciled suites: **188/0/0**.

## Integration Tests

In-memory: `PeopleEndpointsTests.cs` and `ProfileEndpointsTests.cs` (new, 70/0/0 combined for this pair)
cover search pagination/exclusion, the unified `Profile.NotVisible` 404 across every denial branch,
viewer-context authorization, and the two drill-down endpoints' privacy filtering and cursor validation.
Real-Postgres: `FriendsMigrationSmokeTests.cs` (15/0/0, extended for the two new migrations),
`FriendsPostgresConcurrencyTests.cs` (11/0/0, extended with `EXPLAIN` proof that the new prefix-search
indexes and the mutual-count subquery are actually used, no sequential scan), and
`ProfilePrivacyMigrationSmokeTests.cs` (new, backfill correctness). Combined total: **IntegrationTests
224/0/0**, 0 skipped.

## Security/Authorization Tests

The `--security=asvs-lite` review of the revision-2 delta
(`SimPle.Project/docs/security/audits/module-03-friends-social-graph.md`) found zero Critical/High
findings. Two Medium findings (M03-008: friend/mutual visible-count privacy-filter divergence from the
paged-list queries; M03-009: a migration backfill that ignored existing users' current profile visibility)
and two Low findings (M03-010: an intentional independent rate-limit budget split, confirmed by product
decision; M03-011: a missing explicit cache header on the anonymous profile branch) were opened and have
all since been **fixed (M03-008, M03-009, M03-011) or resolved (M03-010) and verified on 2026-07-10** via a
targeted unit re-run (202/202), a live Playwright run against real Postgres exercising the corrected
correlated-subquery LINQ, a manual re-derivation `UPDATE` equivalent to a fresh migration apply, and a
`curl` header check. Zero open findings above Info remain for the revision-2 delta. All revision-1 findings
(M03-001, M03-006, M03-007) were already fixed as of 2026-07-06.

## Frontend Tests If Applicable

- Existing UI reused: yes (Sidebar, FriendsPage, Settings, Dashboard).
- Frontend integration points tested: `friendsApi`, `friendsErrors`, `FriendSummaryContext`, `peopleApi`,
  `profileApi`, `PlayerIdentity`, `PeopleSearchCombobox`, badge, modals, safe discovery, suggestion dismiss,
  profile friend-count linking.
- Visual changes made: deferred buttons rendered `disabled`; "Online" tab hidden; ELO/level chips and
  presence dot removed from profile headers; mock overview/performance/match-history/achievements/
  favorite-games renderers replaced with honest "Available in Module X" `EmptyState` placeholders; Games/
  Public Lobbies search groups labelled unavailable.

## Realtime Tests If Applicable

Not applicable — realtime deferred to Module 7.

## Database/Migration Checks

- Existing database impact: additive (`Friendship` extended again, `RetiredUsername` new,
  `UserFriendSettings` gains three columns, `users` gains three send-cap columns + two prefix indexes).
- Migrations added: `20260709054351_AddProfilePrivacyAndRetiredUsernames`,
  `20260709094629_AddPeopleSearchAndSendCap`.
- Migration safety notes: both forward-only/additive, verified on real PostgreSQL 16
  (`FriendsMigrationSmokeTests.cs`, `ProfilePrivacyMigrationSmokeTests.cs`, 2026-07-09). The
  `SearchVisibility` backfill defect found by the 2026-07-09 security review (M03-009) was corrected and
  re-verified 2026-07-10 via a manual re-derivation `UPDATE` against local dev Postgres equivalent to a
  fresh migration apply; a from-scratch migration run re-exercising the corrected `Up()` end-to-end was not
  performed this pass (see the security audit's residual-risk note).
- Data preservation notes: no existing data altered destructively.
- Destructive DB changes: none.

## Backend/API/Swagger Alignment

All 5 new/changed revision-2 endpoints carry `[SwaggerOperation]` + `[ProducesResponseType]`; documented in
full in `api-reference.md` (updated this pass).

## Frontend/API Integration Alignment

`node scripts/check-contract-drift.mjs` reports **DRIFT = 0** — 58 backend routes, 49 resolved frontend
calls. 5 `apiFetch` call sites use interpolated paths the script's heuristic cannot statically resolve
("unresolved (dynamic)"); all 5 were manually verified against the backend controller routes and confirmed
correct.

## Edge Cases Tested

All revision-1 edge cases (self-action, exact repeat, reverse/cross-send convergence, cooldown boundary,
simultaneous send, accept-vs-decline/cancel/block races, stale `xmin`, guessed ids, malformed cursor,
discovery timing parity, dismissal repeat/expiry, debounce, stale-response suppression) remain covered.
Revision 2 adds: people-search ranking/exclusion (self, ineligible, blocked-either-direction, deleted,
suspended, banned), viewer-context derivation for all six relationship states, `BlockedByTarget` never
surfacing, visible-count parity with the corresponding paged list (post M03-008 fix), cursor invalidation on
a `PrivacyPolicyVersion` bump from a settings change, and legacy-profile-id redirect/fallback behavior.

## Bugs Found During Testing

Carried from revision 1 (already fixed, unchanged): a test-only double-call assertion bug in the discovery
test, and two Playwright selector bugs in the original `module-03-friends.spec.ts`. This revision: fixed a
pre-existing `vitest.config.ts` gap (missing `tests/e2e/**` exclude) that had been causing Vitest to attempt
to load the two Playwright-only spec files and fail 2 suites with zero actual product regressions — a
one-line test-tooling fix, not a product-module change. **Two real product bugs surfaced during the live
E2E run (2026-07-10)**:
- **Cursor pagination defect**: `Cursor.TryFromBase64Url` (`SimPLe.Backend/src/SimPle.Application/Common/
  Pagination/Cursor.cs`) used `string.IsNullOrEmpty` on a decoded cursor segment, incorrectly rejecting a
  legitimate empty-string component (e.g. an unset search filter) and breaking the friends/mutual-friends
  "Load more" pagination in the common no-filter case.
- **Anonymous public-profile routing gap**: `ProtectedRoute` unconditionally redirected anonymous/unverified
  visitors away from every `(app)`-group route, including `Public`-visibility profiles the backend already
  served anonymously — a frontend architecture gap, not a backend defect.

## Fixes Made After Test Failures

`vitest.config.ts` `tests/e2e/**` exclude added (see above). Backend security-review findings M03-008,
M03-009, and M03-011 were fixed in `FriendRepository.cs`, the
`AddProfilePrivacyAndRetiredUsernames` migration, and `ProfileController.cs` respectively, and re-verified
per "Security/Authorization Tests" above. From the live E2E run: `Cursor.cs` fixed to check `value is null`
instead of `string.IsNullOrEmpty` (validated by E2E step 5: 20→25 rows across the cursor boundary, no
duplicates); `/u/[username]`, `/u/[username]/friends`, and `/u/[username]/mutual-friends` moved into a new
`(public)` Next.js route group whose layout renders the full `AppShell` for authenticated sessions or a
minimal public header for anonymous/unverified visitors (validated by E2E step 7) — this frontend
architectural change was made with explicit user sign-off (`AskUserQuestion` → "Fix it now").

## Remaining Untested/Deferred Items

- Statement/branch coverage percentages have not been re-collected since the revision-1 reconciliation.
- `scripts/run-module-e2e.mjs` still fails on Windows (`spawnSync npm.cmd EINVAL`); direct Playwright
  invocation remains the workaround. Fixing the runner is deferred.
- No automated E2E seed/reset fixture existed for revision 1's 2-user scenario; `seed-b-friends.mjs` now
  exists for the revision-2 multi-user scenario and has been run successfully (one-time, ~8-9 minutes) as
  part of the 2026-07-10 live E2E verification.
- Manual-only browser checks (responsive collapse, keyboard reachability, focus trap/restore, `aria-expanded`
  states, no-console-error sweep) beyond what the live E2E scenario and automated Vitest suite already cover
  remain unverified; local dev test-data contamination from the verification run was cleaned up (not a code
  bug).
- `mock/friends.ts` retained (still imported by lobby/game surfaces); deletion deferred to Module 5/7.
- Legacy `/profile/{uuid}` resolution for non-owner ids is an accepted limitation (no backend UUID→username
  lookup endpoint exists), not a bug to fix in this revision.
- A from-scratch migration run re-exercising the corrected M03-009 backfill end-to-end (rather than a manual
  equivalent `UPDATE`) is recommended but not yet performed.

## Final Status

Backend (321/0/0 unit, 224/0/0 integration incl. real-Postgres migration/concurrency tests) and frontend
(188/0/0 vitest, DRIFT=0) are green. The `asvs-lite` security review found zero Critical/High findings, and
all four revision-2 Medium/Low findings are fixed/resolved and independently re-verified as of 2026-07-10.
**The expanded multi-user Playwright scenario has been executed against a live seeded local stack and
passed (1/1, 25.7s)**, proving the full A/B/C/anonymous journey: composed search, request send/accept,
authorized paginated friends drill-down (20→25 rows across the cursor boundary, no duplicates), live
friends-list-visibility enforcement, anonymous Public/Private profile split, `/profile/me` canonical
resolution, and block convergence across search/profile/friends-list/mutual-friends. Two real product bugs
surfaced and were fixed during that run (see "Bugs Found During Testing"); both fixes are validated by the
same passing run. Evidence: `docs/ai-workflow/evidence/checkpoints/module-03-friends-social-graph/
verification.json`. Production review and final evidence sign-off remain before Module 3 revision 2 is
declared complete.

# Testing Report - Module 04: Game Library & Discovery

## Test Strategy

Backend logic, invariants, and DB constraints are covered by xUnit unit tests, in-memory/HTTP-contract
integration tests, and a real-PostgreSQL suite run against disposable scratch roles
(`m4_test_runner`, `module4_scratch`, dropped after each run). Frontend wiring is covered by Vitest
(component + API-client tests). A dedicated Playwright E2E spec
(`module-04-game-library.spec.ts`) was written during the frontend slice and **executed against a live
local stack (real backend :5147 + frontend :3000 + real Postgres) and passed (2/2, 9.1s)** at the
verification stage, which was also the first module run to enforce `accessibilityPolicy: "required"`.
Dates: 2026-07-10 (all backend, security, frontend, and verification work for this module happened in a
single day).

## Coverage Target

90%+ meaningful module coverage (advisory).

## Coverage Result

Backend: **UnitTests 412/412** (full solution, including `GamesServiceTests.cs`,
`GameCatalogCursorTests.cs`, `GameTests.cs`, `UserFavoriteGameTests.cs`), **IntegrationTests 219/219**
(non-Postgres HTTP-contract), plus a real-Postgres suite of **32/32** (`GameCatalogMigrationTests` 8/8,
`GameCatalogSeederTests` 5/5, `GamesPostgresConcurrencyTests` 8/8, `FriendsPostgresConcurrencyTests` 11/11
unaffected/regression-checked). A statement/branch coverage percentage was not collected this module;
`dotnet test SimPle.sln --collect:"XPlat Code Coverage"` remains the command to regenerate one. Frontend:
`npm run test` (vitest) **223/223** passing across the full reconciled suite.

## Commands Run

```bash
# Backend (2026-07-10, 4A/4B sessions)
dotnet build SimPle.sln
dotnet test tests/SimPle.UnitTests                          # Games domain/seeder unit tests, 36/36 (4A)
dotnet test tests/SimPle.IntegrationTests                    # real Postgres (m4_test_runner, dropped), 13/13 (4A)
dotnet test                                                  # full-solution unit tests, 412/412 (4B)
dotnet test tests/SimPle.IntegrationTests/Games/GamesEndpointsTests.cs   # HTTP-contract, 219/219 (4B)
dotnet test                                                  # real Postgres (module4_scratch, dropped):
                                                               # GameCatalogMigrationTests 8/8,
                                                               # GameCatalogSeederTests 5/5,
                                                               # GamesPostgresConcurrencyTests 8/8,
                                                               # FriendsPostgresConcurrencyTests 11/11 (4B)
dotnet build SimPle.sln --nologo -v:q                         # security-review session, catch-up confirmation

# Frontend (2026-07-10)
cd SimpLe.Frontend
npx tsc --noEmit                        # clean
npm run lint                            # clean (after 4 react-hooks/set-state-in-effect eslint-disable fixes,
                                         #   1 unused-import removal)
npm run test                            # vitest run, 223/223
node scripts/check-contract-drift.mjs   # DRIFT=0 (64 backend routes, 52 resolved frontend calls)

# Live E2E + accessibility verification (2026-07-10, run-2026-07-10T16-01-37-336Z-...)
npm run test:e2e -- tests/e2e/module-04-game-library.spec.ts   # live backend+frontend+real Postgres, 2 passed, 9.1s
npm run test:e2e -- tests/e2e/smoke.spec.ts                    # shared app-shell regression re-check, 2 passed, 4.0s
node scripts/check-contract-drift.mjs                           # re-run, DRIFT=0 (64/52)
```

## Unit Tests

Backend combined total **412/412**, including `GamesServiceTests.cs` (search/filter/sort validation,
cursor encode/decode round-trip and query-shape-hash binding, ETag derivation, favorite idempotency logic),
`GameCatalogCursorTests.cs`, `GameTests.cs` (lifecycle state-machine transitions), and
`UserFavoriteGameTests.cs` (soft-delete `IsActive`/`CycleId` semantics). Frontend: `gamesApi.test.ts`,
`LibraryPage.test.tsx`, `GameDetailPage.test.tsx`, `ProfileGamesTab.test.tsx`, and
`ProfileFriendCount.test.tsx` (fixed this module — see "Bugs Found During Testing") — combined with the
rest of the reconciled suites: **223/0/0**.

## Integration Tests

Non-Postgres HTTP-contract: `GamesEndpointsTests.cs` (**219/219**) covers request/response shape,
validation error codes, anonymous-vs-authorized access split, and the 410 tombstone response for retired
games. Real-Postgres: `GameCatalogMigrationTests.cs` (8/8, both migrations applied/rolled back cleanly),
`GameCatalogSeederTests.cs` (5/5, advisory-lock + checksum idempotency proven under repeated runs), and
`GamesPostgresConcurrencyTests.cs` (8/8, concurrent favorite writes resolved correctly via the outbox
unique-index conflict path). `FriendsPostgresConcurrencyTests.cs` (11/11) was re-run alongside as a
regression check that Module 4's schema/migration additions did not disturb Module 3's concurrency
behavior. Combined real-Postgres total: **32/32**.

## Security/Authorization Tests

The `--security=light` review
(`SimPle.Project/docs/security/audits/module-04-game-library-discovery.md`) covered both the backend phase
and a post-frontend phase and found **zero unwaived Critical/High/Medium findings** in either. Two Low
findings remain open and deferred: **M04-001** (Name/Difficulty catalog sorts cannot use their intended
indexes — computed-expression `ORDER BY` vs raw-column index — confirmed via `EXPLAIN`; bounded by rate
limits and the current 8-row catalog size) and **M04-002** (no composite index for the
`(UserId, IsActive)+(UpdatedAt DESC, Id DESC)` favorites-list query pattern; self-scoped query, bounded by
the 60/min/account rate limit). Four Info findings were also recorded and deferred: **M04-003** (correlation
id unimplemented project-wide, pre-existing, not Module-4-owned), **M04-004** (`GameArt.tsx` interpolates
color/token fields into CSS/SVG with no `#rrggbb` validation — not exploitable today since the source is the
server-curated catalog, not user input), **M04-005** (`gamesApi.ts`'s `getDetail` uses a raw `fetch` instead
of the shared `apiFetch<T>()` wrapper to preserve the 410 tombstone body — confirmed it still replicates
`credentials:'include'`, `cache:'no-store'`, and `Accept` headers; GET-only, no CSRF header required), and
**M04-006** (search inputs have no client-side minimum-length guard matching the server's 2-char floor — a
UX nit, server-side validation is unaffected). The primary IDOR threat flagged for this module in the
module registry is closed by construction: favorite mutations operate only on the authenticated session's
own `UserId`, with no id parameter a caller could substitute.

## Frontend Tests If Applicable

- Existing UI reused: yes (card/tab/`EmptyState`/`Skeleton` components, dashboard layout).
- Frontend integration points tested: `gamesApi`, `types.ts`, `GameArt.tsx`, `LibraryPage.tsx`,
  `GameDetailPage.tsx`, `DashboardPage.tsx`, `SearchResultsPage.tsx`, profile Favorite games tab.
- Visual changes made: none beyond the new game-library/detail/favorites surfaces themselves (net-new
  pages, not edits to existing visual design). Fake "online now"/stats claims removed from game detail;
  all five entry actions rendered `disabled` with real owning-module disclosure text.

## Realtime Tests If Applicable

Not applicable — Module 4 has no real-time surface.

## Database/Migration Checks

- Existing database impact: additive (`games`, `game_tags`, `game_mode_capabilities`,
  `user_favorite_games`, `catalog_seed_history` — all new tables).
- Migrations added: `20260710072312_AddGameCatalog`, `20260710073819_AddGameLifecycleVersion`.
- Migration safety notes: both forward-only/additive, verified on real PostgreSQL
  (`GameCatalogMigrationTests.cs`, 8/8). A partial unique index enforces the single-featured-rank
  invariant; raw-SQL DDL was not required for these migrations (contrast with Module 3's prefix-search
  indexes).
- Data preservation notes: no existing data altered; the seeder's advisory-lock + checksum guard
  (`GameCatalogSeederTests.cs`, 5/5) confirms repeated runs never duplicate or mutate the eight canonical
  seed rows.
- Destructive DB changes: none.

## Backend/API/Swagger Alignment

All six `GamesController` endpoints carry `[SwaggerOperation]` + `[ProducesResponseType]`; documented in
full in `api-reference.md`.

## Frontend/API Integration Alignment

`node scripts/check-contract-drift.mjs` reports **DRIFT = 0** — 64 backend routes, 52 resolved frontend
calls, 5 dynamic-path call sites manually verified against `GamesController.cs` and confirmed correct (the
same pre-existing heuristic limitation already accepted for Module 3's endpoints).

## Edge Cases Tested

Query-shape-bound cursor tampering (a cursor minted under one filter/sort/search combination rejected if
replayed against another); retired-game direct detail access (honest 410 tombstone, not a 404 or stale
render); favorite `PUT`/`DELETE` idempotency including a concurrency-conflict reread-and-retry path;
anonymous access to catalog/detail/featured endpoints with no auth cookie; all three catalog reads confirmed
anonymous while `/me/favorites` confirmed `[Authorize]`-gated; lifecycle filtering (only `Available`/
`ComingSoon` games surfaced in list/search; `Draft`/`Maintenance`/`Retired` excluded); search-term
`LIKE`-wildcard escaping; filter cardinality cap (5 values per dimension) enforcement; seeder idempotency
under repeated advisory-locked runs. The live E2E scenario additionally proved: Module 3 people-search
regression (still functional after Module 4's shared-layout changes), browse/filter/search by name, a
ComingSoon game detail with no fake online/play/stat claims rendered, all three distinct entry-action
disabled-reason texts (quick match/create lobby/invite friend, each legitimately naming Module 6) plus the
Module 8 and Module 9 actions, favorite/unfavorite round-trip reflected on the profile tab, and — as the
first module to enforce `accessibilityPolicy: "required"` — a zero-violation axe-core scan across every
page visited along that path, after six real accessibility defects (detailed below) were found and fixed in
shared app-shell code.

## Bugs Found During Testing

No product-code defects were found in Module 4's own feature code during any test phase. All bugs found and
fixed during the live E2E/accessibility verification pass were in **shared, pre-existing app-shell code**,
not Module 4 code, and were fixed with explicit user sign-off (`AskUserQuestion`):

- **Accessibility test-fixture bug**: `tests/e2e/fixtures/accessibility.ts` ran an axe scan unconditionally
  in `afterEach`, including for API-only tests that use the `request` fixture and never navigate `page`,
  leaving it at `about:blank`. Fixed with an early return when `page.url() === 'about:blank'`.
- **Module 1 (Auth) accessibility bug**: `AuthPage.tsx`'s `Field` component placed a hint (e.g. a "Forgot?"
  button) before the input in DOM order, so the browser's implicit label association resolved to the hint
  instead of the real input. Fixed by reordering children before the hint in DOM order and restoring the
  original visual layout with CSS `order`.
- **Six real axe-core accessibility violations**, all in shared app-shell/layout components (first module to
  enforce `accessibilityPolicy: "required"`): (1) `link-name` x7 — icon-only sidebar nav links lost their
  accessible name in rail mode (`Sidebar.tsx`'s label span was `display:none` between 769-1280px viewport
  widths); fixed in `globals.css` by clipping the label offscreen (sr-only technique) instead of removing it
  from the accessibility tree. (2) `landmark-banner-is-top-level`/`landmark-no-duplicate-banner`/
  `landmark-unique` — `AppShell.tsx` wrapped `Topbar` (which itself renders a `<header class="topbar">`) in
  a second `<header class="app__topbar">`, producing two nested banner landmarks; fixed by changing the
  outer wrapper to a `<div>`. (3) `page-has-heading-one` — `ProfilePage.tsx` rendered the profile display
  name as a `<div>` instead of an `<h1>`; fixed by changing the tag. (4) `color-contrast` — the shared
  `--text-lo` muted-text color token (`#7A8299`) scored 4.42:1 against a `#161c2e` card background, just
  under the 4.5:1 AA threshold; bumped to `#7C849D` (~4.55:1), applied to the shared dark-theme token so it
  improves (never regresses) contrast for every consumer.
- In-scope Playwright locator specificity fixes within the Module 4 spec and shared `smoke.spec.ts` (narrow,
  in-file test fixes, no separate approval sought): exact-match on the "Sign in" button (a broad regex also
  matched "Sign in with Google"); scoped the page-title assertion to `getByRole('main')`; scoped the
  ComingSoon-detail click to the link role; added `.first()` to three deferred-entry-action text assertions
  (Module 6 legitimately backs 3 distinct actions producing 3 identical disabled-reason nodes by design).
- `ProfileFriendCount.test.tsx` (pre-existing Module 3 test) broke when `ProfilePage.tsx`'s new "Browse
  games" empty-favorites action called `useRouter()` with no mock present in that test file; fixed by adding
  the same minimal `useRouter` mock already used in `ProfileGamesTab.test.tsx`, no product code changed.

## Fixes Made After Test Failures

All fixes listed above under "Bugs Found During Testing" are already applied and re-verified by the same
passing runs (`npm run test` 223/223, `module-04-game-library.spec.ts` 2/2, `smoke.spec.ts` 2/2, zero axe
violations across every page visited in the E2E path). No backend product-code fixes were required this
module.

## Remaining Untested/Deferred Items

- `scripts/run-module-e2e.mjs` could not be used as the invocation wrapper this module:
  `spawnSync npm.cmd EINVAL` on this Windows/Node environment, confirmed via an isolated repro unrelated to
  the script's own logic. Worked around by invoking `npm run test:e2e -- <spec>` directly; the
  manifest-declared spec scope (module-04-game-library.spec.ts only) was still honored manually.
- Coverage honesty: the live E2E scenario proves the happy path the spec exercises (people-search
  regression, browse/filter/search, ComingSoon detail with no fake claims, favorite round-trip,
  deferred-entry-action module naming, anonymous public GET access) plus a first-time enforced accessibility
  scan of the pages visited along that path. It is not a full audit of every Module 4 page/state, and the
  contract-drift check remains a static heuristic.
- 7 other feature pages (Dashboard, Friends, Settings, Lobby, Leaderboards, Search) reuse the same
  `.page-title` div convention that `ProfilePage.tsx` used before its accessibility fix; only the page
  actually exercised by this checkpoint's axe scan (profile) was changed. Sweeping the remaining pages to
  `<h1>` is deferred as a separate, explicitly-scoped follow-up, not silently bundled here.
- Legacy `mock/games.ts` retained for 5 out-of-scope consumers (`LandingPage.tsx`, `CreateLobbyModal.tsx`,
  `InviteFriendModal.tsx`, `GameRoomPage.tsx`, `LobbyPage.tsx`); no test suite exists for those 5 consumers,
  so `tsc`+lint clean is the only regression signal available for them.
- M04-001 and M04-002 (Low) remain open and deferred, bounded by existing rate limits and current data
  volumes — see "Security/Authorization Tests" above.
- Local test-fixture setup (operational, not code): `e2e-test-user` was registered via
  `POST /api/auth/register` with the dev CAPTCHA bypass token, then `IsEmailVerified = true` was set
  directly in the local dev Postgres `users` table (no dev bypass equivalent exists for email verification).

## Final Status

Backend (412/412 unit, 219/219 HTTP-contract integration, 32/32 real-Postgres) and frontend (223/223 vitest,
DRIFT=0) are green. The `--security=light` review found zero unwaived Critical/High/Medium findings across
both the backend and post-frontend phases; two Low and four Info findings are recorded and deferred, none
blocking. **The dedicated Playwright E2E scenario has been executed against a live local stack and passed
(2/2, 9.1s)**, proving browse/filter/search, honest ComingSoon/deferred-action rendering, the favorite
round-trip, and anonymous catalog access — plus, as the first module to enforce
`accessibilityPolicy: "required"`, a zero-violation axe-core scan after fixing six real accessibility defects
in shared app-shell code (with explicit user sign-off) and two unrelated pre-existing bugs found along the
way (a test-fixture gap and a Module 1 label-association defect). Evidence:
`docs/ai-workflow/evidence/checkpoints/module-04-game-library-discovery/verification.json`. Production
review and final evidence sign-off remain before Module 4 is declared complete.

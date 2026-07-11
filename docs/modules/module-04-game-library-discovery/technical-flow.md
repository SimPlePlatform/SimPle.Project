# Technical Flow - Module 04: Game Library & Discovery

## Summary

Module 4 gives SimPle a real game catalog: a browsable, filterable, searchable library backed by Postgres
instead of a static mock array, a per-game detail page that never invents online-player counts or fake
stats, and a favorites system a signed-in player can build on their profile. Every game's lifecycle
(`Draft → ComingSoon/Retired → Available/Retired → Maintenance/Retired`) is enforced server-side, so a
retired or not-yet-released game can never be discovered or favorited through a stale link. The five
"play this game" actions (quick match, create lobby, invite friend, play vs AI, enter match room) are shown
honestly disabled with the real module that will implement them, rather than omitted or faked as clickable —
consistent with the platform's no-fabrication rule for pages built ahead of their dependencies.

## Problem Solved

Before this module, `/games`, the game detail page, the dashboard's featured section, and the profile's
"Favorite games" tab were all backed by a static in-memory mock array with fabricated online-player counts.
There was no real catalog table, no lifecycle concept, and no way for a player's favorite to actually
persist. Module 4 replaces that mock with a real, seeded, lifecycle-aware catalog and a genuine
per-user favorites relationship, while keeping every "this needs another module" surface (matchmaking,
lobbies, stats) honestly labelled instead of hidden or faked.

## Architecture Overview

```
Browser
  ├── /games              → LibraryPage (filter/sort/search, cursor "load more")
  ├── /games/{slug}        → GameDetailPage (lifecycle-aware, favorite toggle, deferred entry actions)
  ├── /search (Games tab)  → SearchResultsPage (reuses gamesApi.list)
  ├── /dashboard            → DashboardPage (featured strip)
  └── /profile (Favorite games tab) → cursor-paged favorites list

gamesApi.ts ──→ apiFetch<T>() / raw fetch (detail, to preserve 410 tombstone body) ──→ /api/games/*
                                                                    │
                                                          GamesController
                                                (anonymous GET catalog/detail/featured;
                                                 [Authorize] + CSRF on /me/favorites mutations)
                                                                    │
                                                            GamesService
                                    (validation, query-shape-bound cursor encode/decode,
                                     ETag derivation, lifecycle filtering, favorite idempotency)
                                                                    │
                                                           GameRepository ──→ PostgreSQL
                                (games, game_tags, game_mode_capabilities,
                                 user_favorite_games, catalog_seed_history)
                                                                    │
                                        GameOutbox (same transaction as favorite writes)
                                                                    │
                              GameCatalogSeeder (advisory-lock + checksum-idempotent,
                                                   runs from catalog.seed.v1.json at startup)
```

## Backend Flow

`GamesController` exposes six endpoints under `/api/games`: `GET /` (cursor-paginated catalog with
filter/sort/search), `GET /featured`, `GET /{slug}`, `GET /me/favorites`, and `PUT`/`DELETE
/me/favorites/{slug}`. The three catalog/detail reads are anonymous by design (confirmed by the
controller's own XML doc comments); only the favorites endpoints are `[Authorize]`-gated and require the
shared `X-Requested-With: XMLHttpRequest` CSRF header on mutations, matching the cookie-JWT convention used
by every other controller in the app. `GamesService` owns validation (search terms 2-100 chars with
`LIKE`-wildcard escaping, filter cardinality capped at 5 values per dimension, allow-listed lifecycle/
difficulty/sort values), encodes/decodes the keyset cursor via `Cursor.EncodeCatalog`/`TryDecodeCatalog`
bound to a hash of the requesting query's shape (so a cursor minted under one filter/sort combination is
rejected if replayed against another), and derives the response `ETag` as a hash of the actual returned row
data rather than a single global catalog-version counter. `GameRepository` applies lifecycle filtering
(only `Available` and `ComingSoon` games are ever publicly listed; `Draft`/`Maintenance`/`Retired` are
excluded from list/search but `Retired` still resolves on direct detail lookup as an honest 410 tombstone).
Favorites are a soft-delete relationship: `UserFavoriteGame.IsActive` plus a `CycleId` (mirroring
`Friendship.RequestCycleId`) tracks re-favorite/un-favorite cycles without ever deleting the row, and both
`PUT`/`DELETE` are idempotent with a concurrency-conflict reread-and-retry path detected via the outbox's
unique `(AggregateId, EventType, AggregateDomainVersion)` index (there is no dedicated concurrency token on
`UserFavoriteGame` itself). `GameCatalogSeeder` runs at startup, takes a Postgres advisory lock, and compares
a checksum of `catalog.seed.v1.json` against `catalog_seed_history` so re-deploys never re-insert or
duplicate the eight canonical seed games.

## Frontend Flow

- **Existing UI reused:** card/tab/`EmptyState`/`Skeleton` components, dashboard layout — logic wired in,
  no redesign.
- **Frontend integration points:** `gamesApi.ts` (new), `types.ts` (new, mirrors backend DTOs field-for-field
  in camelCase), `GameArt.tsx` (prop contract tightened to the real `GameCatalogDto` shape), `LibraryPage.tsx`,
  `GameDetailPage.tsx`, `DashboardPage.tsx`, `SearchResultsPage.tsx`, `ProfilePage.tsx` (Favorite games tab).
- **Mocks/placeholders replaced with real, honest behavior this module:**
  - Static `mock/games.ts` array powering `/games`, game detail, the dashboard featured strip, and search's
    Games tab → live `gamesApi` client wired to `GET /api/games` (list, cursor-paginated, filter/sort/search),
    `GET /api/games/featured`, `GET /api/games/{slug}`.
  - Mock "Favorite games" profile tab (fake entries) → real cursor-paginated
    `GET /api/games/me/favorites` for the viewer, with honest empty/loading/error states and a "Browse games"
    action linking to `/games` when empty.
  - No favorite/unfavorite affordance on game detail → a favorite toggle wired to the real `PUT`/`DELETE`
    endpoints, idempotency-normalized `aria-pressed` state, reflected live on the profile tab.
  - Fake "online now"/stats claims on game detail → removed; `ComingSoon` lifecycle shows a "Coming soon"
    chip, and the stats tab shows "No stats yet" plus an honest "Available once Module 10 ships" disclosure
    instead of fabricated numbers.
  - All five entry actions (quick match, create lobby, invite friend, play vs AI, enter match room) rendered
    as disabled controls naming their real owning module (6, 8, or 9) instead of being omitted or faked as
    clickable — this is a backend characteristic (the action list is fixed and non-conditional), not a
    frontend simplification.
  - Composed `/search` Games tab (previously an "unavailable" placeholder from the Module 3 slice) → now
    live, backed by the same `gamesApi.list` search, with a "See all games" link to `/games?query=...`.
- **Known, accepted limitations carried forward (not defects):** legacy `mock/games.ts` was **not** deleted —
  5 out-of-scope consumers (`LandingPage.tsx`, `CreateLobbyModal.tsx`, `InviteFriendModal.tsx`,
  `GameRoomPage.tsx`, `LobbyPage.tsx`) still depend on the legacy shape and are owned by other modules
  (M6/M7/M9); instead `GameArt.tsx`'s prop contract was tightened to the real DTO shape and the two in-scope
  call sites that broke (`CreateLobbyModal.tsx`, `LandingPage.tsx`) were given minimal inline adapter
  objects. `GameDetailPage.tsx` uses a local `notFoundMessage` state + `EmptyState` render instead of
  Next.js `notFound()` — the mandatory part of the underlying spec risk (removing a silent fallback to the
  wrong game on an unknown slug) is satisfied regardless.
- **Visual changes made:** none beyond the new game-library/detail/favorites surfaces themselves, which are
  net-new pages rather than edits to existing visual design.

## Database/Domain Model Changes

- **Existing database impact:** additive only. New tables: `games`, `game_tags`,
  `game_mode_capabilities`, `user_favorite_games`, `catalog_seed_history`.
- **Migration added:** yes — `20260710072312_AddGameCatalog` (all five tables, indexes, constraints) and
  `20260710073819_AddGameLifecycleVersion` (lifecycle version column follow-up).
- **Migration safety notes:** both are forward-only and additive; `Down()` on each drops only what `Up()`
  added. The `games` table uses a partial unique index to enforce the "at most one featured-rank per rank
  value" invariant, and computed-expression name/difficulty sort indexes were confirmed via `EXPLAIN` to be
  unusable by their intended `ORDER BY` (a known, deferred limitation — see below).
- **Data preservation notes:** no existing data altered; the seeder is advisory-lock- and
  checksum-guarded so repeated deploys never duplicate or mutate the eight canonical seed rows.
- **Destructive DB changes:** none.

## API Contract

- **Backend/API/Swagger alignment:** all six endpoints carry `[SwaggerOperation]` +
  `[ProducesResponseType]`; documented in full in `api-reference.md`.
- **Frontend/API integration alignment:** `check-contract-drift.mjs` reports **DRIFT = 0** (64 backend
  routes, 52 resolved frontend calls). 5 `apiFetch` call sites use interpolated template-literal paths the
  script's regex heuristic cannot statically resolve and lists as "unresolved (dynamic)"; each was manually
  verified by reading both `gamesApi.ts` and `GamesController.cs` directly and confirmed to correctly target
  existing, already-implemented endpoints — the same pre-existing heuristic limitation already accepted for
  Module 3's endpoints.

## Validation And Error Handling

Search terms are bounded to 2-100 characters with `LIKE`-wildcard escaping before use; filter values are
allow-listed against the real `GameLifecycle`/`GameDifficulty` enums with a cardinality cap of 5 values per
filter dimension (a documented design decision, not a literal brief number). Cursor tampering — including a
cursor minted under a different filter/sort/search combination than the one it's replayed against — is
rejected via the query-shape-hash binding rather than silently producing a wrong or empty page. A `Retired`
game's detail lookup returns a **410** `GameTombstoneDto` (deliberately **not** wrapped in the shared
`ApiErrorResponse` envelope, a documented deviation) so the frontend can show an honest "this game was
retired" state instead of a generic 404. See `api-reference.md`'s Error Format table for the full six-code
catalogue.

## Authorization And Security Decisions

Catalog reads (list/featured/detail) are anonymous by design; only `/me/favorites` (read and both
mutations) is `[Authorize]`-gated and requires the CSRF header on mutations. Favorite mutations operate only
on the authenticated session's own `UserId` — there is no id parameter a caller could substitute to affect
another account's favorites, so the IDOR surface flagged as Module 4's primary threat in the module registry
is closed by construction rather than by a runtime ownership check. The `--security=light` review
(`SimPle.Project/docs/security/audits/module-04-game-library-discovery.md`) covered both the backend phase
and a post-frontend phase and found **zero unwaived Critical/High/Medium findings** in either. Two Low
findings remain open and deferred (M04-001: computed-expression sort indexes unusable by their `ORDER BY`,
bounded by rate limits and the current 8-row catalog size; M04-002: no composite index for the
favorites-list query pattern, bounded by the 60/min/account rate limit) plus four Info findings, all recorded
in the audit and cross-referenced in `testing-report.md`.

**Spec deviation D1:** the cache header for list/detail responses uses `Vary: Cookie` rather than the
spec's originally stated `Vary: Authorization`, since the app's auth model is cookie-based JWT, not a
bearer `Authorization` header — `Vary: Authorization` would not have varied the cache on the credential the
app actually uses. Documented in the spec reconciliation ledger before implementation, not discovered as a
defect afterward.

## Realtime/Socket.IO Flow If Applicable

Not applicable — Module 4 has no real-time surface. Online-player counts and live status, previously
fabricated by the mock data this module replaced, are honestly omitted rather than simulated.

## State Management If Applicable

No new shared context. `LibraryPage.tsx` and `SearchResultsPage.tsx` hold their own filter/sort/search/cursor
state locally; the profile Favorite games tab and `GameDetailPage.tsx`'s favorite toggle each fetch and
mutate independently rather than sharing a global favorites store, since a stale cross-page favorite state
would be a worse bug than one extra request on toggle.

## Edge Cases Handled

- **Query-shape-bound cursor tampering:** a cursor minted under one filter/sort/search combination is
  rejected (not silently reinterpreted) if replayed against a different one.
- **Retired-game direct access:** a bookmarked or shared link to a since-retired game's detail page returns
  an honest 410 tombstone instead of a 404 or a stale rendering of removed data.
- **Favorite idempotency:** repeated `PUT`/`DELETE` favorite calls (e.g. double-click, retry after a dropped
  response) are idempotent; a concurrency conflict triggers a reread-and-retry rather than surfacing a raw
  error.
- **Anonymous favorite state:** unauthenticated visitors can browse/filter/search/view games but see no
  favorite state or toggle, since the endpoint is authenticated-only by design.
- **Fixed non-conditional entry actions:** all five entry actions are shown disabled for every game
  regardless of its declared mode capabilities (a backend characteristic — the action list does not vary
  per game), so the frontend never has to guess which actions a given game "should" eventually support.
- **Seeder idempotency:** the advisory-lock + checksum guard means the seed script can safely run on every
  deploy without needing an external "have I already seeded" flag or manual intervention.

## Design Tradeoffs

ETag is derived from a hash of returned row data rather than the spec's originally stated single global
`catalogVersion` counter — functionally equivalent (never stale, correctly invalidates on any relevant row
change) and required no new schema or write-path change to maintain a counter. Favorites use soft-delete
(`IsActive` + `CycleId`) rather than hard delete, trading a small amount of table growth for an auditable
favorite/unfavorite history consistent with the same pattern already established by `Friendship
.RequestCycleId` in Module 3. The name/difficulty sort indexes were left as-is rather than converted to
functional/expression indexes this pass, since the catalog is an 8-row seed set today and the cost of a
premature index redesign was judged higher than the current, rate-limit-bounded query cost.

## Files Changed And Why

**Backend** (`backend.json`): `GamesController.cs`, `GamesService.cs`/`IGamesService.cs` (new); `Cursor.cs`
(extended with `EncodeCatalog`/`TryDecodeCatalog`); `Game.cs`, `GameTag.cs`, `GameModeCapability.cs`,
`UserFavoriteGame.cs`, `CatalogSeedHistory.cs` (new domain entities); `GameCatalogDto.cs`,
`GameFavoriteDto.cs`, `GameTombstoneDto.cs`, `GameEntryActionDto.cs`, `GameEntryActions.cs` (fixed
five-action list); `GameOutbox.cs`; `GameRepository.cs`/`IGameRepository.cs`; `GameCatalogSeeder.cs`,
`CatalogSeedManifest.cs`, `catalog.seed.v1.json`, `catalog.seed.schema.json`; EF configurations for all five
new tables; migrations `20260710072312_AddGameCatalog`, `20260710073819_AddGameLifecycleVersion`.

**Frontend** (`frontend.json`): `gamesApi.ts`, `types.ts` (new); `GameArt.tsx` (prop contract tightened to
the real DTO shape); `LibraryPage.tsx`, `GameDetailPage.tsx` (new pages); `DashboardPage.tsx`,
`SearchResultsPage.tsx`, `ProfilePage.tsx`, `CreateLobbyModal.tsx`, `LandingPage.tsx` (wired to real data or
given minimal adapter objects); `app/(app)/games/page.tsx`; `.claude/config/module-e2e-manifest.json`
flipped to `present`; `tests/e2e/module-04-game-library.spec.ts` (written this slice, executed at
verification).

**Frontend, fixed during live E2E/accessibility verification** (`verification.json`, first module to enforce
`accessibilityPolicy: "required"`): six real axe-core violations were found and fixed, all in shared
app-shell/layout components rather than Module 4 feature code — `Sidebar.tsx`/`globals.css` (icon-only rail
nav links lost their accessible name; fixed with an sr-only-clipped label instead of `display:none`),
`AppShell.tsx` (a duplicate nested `<header>` landmark; changed the outer wrapper to a `<div>`),
`ProfilePage.tsx` (the profile display name was a `<div>` instead of an `<h1>`; changed the tag), and the
shared `--text-lo` dark-theme color token (bumped from 4.42:1 to ~4.55:1 contrast against card backgrounds).
All six were fixed with explicit user sign-off. Also fixed: `tests/e2e/fixtures/accessibility.ts` (an axe
scan ran unconditionally in `afterEach` even for API-only tests that never navigate `page`, left at
`about:blank`) and `AuthPage.tsx` (a pre-existing Module 1 label-association bug, unrelated to Module 4,
found by the same accessibility pass and fixed with the same sign-off).

## How To Read The Implementation

Start at `gamesApi.ts`/`types.ts` (the contract), then `LibraryPage.tsx` and `GameDetailPage.tsx` (the two
main new surfaces). On the backend, start at `GamesController.cs`, then `GamesService.cs` for the validation/
cursor/ETag/favorite-idempotency logic, then `GameRepository.cs` for the lifecycle-filtering query shape,
then `GameCatalogSeeder.cs` for the advisory-lock + checksum idempotency pattern.

## Future Improvements / Deferred Items

| Feature | Deferred to | Current state |
|---------|------------|---------------|
| Quick match / matchmaking entry action | Module 6 | Rendered `disabled`, names Module 6 |
| Create lobby entry action | Module 6 | Rendered `disabled`, names Module 6 |
| Invite friend entry action | Module 6 | Rendered `disabled`, names Module 6 |
| Play vs AI entry action | Module 9 | Rendered `disabled`, names Module 9 |
| Enter match room entry action | Module 8 | Rendered `disabled`, names Module 8 |
| Game stats tab | Module 10 | "No stats yet" honest disclosure, no fabricated numbers |
| `mock/games.ts` for 5 out-of-scope consumers | Modules 6/7/9 | Retained; `GameArt.tsx` contract tightened instead of a full mock removal |
| Name/Difficulty sort functional indexes | Later hardening | Confirmed via `EXPLAIN` unusable by current computed-expression `ORDER BY`; bounded by rate limits and current catalog size |
| Favorites-list composite index | Later hardening | No supporting index for `(UserId, IsActive)+(UpdatedAt DESC, Id DESC)`; correctness unaffected at current volumes |
| Correlation id | Project-wide, unowned by Module 4 | Unimplemented pre-existing gap |
| Production review and final evidence sign-off | `/simple production-review module=4` | This docs stage is in progress; production-review and final evidence remain |

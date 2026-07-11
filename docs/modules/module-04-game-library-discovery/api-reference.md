# API Reference - Module 04: Game Library & Discovery

## Overview
- Existing UI reused: card/tab/`EmptyState`/`Skeleton` components and the dashboard layout, unchanged and
  reused rather than duplicated. One new approved control: a keyboard-labelled favorite toggle in the
  game-detail header, reused on the profile favorites tab.
- Frontend integration points: `features/games/gamesApi.ts`, `features/games/types.ts`,
  `features/games/LibraryPage.tsx`, `features/games/GameDetailPage.tsx`, `components/ui/GameArt.tsx`,
  `features/dashboard/DashboardPage.tsx` (featured card), `features/search/SearchResultsPage.tsx` (composed
  Games tab), `features/profile/ProfilePage.tsx` (Favorite games tab).
- Existing database impact: additive only. Five new tables (`games`, `game_tags`, `game_mode_capabilities`,
  `user_favorite_games`, `catalog_seed_history`); no existing table altered or dropped.

## Base Route / Route Group
`/api/games`, source of truth `SimPLe.Backend/src/SimPle.Api/Controllers/GamesController.cs`. Authentication
is cookie-based (`credentials: 'include'`); the three catalog reads are anonymous and auth-independent, the
three `me/favorites` endpoints require a session. Mutating favorite calls (`PUT`/`DELETE`) require the
`X-Requested-With: XMLHttpRequest` CSRF header (missing → 400 `Auth.CsrfHeaderRequired`).

## Authentication And Authorization Requirements
`GET /api/games`, `GET /api/games/{slug}`, and `GET /api/games/featured` have no `[Authorize]` attribute and
serve identical, auth-independent bodies to anonymous and authenticated callers (no `isFavorited`, no
user-linked data). All three `me/favorites` endpoints carry `[Authorize]`; favorite identity is derived only
from the JWT `sub` claim (`TryGetUserId`), never from a request body or route-supplied user id, so the
favorite endpoints bind only the route `slug` — an IDOR/BOLA-safe-by-construction shape (OWASP API3:2023).
Catalog mutation has no public controller at all; the checked-in seed manifest applied by a local CLI
(`--seed-game-catalog`) is the only write path to the catalog itself.

## Endpoint Summary Table

| # | Method | Path | Purpose | Auth | Notes |
|---|--------|------|---------|------|-------|
| 1 | GET | `/api/games` | List/search the catalog (keyset cursor) | Anonymous | `Cache-Control: public, max-age=60`, `Vary: Cookie`, `ETag` |
| 2 | GET | `/api/games/featured` | The single featured game, or none | Anonymous | 200 or 204; same cache headers as (1) |
| 3 | GET | `/api/games/{slug}` | Single game by slug | Anonymous | 200 (ComingSoon/Available/Maintenance), 404 (unknown/Draft), 410 (Retired tombstone) |
| 4 | GET | `/api/games/me/favorites` | The caller's active favorites (keyset cursor) | Required | `Cache-Control: private, no-store` |
| 5 | PUT | `/api/games/me/favorites/{slug}` | Favorite a game (idempotent) | Required + CSRF | 200 on first and repeat calls with identical DTO |
| 6 | DELETE | `/api/games/me/favorites/{slug}` | Unfavorite a game (idempotent) | Required + CSRF | 204 whether present, absent, or already inactive |

## Endpoints

### GET /api/games
- Purpose: keyset-paged, filterable, searchable catalog list. First entry point for `/games` and the
  composed `/search?type=games` tab.
- Request parameters (all query, all optional): `query` (string, 2–100 normalized chars), `category[]`,
  `tag[]`, `mode[]`, `lifecycle[]` (each ≤ 5 values, allow-listed server-side), `sort`
  (`default`\|`name`\|`difficulty`\|`duration`), `limit` (default 24, max 50), `after` (opaque cursor).
- Request body: none.
- Validation rules: `query` is whitespace-collapsed then bounded to 2–100 chars (`Validation.Failed` outside
  that range); each multi-value filter is capped at 5 values (`Validation.Failed` beyond that) and every
  value must be allow-listed (`GameCatalogAllowLists.Tags`/`Modes`); `lifecycle` accepts only
  `ComingSoon`\|`Available`\|`Maintenance` — `Draft`/`Retired` cannot be forced into the list via the query
  string; `sort` must be one of the four allowed keys; `limit` must be 1–50; a supplied `after` cursor is
  decoded and its embedded query-shape hash must match the current request's shape, or it is rejected as
  `Pagination.InvalidCursor` rather than silently restarting or blending pages.
- Success response: `200 CursorPage<GameCatalogDto>` (`items[]`, `nextCursor` — `null` on the last page), or
  `304 Not Modified` with no body when `If-None-Match` matches the current `ETag`.
- Error responses: `400 Validation.Failed`, `400 Pagination.InvalidCursor`, `429 RateLimit.Exceeded`.
- Authorization behavior: none required; response body is byte-identical for anonymous and authenticated
  callers.
- Rate limiting / abuse notes: `catalog-read` (120/min/IP) normally; a request with a non-empty `query`
  additionally counts against the narrower `catalog-search` (30/min/IP) via a path-scoped limiter branch.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Games_List")]` + `[ProducesResponseType]` for
  200/304/400/429.
- Backend/API/Swagger alignment: verified by reading `GamesController.cs:34-58` directly.
- Frontend/API integration alignment: `gamesApi.list()` builds the query string with `URLSearchParams`
  (repeated keys for array filters) and calls `apiFetch<CursorPage<GameCatalogDto>>`.
- Example request: `GET /api/games?category=puzzle&sort=name&limit=24`
- Example response: `{ "items": [ { "slug": "online-sudoku", "name": "Online Sudoku", ... } ], "nextCursor": null }`

### GET /api/games/featured
- Purpose: the single spotlighted game for the dashboard featured card and library hero.
- Request parameters: none.
- Request body: none.
- Validation rules: none (no input).
- Success response: `200 GameCatalogDto` when a featured game exists, `204 No Content` when none does (the
  partial unique index guarantees at most one), or `304 Not Modified`.
- Error responses: `429 RateLimit.Exceeded`.
- Authorization behavior: none required; same auth-independent DTO as the list endpoint.
- Rate limiting / abuse notes: `catalog-read`, 120/min/IP.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Games_GetFeatured")]`, `[ProducesResponseType]`
  for 200/204/304/429.
- Backend/API/Swagger alignment: `GamesController.cs:60-75`.
- Frontend/API integration alignment: `gamesApi.getFeatured()`; `apiFetch` returns `undefined` for the 204.
- Example request: `GET /api/games/featured`
- Example response: `{ "slug": "chess-lite", "name": "Chess Lite", "featuredRank": 1, ... }` or `204` empty.

### GET /api/games/{slug}
- Purpose: game detail page.
- Request parameters: `slug` (route, string).
- Request body: none.
- Validation rules: none beyond slug lookup; unknown slug and `Draft`-lifecycle slug are deliberately
  indistinguishable (both `404 Games.NotFound`) so a caller cannot enumerate admin-only draft entries.
- Success response: `200 GameCatalogDto` for `ComingSoon`/`Available`/`Maintenance`, or `304 Not Modified`.
- Error responses: `404 Games.NotFound` (unknown or Draft), `410 GameTombstoneDto` (Retired — the raw
  tombstone DTO is returned directly, **not** wrapped in the shared `ApiErrorResponse` envelope, since a
  retired game is a valid-but-gone resource state rather than a request error), `429 RateLimit.Exceeded`.
- Authorization behavior: none required.
- Rate limiting / abuse notes: `catalog-read`, 120/min/IP.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Games_GetBySlug")]`, `[ProducesResponseType]` for
  200/304/404/410/429.
- Backend/API/Swagger alignment: `GamesController.cs:77-97`.
- Frontend/API integration alignment: `gamesApi.getDetail()` deliberately uses a raw `fetch` (not the shared
  `apiFetch<T>()` wrapper) so it can read the 410 tombstone body; it still replicates
  `credentials: 'include'`, `cache: 'no-store'`, and the `Accept` header — reviewed and confirmed safe
  (M04-005, security audit).
- Example request: `GET /api/games/chess-lite`
- Example response (410): `{ "slug": "old-game", "name": "Old Game", "lifecycle": "Retired", "reasonCode": "Games.Retired" }`

### GET /api/games/me/favorites
- Purpose: the caller's active favorites, for the profile "Favorite games" tab.
- Request parameters: `limit` (default 24, max 50), `after` (opaque cursor).
- Request body: none.
- Validation rules: `limit` 1–50 (`Validation.Failed` otherwise); malformed/forged cursor →
  `Pagination.InvalidCursor`.
- Success response: `200 CursorPage<GameFavoriteDto>`.
- Error responses: `401 Unauthorized`, `400 Validation.Failed`, `400 Pagination.InvalidCursor`,
  `429 RateLimit.Exceeded`.
- Authorization behavior: `[Authorize]`; results are always scoped to the JWT `sub`.
- Rate limiting / abuse notes: `game-favorites`, 60/min, partitioned by account with an IP fallback for the
  rare unauthenticated-partition edge case.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Games_GetFavorites")]`.
- Backend/API/Swagger alignment: `GamesController.cs:101-118`.
- Frontend/API integration alignment: `gamesApi.getFavorites()`.
- Example request: `GET /api/games/me/favorites?limit=24`
- Example response: `{ "items": [ { "slug": "chess-lite", "name": "Chess Lite", "favoritedAt": "<ISO-8601 timestamp>", ... } ], "nextCursor": null }`

### PUT /api/games/me/favorites/{slug}
- Purpose: favorite a game.
- Request parameters: `slug` (route).
- Request body: none.
- Validation rules: `slug` must resolve to a non-Draft game; a `Retired` game rejects a **new** favorite with
  `409` (an existing owner's favorite on a since-retired game is left untouched by this endpoint). Repeating
  the call on an already-active favorite returns the identical DTO with no new outbox event.
- Success response: `200 GameFavoriteDto`, identical on first and repeated calls.
- Error responses: `401 Unauthorized`, `404 Games.NotFound`, `409 Games.Retired`, `429 RateLimit.Exceeded`,
  `400 Auth.CsrfHeaderRequired` (missing CSRF header).
- Authorization behavior: `[Authorize]`; ownership is always the JWT `sub` — no body/route `userId` is
  accepted, so no other account's favorites can be targeted.
- Rate limiting / abuse notes: `game-favorites`, 60/min/account.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Games_PutFavorite")]`.
- Backend/API/Swagger alignment: `GamesController.cs:120-138`.
- Frontend/API integration alignment: `gamesApi.favorite(slug)` via the shared `apiFetch<T>()`, which attaches
  the CSRF header automatically.
- Example request: `PUT /api/games/me/favorites/chess-lite`
- Example response: `{ "slug": "chess-lite", "name": "Chess Lite", "lifecycle": "ComingSoon", "favoritedAt": "<ISO-8601 timestamp>", ... }`

### DELETE /api/games/me/favorites/{slug}
- Purpose: unfavorite a game.
- Request parameters: `slug` (route).
- Request body: none.
- Validation rules: none beyond slug lookup; unfavoriting a game that was never favorited, or is already
  inactive, still succeeds.
- Success response: `204 No Content` — present, absent, or already-inactive all converge to the same result.
- Error responses: `401 Unauthorized`, `404 Games.NotFound` (unknown slug only), `429 RateLimit.Exceeded`,
  `400 Auth.CsrfHeaderRequired`.
- Authorization behavior: `[Authorize]`, JWT `sub`-scoped, same as `PUT`.
- Rate limiting / abuse notes: `game-favorites`, 60/min/account.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Games_DeleteFavorite")]`.
- Backend/API/Swagger alignment: `GamesController.cs:140-157`.
- Frontend/API integration alignment: `gamesApi.unfavorite(slug)`.
- Example request: `DELETE /api/games/me/favorites/chess-lite`
- Example response: `204` empty body.

## Data Models / DTOs

```typescript
GameLifecycle = 'Draft' | 'ComingSoon' | 'Available' | 'Maintenance' | 'Retired';
GameDifficulty = 'Easy' | 'Medium' | 'Hard';
GameSort = 'default' | 'name' | 'difficulty' | 'duration';

// Auth-independent — no isFavorited, online count, lastPlayed, or stats (spec deviation D1).
GameEntryActionDto = {
  action: 'play-vs-ai' | 'quick-match' | 'create-lobby' | 'invite-friend' | 'enter-match-room';
  status: 'deferred' | 'enabled'; // every action is 'deferred' in Module 4
  reasonCode: string;             // e.g. 'Games.EntryDeferred.AI'
  ownerModule: number;            // the module that will flip this action to 'enabled'
}

GameCatalogDto = {
  slug: string; name: string; summary: string; rulesSummary: string;
  category: string; tags: string[];
  difficulty: GameDifficulty;
  estimatedDurationMinMinutes: number; estimatedDurationMaxMinutes: number;
  minPlayers: number; maxPlayers: number;
  lifecycle: GameLifecycle; capabilities: string[]; featuredRank: number | null;
  artToken: string; artColorA: string; artColorB: string; artAltText: string;
  entryActions: GameEntryActionDto[];
}

// Minimal 410 body — no summary, tags, capabilities, or art.
GameTombstoneDto = { slug: string; name: string; lifecycle: GameLifecycle; reasonCode: string; }

// Private favorites-list / favorite-mutation DTO. Never shared-cached.
GameFavoriteDto = {
  slug: string; name: string; lifecycle: GameLifecycle;
  artToken: string; artColorA: string; artColorB: string; artAltText: string;
  favoritedAt: string; // ISO 8601
}

CursorPage<T> = { items: T[]; nextCursor: string | null; }
```

## Error Format
Envelope: `{ error: { code, message } }` (via `ApiErrorResponse`/`MapError` in `GamesController.cs`), except
the `410` tombstone response, which returns a bare `GameTombstoneDto` — deliberate, not an inconsistency.

| Code | HTTP | Meaning |
|------|------|---------|
| `Games.NotFound` | 404 | Unknown slug **or** a `Draft` game — never distinguishes the two. |
| `Games.Retired` | 410 (detail read, tombstone body) / 409 (new favorite) | Retired game. |
| `Pagination.InvalidCursor` | 400 | Forged, malformed, or query-shape-mismatched cursor. |
| `Validation.Failed` | 400 | Search length out of 2–100, non-allow-listed filter/sort/mode/lifecycle, filter cardinality > 5, page size outside 1–50. |
| `RateLimit.Exceeded` | 429 | With `Retry-After`. |
| `Auth.CsrfHeaderRequired` | 400 | Missing `X-Requested-With` header on `PUT`/`DELETE` favorites. |

## Security Considerations
Favorite ownership always derives from the JWT `sub` claim; the route accepts only a `slug`, never a
body-supplied user or game id, so BOLA/BOPLA overposting cannot target another account's favorites. Catalog
DTOs are auth-independent by construction, which is what makes `Cache-Control: public, max-age=60` safe —
see spec deviation **D1** (`Vary: Cookie`, not the brief's literal `Vary: Authorization`, because this app
authenticates by cookie and never reads the `Authorization` header). Search input is length-bounded
(2–100 chars) before touching the database and relies on EF Core's Npgsql provider `LIKE`-escaping for
`Contains()` translation, independently exercised against real PostgreSQL. Filter/sort/mode/lifecycle values
are server-side allow-listed; `Draft`/`Retired` cannot be forced into a public list via query parameters. The
`--security=light` review (`SimPle.Project/docs/security/audits/module-04-game-library-discovery.md`) found
zero Critical/High/Medium findings across both the backend and post-frontend phases; two Low index-gap
findings (M04-001, M04-002) and four Info findings (M04-003 through M04-006) are open, deferred, and
non-blocking — see that document for full detail.

## Related Tests
Backend: 412/412 unit tests, 219/219 non-Postgres integration tests, 32/32 real-PostgreSQL tests (all green).
Frontend: `npm run test` (Vitest) 223/223 passing; `node scripts/check-contract-drift.mjs` reports `DRIFT=0`
(64 backend routes, 52 resolved frontend calls). Live E2E: `module-04-game-library.spec.ts` passed 2/2 against
a live local stack with the shared axe accessibility fixture (zero violations). Full detail in
`testing-report.md`.

## Last Verified Command
Backend: `dotnet build SimPle.sln` (0 errors, 0 warnings). Frontend: `npx tsc --noEmit`,
`npm run lint`, `npm run test` (223/223), `node scripts/check-contract-drift.mjs` (`DRIFT=0`).
Live E2E: `npm run test:e2e -- tests/e2e/module-04-game-library.spec.ts` against local backend `:5147` +
frontend `:3000` + real PostgreSQL — 2 passed, 9.1s.

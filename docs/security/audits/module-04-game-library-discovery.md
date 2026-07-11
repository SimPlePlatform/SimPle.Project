# Security Audit - Module 04: Game Library & Discovery

Date: 2026-07-10

## Scope
**Backend phase (2026-07-10):** light security review of Module 4's game catalog and favorites backend slice
(4A schema/seed + 4B reads/cache/favorites/outbox): `GamesController`, `GamesService`, `GameRepository`,
`Cursor` (catalog cursor), Games DTOs, the `AddGameCatalog`/`AddGameLifecycleVersion` migrations and EF
configurations, the catalog seeder, and the three new rate-limiter policies in `Program.cs`.

**Post-frontend phase (2026-07-10):** light, read-only security review of the Module 4 frontend slice that
wires the UI to the already-reviewed backend: `gamesApi.ts`, `types.ts`, `routes.ts`, `GameArt.tsx`,
`LibraryPage.tsx`, `GameDetailPage.tsx`, `DashboardPage.tsx`, `app/(app)/games/page.tsx`,
`SearchResultsPage.tsx`, `ProfilePage.tsx`, and the minor adapter touches in `CreateLobbyModal.tsx` /
`LandingPage.tsx`, plus associated Vitest test files and the new Playwright E2E spec (read for hygiene, not
executed this session — execution is deferred to `/simple-verify-checkpoint`). No backend code was changed or
re-audited in this phase; findings from the backend phase are not re-litigated.

## Assessment Type
light review

Review phase: backend + post-frontend (both phases recorded in this single document; see dated Scope entries
above)

## Authorization Statement
Local authorized project-only review. No external systems, production services, real secrets, or real user data were used.

## Executive Summary
No Critical or High findings. The backend slice correctly derives favorite ownership from the JWT `sub`
claim only (never a request-body id), keeps public catalog reads anonymous/auth-independent so the
`Cache-Control: public` + `Vary: Cookie` pairing (spec deviation D1) cannot cross-serve an authenticated
body to an anonymous caller or vice versa, allow-lists every filter/sort/lifecycle value server-side, bounds
search length (2-100) and filter cardinality (max 5 values/dimension), validates pagination cursors against
a hash of the full query shape (rejecting stale cursors after a filter change with `400
Pagination.InvalidCursor` rather than blending result sets), and relies on EF Core's Npgsql provider's
built-in `LIKE` wildcard escaping for `Contains()`-translated search (independently exercised by
`Search_PercentWildcardInQuery_IsEscaped_MatchesOnlyLiteralSubstring` /
`..._UnderscoreWildcardInQuery_IsEscaped_...` against real PostgreSQL per the 4B test record). Favorite
mutation endpoints require `[Authorize]` plus the existing `X-Requested-With` CSRF header convention, and the
single-featured-rank invariant is enforced by a real partial unique index, not application code alone. Two
Low/Info items are recorded below as accepted, non-blocking observations consistent with light-depth scope.

**Post-frontend addendum:** the frontend slice introduces no Critical/High/Medium/Low findings. All
state-changing calls (`favorite`/`unfavorite`) route through the shared `apiFetch<T>()` client, which attaches
the project's `X-Requested-With` CSRF header on every non-GET call; favorite identity is always the server's
JWT `sub` claim via `/api/games/me/favorites`, never a client-supplied user id, so no IDOR path exists.
`GameDetailPage.tsx` has no `?? GAMES[0]`-style fallback (confirmed by reading the current file — the legacy
mock array is not imported), so an unknown/retired slug cannot silently render the wrong game. All five game
entry actions render as honestly-disabled controls naming their real owning future module, sourced from the
server's fixed `entryActions` list, with no client-side bypass. Three Info-level, non-exploitable
defense-in-depth notes are recorded below (M04-004 through M04-006).

## Severity Summary Table

| Severity | Count | Notes |
|---|---:|---|
| Critical | 0 | |
| High | 0 | |
| Medium | 0 | |
| Low | 2 | M04-001, M04-002 |
| Info | 4 | M04-003 (backend), M04-004, M04-005, M04-006 (post-frontend) |

## OWASP Mapping
- OWASP Top 10 web: A01 Broken Access Control (favorite ownership/CSRF), A03 Injection (search LIKE
  escaping; frontend CSS/DOM injection surface at M04-004, mitigated by trusted data source), A04 Insecure
  Design (cache-key/Vary correctness; frontend reliance on server-side input validation at M04-006, correctly
  deferred, not a violation), A05 Security Misconfiguration (rate limits).
- OWASP API Security Top 10: API3:2023 Broken Object Property Level Authorization (favorites bind only the
  route slug, never a body id, confirmed unchanged from the frontend's perspective), API4:2023 Unrestricted
  Resource Consumption (page-size cap, filter cardinality cap, catalog-read/catalog-search/favorites rate
  limits), API1:2023 Broken Object Level Authorization — no findings; frontend does not bypass or duplicate
  server-side ownership checks.
- WebSocket/Socket.IO checklist: not applicable (no realtime surface in Module 4).

## Methodology
Read the authoritative brief (`docs/module-requirements/module-04-game-library-discovery.md`), the approved
spec and reconciliation ledger (D1 cache/`Vary` deviation), the shared quality baseline, and
`docs/ai-workflow/project-state.md`'s recorded 4A/4B evidence. Selected threat playbooks from the module's
registry threat profile (`idor`, `input-validation`) plus the Module-4-specific
`docs/security/threat-playbooks/catalog-search.md` and `authorization-idor-bola.md`. Performed targeted
white-box source review (not live exploit automation) of every changed backend file against the light
checklist (auth, ownership, DTO privacy, input validation, CSRF/cookie assumptions, secrets), plus the
catalog-search playbook's filter/sort allow-listing, cache-key, and favorite-race requirements. Did not
re-run the full unit/integration/real-Postgres suite this session; cited the already-verified 4A/4B test
evidence recorded in `project-state.md` (independently verified in the orchestrating sessions) and
independently re-ran only `dotnet build SimPle.sln` to confirm a clean, unmodified current state. No secrets
were read; no destructive payloads or third-party systems were used.

**Post-frontend methodology:** delegated to the project's `security-reviewer` subagent (read-only tools:
Read/Grep/Glob/Bash) with the frontend-security and light checklists as its review method, scoped to the
files listed in the Module 4 `frontend.json` checkpoint's `changedFiles`. The subagent read every listed
source file directly (not just the checkpoint summary), grepped the frontend tree for
`dangerouslySetInnerHTML`, `innerHTML`, `eval(`, `localStorage`, `sessionStorage`, `document.cookie`, raw
`fetch()` calls bypassing the shared `apiFetch<T>()` client, `target="_blank"` without `rel=noopener`, and
hardcoded-looking secrets in test fixtures. It independently verified the two frontend-checkpoint claims
(no `?? GAMES[0]` fallback; all five entry actions honestly disabled) by reading current file contents rather
than trusting the checkpoint's prose. No files were modified; this phase used no `--fix`. The orchestrating
session (this document's author) reviewed the subagent's findings against the checkpoint evidence before
recording them below.

## Module Architecture Reviewed
- Existing UI reused: yes — card/tab/EmptyState/Skeleton components and dashboard layout preserved unchanged
  and reused rather than duplicated (per the frontend checkpoint's `qualityFindings`).
- Frontend integration points: `/games`, `/games/[gameId]`, the composed `/search` Games tab, the dashboard
  featured card, and the profile "Favorite games" tab, all wired to `GET /api/games`, `/featured`, `/{slug}`,
  `/me/favorites`, and the favorite-toggle mutation endpoints reviewed in the backend phase above. No new
  backend surface was added for this phase.
- Existing database impact: additive only. Five new tables (`games`, `game_tags`, `game_mode_capabilities`,
  `user_favorite_games`, `catalog_seed_history`), no columns dropped/altered/renamed on existing tables.
- Migration added: yes (`20260710072312_AddGameCatalog`, `20260710073819_AddGameLifecycleVersion`).
- Migration safety notes: `AddGameCatalog.Up()` is `CreateTable`/`CreateIndex`/`Sql` only (verified by
  grepping the migration source this session); the raw-SQL partial unique index
  `ux_games_featured_rank_one` (`WHERE "FeaturedRank" = 1`) is created in `Up()` with a matching
  `DROP INDEX IF EXISTS` as the first line of `Down()`. `AddGameLifecycleVersion` adds one `int` column with
  `defaultValue: 1`, additive. Both were applied and verified against real PostgreSQL in the 4A/4B sessions
  per `project-state.md`.
- Data preservation notes: `UserFavoriteGame` FK to `Game` is `DeleteBehavior.Restrict` (a game cannot be
  deleted out from under a favorite) and FK to `User` is `DeleteBehavior.Cascade` (account deletion removes
  favorites, matching the brief's account-deletion requirement). Retired games remain as tombstones, never
  deleted, so historical favorites keep resolving.
- Destructive DB changes: none.
- Backend/API/Swagger alignment: all six `GamesController` endpoints carry `[SwaggerOperation]` and
  `[ProducesResponseType]` attributes for their documented status codes (200/304/400/401/404/409/410/429).
- Frontend/API integration alignment: not applicable this phase (no frontend slice yet).

## Threat Model
Threat profile (module registry): `idor`, `input-validation`. Applicable playbooks: `catalog-search.md`
(SQL/filter injection, unbounded/catastrophic search, mass-assignment of lifecycle/capabilities, cache-key
authorization mistakes, favorite races, misleading availability) and `authorization-idor-bola.md` (missing
object ownership checks, predictable IDs, confused-deputy flows). Primary abuse cases considered: an
authenticated user mutating another account's favorites via a forged id; an anonymous caller forcing a
cache-poisoned authenticated-looking response; a crafted `%...%...%` search string causing a catastrophic
`LIKE` scan; a forged/replayed pagination cursor blending two different filter shapes' result sets; a
concurrent request racing to create two `featuredRank = 1` games or double-favorite the same game.

## Findings

### M04-001 - Name/Difficulty catalog sorts cannot use their declared indexes
- Severity: Low
- Affected asset: `GameRepository.GetCatalogPageAsync` (Name and Difficulty sort branches);
  `ix_games_name_slug` / `ix_games_difficulty_slug`.
- Description: the Name and Difficulty sort branches order by computed expressions
  (`g.Name.ToUpper()`, a CASE-based difficulty rank) but the supporting indexes are plain raw-column
  indexes, so PostgreSQL cannot use them for those two sort orders — confirmed via `EXPLAIN` with
  `enable_seqscan=off` still choosing a sequential scan (per the 4B test record,
  `Explain_DifficultySortKeyset_CannotUseRawIndex_DocumentedGap`). This is a performance/availability
  concern (an anonymous, rate-limited but still index-less sort path under load), not a data-exposure or
  authorization issue — the allow-list, page-size cap, and per-IP rate limit already bound worst-case cost
  per request.
- How it could be exploited, written safely: a caller repeatedly requesting `sort=name` or `sort=difficulty`
  against a much larger catalog than the current 8-row seed would force repeated sequential scans within the
  existing 120/min (or 30/min when combined with `query`) per-IP budget — a resource-consumption amplifier,
  not a bypass of any control.
- Evidence: `GameRepository.cs` sort branches; ground-truth `EXPLAIN` test in the 4B integration suite
  (`GamesEndpointsTests`/related Postgres tests) already documented as a known gap in
  `project-state.md`.
- Fix implemented: none this session (pre-existing, documented deviation; not part of the light-review
  fix scope and the catalog is only 8 rows in Phase 1).
- Verification after fix: n/a (deferred).
- Residual risk: Low. Bounded by existing rate limits and small current catalog size; would need an
  expression/functional index before a materially larger catalog.

### M04-002 - `user_favorite_games` favorites-list query has no supporting composite index
- Severity: Low
- Affected asset: `GameRepository.GetFavoritesPageAsync`; `user_favorite_games` table (only unique index is
  `(UserId, GameId)`).
- Description: `GetFavoritesPageAsync` filters on `(UserId, IsActive)` and orders by
  `(UpdatedAt DESC, Id DESC)` with no composite index covering that access pattern, so a user with a very
  large favorites history would force a sequential scan scoped to their own rows.
- How it could be exploited, written safely: not an authorization or data-exposure issue (the query is
  already scoped to the authenticated caller's own `UserId`); at most a self-inflicted latency cost bounded
  by the existing 60/min/account `game-favorites` rate limit.
- Evidence: `UserFavoriteGameConfiguration.cs` (single unique index only); documented in `project-state.md`
  as a known, accepted gap.
- Fix implemented: none this session (correctness unaffected at current data volumes; out of light-review
  fix scope).
- Verification after fix: n/a (deferred).
- Residual risk: Low.

### M04-003 - Correlation id remains unimplemented project-wide
- Severity: Info
- Affected asset: every `"Security: …"` structured log line in `Program.cs`, including the new
  `catalog-read`/`catalog-search`/`game-favorites` rate-limit rejection logs.
- Description: pre-existing, cross-cutting gap carried forward from Module 1-3 audits; no per-request
  correlation id exists to stitch a rejected request's log line to other logs for the same request.
- How it could be exploited, written safely: not directly exploitable; reduces incident-investigation
  efficiency only.
- Evidence: `Program.cs` rate-limit `OnRejected` handler comment ("No correlation-id infrastructure exists
  in this codebase yet (pre-existing gap, tracked separately)").
- Fix implemented: none (explicitly out of Module 4 scope; project-wide concern).
- Verification after fix: n/a.
- Residual risk: Info, carried forward unchanged.

### M04-004 - Art color/token values interpolate into CSS/SVG without validation
- Severity: Info
- Affected asset: `GameArt.tsx` (background gradient string interpolation, SVG `fill`/`stroke` attributes).
- Description: `artColorA`/`artColorB`/`artToken` are string-interpolated directly into a CSS gradient
  shorthand and SVG paint attributes with no format validation (e.g. no `#rrggbb` allow-list). If these
  values were ever attacker-controlled, a payload could inject a CSS `url()` into the background shorthand
  (external fetch/beacon). Not currently exploitable: the source is the server-curated Games catalog DTO
  (admin-authored), never user input.
- How it could be exploited, written safely: only reachable if a future module lets end users author or
  submit art tokens/colors for their own or others' games; no such surface exists in Module 4 or any shipped
  module.
- Evidence: `GameArt.tsx` background gradient construction (`radial-gradient(... ${a}33 ...), linear-gradient(180deg, ${b}, #07090F)`).
- Fix implemented: none this pass (not exploitable with the current trusted data source).
- Verification after fix: n/a (deferred).
- Residual risk: Info. Revisit with a `#rrggbb` hex-format validation if any future module lets non-admin
  input reach these fields.

### M04-005 - `gamesApi.getDetail` uses a raw `fetch` instead of the shared `apiFetch<T>()` wrapper
- Severity: Info
- Affected asset: `gamesApi.ts` `getDetail`.
- Description: deliberate deviation to preserve the `410` tombstone response body (`GameTombstoneDto`),
  which the shared wrapper's generic error path would otherwise discard. Verified the raw call still
  replicates every security-relevant convention: `credentials: 'include'`, `cache: 'no-store'`,
  `Accept: application/json`. It is a `GET` (no state change), so the shared wrapper's CSRF header is
  correctly not required here.
- How it could be exploited, written safely: not exploitable; documented as a confirmed non-issue.
- Evidence: `gamesApi.ts` `getDetail` implementation.
- Fix implemented: none needed.
- Verification after fix: n/a.
- Residual risk: Info, informational only.

### M04-006 - Client-side search input has no minimum-length guard matching the server's 2-char floor
- Severity: Info
- Affected asset: `LibraryPage.tsx`, `SearchResultsPage.tsx` search inputs.
- Description: a 1-character query is sent to the server, which correctly rejects it (2-100 char validation,
  reviewed in the backend phase) and surfaces as a generic error/empty state client-side. UX nit only — the
  client does not substitute for or weaken server-side validation.
- How it could be exploited, written safely: not exploitable.
- Evidence: search input handlers in `LibraryPage.tsx`/`SearchResultsPage.tsx`; server-side validation
  confirmed unchanged in the backend phase above.
- Fix implemented: none needed.
- Verification after fix: n/a.
- Residual risk: Info.

## Fixed Issues Summary
None required this pass — no Critical/High/Medium findings were identified in either phase.

## Deferred Issues
- M04-001 (Low) — Name/Difficulty sort index gap; revisit if Phase 1 catalog size grows materially beyond
  the current 8-row seed.
- M04-002 (Low) — favorites-list composite index gap; revisit if per-user favorite counts grow large.
- M04-003 (Info) — project-wide correlation id, tracked outside Module 4.
- M04-004 (Info) — art color/token CSS/SVG interpolation has no format validation; revisit only if a future
  module lets non-admin input reach these fields.
- M04-005 (Info) — documented, confirmed-safe deviation from the shared `apiFetch` wrapper in `getDetail`.
- M04-006 (Info) — client search input has no client-side min-length guard; server validation is unaffected.
- All items already listed as deviations in `project-state.md`'s 4B section (ETag design, 410 envelope
  shape, multi-value filter cardinality cap of 5, `UserFavoriteGame` concurrency via outbox uniqueness
  instead of a row-version token) were reviewed and are consistent with the approved spec/reconciliation;
  none introduce a new Critical/High security exposure.
- Frontend-slice deviations already listed in `project-state.md` (legacy `mock/games.ts` retained for 5
  out-of-scope consumers; `GameDetailPage.tsx` uses local `notFoundMessage` state instead of Next.js
  `notFound()`; Playwright E2E spec written but not executed this session) were reviewed and introduce no new
  security exposure; the E2E spec's execution remains deferred to `/simple-verify-checkpoint` per the
  manifest's own documented expectation.

## Tests/Security Checks Run
- `dotnet build SimPle.sln --nologo -v:q` (this session): 0 errors, 0 warnings.
- Cited, already-verified evidence from the 4A/4B implementation sessions (see
  `docs/ai-workflow/evidence/checkpoints/module-04-game-library-discovery/backend.json`): 36/36 +
  412/412 unit tests, 13/13 + 219/219 non-Postgres integration tests, and 32/32 real-PostgreSQL tests
  (including `Search_PercentWildcardInQuery_IsEscaped_MatchesOnlyLiteralSubstring`,
  `..._UnderscoreWildcardInQuery_...`, `RefavoriteRace_TwoContextsReactivateSameInactiveRow_...`, and the
  single-featured partial-unique-index rejection test), all passing.
- White-box source review this session: `GamesController.cs`, `GamesService.cs`, `GameRepository.cs`,
  `Cursor.cs`, all Games DTOs, `GameEntryActions.cs`, `GameConfiguration.cs`,
  `UserFavoriteGameConfiguration.cs`, the `AddGameCatalog` migration body, and the
  `catalog-read`/`catalog-search`/`game-favorites` rate-limiter policies in `Program.cs`.
- **Post-frontend session:** cited, already-verified evidence from the frontend checkpoint
  (`docs/ai-workflow/evidence/checkpoints/module-04-game-library-discovery/frontend.json`): `npx tsc --noEmit`
  clean, `npm run lint` clean, `npm run test` (vitest) 223/223 passing, `node scripts/check-contract-drift.mjs`
  DRIFT=0. No frontend test suite was re-run this session; the security-reviewer subagent performed a
  read-only white-box source review (via Read/Grep) of every file in the frontend checkpoint's
  `changedFiles`: `gamesApi.ts`, `types.ts`, `routes.ts`, `api-client.ts`, `GameArt.tsx`, `LibraryPage.tsx`,
  `GameDetailPage.tsx`, `DashboardPage.tsx`, `app/(app)/games/page.tsx`, `SearchResultsPage.tsx`,
  `ProfilePage.tsx`, `CreateLobbyModal.tsx`, `LandingPage.tsx`, `gamesApi.test.ts`, and the new Playwright E2E
  spec (grepped for hygiene only, not executed). Repo-wide greps run for `dangerouslySetInnerHTML`,
  `innerHTML`, `eval(`, `localStorage`, `sessionStorage`, `document.cookie`, raw `fetch()` bypassing
  `apiFetch<T>()`, and `target="_blank"` without `rel=noopener` across `SimpLe.Frontend/src`.

## Files Changed
None (review-only; no `--fix` requested, no product code modified in either phase). Evidence artifacts added
this session:
- `docs/ai-workflow/evidence/checkpoints/module-04-game-library-discovery/backend.json` (catch-up emission
  for the already-completed 4A/4B backend slice; see that file's `deferredItems` for why it was emitted
  retroactively in this session rather than at 4B's own close).
- `docs/ai-workflow/evidence/checkpoints/module-04-game-library-discovery/security.json` (backend stage).
- `SimPle.Project/docs/security/audits/module-04-game-library-discovery.md` (this file, replacing the stale
  pre-implementation placeholder, then extended this session with the post-frontend phase).
- `docs/ai-workflow/evidence/checkpoints/module-04-game-library-discovery/frontend-security.json`
  (post-frontend stage, this session).

## Final Security Status
Backend phase: **CLOSED, zero unwaived Critical/High findings.** 2 Low + 1 Info, all deferred as documented
above and consistent with light-review depth.

Post-frontend phase: **CLOSED, zero unwaived Critical/High findings.** 0 Medium/Low + 3 Info (M04-004,
M04-005, M04-006), all confirmed non-exploitable given the trusted server-side data source and
server-authoritative access control, and deferred as documented above. `securityGate`: 0 unwaived
Critical/High across both phases combined; no waivers were needed. Module 4's declared `frontend-security`
stage (`.claude/config/module-stage-manifest.json`) is satisfied.

## Reviewer Notes
This review also discovered and resolved a workflow-evidence gap unrelated to product security: the
Module 4 `backend` stage checkpoint had never been emitted (only `planning.json` existed in the checkpoint
index) despite 4A/4B being complete and documented in `project-state.md`. Per explicit user decision, a
`backend.json` checkpoint was constructed from the already-verified 4A/4B record and a fresh confirmation
build, then emitted before this `security` checkpoint — see that file's `deferredItems` field for full
disclosure. No product code was changed to produce either checkpoint.

**Post-frontend session note:** the frontend-boundary review itself was delegated to the `security-reviewer`
subagent (read-only), per the workflow's default of using read-only subagents for research/review; its
findings were checked against the frontend checkpoint's evidence by the orchestrating session before being
recorded in this document. No product code was changed. This closes all 8 of Module 4's manifest-required
checkpoint stages that precede verification: planning, backend, security, frontend, frontend-security.

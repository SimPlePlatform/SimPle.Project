# Testing Report - Module 06: Lobby & Matchmaking System

## Test Strategy

Backend domain invariants, command validation, and race-condition correctness are covered by xUnit unit
tests, in-memory/HTTP-contract integration tests, a fake-clock suite for the matchmaking bands and
expiry boundaries, and a real-PostgreSQL suite run against disposable scratch roles for migration/
concurrency/race proof (including a two-worker double-claim test). Frontend wiring is covered by Vitest
(component + API-client tests). A dedicated Playwright E2E spec
(`module-06-lobby-matchmaking.spec.ts`) was written during the frontend slice and **executed against a
live local stack (real backend :5147 + frontend :3000 + real Postgres, no mocks) at the verification
stage and passed (2/2)**, after a fix-and-rerun loop that found and fixed one real product bug and two
real accessibility defects. Backend, both security review phases, frontend, and verification were each
completed as separate sessions/slices; this docs pass writes from their already-recorded evidence only —
no new test or build command was run to produce this report.

## Coverage Target

90%+ meaningful module coverage (advisory).

## Coverage Result

Backend: **UnitTests 862/862** (full solution), **IntegrationTests 375/375** (0 failed, real PostgreSQL —
migration, CHECK/UNIQUE/FK/partial-index, concurrent last-seat-join, two-worker double-claim, cross-table
one-active-lobby-or-ticket, serialization/deadlock retry, credential collision/rotation, expiry sweep, and
outbox atomicity suites all included). A statement/branch coverage percentage was not collected this
module; `dotnet test SimPle.sln --collect:"XPlat Code Coverage"` remains the command to regenerate one.
Frontend: `npx vitest run` **243/243** passing across 24 test files.

## Commands Run

```bash
# Backend (6A/6B/6C sessions)
dotnet build SimPLe.Backend/SimPle.sln                        # 0 errors, 0 new warnings (3 pre-existing)
dotnet test tests/SimPle.UnitTests                            # 862/862
dotnet test tests/SimPle.IntegrationTests                     # 375/375, real Postgres

# Security review (backend phase, then post-frontend phase)
--security=asvs-lite backend-phase review                     # zero unwaived Critical/High/Medium
--security=asvs-lite post-frontend-phase review                # zero unwaived Critical/High/Medium

# Frontend (frontend slice)
cd SimpLe.Frontend
npx tsc --noEmit                                              # clean
npm run lint                                                  # initially 10 errors + 1 warning, fixed; re-run clean
npx vitest run                                                # 243/243
node scripts/check-contract-drift.mjs                          # DRIFT=0 (85 backend routes, 71 frontend calls)
npm run build                                                  # Next.js production build, all 19 routes generated

# Verification (live stack, this checkpoint)
dotnet ef database update --project SimPLe.Backend/src/SimPle.Infrastructure \
  --startup-project SimPLe.Backend/src/SimPle.Api             # applies the Module 6 migration
dotnet run --project SimPLe.Backend/src/SimPle.Api -- --seed-game-capabilities   # 8 created, 0 updated
dotnet run --project SimPLe.Backend/src/SimPle.Api -- --publish-game chess-lite  # promotes a game to Available
npm run test:e2e -- tests/e2e/module-06-lobby-matchmaking.spec.ts   # 5 reruns during fix loop, final: 2 passed, 0 failed
npm run lint                                                   # clean (re-confirmed)
npx vitest run                                                 # 243/243 (re-confirmed)
node scripts/check-contract-drift.mjs                          # DRIFT=0 (re-confirmed, unchanged)
```

## Unit Tests

Backend combined total **862/862**, including lobby/membership/invite/ticket lifecycle transition and
illegal-transition rejection tests, readiness-reset-scope tests (every settings change and every
join/leave/kick, host implicitly ready and never reset), deterministic host-transfer tests
(longest-tenured, user-id tie-break, close-when-none), capability-validation tests against the pinned
`GameCapabilityProfile`, matchmaking band-selection and group-compatibility tests covering the full
4-level tie-break ordering, credential generation-entropy and constant-time digest-compare tests, region
resolution (`Auto` → profile → deployment default), and a dedicated fake-clock suite proving the exact
15/30/60-second band boundaries (at, just below, and just above each), the 2-hour lobby expiry, the
30-minute credential/invite expiry, and that using a credential does not extend its own deadline — only
provable with the injected `TimeProvider`, since wall-clock tests would be flaky at these boundaries.

## Integration Tests

Non-Postgres HTTP-contract tests cover every endpoint's happy path, auth, CSRF, validation, and error
mapping; idempotency-key replay; stale-revision conflict; BOLA proof that another user's lobby/ticket/
invite id returns the privacy-safe not-found, never a 403; wrong/expired/rotated code indistinguishable
from closed; rate-limit rejection with `Retry-After`; and `Start` returning
`Lobbies.MatchRuntimeUnavailable` while no engine/runtime is registered (pinned by
`Start_WithNoEnginesInstalled_BlamesTheMissingRuntime_NotTheLobbysCapability`, confirming deviation R7's
check ordering). Real-PostgreSQL tests (`[SkippableFact]`, throwaway database per class) prove: the
migration applies cleanly; every partial unique index, CHECK, and FK behaves as specified; concurrent
last-seat joins produce exactly one winner; two competing workers claiming matchmaking tickets under `FOR
UPDATE SKIP LOCKED` produce **zero duplicate assignment**; the cross-table one-active-lobby-or-ticket
invariant holds under concurrent attempts; serialization/deadlock retries rerun the whole
`BoundedTransactionRetry`-wrapped command and never surface a raw 500; credential collision and rotation
behave correctly; the expiry sweep closes/cancels on schedule; and the outbox commits its state change and
event together or not at all. During this suite's development, an integration test caught an
over-restrictive first version of the `ck_matchmaking_tickets_no_worker_while_queued` CHECK constraint,
which was rewritten — see "Bugs Found During Testing." Combined real-Postgres total is included in the
**375/375** integration figure above.

## Security/Authorization Tests

The `--security=asvs-lite` review
(`SimPle.Project/docs/security/audits/module-06-lobby-matchmaking-system.md`) covered both the backend
phase and a post-frontend phase and found **zero unwaived Critical/High/Medium findings** in either. Backend
phase: one Low finding (**M06-001**, the join-failure throttle is per-instance in-memory and does not share
state across horizontally scaled deployments — bounded, since a single instance still throttles correctly)
and three Info findings (**M06-002** through **M06-004**, including the advisory-lock key's 64-bit GUID
truncation). Post-frontend phase: one Low finding (**M06-005**, the join credential persists in browser
`sessionStorage` under a per-lobby key and is not cleared on leave/kick/close — bounded by same-origin/
per-tab storage, ~60-bit code entropy, and the confirmed absence of any XSS sink in the reviewed diff) and
two Info findings (**M06-006**, a persisted credential carries no generation tag so a stale code can remain
displayed in another tab, but the backend safely rejects it; **M06-007**, route-id interpolation without
`encodeURIComponent`, exercised only with server-issued GUIDs, never attacker-controlled input). The primary
threat profile flagged for this module in the module registry — IDOR, authorization, abuse — was
independently verified closed by construction across five focus areas in each phase: BOLA on tickets/
lobbies/invites (privacy-safe not-found, not 403), credential-oracle prevention (wrong/expired/rotated/
closed indistinguishable, throttled), cross-table advisory-lock parity for the one-active invariant, the
outbox dead-letter path never logging exception message or PII, and the matchmaking worker's M8 gate on the
frontend side (no toast or navigation claims a deferred action succeeded).

## Frontend Tests If Applicable

- Existing UI reused: yes (`Modal`/`Button` primitives, `/lobby/[lobbyId]` route, composed search shell,
  dashboard cards, profile action buttons, game-detail entry-action rows).
- Frontend integration points tested: `CreateLobbyModal.tsx`, `QuickMatchModal.tsx`,
  `InviteFriendModal.tsx`, `LobbyPage.tsx`, `SearchResultsPage.tsx`'s Public Lobbies tab,
  `DashboardPage.tsx`, `GameDetailPage.tsx`'s new enabled/gating branches.
- Visual changes made: none beyond the one new approved surface (the Quick Match queue-status modal) and
  honest-disabled-state text for Start/chat/AI fill.
- `npm run lint` initially reported 10 errors and 1 warning across the six modified component files
  (`react-hooks/set-state-in-effect`, a `react-hooks/purity` violation from a `Date.now()` render call, one
  unescaped entity, one stale `eslint-disable`); confirmed via `git stash` that pre-Module-6 `HEAD` lints
  clean, so all 10 were newly introduced by this module. Fixed with the codebase's established
  `eslint-disable-next-line` convention plus one real refactor moving `Date.now()` out of render in
  `QuickMatchModal`'s `useElapsedSeconds` hook; re-run clean (0 errors, 0 warnings).

## Realtime Tests If Applicable

Not applicable — Module 6 has no real-time surface. The Quick Match queue-status modal's 2-second poll and
its cleanup-on-unmount/terminal-state behavior are covered by Vitest, not a realtime test category.

## Database/Migration Checks

- Existing database impact: additive (`lobbies`, `lobby_members`, `lobby_invites`,
  `lobby_join_credentials`, `lobby_start_requests`, `matchmaking_tickets`, `matchmaking_assignments`,
  `game_capability_profiles` — all new tables; a new `AK_games_Slug` alternate key added to Module 4's
  `games` table).
- Migration added: `20260711195731_AddLobbyMatchmakingAndCapabilities`.
- Migration safety notes: forward-only/additive, verified on real PostgreSQL including every CHECK/UNIQUE/
  FK/partial-index behavior; raw `Sql` was required for the seven partial unique indexes (EF's fluent filter
  API cannot express all of them), matching Module 3's precedent for prefix-search indexes.
- Data preservation notes: no Module 1-5 data altered.
- Destructive DB changes: none.
- Applied and confirmed at verification: `dotnet ef database update` against local dev Postgres succeeded;
  `--seed-game-capabilities` created 8 capability profiles, 0 updated (idempotent on rerun, same
  advisory-lock + checksum pattern as `GameCatalogSeeder`, distinct lock key).

## Backend/API/Swagger Alignment

All 20 endpoints (17 under `/api/lobbies`, 3 under `/api/matchmaking`) carry `[SwaggerOperation]` +
`[ProducesResponseType]`; documented in full in `api-reference.md`.

## Frontend/API Integration Alignment

`node scripts/check-contract-drift.mjs` reports **DRIFT = 0** — 85 backend routes, 71 unique frontend
calls, re-confirmed unchanged after the verification-stage fixes. A small number of dynamic-path call sites
were manually verified against the controllers directly, the same pre-existing heuristic limitation already
accepted for Modules 3 and 4.

## Edge Cases Tested

Concurrent last-seat join (exactly one winner); two-worker matchmaking claim race (zero duplicate
assignment under `FOR UPDATE SKIP LOCKED`, correctness actually guaranteed by the partial unique index);
cross-table one-active-lobby-or-ticket enforcement under concurrency; serialization/deadlock retry
(whole-command rerun, never a 500); credential collision and rotation; wrong/expired/rotated/closed
credential indistinguishability; BOLA on lobby/ticket/invite ids; exact 15/30/60-second matchmaking band
boundaries under a fake clock; 2-hour lobby and 30-minute credential/invite expiry under a fake clock;
`Start` with zero engines/no runtime returning the honest `Lobbies.MatchRuntimeUnavailable` rather than
blaming the lobby's own capability; late ticket cancel after worker claim (200, not an error); outbox
atomicity (state change and event commit together or not at all); a new M3 block inside an open lobby
triggering the `LobbyBlockHandler`'s idempotent leave/remove. The live E2E scenario additionally proved:
sign-in, a real game-detail entry action reaching a genuine lobby-creation flow, the host's ready state
displaying correctly (implicitly ready, no unsupported toggle), the join code/link visible immediately to
the creator, leaving back to the dashboard, and Search's Public Lobbies tab rendering real backend data —
plus a zero-violation axe-core scan after two real accessibility fixes.

## Bugs Found During Testing

Two real product-code defects were found and fixed during this module's testing, both with explicit user
authorization:

- **Backend/frontend lifecycle-gating inconsistency** (found during live E2E verification):
  `GameDetailPage.tsx`'s `gatingReason()` never checked `game.lifecycle`, so the `create-lobby`/
  `quick-match`/`invite-friend` entry actions rendered enabled for any game regardless of catalog
  lifecycle, while `CreateLobbyModal.tsx` only ever listed `Lifecycle=Available` games for its own
  game-picker — and no code path anywhere (seeder or controller) ever called `Game.MakeAvailable()`, so no
  game could reach `Available` in any environment, making the entry actions unreachable end-to-end. Fixed
  by adding the lifecycle check to `gatingReason()` and adding a CLI-only `--publish-game <slug>`
  promotion flag to `Program.cs`, mirroring the existing `--seed-game-*` flag pattern (never an HTTP
  endpoint). Verified: `chess-lite` promoted to `Available` via direct SQL, the entry action then correctly
  gated end-to-end, and lobby creation became genuinely reachable.
- **`ck_matchmaking_tickets_no_worker_while_queued` CHECK constraint too restrictive** (found during
  backend integration testing, 6C): the original constraint rejected a valid intermediate state a
  worker-claim transition legitimately passes through. Rewritten to match the actual `Queued → Claimed`
  state machine; re-verified by the real-Postgres CHECK-behavior suite.

Two real, pre-existing accessibility defects, unrelated to this module's own feature code, were also found
and fixed during live E2E verification, with explicit user authorization, following the same `<h1>` pattern
Module 4's `ProfilePage.tsx` fix established:

- `SearchResultsPage.tsx` used a `<div className="page-title">` instead of an `<h1>` — a real axe
  `page-has-heading-one` violation. Fixed.
- `DashboardPage.tsx` used the same `<div className="page-title">` pattern — same violation, surfaced only
  after the E2E scenario's final rerun since the shared axe fixture scans only after a passing test. Fixed.

The E2E spec file itself also encoded two wrong assumptions about lobby behavior, corrected in the spec
only (no product code changed for these): it assumed the host starts "Not ready" and must toggle
readiness, but the host is implicitly ready by design and the action is deliberately omitted for the host —
the spec now asserts the host's seat shows "Ready" directly; and it assumed a separate "Reveal code" click
was needed, but the create-lobby response already returns and caches the join credential immediately, so
the code is already visible to the lobby's own creator. Two Playwright strict-mode locator collisions were
also fixed narrowly within the spec file (exact-match locators for the per-game "Create lobby" button vs.
the topbar's global shortcut, and for the Privacy toggle's "Public" button, whose wrapping `<label>` bleeds
its text into both toggle buttons' accessible names) — an in-scope test-only fix, consistent with the
Module 4 precedent that locator-specificity fixes do not require separate sign-off.

## Fixes Made After Test Failures

All fixes listed above under "Bugs Found During Testing" are already applied and re-verified by the same
passing runs: `module-06-lobby-matchmaking.spec.ts` 2/2 (final rerun, after five iterations of the
fix-and-rerun loop), `npm run lint` clean, `npx vitest run` 243/243, `node scripts/check-contract-drift.mjs`
DRIFT=0. No further backend product-code fixes were required after the CHECK-constraint rewrite in 6C.

## Remaining Untested/Deferred Items

- `scripts/run-module-e2e.mjs` could not be used as the invocation wrapper: `spawnSync npm.cmd EINVAL` on
  this Windows/Node environment, a pre-existing bug in the script's own `spawnSync` call unrelated to
  Module 6's logic. Worked around by invoking `npm run test:e2e -- <spec>` directly; the manifest-declared
  single-spec scope was still honored manually.
- `--seed-game-catalog` failed with a checksum mismatch this session, caused by `git core.autocrlf`
  normalizing `catalog.seed.v1.json` to CRLF in the working tree while the stored checksum was computed
  from the original LF git-blob bytes. Confirmed via direct SQL that the `games` table already had the
  complete, correct catalog data from an earlier real seed, so no reseed was actually necessary and no data
  was lost — a real fragility worth fixing eventually, out of this session's scope.
- `CreateLobbyModal.tsx`'s Privacy toggle wraps both the "Private (link)" and "Public" buttons in a single
  `<label>`, causing their computed accessible names to bleed into each other — a real, disclosable
  accessibility concern surfaced while diagnosing an E2E locator collision. Not fixed; worked around with
  an exact-match test locator instead.
- `Sidebar.tsx`'s "Active Lobby" nav item is hardcoded to the literal placeholder lobby id `SP-7F-29`
  instead of the caller's real active lobby (unlike `DashboardPage.tsx`'s own "Open active lobby" button,
  which correctly uses `activeLobby.lobbyId`). This link always renders and always resolves to a
  nonexistent lobby regardless of the signed-in user's real state — a real, pre-existing product defect
  discovered while diagnosing a stale test-lobby cleanup step. Not fixed in this session; out of the
  explicitly authorized scope.
- Module 4's deferred `.page-title` → `<h1>` sweep is now closer to complete (Search and Dashboard fixed
  this module, Profile fixed in Module 4) but not exhaustive across every feature page; remaining pages
  were not audited this session.
- M06-001 and M06-005 (Low) remain open and deferred, bounded as described in "Security/Authorization
  Tests" above.
- Coverage honesty: the live E2E run proves exactly the two scenarios `module-06-lobby-matchmaking.spec.ts`
  encodes (a full private-lobby create/ready/reveal/leave flow, and Public Lobbies discovery), both against
  a live backend + frontend + real Postgres with no mocks. It is not a full audit of every Module 6 page/
  state, and `check-contract-drift.mjs` remains a static heuristic that does not by itself validate runtime
  behavior.
- **Blocking M8 handoff item:** the matching worker and `Start` are both gated behind
  `IMatchRuntimeProbe` and are dormant in production. Only a post-M8 integration test may close this item;
  Module 6 completion does not and may not claim a playable room.
- Local test-fixture cleanup (operational, not code): a stale open lobby left behind by an earlier failed
  E2E rerun was closed via a one-off throwaway script calling `POST /api/lobbies/{id}/leave` against the
  `e2e-test-user` account, found via `GET /api/lobbies/me/active`; no product code was touched.

## Final Status

Backend (862/862 unit, 375/375 integration including real-Postgres migration/concurrency/race suites) and
frontend (243/243 vitest, DRIFT=0) are green. The `--security=asvs-lite` review found zero unwaived
Critical/High/Medium findings across both the backend and post-frontend phases; two Low and five Info
findings are recorded and deferred, none blocking. **The dedicated Playwright E2E scenario has been
executed against a live local stack and passed (2/2)**, after a fix-and-rerun loop that found and fixed one
real cross-cutting product bug (the game-lifecycle gating gap, closed by adding the `--publish-game` CLI
promotion path) and two real pre-existing accessibility defects (`SearchResultsPage.tsx` and
`DashboardPage.tsx`'s missing `<h1>`), plus corrected two wrong assumptions and two locator collisions
within the E2E spec itself. Four items remain disclosed-but-unfixed, out of this verification session's
authorized scope: the Privacy-toggle label accessible-name bleed, `Sidebar.tsx`'s hardcoded placeholder
active-lobby link, the `run-module-e2e.mjs` Windows `spawnSync` bug, and the catalog seeder's autocrlf
checksum fragility. Evidence:
`docs/ai-workflow/evidence/checkpoints/module-06-lobby-matchmaking-system/verification.json`. **Module 6
completion carries a blocking M8 handoff item** — the matching worker and Start are dormant behind
`IMatchRuntimeProbe` until Module 8 registers a runtime, and only the post-M8 integration test may close it;
this module does not and may not claim a playable match room. **Module 6 is locally complete.** Hosted CI,
portable staging, release provenance, and cloud deployment evidence are separate Module 14
responsibilities; none is claimed by this local module evidence.

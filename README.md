# SimPle

**SimPle** is a full-stack social gaming platform. Users create accounts, build
friend lists, host lobbies, chat in real time, and compete across a growing
catalog of online games. The platform is designed so each game can plug into the
host platform instead of being hard-coded into the app shell.

---

## Repositories

| Repository | Description |
|---|---|
| [SimPlePlatform/SimPLe.Backend](https://github.com/SimPlePlatform/SimPLe.Backend) | ASP.NET Core 8 backend: auth, API, database, tests |
| [SimPlePlatform/SimpLe.Frontend](https://github.com/SimPlePlatform/SimpLe.Frontend) | Next.js 16 frontend: UI, auth pages, app shell, tests |

---

## Phase Overview

| Phase | Scope |
|---|---|
| **Phase 1** | Social gaming host platform: auth, profiles, friends, game library, game-hosting architecture, lobbies, realtime, chat, match room, stats, notifications, admin, subscriptions, security/production readiness, trust & legal/compliance surfaces |
| **Phase 2** | Actual games: Five-Letter Duel, Online Sudoku, Four in a Row, Falling Blocks Arena, Chess Lite, Checkers, Memory Grid, Snake Rush |
| **Future** | Hardware-enabled games via embedded devices |

Phase 1 builds everything around the games. Phase 2 adds the games themselves
using the hosting architecture created in Phase 1.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Next.js 16 (App Router), TypeScript, Tailwind CSS |
| Backend | ASP.NET Core 8, C# |
| Database | PostgreSQL + Entity Framework Core 8 |
| Auth | JWT HttpOnly access cookie + rotating hashed refresh tokens |
| Password hashing | Argon2id |
| OAuth | Google Identity Services ID token flow |
| CAPTCHA | Google reCAPTCHA v2 server-side verification |
| Email | MailKit / SMTP |
| Real-time | SignalR, planned |
| Testing | xUnit + NSubstitute, Vitest |

---

## Architecture

The backend follows Clean Architecture with a modular monolith structure:

```text
SimPle.Api -> SimPle.Application -> SimPle.Domain
                       |
           SimPle.Infrastructure
           EF Core, JWT, Argon2, SMTP, external services
```

Each feature module is a folder inside the application/domain/infrastructure
layers, not a separate service. This keeps deployment simple while keeping
module boundaries clear.

The frontend is a Next.js App Router application. The `(app)` route group wraps
authenticated pages in the shared `AppShell` layout. Feature components live in
`src/features/`, UI primitives in `src/components/ui/`, and current planned
product data lives in `src/mock/`.

---

## Current Status

### Module 1: Authentication & Account Security - Complete Core Scope

| Area | Status |
|---|---|
| Email/password register, login, logout, refresh | Done |
| JWT access cookie and rotating hashed refresh tokens | Done |
| Email verification and password reset | Done |
| Google OAuth ID token flow and account linking | Done |
| reCAPTCHA v2 on login and registration | Done |
| Rate limiting, account lockout, CSRF checks, secure headers | Done |
| Optimistic concurrency on refresh rotation | Done |
| Security event logging and token cleanup background service | Done |
| Change password, change email, active sessions, revoke session, delete account | Done |
| Backend: 120 unit + 59 integration tests | Done |
| Frontend auth pages, protected routes, Google Sign-In, account security settings wired | Done |

### Module 2: User Profile & Social Identity - Complete Local Scope

| Area | Status |
|---|---|
| Backend: UserProfile fields on User entity (StatusMessage, Visibility, avatar/banner object keys, fallback color) | Done |
| Backend: Default profile exists for every registered user | Done |
| Backend: Current-user profile endpoint | Done |
| Backend: Public profile endpoint with visibility rules | Done |
| Backend: Profile update (display name, bio, region, status, fallback avatar color, visibility) | Done |
| Backend: S3 presigned upload flow for avatar and cover images | Done |
| Backend: Local MinIO support for S3-compatible profile media storage | Done |
| Backend: AWS S3 production path preserved through storage configuration | Done |
| Backend: Monthly username change policy with immediate change and admin-review request tracking | Done |
| Backend: External social links (GitHub, X/Twitter, Instagram, Discord, website) | Done |
| Backend: Profile type social identity (`Player`, `Developer`) | Done |
| Backend: Game interest tags (board-games, word-games, puzzle, strategy, arcade, casual, card, trivia) | Done |
| Backend: EF Core migration `AddUserProfiles` | Done - verified locally |
| Backend: 25 unit + 16 integration tests for profile scope | Done |
| Frontend: ProfilePage wired to real profile API | Done |
| Frontend: SettingsPage profile card wired to real profile API | Done |
| Frontend: Topbar/Sidebar identity already wired via auth session | Done |
| Security: Ownership checks, safe DTOs, visibility rules, validation | Done |
| Production: CloudFront delivery and deployed S3 verification | Pending deployment |

### Module 3: Friends & Social Graph - Revision 2 Complete, Merged to Main

The original revision-1 backend/security/frontend/E2E evidence remains valid for the narrower friendship
contract. A later product-journey audit found that global people search, canonical profile routing, identity
links, relationship-aware profile actions, and privacy-aware profile/mutual friend drill-down were not in that
contract. Module 3 was reopened before Module 4; the revision-2 backend, frontend, live E2E verification,
production review, and final evidence sign-off are now all complete (including two real bugs found and fixed
during the live E2E run — see `docs/modules/module-03-friends-social-graph/testing-report.md`), and the module
is **merged to `main`** in both `SimPLe.Backend` and `SimpLe.Frontend`.

| Area | Status |
|---|---|
| Backend: 16 `/api/friends` endpoints (list/search, requests, discovery, suggestions, blocks, settings) | Done |
| Backend: Friendship/Block/UserFriendSettings/DismissedFriendSuggestion domain + migrations | Done - verified on real PostgreSQL |
| Backend: Transactional integration-event outbox (7 event types staged with the aggregate write) | Done |
| Backend: Cross-send auto-accept, decline/cancel cooldowns, block atomicity, concurrency retry | Done |
| Backend: 273 unit + 187 integration tests (incl. 18 real-Postgres concurrency/migration tests) | Done - 0 failed, 0 skipped |
| Security: BOLA/IDOR to privacy-safe 404, timing-safe discovery, per-account rate limits | Done - `--security=asvs-lite`, no Critical/High findings |
| Security: Audit-event logging for denials | Done - M03-006 fixed |
| Security: Block-endpoint response minimality | Done - M03-007 fixed |
| Frontend: `/friends`, dashboard, sidebar badge, invite picker, settings privacy/blocks wired to real API | Done |
| Frontend: 96 Vitest tests across 7 reconciled suites; contract-drift check DRIFT=0 | Done |
| Verification: Two-user Playwright E2E against a live local stack | Done - 1/1 passed |
| Revision 2: canonical `/u/{username}` route and public/authenticated profile behavior | Done |
| Revision 2: composed people search, identity links, and relationship-aware profile actions | Done |
| Revision 2: privacy-aware target/mutual friends lists with 20/50 keyset pagination | Done |
| Revision 2: independent search/request/friends-list visibility and abuse caps | Done |
| Revision 2: remove fake profile presence/ELO/history/achievements/favorites | Done |
| Revision 2: backend 321 unit + 224 integration; frontend 188 Vitest; contract-drift DRIFT=0 | Done - 0 failed |
| Revision 2: security findings M03-008/M03-009/M03-011 fixed, M03-010 resolved (product decision) | Done - independently re-verified |
| Revision 2: expanded 3-user/anonymous navigation, privacy, and pagination Playwright | Done - 1/1 passed, 25.7s, live local stack |
| Revision 2: production review and final evidence sign-off | Done - merged to `main` |

### Module 4: Game Library & Discovery - Backend/Frontend/E2E Verified, Production Review Pending

Backend, both security review phases, frontend, and live E2E/accessibility verification are complete and
independently verified. Module 4 is also the first module whose `module-e2e-manifest.json` entry sets
`accessibilityPolicy: "required"`; the required axe-core scan surfaced 6 real accessibility defects in shared
app-shell code (not Module 4 code), which were fixed with explicit user sign-off before the scan went clean.
Documentation (`api-reference.md`, `technical-flow.md`, `testing-report.md`) is complete — see
`docs/modules/module-04-game-library-discovery/`. The module is **not yet complete**: production review and
final evidence sign-off are still outstanding.

| Area | Status |
|---|---|
| Backend: 6 `/api/games` endpoints (catalog list/detail/featured, favorites list/PUT/DELETE) | Done |
| Backend: `Game`/`GameTag`/`GameModeCapability`/`UserFavoriteGame`/`CatalogSeedHistory` domain + migrations | Done - verified on real PostgreSQL |
| Backend: Advisory-lock + checksum-idempotent catalog seeder (8 canonical games) | Done |
| Backend: Query-shape-bound keyset cursor, ETag/304 revalidation, lifecycle state machine | Done |
| Backend: 412 unit + 219 integration tests (incl. 32 real-Postgres tests) | Done - 0 failed |
| Security: `--security=light` backend-phase and post-frontend-phase review | Done - zero unwaived Critical/High/Medium; 2 Low + 4 Info deferred |
| Frontend: `/games`, detail, dashboard, search, and profile favorites wired to real API | Done |
| Frontend: 223 Vitest tests; `check-contract-drift.mjs` DRIFT=0 | Done |
| Verification: Playwright E2E against a live local stack | Done - 2/2 passed |
| Verification: First module to enforce `accessibilityPolicy: "required"`; 6 axe violations fixed in shared app shell | Done - zero violations after fix |
| Documentation: `api-reference.md`, `technical-flow.md`, `testing-report.md` | Done |
| Production review and final evidence sign-off | Pending |

### Modules 5-14, 16: Planned; Module 15 Future

The frontend already includes mock UI for dashboard, profile, settings, friends,
game library, game detail, lobby, chat, match room, leaderboards, and
notifications. These screens are the product target, but they are not all wired
to backend APIs yet.

The roadmap below assigns every visible mock UI surface to a module so that when
the project is complete, the current UI can be 100% functional as intended.

---

## Quick Start

### Backend

```powershell
cd backend
dotnet restore
.\scripts\Initialize-AuthEnvironment.ps1
docker compose -f compose.auth.yml up -d
dotnet ef database update --project src/SimPle.Infrastructure --startup-project src/SimPle.Api
dotnet run --project src/SimPle.Api
```

Swagger runs at `https://localhost:7139/swagger` when the backend is running.

### Frontend

```bash
cd frontend
npm install
cp .env.local.example .env.local
npm run dev
```

The frontend runs at `http://localhost:3000`. The backend API must be running at
`NEXT_PUBLIC_API_URL`, defaulting to `http://localhost:5147`.

---

## Modules & Features Roadmap

### Module 1: Authentication & Account Security

Purpose:
- Secure account creation, sign-in, browser sessions, account recovery, and
  account-security settings.

- [x] Email/password register, login, logout, logout-all, refresh token flow
- [x] Current user endpoint
- [x] JWT access cookie and hashed rotating refresh token storage
- [x] Email verification and resend verification
- [x] Password reset request and confirmation
- [x] Google OAuth ID token flow and account linking
- [x] Frontend auth pages wired and tested
- [x] Rate limiting, validation, secure cookies, CSRF header, security headers
- [x] reCAPTCHA on login and registration
- [x] Account lockout and suspension enforcement
- [x] Security event logging and token cleanup background service
- [x] Change password (verifies current, revokes all sessions)
- [x] Change email flow (verification link to new address)
- [x] Active sessions list with IP and device info
- [x] Revoke individual session
- [x] Revoke all sessions / sign out all devices
- [x] Account delete with password confirmation
- [ ] Google OAuth link/unlink management (planned)
- [ ] Production PostgreSQL migration verification (pending deployment)

Status: **Complete** for core auth and account-security settings.

### Module 2: User Profile & Social Identity

Purpose:
- Public social identity, profile page, and profile-settings UI wired to the backend.

- [x] Display name, bio, region, status message, fallback avatar color, avatar/banner display URLs
- [x] Avatar/profile picture upload, replace, remove, and fallback avatar color
- [x] Cover/banner upload, replace, remove, and fallback banner
- [x] Local MinIO support for S3-compatible profile media storage
- [x] AWS S3 production path preserved through storage configuration
- [x] Presigned upload flow for profile media
- [x] Avatar and banner image upload via private S3-compatible presigned URLs (JPEG/PNG/WebP, SVG not allowed, 5 MB / 10 MB limits)
- [x] Username/handle display; 1 immediate change and 1 admin-review request per UTC calendar month
- [x] Profile visibility: public, friends-only (owner-only until Module 3), private
- [x] Web profiles: external social links for Instagram, X/Twitter, website, GitHub, and Discord where supported
- [x] Privacy control: public and private profile visibility
- [x] Friends-only visibility stored/handled if present, with Module 3 behavior documented
- [x] Profile type: Player and Developer social identity distinction
- [x] Game interest tags (board-games, word-games, puzzle, strategy, arcade, casual, card, trivia)
- [x] Public profile page with visibility enforcement
- [x] Own profile page with inline edit
- [x] Settings page profile card wired to real API
- [x] Sidebar and topbar identity from real auth session
- [x] Role and legacy ELO display (read-only; revision-2 Module 3 removes it from production profile UI until M10)
- [x] Ownership checks and safe DTOs (no email/auth fields in public profile)
- [x] EF Core migrations: `AddUserProfiles`, `AddUsernameChangeRequests`, `AddProfileSocialIdentityFields`, `FixProfileSocialIdentityAndUsernamePolicy`
- [x] Unit and integration test coverage >90% for profile scope
- [x] `docs/modules/module-02-user-profile-social-identity/` documentation added
- [x] FriendsOnly visibility enforced per accepted friend (Module 3 revision 1)
- [ ] Production CloudFront delivery and deployed S3 environment verification (pending deployment)

Status: **Complete** for local/backend/frontend Module 2 scope. Production CloudFront delivery and deployed environment verification remain planned.

### Module 3: Friends & Social Graph

> Product behavior is authoritative in `../docs/module-requirements/module-03-friends-social-graph.md`;
> this roadmap records status only.

Purpose:
- Make friends, friend requests, suggestions, blocking, and friend-related
  privacy controls functional.

Current UI target:
- `/friends`
- Dashboard friends panels
- Friend request badge in sidebar
- Invite friend modal friend picker
- `/settings` -> Privacy -> friend request controls and block list

Included features:
- [x] Friend list (keyset-paged)
- [x] Search friends
- [x] Send, accept, decline, cancel friend requests (incl. cross-send auto-accept and cooldowns)
- [x] Remove friend
- [x] Suggested players
- [x] Mutual friends count
- [x] Block/unblock users
- [x] Friend request privacy: anyone, friends-of-friends, off
- [x] Friend count surfaced on profile
- [x] Safe exact-username discovery (Add Friend flow)
- [x] Canonical `/u/{username}` profile route; UUID/username/`me` ambiguity resolved (non-owner legacy ids
      show an honest "moved" state — no backend UUID→username lookup endpoint exists)
- [x] Authenticated bounded people search by username/display-name prefix
- [x] Profile navigation from every friend/request/suggestion/discovery/dashboard identity
- [x] Server-derived relationship state and Add/Cancel/Accept/Decline/Remove/Block/Share profile actions
- [x] Privacy-aware profile Friends and Mutual Friends drill-down with visible counts and keyset pagination
- [x] Independent profile, search, friend-request, and friends-list visibility controls
- [x] Composed topbar search shell: People now, Games/Public Lobbies explicitly labelled unavailable (M4/M6)
- [x] Truthful unavailable states instead of fake profile presence/ELO/history/achievements/favorites

Backend/database/API work:
- [x] Persist friendships, blocks, settings, suggestion dismissals, and a transactional integration-event
      outbox
- [x] Friends controller, service, repository, DTOs, validators (16 endpoints)
- [x] Enforce block rules across friend requests and visibility (chat/invites enforcement is out of scope
      until Modules 6/7 add those surfaces)
- [x] Real-PostgreSQL verification of expression uniqueness, `xmin` concurrency, CHECK/cascade, and migration
      backfill
- [x] People search, viewer-context, and friends/mutual-friends drill-down endpoints (5 new/changed
      revision-2 endpoints), independent search/friends-list visibility + `PrivacyPolicyVersion`, retired
      usernames, durable send caps — verified on real PostgreSQL (321 unit + 224 integration, 0 failed)

Frontend work:
- [x] Wire `/friends` tabs and actions to API
- [x] Replace mock friend counts, pending requests, and suggestions
- [x] Replace fake presence/activity/profile progression with honest unavailable states (deferred to
      M7/M10/M11 as documented placeholders, not silently faked)
- [x] Composed people search (`PeopleSearchCombobox`, `/search`), canonical profile page, shared
      `PlayerIdentity` component, friends/mutual-friends drill-down pages — 188 Vitest tests, DRIFT=0

Revision-1 verification (historical; superseded in scope by revision-2 evidence below):
- [x] Backend: xUnit 273 unit + 187 integration (incl. 18 real-Postgres tests), 0 failed, 0 skipped
- [x] Security review (`--security=asvs-lite`): no Critical/High production findings
- [x] Frontend: Vitest 96/0 across 7 reconciled suites, `check-contract-drift.mjs` DRIFT=0
- [x] Module E2E (Playwright, live local stack, two users): 1/1 passed
- [x] Revision-1 production review and final evidence

Revision-2 verification:
- [x] Backend: xUnit 321 unit + 224 integration (incl. real-Postgres migration/concurrency tests), 0 failed,
      0 skipped
- [x] Security review (`--security=asvs-lite`): no Critical/High findings; M03-008/M03-009/M03-011 fixed and
      M03-010 resolved by product decision, all independently re-verified
- [x] Frontend: Vitest 188/0 across all reconciled suites, `check-contract-drift.mjs` DRIFT=0
- [x] Module E2E: the expanded A/B/C/anonymous Playwright scenario (`module-03-friends.spec.ts`) executed
      against a live seeded local stack and **passed** (1/1, 25.7s) — proving composed search,
      request send/accept, authorized paginated friends drill-down (20→25 rows across the cursor boundary,
      no duplicates), live friends-list-visibility enforcement, anonymous Public/Private profile split,
      `/profile/me` canonical resolution, and block convergence across search/profile/friends-list/
      mutual-friends. Two real product bugs were found and fixed during this run: a `Cursor.cs` pagination
      defect and a `ProtectedRoute`/route-group gap blocking anonymous access to `Public` profiles (now a
      dedicated `(public)` route group) — see `testing-report.md`.
- [x] Production review and final evidence sign-off for the full revision-2 scope

Status:
- Revision 1 is complete and green (see `docs/modules/module-03-friends-social-graph/`, the security audit,
  and historical final evidence); M03-006 and M03-007 were fixed in a follow-up pass.
- Revision 2 backend (Steps 2A/2B), frontend (Steps 4A/4B), live E2E verification, production review, and
  final evidence are all implemented and independently verified, including a follow-up security fix pass
  verified (see `docs/security/audits/module-03-friends-social-graph.md`). **Module 3 is
  complete and merged to `main`** in both `SimPLe.Backend` and `SimpLe.Frontend`
  (`docs/ai-workflow/evidence/module-03-friends-social-graph/revision-2/final.json`).

### Module 4: Game Library & Discovery - Backend/Frontend/E2E Verified, Production Review Pending

> Product behavior is authoritative in `../docs/module-requirements/module-04-game-library-discovery.md`.

Purpose:
- Make the game library and game detail pages real before building matchmaking
  and match state.

Current UI target:
- `/games`
- `/games/[slug]`
- Dashboard continue-playing and recommended game cards
- Topbar/composed search Games tab
- Profile favorite games tab

Included features:
- [x] Game catalog (8 seeded games, lifecycle-aware: Draft/ComingSoon/Available/Maintenance/Retired)
- [x] Game detail pages, including an honest 410 tombstone for retired games
- [x] Search, filters (category/tag/mode, capped at 5 values/dimension), sort, keyset "load more"
- [x] Game rules/descriptions and difficulty display
- [x] Featured/spotlight game (single-featured-rank invariant enforced by a partial unique index)
- [x] Favorite games (soft-delete `IsActive`+`CycleId`, idempotent PUT/DELETE, real per-user persistence)
- [ ] Supported modes: solo, AI, multiplayer, ranked (entry actions honestly disabled, naming Modules 6/8/9)
- [ ] Active/disabled game state per-mode (deferred to owning modules; lifecycle state itself is real)

Backend/database/API work:
- [x] `GamesController` (6 endpoints), `GamesService`, `GameRepository`
- [x] Game DTOs matching the UI cards/detail page (`GameCatalogDto`, `GameTombstoneDto`, `GameFavoriteDto`,
      `GameEntryActionDto`)
- [x] Seeded initial game catalog via advisory-lock + checksum-idempotent `GameCatalogSeeder`
- [x] Two additive EF Core migrations, verified on real PostgreSQL

Frontend work:
- [x] Replaced `GAMES` mock data with live `gamesApi` calls on `/games`, detail, dashboard, search, profile
- [x] Play, Quick Match, Invite Friend, Create Lobby, and Enter Match Room buttons rendered honestly
      `disabled`, each naming its real owning module (6, 8, or 9) until that module ships

Verification:
- [x] Backend: 412 unit + 219 non-Postgres integration + 32 real-Postgres tests, 0 failed
- [x] Security review (`--security=light`, both backend and post-frontend phases): zero unwaived
      Critical/High/Medium findings; 2 Low + 4 Info findings recorded and deferred
- [x] Frontend: 223 Vitest tests, `check-contract-drift.mjs` DRIFT=0
- [x] Module E2E (Playwright, live local stack): `module-04-game-library.spec.ts` 2/2 passed; also the first
      module to enforce `accessibilityPolicy: "required"` — 6 real axe-core violations were found and fixed
      in shared app-shell code (with explicit user sign-off), after which the scan is clean
- [ ] Production review and final evidence sign-off (next)

Status:
- Backend, security (both phases), frontend, live E2E/accessibility verification, and documentation
  (`api-reference.md`, `technical-flow.md`, `testing-report.md`) are complete
  (see `docs/modules/module-04-game-library-discovery/`). Production review and final evidence sign-off
  remain before Module 4 is declared complete.

### Module 5: Game Hosting Architecture

> Product behavior and ownership boundaries are authoritative in
> `../docs/module-requirements/module-05-game-hosting-architecture.md`; Module 5 owns engine contracts,
> serialization, and registry behavior, while Module 8 owns persisted match sessions.

Purpose:
- Define how games plug into the platform without hard-coding each game directly
  into the app shell.

Included features:
- [ ] `IGameEngine` registration pattern
- [ ] Game state serializer pattern
- [ ] Generic deterministic engine state/command/view contracts
- [ ] Server-authoritative move validation contract
- [ ] Versioned terminal-result handoff contract; Module 10 owns rating/stats calculations

Backend/database/API work:
- [ ] Complete game engine registry/service
- [ ] Define engine-state serialization; persisted match/session ownership remains Module 8
- [ ] Add tests for engine lookup, deterministic commands, serialization, views, and terminal results

Frontend work:
- [ ] No major new UI required yet
- [ ] Existing room UI stays mock until Module 8

Status:
- Planned, with backend architecture stubs.

### Module 6: Lobby & Matchmaking System

> Product behavior is authoritative in `../docs/module-requirements/module-06-lobby-matchmaking-system.md`.

Purpose:
- Make the create-lobby modal and lobby page real.

Current UI target:
- Topbar Create Lobby button
- `/lobby/[lobbyId]`
- Game detail Create Lobby action
- Dashboard lobby invites and active lobby link

Included features:
- [ ] Create lobby
- [ ] Join lobby by code/link
- [ ] Leave lobby
- [ ] Public/private lobby
- [ ] Seats and max player count
- [ ] Ready state
- [ ] Host controls
- [ ] Invite links/codes with expiry
- [ ] Lobby settings: game, time control, ranked/casual, region, spectators
- [ ] AI fill toggle as a setup option, with actual AI behavior deferred to
      Module 9
- [ ] Required same-region Quick Match queue with deterministic widening per-game rating bands

Backend/database/API work:
- [ ] Persist lobbies and lobby slots
- [ ] Lobby controller, service, repository, DTOs, validators
- [ ] Capacity, expiry, privacy, and host authorization checks

Frontend work:
- [ ] Wire create/join/leave/ready/start actions
- [ ] Replace hard-coded `SP-7F-29` with real lobby codes
- [ ] Keep live updates and chat mock until Module 7

Status:
- UI only, with partial backend domain stub.

### Module 7: Real-Time Presence, Lobby Updates & Chat

> Product behavior is authoritative in `../docs/module-requirements/module-07-realtime-presence-chat.md`.

Purpose:
- Make online status, lobby updates, and chat live.

Current UI target:
- Presence dots in sidebar, topbar, friends page, lobby, and match room
- Lobby chat panel
- Match chat panel
- Lobby updates without refresh

Included features:
- [ ] Presence states: online, away, playing, in lobby, offline
- [ ] Lobby live updates over SignalR
- [ ] Lobby chat
- [ ] Match chat
- [ ] Persistent lobby chat with 30-day retention and authorized cursor history
- [ ] Basic abuse controls: length limits, rate limits, delete/flag hooks

Backend/database/API work:
- [ ] SignalR hubs for presence, lobby updates, and chat
- [ ] Chat persistence, retention, moderation evidence handoff, and reconnect snapshot convergence
- [ ] Authenticated hub connections

Frontend work:
- [ ] Wire `ChatPanel` to realtime events
- [ ] Replace mock presence/activity strings

Status:
- UI only, with backend notifier/chat stubs.

### Module 8: Generic Match Room & Match State

> Product behavior is authoritative in `../docs/module-requirements/module-08-generic-match-room-state.md`.

Purpose:
- Make `/room/[matchId]` represent a real server-authoritative match.

Current UI target:
- `/room/[matchId]`
- Match timers, turn state, players, score, pause, forfeit, result modal
- Sudoku-style mock board currently used as a room placeholder

Included features:
- [ ] Match/session entity
- [ ] Match participants
- [ ] Get current match state
- [ ] One authoritative move-command service used by REST/realtime/AI adapters
- [ ] Turn validation
- [ ] Pause/resume
- [ ] Forfeit
- [ ] Disconnect/timeout handling
- [ ] Result recording
- [ ] Match history source for profile/dashboard later

Backend/database/API work:
- [ ] Persist sessions, participants, moves/events, and results
- [ ] Match controller or hub
- [ ] Server-side move validation through Module 5 engine contracts

Frontend work:
- [ ] Replace local board, turn, and timer state with server state
- [ ] Keep game-specific polish limited until actual Phase 2 games

Status:
- UI only, with backend session stubs.

### Module 9: Solo vs AI Platform Flow

> Product behavior is authoritative in `../docs/module-requirements/module-09-solo-vs-ai-flow.md`.
> Phase 1 validates the AI platform against the internal reference engine; catalog entry points remain
> capability-disabled until a production game supplies an AI strategy.

Purpose:
- Make Play vs AI, AI difficulty, and AI-filled seats work.

Current UI target:
- Dashboard Play vs AI
- Game detail Play vs AI and difficulty chips
- Lobby AI fill
- Match room `Vs AI` state

Included features:
- [ ] AI match creation
- [ ] Difficulty levels
- [ ] AI player identity
- [ ] AI move generation through game engines
- [ ] Solo result recording
- [ ] Solo stats later through Module 10

Backend/database/API work:
- [ ] AI player service and strategies
- [ ] Integrate AI actions with Module 8 match state

Frontend work:
- [ ] Wire AI mode buttons to real match creation
- [ ] Replace hard-coded AI opponent display

Status:
- Planned, with frontend entry points.

### Module 10: Stats, Achievements & Leaderboards

> Product behavior is authoritative in `../docs/module-requirements/module-10-stats-achievements-leaderboards.md`.

Purpose:
- Make dashboard/profile/game/leaderboard stats real.

Current UI target:
- Dashboard stat cards, recent matches, daily quests, recommended games
- `/profile/[userId]` stats, ELO chart, match history, achievements, favorite games
- `/leaderboards`
- Game detail Your Stats and Leaderboard tabs
- Match result modal ELO changes

Included features:
- [ ] Per-game stats
- [ ] Per-game Elo as the sole rating authority, with an explicit migration from legacy global `User.Elo`
- [ ] Match history
- [ ] Win rate, streaks, best season
- [ ] Achievement definitions
- [ ] User achievement unlock/progress
- [ ] Global-within-selected-game leaderboards
- [ ] Friends leaderboards
- [ ] Season/tier display
- [ ] Three server-generated daily quests from versioned definitions tied to real events

Backend/database/API work:
- [ ] Stats service
- [ ] Achievement service
- [ ] Leaderboard service
- [ ] Tables for player stats, achievements, user achievements, seasons, match results
- [ ] Result ingestion from Module 8

Frontend work:
- [ ] Replace mock stats, charts, leaderboards, achievements, and match history
- [ ] Keep reward visuals passive unless Module 13 provides premium/billing behavior

Status:
- UI only.

### Module 11: Notifications & Activity Feed

> Product behavior is authoritative in `../docs/module-requirements/module-11-notifications-activity-feed.md`.

Purpose:
- Make the topbar notification bell, unread counts, preferences, and activity
  surfaces functional.

Current UI target:
- Topbar notification bell/dropdown
- Dashboard invite waiting text and lobby invite card
- `/settings` -> Notifications
- Friends page friend activity sidecar

Included features:
- [ ] In-app notifications
- [ ] Unread count
- [ ] Mark all read
- [ ] Dismiss/read individual notification
- [ ] Notification triggers for friend requests, lobby invites, match results,
      achievements, and system/season messages
- [ ] Notification preferences
- [ ] Privacy-filtered friend activity feed from the brief's allow-listed real events

Backend/database/API work:
- [ ] Notifications controller, service, repository, DTOs
- [ ] Notification preferences persistence
- [ ] Event triggers from other modules

Frontend work:
- [ ] Replace `NOTIFICATIONS` mock data
- [ ] Wire settings notification toggles

Status:
- UI only, with backend domain stub.

### Module 12: Moderation & Admin Dashboard

> Product behavior is authoritative in `../docs/module-requirements/module-12-moderation-admin-dashboard.md`.

Purpose:
- Support basic safety and admin review without adding unrelated enterprise
  features.

Included features:
- [ ] Report user/content
- [ ] Suspend/ban users
- [ ] Review flagged chat/profile content
- [ ] Admin action audit log
- [ ] Bounded operational moderation metrics defined by the module brief

Backend/database/API work:
- [ ] Admin/moderation controller and service
- [ ] Reports, suspension records, admin audit log
- [ ] Strict role checks

Frontend work:
- [ ] Admin dashboard after backend role checks exist

Status:
- Planned, not visible in current UI.

### Module 13: Premium / Subscription System

> Product behavior is authoritative in `../docs/module-requirements/module-13-premium-subscription-system.md`.

Purpose:
- Support account tiers only after the core social gaming flow works.

Included features:
- [ ] Display account tier if present
- [ ] Subscription plans
- [ ] Payment-provider abstraction
- [ ] Stripe sandbox hosted Checkout and Customer Portal behind `IPaymentProvider`
- [ ] Webhook handling
- [ ] Subscription status enforcement

Backend/database/API work:
- [ ] Subscription records and provider IDs
- [ ] Webhook event log
- [ ] Signature verification for webhooks

Frontend work:
- [ ] Billing/settings UI only when backend billing is real

Status:
- Planned; the existing `Free|Plus|Pro` enum is legacy compatibility input. Module 13 introduces the
  authoritative Free/Premium Supporter entitlement model and a documented additive migration.

### Module 14: Security, Testing & Production Readiness

> Product behavior and evidence levels are authoritative in
> `../docs/module-requirements/module-14-security-testing-production-readiness.md`.

Purpose:
- Keep every implemented module reviewable and honest.

Included features:
- [ ] Full input validation for every module
- [ ] OpenAPI docs for implemented APIs
- [ ] CI/CD checks
- [ ] Health checks
- [ ] Vulnerability scans
- [ ] PostgreSQL migration verification
- [ ] Production configuration review
- [ ] Security audit updates per module

Backend/frontend/docs work:
- [ ] Keep module docs current with actual implementation
- [ ] Do not claim production readiness until deployment and database checks are real

Status:
- Partially implemented for auth; ongoing.

### Module 15: Hardware-Enabled Games & Embedded Integration

Purpose:
- Future embedded-device game support after the web platform is stable.

Included features:
- [ ] Device pairing
- [ ] Device identity and authentication
- [ ] Hardware event ingestion
- [ ] Hardware-backed game room
- [ ] Device status display

Backend/database/API work:
- [ ] Hardware devices table
- [ ] Pairing codes
- [ ] Device event ingestion endpoint
- [ ] Replay/rate-limit protection

Frontend work:
- [ ] Pairing and device status UI later

Status:
- Planned, not visible in current UI.

### Module 16: Trust, Legal & Compliance Surfaces

> Product behavior is authoritative in
> `../docs/module-requirements/module-16-trust-legal-compliance-surfaces.md`.

Purpose:
- Give every user a reachable Terms/Privacy/cookie-consent, accessibility statement, help/changelog, and
  self-service "download my data" export surface — added as the last Phase 1 module, since no
  other module owned this and Module 14 explicitly excludes new product UI.

Included features:
- [ ] Terms of Service / Privacy Policy / cookie-consent pages and versioned consent recording
- [ ] Public accessibility statement page
- [ ] Help/FAQ and changelog pages
- [ ] Consolidated self-service data-export request/download flow
- [ ] Settings links to cookie preferences and to Module 1's existing account deletion

Backend/database/API work:
- [ ] `UserConsent` and `DataExportRequest` tables and endpoints
- [ ] Export aggregation job across Modules 2/3/10/11/13's existing per-module export data

Frontend work:
- [ ] Public legal/help/changelog/accessibility routes with sitewide footer links
- [ ] Cookie-consent banner and Settings export/consent controls

Status:
- Planned, not visible in current UI. See `docs/ai-workflow/module-registry.md` for the explicitly
  out-of-scope list (2FA/MFA, non-Google OAuth, tournaments, clans/guilds, referral program, guest play)
  closed out during the same gap-closure pass.

---

## Later Docs To Update

- Keep `docs/reviewer-notes.md` synchronized after each completed module.
- Add or update module docs and security audit notes from current evidence only;
  do not copy stale status from previous modules.
- Keep deployment caveats until production database, storage, CloudFront, CI/CD,
  and environment verification evidence exists.

---

### Phase 2: Actual Games

After Phase 1 is complete, games are added as plugins:

- [ ] Five-Letter Duel
- [ ] Online Sudoku
- [ ] Four in a Row
- [ ] Falling Blocks Arena
- [ ] Chess Lite
- [ ] Checkers
- [ ] Memory Grid
- [ ] Snake Rush

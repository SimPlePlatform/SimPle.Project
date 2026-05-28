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
| [SimPlePlatform/SimpLe.Frontend](https://github.com/SimPlePlatform/SimpLe.Frontend) | Next.js 14 frontend: UI, auth pages, app shell, tests |

---

## Phase Overview

| Phase | Scope |
|---|---|
| **Phase 1** | Social gaming host platform: auth, profiles, friends, game library, game-hosting architecture, lobbies, realtime, chat, match room, stats, notifications, admin, subscriptions |
| **Phase 2** | Actual games: Wordle with friends, Online Sudoku, Connect Four, Tetris Arena, Chess Lite, Checkers, Memory Grid, Snake Rush |
| **Future** | Hardware-enabled games via embedded devices |

Phase 1 builds everything around the games. Phase 2 adds the games themselves
using the hosting architecture created in Phase 1.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Next.js 14 (App Router), TypeScript, Tailwind CSS |
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

### Module 1: Authentication & Account Security - Complete

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

### Module 2: User Profile & Social Identity — Complete

| Area | Status |
|---|---|
| Backend: UserProfile fields on User entity (StatusMessage, Visibility) | Done |
| Backend: Default profile exists for every registered user | Done |
| Backend: Current-user profile endpoint | Done |
| Backend: Public profile endpoint with visibility rules | Done |
| Backend: Profile update (display name, bio, region, status, avatar, banner, visibility) | Done |
| Backend: Username/handle change with uniqueness enforcement | Done |
| Backend: External social links (GitHub, Twitter, Instagram, Discord, YouTube, Twitch, LinkedIn, website) | Done |
| Backend: Game interest tags (board-games, word-games, puzzle, strategy, arcade, casual, card, trivia) | Done |
| Backend: EF Core migration `AddUserProfiles` | Done — verified locally |
| Backend: 25 unit + 16 integration tests for profile scope | Done |
| Frontend: ProfilePage wired to real profile API | Done |
| Frontend: SettingsPage profile card wired to real profile API | Done |
| Frontend: Topbar/Sidebar identity already wired via auth session | Done |
| Security: Ownership checks, safe DTOs, visibility rules, validation | Done |
| Production: Deployed migration verification | Pending deployment |

### Modules 3–15: Planned

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

Implemented:
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

Planned to support current settings mock UI:
- [ ] Change email flow
- [ ] Change password flow
- [ ] Google OAuth link/unlink management
- [ ] Active sessions/device list
- [ ] Revoke active session
- [ ] Account deactivation/delete flow with confirmation
- [ ] Production PostgreSQL migration verification

Status:
- Implemented for core auth.
- Account-security settings are planned.

### Module 2: User Profile & Social Identity

Purpose:
- Make the current profile and profile-settings mock UI real.
- Own public social identity, not account security.

Current UI target:
- `/profile/[userId]`
- `/settings` -> Account -> Profile card
- Sidebar/topbar user identity display

Included features:
- [ ] Public profile page
- [ ] Own profile page
- [ ] Display name
- [ ] Username/handle, with validation and change limits
- [ ] Bio/about text
- [ ] Avatar display
- [ ] Banner/cover display
- [ ] Region/location display
- [ ] Profile visibility: public, friends-only, private
- [ ] Optional status message if kept separate from realtime presence
- [ ] Optional external social links if added to UI later
- [ ] Read-only role/account tier display if useful, without billing logic

Backend scope:
- [ ] `ProfileController`
- [ ] Profile service
- [ ] Public profile DTO
- [ ] Own profile DTO
- [ ] Update profile DTO
- [ ] Validators for username, display name, bio, visibility, links
- [ ] Server-side ownership checks for updates
- [ ] Server-side visibility checks for public/friends/private profiles

Frontend scope:
- [ ] Replace `CURRENT_USER` mock data in profile identity areas with API data
- [ ] Wire profile save actions to API
- [ ] Keep stats, achievements, match history, friends count, and favorite games
      as planned placeholders until later modules provide real data

Database scope:
- [ ] Reuse existing `User` profile fields for MVP where possible: display name,
      bio, avatar URL, banner URL, color, initials, region
- [ ] Add only missing profile fields needed by the UI, such as visibility and
      optional status message/location
- [ ] Defer dedicated file-upload storage unless avatar/banner upload is built

Security/testing scope:
- [ ] Do not expose email on public profiles
- [ ] IDOR tests for editing another user's profile
- [ ] Validation tests for display name, username, bio, and visibility
- [ ] Public/private profile access tests

Documentation scope:
- [ ] Add `docs/modules/profile/README.md`
- [ ] Add `docs/modules/profile/api-reference.md`
- [ ] Add `docs/modules/profile/technical-flow.md`
- [ ] Add `docs/modules/profile/testing-report.md`
- [ ] Update Module 2 security audit to mention existing mock UI

Status:
- UI only, with partial backend domain fields already on `User`.

### Module 3: Friends & Social Graph

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
- [ ] Friend list
- [ ] Search friends
- [ ] Send, accept, decline, cancel friend requests
- [ ] Remove friend
- [ ] Suggested players
- [ ] Mutual friends count
- [ ] Block/unblock users
- [ ] Friend request privacy: anyone, friends-of-friends, off
- [ ] Friend count surfaced on profile

Backend/database/API work:
- [ ] Persist friendships and blocks
- [ ] Friends controller, service, repository, DTOs, validators
- [ ] Enforce block rules across friend requests, invites, chat, and visibility

Frontend work:
- [ ] Wire `/friends` tabs and actions to API
- [ ] Replace mock friend counts, pending requests, and suggestions
- [ ] Keep presence/activity text mock until Module 7 and Module 11

Status:
- UI only, with partial backend domain stubs.

### Module 4: Game Library & Discovery

Purpose:
- Make the game library and game detail pages real before building matchmaking
  and match state.

Current UI target:
- `/games`
- `/games/[gameId]`
- Dashboard continue-playing and recommended game cards
- Topbar search for games
- Profile favorite games placeholder

Included features:
- [ ] Game catalog
- [ ] Game detail pages
- [ ] Search, filters, categories/tags, sort
- [ ] Game rules and descriptions
- [ ] Supported modes: solo, AI, multiplayer, ranked
- [ ] Active/disabled game state
- [ ] Featured/spotlight game
- [ ] Favorite games or played games if kept in profile UI

Backend/database/API work:
- [ ] Games controller, service, repository or static catalog provider
- [ ] Game DTOs matching the UI cards/detail page
- [ ] Seed/configure initial game catalog

Frontend work:
- [ ] Replace `GAMES` mock data with API data
- [ ] Keep Play, Quick Match, Invite Friend, and Create Lobby buttons routed to
      placeholder flows until Modules 6, 8, and 9 are ready

Status:
- UI only, with partial backend domain stub.

### Module 5: Game Hosting Architecture

Purpose:
- Define how games plug into the platform without hard-coding each game directly
  into the app shell.

Included features:
- [ ] `IGameEngine` registration pattern
- [ ] Game state serializer pattern
- [ ] Generic game session lifecycle
- [ ] Server-authoritative move validation contract
- [ ] Hooks for stats and result recording

Backend/database/API work:
- [ ] Complete game engine registry/service
- [ ] Define game session persistence strategy
- [ ] Add tests for engine lookup and lifecycle behavior

Frontend work:
- [ ] No major new UI required yet
- [ ] Existing room UI stays mock until Module 8

Status:
- Planned, with backend architecture stubs.

### Module 6: Lobby & Matchmaking System

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
- [ ] Quick match queue only if needed after basic lobbies work

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
- [ ] Message history if needed
- [ ] Basic abuse controls: length limits, rate limits, delete/flag hooks

Backend/database/API work:
- [ ] SignalR hubs for presence, lobby updates, and chat
- [ ] Chat persistence if history is kept
- [ ] Authenticated hub connections

Frontend work:
- [ ] Wire `ChatPanel` to realtime events
- [ ] Replace mock presence/activity strings

Status:
- UI only, with backend notifier/chat stubs.

### Module 8: Generic Match Room & Match State

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
- [ ] Submit move endpoint or hub action
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
- [ ] Global/user ELO
- [ ] Match history
- [ ] Win rate, streaks, best season
- [ ] Achievement definitions
- [ ] User achievement unlock/progress
- [ ] Global leaderboards
- [ ] Friends leaderboards
- [ ] Season/tier display
- [ ] Daily quests only if kept simple and tied to real events

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
- [ ] Friend activity feed if kept after Modules 3, 8, and 10 provide events

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

Purpose:
- Support basic safety and admin review without adding unrelated enterprise
  features.

Included features:
- [ ] Report user/content
- [ ] Suspend/ban users
- [ ] Review flagged chat/profile content
- [ ] Admin action audit log
- [ ] Simple admin metrics only if useful

Backend/database/API work:
- [ ] Admin/moderation controller and service
- [ ] Reports, suspension records, admin audit log
- [ ] Strict role checks

Frontend work:
- [ ] Admin dashboard after backend role checks exist

Status:
- Planned, not visible in current UI.

### Module 13: Premium / Subscription System

Purpose:
- Support account tiers only after the core social gaming flow works.

Included features:
- [ ] Display account tier if present
- [ ] Subscription plans
- [ ] Payment-provider abstraction
- [ ] Stripe or similar checkout integration
- [ ] Webhook handling
- [ ] Subscription status enforcement

Backend/database/API work:
- [ ] Subscription records and provider IDs
- [ ] Webhook event log
- [ ] Signature verification for webhooks

Frontend work:
- [ ] Billing/settings UI only when backend billing is real

Status:
- Planned; backend has `SubscriptionTier` enum only.

### Module 14: Security, Testing & Production Readiness

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

---

## Later Docs To Update

- `docs/modules/README.md` should list Module 2 once profile work begins.
- `docs/security/audits/module-02-user-profile-social-identity.md` should be
  updated to say profile mock UI exists but backend/API work is not implemented.
- `docs/reviewer-notes.md` should stay honest about which modules are wired and
  which are still mock UI.

---

### Phase 2: Actual Games

After Phase 1 is complete, games are added as plugins:

- [ ] Wordle with friends
- [ ] Online Sudoku
- [ ] Connect Four
- [ ] Tetris Arena
- [ ] Chess Lite
- [ ] Checkers
- [ ] Memory Grid
- [ ] Snake Rush

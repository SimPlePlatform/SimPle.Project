# SimPle

**SimPle** is a premium full-stack social gaming platform. Users create accounts, build friend lists, host lobbies, chat in real time, and compete across a growing catalog of online games. The platform is designed for scalability — each game is a plugin, not a hard-coded feature.

---

## Repositories

| Repository | Description |
|---|---|
| [SimPlePlatform/SimPLe.Backend](https://github.com/SimPlePlatform/SimPLe.Backend) | ASP.NET Core 8 backend — auth, API, database, tests |
| [SimPlePlatform/SimpLe.Frontend](https://github.com/SimPlePlatform/SimpLe.Frontend) | Next.js 14 frontend — UI, auth pages, app shell, tests |

---

## Phase Overview

| Phase | Scope |
|-------|-------|
| **Phase 1** | Complete social gaming host platform — auth, profiles, friends, lobbies, real-time, chat, stats, leaderboards, admin, subscriptions, game-hosting architecture |
| **Phase 2** | Actual games — Wordle with friends, Online Sudoku, Connect Four, Tetris Arena, Chess Lite, Checkers, Memory Grid, Snake Rush |
| **Future** | Hardware-enabled games via embedded devices (reaction duels, physical controllers, RFID games) |

Phase 1 builds everything *around* the games. Games themselves are added in Phase 2 using the game-hosting architecture established in Phase 1.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Next.js 14 (App Router), TypeScript, Tailwind CSS |
| Backend | ASP.NET Core 8, C# |
| Database | PostgreSQL + Entity Framework Core 8 |
| Auth | JWT (HttpOnly access cookie, 15 min) + rotating refresh tokens (SHA-256 hashed, 7-day) |
| Password hashing | Argon2id (64 MiB, 3 iterations) |
| OAuth | Google Identity Services (ID token flow, JWKS validation) |
| CAPTCHA | Google reCAPTCHA v2 server-side verification |
| Email | MailKit / SMTP |
| Real-time | SignalR (planned Phase 1 completion) |
| Testing | xUnit + NSubstitute (backend), Vitest (frontend) |

---

## Architecture

The backend follows **Clean Architecture** with a **Modular Monolith** structure:

```
SimPle.Api  →  SimPle.Application  →  SimPle.Domain
                       ↓
           SimPle.Infrastructure  (EF Core, JWT, Argon2, SMTP, external services)
```

Each feature module (Auth, Friends, Games, Lobbies, …) is a folder within Application and Domain — not a separate service. This keeps deployment simple while maintaining clear module boundaries.

The frontend is a **Next.js App Router** application. The `(app)` route group wraps all authenticated pages in the shared `AppShell` layout. Feature components are in `src/features/`, UI primitives in `src/components/ui/`.

---

## Current Status

### Module 1: Authentication & Sessions — Complete

| Area | Status |
|---|---|
| Email/password register, login, logout, refresh | Done |
| JWT access cookie (15 min) + rotating SHA-256 hashed refresh tokens (7-day) | Done |
| Email verification (send, resend) and password reset (request, confirm) | Done |
| Google OAuth — ID token flow, JWKS validation, account linking | Done |
| reCAPTCHA v2 server-side verification on login and register | Done |
| Rate limiting, account lockout, CSRF checks, secure headers | Done |
| Optimistic concurrency on refresh rotation (PostgreSQL xmin) | Done |
| Security event logging, token cleanup background service | Done |
| Backend: 145 tests (100 unit, 45 integration) | Done |
| Frontend: auth pages, protected routes, Google Sign-In, 47 tests | Done |

### Modules 2–15 — Planned

See the [full roadmap](#modules--features-roadmap) below.

---

## Quick Start

### Backend

```powershell
cd backend
dotnet restore
.\scripts\Initialize-AuthEnvironment.ps1      # generates .env with random local secrets
docker compose -f compose.auth.yml up -d      # start PostgreSQL
dotnet ef database update --project src/SimPle.Infrastructure --startup-project src/SimPle.Api
dotnet run --project src/SimPle.Api
# Swagger: https://localhost:7139/swagger
```

### Frontend

```bash
cd frontend
npm install
cp .env.local.example .env.local             # fill in API URL, reCAPTCHA key, Google client ID
npm run dev                                   # http://localhost:3000
```

---

## Modules & Features Roadmap

### Module 1: Authentication & User Management
- [x] Email/password register, login, logout, refresh token flow
- [x] JWT access cookies and hashed rotating refresh token storage
- [x] Email verification and password reset
- [x] Google OAuth — ID token flow, JWKS validation, account linking
- [x] Frontend: all auth pages wired and tested
- [x] Rate limiting, validation, secure cookies, security headers
- [ ] Production: deployed PostgreSQL migration verification

### Module 2: User Profile & Social Identity
- [ ] Profile entity — display name, avatar, banner, bio, status
- [ ] Profile update endpoints and frontend pages

### Module 3: Friends & Social Graph
- [ ] Friend requests, friend list, block/unblock, status indicators

### Module 4: Game Library & Discovery
- [ ] Game catalog with search/filter, placeholder game cards

### Module 5: Game Hosting Architecture
- [ ] Generic match lifecycle, IGameEngine registration pattern

### Module 6: Lobby & Matchmaking System
- [ ] Create/join/leave lobbies, invite links, host controls

### Module 7: Real-Time Presence, Lobby Updates & Chat
- [ ] SignalR PresenceHub, LobbyHub, ChatHub

### Module 8: Generic Match Room & Match State
- [ ] Match entity, submit move endpoint, match history

### Module 9: Solo vs AI Platform Flow
- [ ] AI match setup, difficulty levels, solo stats

### Module 10: Stats, Achievements & Leaderboards
- [ ] Per-game stats, achievement definitions, global leaderboards

### Module 11: Notifications & Activity Feed
- [ ] Notification triggers, unread counts, activity feed

### Module 12: Moderation & Admin Dashboard
- [ ] Report system, admin metrics, suspend/ban

### Module 13: Premium / Subscription System
- [ ] Subscription plans, Stripe-ready abstraction

### Module 14: Security, Testing & Production Readiness
- [ ] Full input validation, OpenAPI docs, CI/CD, health checks

### Module 15: Hardware-Enabled Games & Embedded Integration
- [ ] Device pairing, event ingestion, hardware game room

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

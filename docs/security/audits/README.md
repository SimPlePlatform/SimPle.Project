# SimPle Security Audits

## Overview

This folder contains security review notes for each SimPle module. The reviews
are code-level audits performed against the local repository — not external
penetration tests or automated scanner results.

**Audit type:** Source review, local automated test verification, no external
attacks.  
**Last updated:** 2026-06-29
**Branch:** `feature/module-03-friends-social-graph`

---

## Module Audit Status

| Module | Implementation | Audit Status | Findings |
|---|---|---|---|
| [01 — Auth & User Management](module-01-authentication-user-management.md) | Complete | Reviewed | 14 findings, all resolved |
| [02 — User Profile & Social Identity](module-02-user-profile-social-identity.md) | Complete | Reviewed | 3 findings, all resolved (2 Medium, 1 Low) |
| [03 — Friends & Social Graph](module-03-friends-social-graph.md) | Implemented; DB verified locally | Open — pending M03-001 | 1 Low (open), 1 Medium (deferred), 10 DB tests passed |
| [04 — Game Library & Discovery](module-04-game-library-discovery.md) | Not started | Planned | No attack surface yet |
| [05 — Game Hosting Architecture](module-05-game-hosting-architecture.md) | Not started | Planned | No attack surface yet |
| [06 — Lobby & Matchmaking](module-06-lobby-matchmaking-system.md) | Not started | Planned | No attack surface yet |
| [07 — Real-Time Presence & Chat](module-07-realtime-presence-chat.md) | Not started | Planned | No attack surface yet |
| [08 — Match Room & State](module-08-generic-match-room-state.md) | Not started | Planned | No attack surface yet |
| [09 — Solo vs AI Flow](module-09-solo-vs-ai-flow.md) | Not started | Planned | No attack surface yet |
| [10 — Stats, Achievements & Leaderboards](module-10-stats-achievements-leaderboards.md) | Not started | Planned | No attack surface yet |
| [11 — Notifications & Activity Feed](module-11-notifications-activity-feed.md) | Not started | Planned | No attack surface yet |
| [12 — Moderation & Admin](module-12-moderation-admin-dashboard.md) | Not started | Planned | No attack surface yet |
| [13 — Premium & Subscriptions](module-13-premium-subscription-system.md) | Not started | Planned | No attack surface yet |
| [14 — Security Testing & Production Readiness](module-14-security-testing-production-readiness.md) | In progress | Ongoing | Cross-cutting concerns |
| [15 — Hardware & Embedded Integration](module-15-hardware-embedded-integration.md) | Not started | Planned | No attack surface yet |

---

## Module 1 Finding Summary

14 findings were identified across code review and test execution. All have been
resolved in this branch.

| Severity | Count | Status |
|---|---|---|
| Medium | 7 | All fixed |
| Low | 4 | All fixed |
| Informational | 3 | All fixed |

See [module-01-authentication-user-management.md](module-01-authentication-user-management.md)
for the full finding list, or the detailed notes in the `auth/` subfolder.

---

## How To Re-run The Audit

```powershell
cd backend

# Build
dotnet build

# Unit tests
dotnet test tests/SimPle.UnitTests/SimPle.UnitTests.csproj

# Integration tests
dotnet test tests/SimPle.IntegrationTests/SimPle.IntegrationTests.csproj

# Scoped coverage (Auth implementation only)
dotnet test tests/SimPle.UnitTests/SimPle.UnitTests.csproj `
  --collect:"XPlat Code Coverage" `
  --settings coverage.unit.runsettings `
  --results-directory ./coverage-unit-scoped

# Check for vulnerable NuGet packages
dotnet list package --vulnerable
```

```powershell
cd frontend

# Type check
npx tsc --noEmit

# Lint
npm run lint

# Production build
npm run build

# Dependency audit
npm audit
```

---

## Remaining Risks (cross-module)

| Risk | Module | Priority |
|---|---|---|
| PostgreSQL migration not applied to live instance | Auth | High (blocks real testing) |
| No security event/audit logging | Auth + future modules | Medium |
| Token table purge job missing | Auth | Medium |
| Proxy-aware IP configuration not set | Auth | Medium (production) |
| PostCSS moderate advisory in Next.js transitive deps | Frontend | Low (build toolchain only; no safe upgrade path without downgrading Next.js) |
| Concurrent refresh race condition | Auth | Low for single instance |

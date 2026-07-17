# SimPle Modules

This folder records modules as they become usable and testable. Each completed module has the canonical
three-file doc set (`api-reference.md`, `technical-flow.md`, `testing-report.md`) under
`module-XX-<slug>/`, following `docs/modules/_templates/STYLE.md`.

| Module | Status | Docs |
|---|---|---|
| 01 — Authentication & User Management | Implemented (local/backend/frontend) | [module-01-authentication-user-management](module-01-authentication-user-management/technical-flow.md) |
| 02 — User Profile & Social Identity | Implemented (local/backend/frontend) | [module-02-user-profile-social-identity](module-02-user-profile-social-identity/technical-flow.md) |
| 03 — Friends & Social Graph | Implemented (UI + backend; see status) | [module-03-friends-social-graph](module-03-friends-social-graph/technical-flow.md) |
| 04 — Game Library & Discovery | Locally complete | [module-04-game-library-discovery](module-04-game-library-discovery/technical-flow.md) |
| 05 — Game Hosting Architecture | Locally complete | [module-05-game-hosting-architecture](module-05-game-hosting-architecture/technical-flow.md) |
| 06 — Lobby & Matchmaking System | Locally complete | [module-06-lobby-matchmaking-system](module-06-lobby-matchmaking-system/technical-flow.md) |

Modules 07 onward are planned. See the root `README.md` for the full roadmap and
`docs/module-requirements/` for the per-module build briefs.

Local end-to-end verification requires PostgreSQL running with migrations applied; run
`/simple-verify-checkpoint` every ~2 modules to exercise the app in a real browser.

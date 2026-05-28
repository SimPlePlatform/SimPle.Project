# Module 4: Game Library & Discovery — Security Audit

## Status

**Not started.** No backend or frontend code exists for this module.

---

## Planned Scope

**Expected backend files (not yet created):**
- `SimPle.Api/Controllers/GamesController.cs`
- `SimPle.Application/Games/Services/GameService.cs`
- `SimPle.Application/Games/DTOs/*.cs`
- `SimPle.Infrastructure/Persistence/Repositories/GameRepository.cs`

**Expected frontend files (not yet created):**
- `frontend/src/features/games/GameLibrary.tsx`
- `frontend/src/features/games/GameCard.tsx`
- `frontend/src/features/games/GameDiscovery.tsx`

---

## Planned Features

- Browse and search available games
- Game detail pages (description, rules, player count, tags)
- User game library (owned/favourite games)
- Game ratings or reviews (optional)

---

## Security Requirements For Implementation

| Requirement | Why |
|---|---|
| Read endpoints may be public; write endpoints require auth | Adding games to library requires a valid session |
| Admin-only game creation | Only admins should be able to add or modify game catalogue entries |
| Input validation on search queries | Full-text search inputs must be sanitized to prevent injection |
| Pagination and result caps | Unbounded queries against a large catalogue are a DoS risk |
| Rate-limit search | Search can be CPU-intensive; open endpoints should be rate limited |
| No sensitive data in game objects | Game DTOs should not leak internal IDs used for access-control decisions |
| IDOR on library mutations | Adding/removing a game from a user's library must check the requesting user's ID |

---

## Findings

None — module not yet implemented.

---

## Remaining Risks

| Risk | Notes |
|---|---|
| Admin authorization gap | Game catalogue management must be gated behind an admin role that does not exist yet |
| Search injection | Depending on the search implementation (EF full-text, raw SQL, Elasticsearch), injection risk varies |

---

## Audit Status

Planned. Will be reviewed when implementation begins.

# Module 10: Stats, Achievements & Leaderboards — Security Audit

## Status

**Not started.** No backend or frontend code exists for this module.

---

## Planned Scope

**Expected backend files (not yet created):**
- `SimPle.Api/Controllers/StatsController.cs`
- `SimPle.Application/Stats/Services/StatsService.cs`
- `SimPle.Application/Achievements/Services/AchievementService.cs`
- `SimPle.Domain/Stats/PlayerStats.cs`
- `SimPle.Domain/Achievements/Achievement.cs`

---

## Planned Features

- Win/loss/draw records per game
- Achievement unlocking
- Global and per-game leaderboards
- Personal stats history

---

## Security Requirements For Implementation

| Requirement | Why |
|---|---|
| Stats are written by the server only | Match results must come from the authoritative match service, not from a client POST |
| Achievement unlock validated server-side | Achievement conditions must be checked against stored game data, not a client claim |
| Leaderboard queries paginated | Unbounded leaderboard queries against a large player base cause database load |
| No PII in leaderboard entries | Display usernames only; do not expose email, internal user ID, or IP in public rankings |
| Rate-limit leaderboard reads | Public endpoints are scraping targets; rate limiting protects the database |
| Admin-only stats override | If stats can be manually corrected by an admin, the override must be gated behind an admin role and audit-logged |

---

## Findings

None — module not yet implemented.

---

## Remaining Risks

| Risk | Notes |
|---|---|
| Stat manipulation | If any code path allows a client to directly write a win or achievement, cheating is trivial |
| Leaderboard scraping | Public leaderboards without rate limits can expose the entire user list |

---

## Audit Status

Planned. Will be reviewed when implementation begins.

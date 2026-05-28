# Module 8: Match Room & State — Security Audit

## Status

**Not started.** No backend or frontend code exists for this module.

---

## Planned Scope

**Expected backend files (not yet created):**
- `SimPle.Api/Hubs/MatchHub.cs` or `SimPle.Api/Controllers/MatchController.cs`
- `SimPle.Application/Match/Services/MatchService.cs`
- `SimPle.Application/Match/DTOs/*.cs`
- `SimPle.Domain/Match/Match.cs`

---

## Planned Features

- Game state synchronization between players
- Turn management and validation
- Move submission and validation
- Match history and result recording

---

## Security Requirements For Implementation

| Requirement | Why |
|---|---|
| Authenticate all move submissions | Moves must come from an authenticated player in the match |
| Authorize by participant — server-side | Only current players in the match may submit moves; check match membership on every action |
| Validate game logic server-side | Client-reported move validity cannot be trusted; the server must enforce game rules |
| Prevent move replay | A submitted valid move should not be reapplied on reconnect |
| Sequence numbers or timestamps on moves | Out-of-order or duplicate move submissions must be detected and rejected |
| Rate-limit move submissions | Prevent automated bots from submitting moves faster than humanly possible |
| State not derived from client input alone | Final game state must be computed by the server, not reported by a client |
| Match result cannot be self-reported | Win/loss recording must come from the authoritative game logic, not a client claim |

---

## Findings

None — module not yet implemented.

---

## Remaining Risks

| Risk | Notes |
|---|---|
| Client-side game logic authority | If the client can report the result of a match, cheating is trivial |
| Race conditions in turn state | Concurrent move submissions from two players in the same turn need atomic handling |
| Reconnection replay | Players reconnecting must receive current state without replaying moves |

---

## Audit Status

Planned. Will be reviewed when implementation begins.

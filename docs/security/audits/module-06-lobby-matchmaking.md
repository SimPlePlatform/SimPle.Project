# Module 6: Lobby & Matchmaking — Security Audit

## Status

**Not started.** No backend or frontend code exists for this module.

---

## Planned Scope

**Expected backend files (not yet created):**
- `SimPle.Api/Controllers/LobbyController.cs`
- `SimPle.Application/Lobby/Services/LobbyService.cs`
- `SimPle.Application/Lobby/DTOs/*.cs`
- `SimPle.Infrastructure/Persistence/Repositories/LobbyRepository.cs`

---

## Planned Features

- Create, join, and leave lobbies
- Lobby settings (game type, player count, privacy: public/private/invite-only)
- Invite-only lobbies with shareable codes
- Matchmaking queue (optional)
- Ready-up flow before game start

---

## Security Requirements For Implementation

| Requirement | Why |
|---|---|
| Authenticate all lobby mutations | Joining, creating, or kicking requires a valid session |
| Authorize kicking by lobby owner only | Only the owner may remove other players |
| Rate-limit lobby creation | Prevent lobby spam from a single user |
| Invite code entropy | Invite codes must be high-entropy random values, not predictable sequential IDs |
| Validate lobby capacity | Server must enforce max player count; client-side cap is bypassed trivially |
| Private lobby join requires code | Server must verify the code, not trust a `isPrivate` flag from the client |
| Prevent double-join | A user must not be able to join the same lobby twice concurrently |
| IDOR on lobby settings | Only the owner may change settings; check ownership on every mutation |
| No user data leaked in lobby listing | Public lobby listing must not expose email addresses or internal user IDs |

---

## Findings

None — module not yet implemented.

---

## Remaining Risks

| Risk | Notes |
|---|---|
| Predictable invite codes | If codes are short or sequential, an attacker can enumerate and join private lobbies |
| Race condition on join | Concurrent join requests from two players filling the last slot may exceed capacity |

---

## Audit Status

Planned. Will be reviewed when implementation begins.

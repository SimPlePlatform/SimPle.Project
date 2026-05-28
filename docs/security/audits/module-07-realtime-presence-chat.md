# Module 7: Real-Time Presence & Chat — Security Audit

## Status

**Not started.** A stub `IHubContext.cs` interface exists in `SimPle.Infrastructure/Realtime/` but no hub or chat logic is implemented.

---

## Planned Scope

**Expected backend files (not yet created):**
- `SimPle.Api/Hubs/PresenceHub.cs`
- `SimPle.Api/Hubs/ChatHub.cs`
- `SimPle.Application/Realtime/Services/PresenceService.cs`
- `SimPle.Application/Realtime/Services/ChatService.cs`

---

## Planned Features

- Online/offline/in-game presence indicators
- Per-lobby or per-room chat
- Direct messages between friends
- Message history (optional)

---

## Security Requirements For Implementation

| Requirement | Why |
|---|---|
| Authenticate SignalR connections | Hub connections must validate the access cookie on connect; reject unauthenticated connections |
| Authorize chat by room membership | Users may only post to rooms/lobbies they are members of |
| Sanitize and encode all chat output | Chat is the highest-risk XSS surface in the app — all messages must be encoded before rendering |
| Rate-limit messages per user | Prevent chat flood or spam |
| Message length cap enforced server-side | Long messages can be used for DoS or UI-breaking attacks |
| Do not broadcast internal IDs or secrets in hub messages | Hub payloads sent to clients must use safe DTOs |
| Block list respected in direct messages | A blocked user must not be able to DM the blocker |
| Audit log for moderation | Deleted messages should be soft-deleted and retained for moderation |
| Presence leakage — private users | Users with private profiles should not expose their online status to non-friends |
| SignalR group membership server-controlled | Clients must not be able to join arbitrary hub groups — group assignment must happen server-side |

---

## Findings

None — module not yet implemented.

---

## Remaining Risks

| Risk | Notes |
|---|---|
| XSS in chat | The highest priority risk. All chat content must be HTML-encoded on the client before insertion into the DOM |
| Presence enumeration | An unauthenticated attacker should not be able to determine who is online |
| Group injection | If clients can self-assign to SignalR groups, they could receive messages intended for other rooms |

---

## Audit Status

Planned. Will be reviewed when implementation begins. Chat and real-time features are among the highest-risk surfaces in this application.

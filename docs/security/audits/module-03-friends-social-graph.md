# Module 3: Friends & Social Graph — Security Audit

## Status

**Not started.** No backend or frontend code exists for this module.

---

## Planned Scope

**Expected backend files (not yet created):**
- `SimPle.Api/Controllers/FriendsController.cs`
- `SimPle.Application/Friends/Services/FriendService.cs`
- `SimPle.Application/Friends/DTOs/*.cs`
- `SimPle.Infrastructure/Persistence/Repositories/FriendRepository.cs`

**Expected frontend files (not yet created):**
- `frontend/src/features/friends/FriendsList.tsx`
- `frontend/src/features/friends/FriendRequestCard.tsx`
- `frontend/src/features/friends/InviteFriendModal.tsx`

---

## Planned Features

- Send, accept, decline, and cancel friend requests
- Block and unblock users
- Friends list with presence indicators
- Friend count and mutual friends display

---

## Security Requirements For Implementation

| Requirement | Why |
|---|---|
| Authenticate all endpoints | Friend actions require a valid access cookie |
| Authorize by user ID | Users may only act on their own friend list |
| Prevent self-friendship | `senderId == recipientId` must be rejected |
| Prevent duplicate requests | One pending request per pair; database unique constraint |
| Block list enforced on request send | Blocked users cannot send friend requests |
| IDOR on accept/decline | Only the recipient may accept or decline a request; not the sender |
| Rate-limit friend requests | Prevent mass harassment via requests |
| No user enumeration via friends API | A blocked user should not be able to determine friendship status of the blocker |
| Pagination on lists | Friend lists can be large; unbounded queries cause database load |

---

## Findings

None — module not yet implemented.

---

## Remaining Risks

| Risk | Notes |
|---|---|
| IDOR on friend actions | Must check requester identity against stored sender/recipient before every action |
| Harassment via requests | Rate limiting and block enforcement are the primary mitigations |
| Social graph exposure | Mutual friends feature reveals relationship data — privacy controls needed |

---

## Audit Status

Planned. Will be reviewed when implementation begins.

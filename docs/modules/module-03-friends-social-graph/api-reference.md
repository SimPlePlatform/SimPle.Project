# API Reference - Module 03: Friends & Social Graph

## Overview
- Existing UI reused: Sidebar, FriendsPage, DashboardPage, SettingsPage, profile surfaces.
- Frontend integration points: `features/friends/friendsApi.ts`, `friendsErrors.ts`, `FriendSummaryContext`.
- Existing database impact: additive (friend-request/friendship edge, block, friend-settings, suggestion
  dismissal, transactional outbox). No destructive changes.

## Base Route / Route Group
`/api/friends`. Source of truth: `SimPle.Backend`. Authentication: cookie-based session
(`credentials: 'include'`); the `X-Requested-With: XMLHttpRequest` CSRF header is required on every mutating
request (missing → 400 `Auth.CsrfHeaderRequired`).

## Authentication And Authorization Requirements
All endpoints require an authenticated session (`[Authorize]`, JWT `sub`). Every action re-derives the
authorization decision server-side from the session subject and object membership — never a body-supplied
actor. Non-owned or guessed ids return **404 `Profile.NotVisible`** (never 403), body- and
latency-indistinguishable from a nonexistent/private/blocked/suspended target (BOLA/IDOR + enumeration
defense).

## Endpoint Summary Table

| # | Method | Path | Description | Request Body / Query | Response |
|---|--------|------|-------------|----------------------|----------|
| 1 | GET | `/api/friends/summary` | Friend/request counts for the current user | — | `FriendSummaryDto` |
| 2 | GET | `/api/friends` | Friend list (keyset cursor) | Query: `query?, limit?≤50, cursor?` | `CursorPage<FriendDto>` |
| 3 | DELETE | `/api/friends/{friendUserId}` | Remove an accepted friend | — | 204 |
| 4 | GET | `/api/friends/requests` | Incoming/outgoing requests (keyset cursor) | Query: `direction=incoming\|outgoing, limit?≤50, cursor?` | `CursorPage<FriendRequestDto>` |
| 5 | POST | `/api/friends/requests` | Send a request (or atomically accept a reverse pending one) | `{ targetUserId, idempotencyKey? }` | `SendFriendRequestResult` 201/200 |
| 6 | POST | `/api/friends/requests/{id}/accept` | Accept an incoming request | — | `FriendRequestDto` 200 |
| 7 | POST | `/api/friends/requests/{id}/decline` | Decline an incoming request | — | `FriendRequestDto` 200 |
| 8 | DELETE | `/api/friends/requests/{id}` | Cancel an outgoing pending request | — | 204 |
| 9 | GET | `/api/friends/suggestions` | Friend suggestions with mutual counts | Query: `limit?≤20` | `FriendSuggestionDto[]` |
| 10 | GET | `/api/friends/discovery` | Look up one user by exact username | Query: `username` | `DiscoveryResultDto` |
| 11 | PUT | `/api/friends/suggestions/{userId}/dismiss` | Dismiss a suggestion (30-day suppression) | — | 204 |
| 12 | GET | `/api/friends/blocks` | Block list (keyset cursor) | Query: `limit?≤50, cursor?` | `CursorPage<BlockDto>` |
| 13 | POST | `/api/friends/blocks` | Block a user | `{ targetUserId }` | `BlockUserResult` 201/200 |
| 14 | DELETE | `/api/friends/blocks/{blockedUserId}` | Unblock a user | — | 204 |
| 15 | GET | `/api/friends/settings` | Friend-request privacy settings | — | `FriendSettingsDto` |
| 16 | PUT | `/api/friends/settings` | Update privacy settings | `{ friendRequestPrivacy }` | `FriendSettingsDto` |

## Endpoints — outcomes & status codes

- **Send (5)** returns `SendFriendRequestResult`: `request_created` → **201**; `already_pending` and
  `cross_request_accepted` → **200**. `cross_request_accepted` means a reverse pending request existed and was
  atomically accepted. Rate limited (`friend-send`).
- **Accept (6) / Decline (7)** are idempotent: re-accepting an already-accepted request (or re-declining a
  declined one) returns **200** with the current `FriendRequestDto`.
- **Cancel (8) / Remove (3)** are idempotent **204**; an unrelated/guessed id → **404**.
- **Discovery (10)** is exact-username, timing-safe, and returns only minimal identity; any
  ineligible/nonexistent/hidden target → **404 `Profile.NotVisible`**. Rate limited (`friend-discovery`).
- **Dismiss (11)** suppresses a suggestion for 30 days; repeat dismiss is idempotent **204**. A daily
  background job purges expired dismissals in bounded batches. Rate limited (`friend-suggestions`).
- **Block (13)** returns `BlockUserResult`: `blocked` → **201**, `already_blocked` → **200**. Blocking
  atomically ends any pending/accepted edge in the same transaction. Rate limited (`friend-block`).
  `BlockUserResult` deliberately carries no target identity fields (M03-007 fix, 2026-07-06): unlike
  Discover/SendFriendRequest, blocking does not gate on the target's visibility, so it must not echo the
  target's username/displayName/avatar — the caller already holds the identity card from whichever surface
  initiated the block.

## Cursor pagination
`limit` default 20 / max 50 (suggestions cap 20). The cursor is an **opaque base64url** token (last sort key
+ UUID tie-breaker), keyset-traversed — not offset. `CursorPage<T>.nextCursor` is `null` at the last page; no
total/count is promised. Sort keys: friends `(normalizedDisplayName, userId)`; requests `(sentAt DESC, id
DESC)`; blocks `(createdAt DESC, id DESC)`. An invalid/forged/stale cursor → **400 `Pagination.InvalidCursor`**.
Friend-list `query`: blank (all) or 2–100 normalized chars. Discovery `username`: 3–30 chars matching the M1
handle pattern (`[a-zA-Z0-9_.-]`).

## Data Models / DTOs

```typescript
CursorPage<T> = { items: T[]; nextCursor: string | null; }

FriendSummaryDto = { friendCount: number; incomingRequestCount: number; outgoingRequestCount: number; }

// No level / elo (removed this module — deferred to M10).
FriendDto = {
  userId: string; username: string; displayName: string; initials: string; color: string;
  avatarUrl: string | null; friendsSince: string; // ISO 8601
}

FriendRequestDto = {
  requestId: string;
  requesterId: string; requesterUsername: string; requesterDisplayName: string;
  requesterInitials: string; requesterColor: string; requesterAvatarUrl: string | null;
  addresseeId: string; addresseeUsername: string; addresseeDisplayName: string;
  addresseeInitials: string; addresseeColor: string; addresseeAvatarUrl: string | null;
  status: 'Pending' | 'Accepted' | 'Declined' | 'Cancelled';
  requestedAt: string; mutualFriendCount: number;
}

SendFriendRequestResult = {
  outcome: 'request_created' | 'already_pending' | 'cross_request_accepted';
  request: FriendRequestDto;
}

// No level / elo. Minimal identity + visible mutual count only.
FriendSuggestionDto = {
  userId: string; username: string; displayName: string; initials: string; color: string;
  avatarUrl: string | null; mutualFriendCount: number;
}

// Minimal identity only — never bio, links, region, status, elo, level, email, or presence.
DiscoveryResultDto = {
  userId: string; username: string; displayName: string; initials: string; color: string;
  avatarUrl: string | null;
}

BlockDto = {
  blockedUserId: string; blockedUsername: string; blockedDisplayName: string;
  blockedInitials: string; blockedColor: string; blockedAvatarUrl: string | null;
  blockedAt: string; // ISO 8601
}

// Minimal by design (M03-007 fix) — no target identity fields on this path.
BlockUserResult = { outcome: 'blocked' | 'already_blocked'; blockedUserId: string; blockedAt: string; }

FriendSettingsDto = { friendRequestPrivacy: 'Anyone' | 'FriendsOfFriends' | 'Off'; }
```

## Error Format
Envelope: `{ error: { code, message, retryAfterUtc? } }`. Canonical catalogue (R12):

| Code | HTTP | Meaning |
|------|------|---------|
| `Friends.SelfRequest` | 400 | Cannot friend yourself |
| `Friends.SelfBlock` | 400 | Cannot block yourself |
| `Friends.RequestsDisabled` | 400 | Target privacy is Off |
| `Friends.NotFriendOfFriend` | 400 | Target requires a mutual friend and you have none |
| `Friends.NotPending` | 400 | Request is not Pending |
| `Friends.RequestCooldown` | 409 | Requester is within decline (7d) / cancel (24h) cooldown (+ `retryAfterUtc`, `Retry-After`) |
| `Friends.AlreadyFriends` | 409 | Already friends |
| `Friends.ConcurrencyConflict` | 409 | Concurrent modification after bounded retry; client retries |
| `Profile.NotVisible` | 404 | Nonexistent, private, blocked, deleted, suspended, or banned — indistinguishable |
| `Pagination.InvalidCursor` | 400 | Invalid/forged/stale cursor |
| `RateLimit.Exceeded` | 429 | Rate limit hit (+ `Retry-After`) |
| `Auth.CsrfHeaderRequired` | 400 | Missing CSRF header on a mutation |
| `Validation.Failed` | 400 | Request/query validation failed |

**Retired** (mapped from the prior spec): `Friends.DuplicateRequest` → 200 `already_pending`;
`Friends.ReverseRequestExists` → 200 `cross_request_accepted`; `Friends.Blocked`,
`Friends.NotAddressee`/`NotRequester`/`NotFriends` → 404 `Profile.NotVisible`. Internal denial reasons stay in
server logs (no PII), never in responses. Frontend mapping: `src/features/friends/friendsErrors.ts`.

## Rate Limiting
Per-account fixed windows (partitioned by JWT subject, IP fallback), rejections carry `Retry-After` +
`RateLimit.Exceeded`: `friend-send` 10/min, `friend-discovery` 30/min, `friend-suggestions` 30/min,
`friend-block` 20/min. Middleware order is `UseAuthentication() → UseRateLimiter() → UseAuthorization()`.

> **Known limitation (this slice):** the spec's *secondary* caps — send **3/day/account-target** and
> discovery **120/hour/IP** — are not yet enforced. The per-account-target daily cap needs a durable per-pair
> counter (persisted store) and the per-IP discovery cap needs a chained global limiter; both are deferred to
> a later slice. Per-account windows above are active.

## Events (transactional outbox)
Each mutation stages exactly one integration event in the same PostgreSQL transaction as the aggregate change:
`FriendRequestCreatedV1`, `FriendRequestAcceptedV1`, `FriendRequestDeclinedV1`, `FriendRequestCancelledV1`,
`FriendshipRemovedV1`, `UserBlockedV1`, `UserUnblockedV1`. `UserBlockedV1` is never a notification to the
target. Payloads carry minimum ids only (relationship id, request cycle, contiguous domain version).

## Security Considerations
Ownership re-derived server-side on every cross-user action (IDOR/BOLA → 404, never 403). Block direction is
never leaked. Discovery/suggestion DTOs expose only minimal identity + visible mutual counts. Mass-assignment
allow-list: `targetUserId`, `friendRequestPrivacy`, `idempotencyKey` only; all server-owned fields are
stripped. `FriendsService` emits structured `Security: ...` log lines (mirroring the Module 1 `AuthService`
convention) for send/cross-accept/accept/decline/cancel/remove/block/unblock (M03-006, fixed 2026-07-06).
`POST /api/friends/blocks` never echoes the target's identity card, regardless of the target's visibility
(M03-007, fixed 2026-07-06) — see `BlockUserResult` above.

## Related Tests
Backend unit + integration + real-PostgreSQL verification (expression uniqueness, xmin, cross-send `23505`
convergence, races, migration, outbox rollback) — UnitTests 273/0/0, IntegrationTests 187/0/0. Frontend
`friendsApi.test.ts` / `friendsErrors.test.ts` and 5 other reconciled suites — 96/0. Two-user Playwright E2E
(`module-03-friends.spec.ts`) — 1/1 passed against a live local stack. See `testing-report.md`.

## Last Verified Command
Full backend `dotnet test` (unit + in-memory + real-Postgres), frontend `npx vitest run` + `npx tsc --noEmit` +
`npm run lint`, `node scripts/check-contract-drift.mjs` (DRIFT=0), and `npx playwright test
tests/e2e/module-03-friends.spec.ts` all run and green as of the 2026-07-06 verification checkpoint.

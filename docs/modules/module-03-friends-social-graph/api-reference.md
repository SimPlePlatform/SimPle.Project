# API Reference - Module 03: Friends & Social Graph

> Revision 2. Supersedes the 2026-07-06 revision-1-only version of this file. Adds bounded people search,
> canonical profile reads, viewer-relationship context, and privacy-aware target/mutual friend-list
> drill-down on top of the unchanged revision-1 `/api/friends/*` contract. Backend evidence:
> `docs/ai-workflow/evidence/checkpoints/module-03-friends-social-graph/backend.json` (321/321 unit,
> 224/224 real-Postgres integration). Frontend evidence: `frontend.json` (188/188 vitest, DRIFT=0). The
> expanded navigation E2E (`module-03-friends.spec.ts`) has been **executed against a live local stack and
> passed** (1/1, 25.7s) — see `verification.json` and `testing-report.md`.

## Overview
- Existing UI reused: Sidebar, FriendsPage, DashboardPage, SettingsPage, and a new shared `PlayerIdentity`
  component used everywhere an account is listed.
- Frontend integration points: `features/friends/friendsApi.ts`, `friendsErrors.ts`,
  `FriendSummaryContext`, `features/people/peopleApi.ts` (new), `features/profile/profileApi.ts`,
  `components/identity/PlayerIdentity.tsx` (new), `components/search/PeopleSearchCombobox.tsx` (new).
- Existing database impact: additive only. Revision 1: `Friendship`, `Block`, `UserFriendSettings`,
  `DismissedFriendSuggestion`, `OutboxMessage`, `OutboxDelivery`. Revision 2 adds: `RetiredUsername` table;
  `SearchVisibility`, `FriendsListVisibility`, `PrivacyPolicyVersion` columns on `UserFriendSettings`;
  `LastSenderId`/`SendCountInWindow`/`SendWindowStartUtc` columns plus two prefix indexes on `users`. No
  destructive changes.

## Base Route / Route Group
Three route groups compose this module's contract:
- `/api/friends` — friend requests, friendships, blocks, suggestions, settings (revision 1, unchanged
  contract).
- `/api/people` — bounded people search (revision 2, new).
- `/api/profile` — public profile read, viewer-relationship context, and target/mutual friend-list
  drill-down (revision 2 additions layered onto Module 2's existing `ProfileController`; `me`,
  avatar/banner upload, and links/interests endpoints are Module 2-owned and out of scope here).

Source of truth: `SimPLe.Backend`. Authentication: cookie-based session (`credentials: 'include'`); the
`X-Requested-With: XMLHttpRequest` CSRF header is required on every mutating request (missing → 400
`Auth.CsrfHeaderRequired`). All endpoints in this reference are reads except the `/api/friends/*` mutations
carried from revision 1.

## Authentication And Authorization Requirements
`/api/friends/*` and `/api/people/search` always require an authenticated session (`[Authorize]`, JWT
`sub`). `/api/profile/{username}` and `/api/profile/{username}/friends` are optionally authenticated:
an anonymous caller is served only when the target's `ProfileVisibility=Public` (and, for the friends list,
additionally `FriendsListVisibility=Everyone`); every other case authenticates or the read 404s.
`/api/profile/{username}/viewer-context` and `/api/profile/{username}/mutual-friends` always require
authentication.

Every action re-derives the authorization decision server-side from the session subject and object
membership — never a body- or query-supplied actor. Non-owned, guessed, hidden, or nonexistent targets
return **404 `Profile.NotVisible`** (never 403), body- and latency-indistinguishable across
nonexistent/private/blocked-either-direction/deleted/suspended/banned (BOLA/IDOR + enumeration defense).
`BlockedByTarget` is never returned as a distinguishable `relationshipState` — the profile read itself 404s
instead of exposing that the viewer is blocked.

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
| 15 | GET | `/api/friends/settings` | Friend-request/search/friends-list privacy settings | — | `FriendSettingsDto` |
| 16 | PUT | `/api/friends/settings` | Update privacy settings (each field independent/optional) | `{ friendRequestPrivacy, searchVisibility?, friendsListVisibility? }` | `FriendSettingsDto` |
| 17 | GET | `/api/people/search` | Bounded people search by username/display-name prefix (keyset cursor) | Query: `q (2–100 chars), limit?≤50, cursor?` | `CursorPage<PeopleSearchResultDto>` |
| 18 | GET | `/api/profile/{username}` | Public profile by username (auth optional) | — | `ProfileDto` |
| 19 | GET | `/api/profile/{username}/viewer-context` | Authenticated viewer's relationship/action state for a profile | — | `ProfileViewerContextDto` |
| 20 | GET | `/api/profile/{username}/friends` | Target's accepted friends (privacy-filtered, auth optional) | Query: `query?, limit?≤50, cursor?` | `CursorPage<PublicIdentityDto>` |
| 21 | GET | `/api/profile/{username}/mutual-friends` | Friends common to the viewer and the target | Query: `limit?≤50, cursor?` | `CursorPage<PublicIdentityDto>` |

## Endpoints — outcomes & status codes

- **Send (5)** returns `SendFriendRequestResult`: `request_created` → **201**; `already_pending` and
  `cross_request_accepted` → **200**. `cross_request_accepted` means a reverse pending request existed and
  was atomically accepted. Rate limited (`friend-send`, 10/min/account) plus a durable **3/day/account-target**
  cap independent of the per-minute window (see Rate Limiting).
- **Accept (6) / Decline (7)** are idempotent: re-accepting an already-accepted request (or re-declining a
  declined one) returns **200** with the current `FriendRequestDto`.
- **Cancel (8) / Remove (3)** are idempotent **204**; an unrelated/guessed id → **404**.
- **Discovery (10)** is exact-username, timing-safe, and returns only minimal identity; any
  ineligible/nonexistent/hidden target → **404 `Profile.NotVisible`**. Rate limited (`friend-discovery`).
- **Dismiss (11)** suppresses a suggestion for 30 days; repeat dismiss is idempotent **204**. A daily
  background job purges expired dismissals in bounded batches. Rate limited (`friend-suggestions`).
- **Block (13)** returns `BlockUserResult`: `blocked` → **201**, `already_blocked` → **200**. Blocking
  atomically ends any pending/accepted edge in the same transaction, and its response deliberately carries
  no target identity fields regardless of the target's visibility (`BlockUserResult` is minimal by design).
- **Settings (15, 16)** now carry three independent fields — `friendRequestPrivacy`, `searchVisibility`,
  `friendsListVisibility` — each changeable without affecting the others. Updating any of them bumps
  `PrivacyPolicyVersion`, which invalidates in-flight profile-friends/mutual-friends cursors bound to the
  old version (they 400 with `Pagination.InvalidCursor` on reuse instead of silently mixing pages under two
  different visibility rules).
- **People search (17)** is authenticated-only, bounded prefix search. Match order: exact username →
  username prefix → display-name prefix; ranking = bucket, then normalized username, then UUID tie-break.
  Excludes self, search-ineligible (`SearchVisibility=Nobody`, or `FriendsOfFriends` with no qualifying
  mutual), blocked (either direction), deleted, suspended, and banned accounts. Never returns a global or
  hidden total. Cursor is bound to `(normalizedQuery, rankingVersion)` — reuse with a different query shape
  → 400 `Pagination.InvalidCursor`. Rate limited (`people-search`, 30/min/account), chained with the shared
  120/hour/IP `GlobalLimiter` that also covers `friend-discovery`.
- **Public profile (18)** unifies every denial (nonexistent, private, blocked either direction, deleted,
  suspended, banned) into the same 404 `Profile.NotVisible`, body- and latency-indistinguishable. Anonymous
  reads are served only for `ProfileVisibility=Public` targets. Sets `Cache-Control: public, max-age=30` +
  `Vary: Cookie` on the anonymous branch and `private, no-store` + `Vary: Cookie` on the authenticated
  branch, so a future CDN/reverse-proxy cache cannot cross-serve one viewer's response to another.
- **Viewer context (19)** is always authenticated and `private, no-store`. `relationshipState` is exactly
  one of `Self | None | IncomingPending | OutgoingPending | Friends | BlockedBySelf` — `BlockedByTarget` is
  never returned (the profile read 404s first, so the state machine never has to represent it).
  `allowedActions` is derived server-side from state and policy, never inferred client-side from missing
  fields.
- **Target/mutual friends (20, 21)** apply the target's current visibility/block/suspension policy to every
  candidate **before** count, order, and cursor construction, so a hidden identity never affects the total,
  order, or page length a caller can observe. `visibleFriendCount` / `visibleMutualFriendCount` (surfaced on
  `ProfileViewerContextDto` and on each people-search result) are computed with the exact same filter set as
  their paged counterpart, so a reported count can never exceed what the same viewer can actually page
  through. The (20) cursor is bound to `(targetUuid, normalizedFilter, viewerPolicyVersion, sort)`; a
  visibility change bumps `PrivacyPolicyVersion` and invalidates any in-flight cursor. Mutual list (21) is
  accepted-friends-of-both, viewer-visible only, and always requires authentication.

## Cursor pagination
`limit` default 20 / max 50 (suggestions cap 20). The cursor is an **opaque base64url** token
(keyset-traversed, not offset); `CursorPage<T>.nextCursor` is `null` at the last page and no total/count is
promised. Sort keys: friends `(normalizedDisplayName, userId)`; requests `(sentAt DESC, id DESC)`; blocks
`(createdAt DESC, id DESC)`; profile-friends `(normalizedDisplayName, userId)` additionally bound to
`(targetUuid, normalizedFilter, viewerPolicyVersion)`; people-search bucket then
`(normalizedUsername, userId)` bound to `(normalizedQuery, rankingVersion)`. An invalid/forged/stale/
cross-shape cursor → **400 `Pagination.InvalidCursor`**. Friend-list `query`: blank (all) or 2–100 normalized
chars. Discovery `username` / people-search `q`: 3–30 / 2–100 chars matching the M1 handle pattern
(`[a-zA-Z0-9_.-]`) where applicable.

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

// Minimal by design — no target identity fields on this path.
BlockUserResult = { outcome: 'blocked' | 'already_blocked'; blockedUserId: string; blockedAt: string; }

FriendSettingsDto = {
  friendRequestPrivacy: 'Anyone' | 'FriendsOfFriends' | 'Off';
  searchVisibility: 'Everyone' | 'FriendsOfFriends' | 'Nobody';
  friendsListVisibility: 'Everyone' | 'Friends' | 'OnlyMe';
}

UpdateFriendSettingsRequestDto = {
  friendRequestPrivacy: 'Anyone' | 'FriendsOfFriends' | 'Off';
  searchVisibility?: 'Everyone' | 'FriendsOfFriends' | 'Nobody';
  friendsListVisibility?: 'Everyone' | 'Friends' | 'OnlyMe';
}

// Shared minimal identity for any surface that lists another account (search, friend/mutual drill-down).
// Later modules compose their own owned fields around this; never bio, links, region, status, elo,
// level, or presence.
PublicIdentityDto = {
  userId: string; username: string; displayName: string; initials: string; color: string;
  avatarUrl: string | null; profileType: string;
}

// PublicIdentityDto + viewer-relative search context. relationshipState never includes BlockedByTarget.
PeopleSearchResultDto = PublicIdentityDto & {
  visibleMutualFriendCount: number;
  relationshipState: 'None' | 'IncomingPending' | 'OutgoingPending' | 'Friends';
}

// Server-derived; RelationshipState is exactly one of the five states below (BlockedByTarget 404s instead).
ProfileViewerContextDto = {
  relationshipState: 'Self' | 'None' | 'IncomingPending' | 'OutgoingPending' | 'Friends' | 'BlockedBySelf';
  visibleMutualFriendCount: number;
  canViewFriends: boolean;
  visibleFriendCount: number | null;
  allowedActions: string[]; // e.g. ['AddFriend','Share','More.Block']
}
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
| `Pagination.InvalidCursor` | 400 | Invalid/forged/stale/cross-shape cursor |
| `RateLimit.Exceeded` | 429 | Rate limit hit (+ `Retry-After`) |
| `Auth.CsrfHeaderRequired` | 400 | Missing CSRF header on a mutation |
| `Validation.Failed` | 400 | Request/query validation failed |

No new error codes were introduced for the revision-2 profile/search family — every denial reuses
`Profile.NotVisible`, `Pagination.InvalidCursor`, `RateLimit.Exceeded`, or `Validation.Failed`. Internal
denial reasons stay in server logs (no PII), never in responses. Frontend mapping:
`src/features/friends/friendsErrors.ts`.

## Rate Limiting
Per-account fixed windows (partitioned by JWT subject), rejections carry `Retry-After` +
`RateLimit.Exceeded`:

| Policy | Limit |
|---|---|
| `friend-send` | 10/min/account, plus a durable **3/day/account-target** cap that survives remove/re-send cycles |
| `friend-discovery` | 30/min/account |
| `friend-suggestions` | 30/min/account |
| `friend-block` | 20/min/account |
| `people-search` | 30/min/account |
| `profile-public` | 120/min/account (coarser anonymous ceiling) |
| `profile-viewer-context` | 120/min/account |
| `profile-friends` | 120/min/account |
| `profile-mutual-friends` | 120/min/account |

`friend-discovery` and `people-search` additionally chain into one shared **120/hour/IP** `GlobalLimiter`.
They remain two independently-keyed 30/min/account windows rather than one shared 30/min budget — confirmed
as the intended design by product decision (2026-07-10, resolves the former M03-010 note); the per-IP hourly
ceiling backstops both regardless. Middleware order is
`UseAuthentication() → UseRateLimiter() → UseAuthorization()`.

## Events (transactional outbox)
Each `/api/friends/*` mutation stages exactly one integration event in the same PostgreSQL transaction as
the aggregate change: `FriendRequestCreatedV1`, `FriendRequestAcceptedV1`, `FriendRequestDeclinedV1`,
`FriendRequestCancelledV1`, `FriendshipRemovedV1`, `UserBlockedV1`, `UserUnblockedV1`. `UserBlockedV1` is
never a notification to the target. Payloads carry minimum ids only. Revision-2 endpoints are reads (people
search, profile, viewer-context, friend/mutual lists) and settings updates; none stage a new outbox event
type.

## Security Considerations
Ownership is re-derived server-side on every cross-user action (IDOR/BOLA → 404, never 403). Block direction
is never leaked; `BlockedByTarget` never appears as a `relationshipState`. Discovery/suggestion/search DTOs
expose only minimal identity plus visible mutual counts. Mass-assignment allow-list on settings:
`friendRequestPrivacy`, `searchVisibility`, `friendsListVisibility` only — `state`, `requesterId`,
`PrivacyPolicyVersion`, and all outbox/domain-version fields are server-owned and stripped.

The `--security=asvs-lite` review of the revision-2 delta (2026-07-09,
`SimPle.Project/docs/security/audits/module-03-friends-social-graph.md`) found zero Critical/High findings.
Two Medium findings were opened and have since been fixed and verified (2026-07-10):
- **M03-008** — `GetVisibleFriendCountAsync`, `GetMutualFriendCountAsync`, and `SearchPeopleAsync`'s
  per-result mutual count now apply the same visibility/suspension/block filters as their sibling paged-list
  queries, so a reported count can no longer exceed what the same viewer can page through.
- **M03-009** — the `AddProfilePrivacyAndRetiredUsernames` migration's flat `SearchVisibility="Everyone"`
  backfill now runs a corrective `UPDATE` that re-derives each existing row's `SearchVisibility` from its
  owner's current `ProfileVisibility` (`Public→Everyone`, `FriendsOnly→FriendsOfFriends`, `Private→Nobody`).

Two Low findings were also opened: **M03-010** (resolved 2026-07-10 by product decision — the two
independent 30/min budgets are the intended design, documented above, no code change) and **M03-011** (fixed
2026-07-10 — the anonymous profile branch now sets an explicit `Cache-Control`/`Vary` header).

## Related Tests
Backend unit + integration + real-PostgreSQL verification — UnitTests 321/321, IntegrationTests 224/224 (0
skipped, incl. migration smoke and Postgres concurrency/translation/EXPLAIN tests). Frontend `npx vitest run`
188/188 across all reconciled suites; `check-contract-drift.mjs` reports DRIFT=0. The expanded multi-user
navigation E2E (`tests/e2e/module-03-friends.spec.ts`) has been **executed against a live local stack and
passed** (1/1, 25.7s, 2026-07-10) — see `docs/ai-workflow/evidence/checkpoints/
module-03-friends-social-graph/verification.json`. Two real product-code bugs surfaced and were fixed during
that run: a `Cursor.cs` pagination defect (`string.IsNullOrEmpty` → `value is null`) and a `ProtectedRoute`/
route-group gap that had been blocking anonymous access to `Public`-visibility profiles (fixed via a new
`(public)` Next.js route group); both fixes are re-validated by the same passing run.

## Last Verified Command
Backend: `dotnet build SimPle.sln`; `dotnet test tests/SimPle.UnitTests` (321/0/0); real-Postgres
`dotnet test tests/SimPle.IntegrationTests` (224/0/0, 0 skipped) — 2026-07-09. Frontend: `npx tsc --noEmit`,
`npm run lint`, `npm run test` (188/188), `node scripts/check-contract-drift.mjs` (DRIFT=0) — 2026-07-09.
Live E2E verification: `node tests/e2e/seed-b-friends.mjs` then `npx playwright test
tests/e2e/module-03-friends.spec.ts --project=chromium` against a live backend/frontend/real-Postgres stack
— 1 passed, 25.7s, plus a follow-up `dotnet build` (Cursor.cs fix) and `npx tsc --noEmit` (route-group
restructuring) — 2026-07-10. Security fix verification (M03-008/M03-009/M03-011): targeted unit filter
re-run plus a live E2E re-run against real Postgres exercising the corrected correlated-subquery LINQ, and a
direct `curl` header check — 2026-07-10.

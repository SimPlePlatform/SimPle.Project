# Technical Flow - Module 03: Friends & Social Graph

## Recruiter-Facing Summary

The friends system lets a SimPle player build their social graph: discover people by exact username without
leaking who exists, send and manage friend requests, remove friends, block abusers, and control who is allowed
to send them requests. It is engineered so every cross-user action re-derives authorization from the session
on the server (never a client-supplied id), so concurrent actions on the same relationship converge instead of
racing into duplicate rows or crashes, and so every state change stages a durable outbox event in the same
database transaction — the event log later modules will consume for notifications and activity feeds.

## Problem Solved

A social gaming platform needs a trustworthy friend graph before lobbies, chat, or matchmaking make sense.
This module delivers that graph — requests, friendships, blocks, discovery, and request-privacy — with the
ownership, concurrency, and abuse controls those later modules depend on.

## Architecture Overview

```
Browser
  └── FriendSummaryProvider (AppShell.tsx)
        ├── useFriendSummary() → { summary, loading, error, invalidate, retry }
        ├── Sidebar → badge (incomingRequestCount)
        ├── FriendsPage → tabs, all panels, mutations
        ├── DashboardPage → friends panel, pending count
        ├── SettingsPage → privacy + block list
        └── AddFriendModal → safe discovery lookup

friendsApi.ts ──→ apiFetch<T>() ──→ /api/friends/*
                                        │
                              FriendsController (auth + CSRF + per-endpoint rate limit)
                                        │
                                  FriendsService (invariants, cooldowns, privacy, outbox staging)
                                        │
                              FriendRepository ──→ PostgreSQL (expression-unique pair index, xmin)
                                        │
                              OutboxMessage/OutboxDelivery (same transaction as the aggregate write)
```

## Backend Flow

All requests hit `FriendsController` under `/api/friends` (16 endpoints, authenticated, CSRF-checked on
mutations). Endpoints cover summary, keyset-paged friend list/requests/blocks, send/accept/decline/cancel/
remove, safe exact-username discovery, suggestions with mutual counts, suggestion dismissal, block/unblock, and
privacy settings. `FriendsService` owns the domain invariants (one `Friendship` row per unordered pair, cross-
send auto-accept, decline/cancel cooldowns, block-ends-edge atomicity) and stages one of seven `*V1` outbox
events in the same PostgreSQL transaction as every mutation. Concurrent writers are handled by catching the
unique-index violation on simultaneous cross-sends and retrying on a stale `xmin`, so races converge on 200/204/
409 outcomes and never surface a 500.

## Frontend Flow

- **Existing UI reused:** Sidebar, FriendsPage, DashboardPage, SettingsPage, profile surfaces — logic wired
  in, no redesign.
- **Frontend integration points:** `friendsApi.ts` (all 16 endpoints), `friendsErrors.ts` (R12 error-code
  mapping), `FriendSummaryContext` (shared counts).
- **Visual changes made:** deferred buttons (Message, Invite/Lobby, Share invite link) rendered `disabled`
  per the approved visual-change list; the "Online" tab and "Show online status" toggle hidden pending
  Module 7; friend-list/suggestion rows show `@username` in the slot the mock previously used for level/ELO
  (R5 — hidden behind `until M10` comments, not deleted).

Key flows (discover → send request; accept/decline/cancel; remove; block/unblock; privacy; dismiss suggestion)
all call `invalidate()` and reload the affected panels — see the Mutation Invalidation Matrix below.

## Database/Domain Model Changes

- **Existing database impact:** additive only — `Friendship` (extended), `Block`, `UserFriendSettings`,
  `DismissedFriendSuggestion`, `OutboxMessage`, `OutboxDelivery`.
- **Migration added:** yes — forward-only corrective migration `20260705120243_HardenFriendsSocialGraph` on
  top of the original `20260627154911_AddFriendsAndBlocks` (adds columns with defaults, three new tables, a
  JSONB payload column, outbox/dismissal unique indexes, keyset cursor indexes, a no-self-dismissal CHECK, and
  an idempotent legacy-history backfill).
- **Migration safety notes:** the unordered-pair unique index is a hand-written `(LEAST, GREATEST)` expression
  index (EF cannot scaffold it); real-PostgreSQL tests prove expression uniqueness, `xmin` optimistic
  concurrency, CHECK constraints, cascade behavior, and the legacy backfill on a disposable `postgres:16-alpine`
  container. EF InMemory cannot enforce any of these and is not used as evidence for them.
- **Data preservation notes:** no existing data altered; the backfill is idempotent and only populates new
  columns on existing rows.
- **Destructive DB changes:** none.

## API Contract

- **Backend/API/Swagger alignment:** endpoints and DTOs documented in `api-reference.md`; Swagger annotations
  present on the controller.
- **Frontend/API integration alignment:** `friendsApi.ts` matches the documented routes/verbs; `node
  scripts/check-contract-drift.mjs` reports DRIFT = 0.

## Validation And Error Handling

Domain errors surface as the canonical R12 error catalogue (`Friends.SelfRequest`, `Friends.SelfBlock`,
`Friends.RequestsDisabled`, `Friends.NotFriendOfFriend`, `Friends.NotPending`, `Friends.RequestCooldown` (409 +
`retryAfterUtc`/`Retry-After`), `Friends.AlreadyFriends`, `Friends.ConcurrencyConflict`, `Profile.NotVisible`,
`Pagination.InvalidCursor`, `RateLimit.Exceeded`), mapped to user-facing messages in
`src/features/friends/friendsErrors.ts`. The prior `Friends.DuplicateRequest`/`Friends.ReverseRequestExists`/
`Friends.Blocked` codes are retired in favor of 200-outcome discriminators and the unified 404.

## Authorization And Security Decisions

Every action re-derives authorization server-side from the session subject and object membership, never a
body-supplied actor id. Guessed or unowned relationship/request/block/user ids return **404
`Profile.NotVisible`** — never 403 — body- and latency-indistinguishable from a nonexistent, private, blocked,
deleted, suspended, or banned target (BOLA + enumeration defense, verified on real Postgres for timing). The
prior direction-neutral-but-403 `Friends.Blocked` design (open item M03-001) is resolved on the Module 3 surface
by this change. Two items remain open per the security audit
(`SimPle.Project/docs/security/audits/module-03-friends-social-graph.md`): **M03-006** (Medium, deferred — no
audit-event logging for denials yet) and **M03-007** (Low — the block endpoint's success response echoes the
target's identity card, bypassing the private/block visibility gate on that one response body).

## Realtime/Socket.IO Flow If Applicable

Not applicable — real-time presence/online status is deferred to Module 7.

## State Management If Applicable

`FriendSummaryContext` (mounted once in `AppShell.tsx`) holds shared badge/count state across route
navigations. Lifecycle: authenticates → `getSummary()`; signs out → clears; `invalidate()`/`retry()`
increment a `rev` counter to re-run the effect; a `cancelled` flag prevents stale updates after unmount.
Known limitation: it refreshes only on explicit `invalidate()`/`retry()`, not on route change.

## Edge Cases Handled

- **Stale response suppression:** every paginated loader uses a sequence ref to discard out-of-order
  responses (FriendsPage friends/incoming/outgoing/suggestions, invite picker).
- **Debounced search:** 300 ms debounce with previous-timer cleanup and a skip-initial-mount guard.
- **Concurrent search guard:** `lookupActive` ref prevents overlapping discovery lookups in AddFriendModal.
- **State reset on modal reopen:** `useEffect([open])` clears username/lookup/error.
- **Cross-send race, decline/cancel cooldown boundary, accept-vs-block and remove-vs-block races, cursor
  tampering, and suggestion-dismiss idempotency/expiry** are handled server-side and proven on real Postgres
  (see `testing-report.md`).

### Mutation Invalidation Matrix

| Action | `invalidate()` | Reload friends | Reload incoming | Reload outgoing | Reload suggestions |
|--------|:---:|:---:|:---:|:---:|:---:|
| Accept request | ✓ | p1 | p1 | — | ✓ |
| Decline request | ✓ | — | p1 | — | ✓ |
| Cancel outgoing | ✓ | — | — | p1 | ✓ |
| Send (discovery/suggestion) | ✓ | — | — | p1 | ✓ |
| Remove friend | ✓ | p1 | — | — | ✓ |
| Block from More | ✓ | p1 | p1 | p1 | ✓ |
| AddFriendModal sent | ✓ | — | — | p1 | ✓ |
| Dismiss suggestion | — | — | — | — | optimistic (rollback on failure) |
| Unblock (settings) | — | — | — | — | n/a |

## Design Tradeoffs

`FriendSummaryContext` refreshes only on explicit invalidation, not on route change. This keeps the shared
state simple and avoids redundant fetches on every navigation, at the cost of possible cross-tab badge
staleness — an acceptable tradeoff until real-time presence (Module 7) supersedes it. Cursor pages are
best-effort (no snapshot isolation across pages, no total/count) rather than offset-paginated, trading exact
counts for O(1) page cost that does not degrade as the graph grows.

## Files Changed And Why

- `features/friends/friendsApi.ts` — all 16 endpoints, keyset `CursorPage<T>` paging, discovery.
- `features/friends/friendsErrors.ts` — R12 error-code → message mapping.
- `features/friends/FriendSummaryContext.tsx` — shared counts.
- `features/friends/AddFriendModal.tsx` — safe discovery lookup instead of the public-profile endpoint.
- `components/friends/InviteFriendModal.tsx` — cursor-based friend picker.
- `features/friends/FriendsPage.tsx`, `features/settings/SettingsPage.tsx` (privacy + block list),
  `components/layout/Sidebar.tsx` (badge), dashboard + profile surfaces — UI wiring.
- Backend: `FriendsService.cs`, `FriendsController.cs`, `FriendOutbox.cs`, `FriendRepository.cs`, `Friendship`/
  `Block`/`UserFriendSettings`/`DismissedFriendSuggestion`/`OutboxMessage`/`OutboxDelivery` domain + EF configs,
  migration `20260705120243_HardenFriendsSocialGraph`.

## How To Read The Implementation

Start at `friendsApi.ts` (the contract), then `FriendSummaryContext.tsx` (shared state), then `FriendsPage.tsx`
(the main surface). Error handling lives in `friendsErrors.ts`. On the backend, start at `FriendsController.cs`,
then `FriendsService.cs` for the invariants, then `FriendOutbox.cs` for event staging.

## Future Improvements / Deferred Items

| Feature | Deferred to | Current state |
|---------|------------|---------------|
| Real-time online status | Module 7 | "Show online status" toggle hidden |
| Message button | Module 11 (chat) | Rendered `disabled` |
| Invite/Lobby button | Module 7 (lobby) | Rendered `disabled` |
| Share invite link | Module 7 | Rendered `disabled` |
| FriendsActivity sidecar | Module 11 | Static mock data |
| ELO/level on friend rows | Module 10 | Removed from DTOs (R5); UI shows `@username` instead |
| Notification delivery on outbox events | Module 11 | Events staged transactionally; no consumer/transport yet |
| Audit-event logging for denials | later hardening | open item M03-006 (Medium, deferred) |
| Block endpoint response leaks target identity card | later hardening | open item M03-007 (Low) |
| Secondary rate caps (send 3/day/account-target; discovery 120/hr/IP) | later hardening | deferred — needs a durable per-pair counter / chained global limiter |

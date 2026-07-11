# Technical Flow - Module 03: Friends & Social Graph

> Revision 2. Adds bounded people search, canonical profile navigation (`/u/{username}`), a server-derived
> viewer-relationship action bar, and privacy-aware friend/mutual-friend drill-downs on top of the unchanged
> revision-1 friend/block/request graph below. Backend evidence:
> `docs/ai-workflow/evidence/checkpoints/module-03-friends-social-graph/backend.json`. Frontend evidence:
> `frontend.json`. Live multi-user E2E execution against a fully seeded local stack has **run and passed**
> (1/1, 25.7s) — see `verification.json` and `testing-report.md`. Two real product-code bugs surfaced and
> were fixed during that run: a `Cursor.cs` pagination defect and a `ProtectedRoute`/route-group gap for
> anonymous public-profile access (both detailed in "Files Changed And Why" below).

## Summary

The friends system lets a SimPle player build and navigate their social graph: search for people by name,
land on a real profile page instead of a raw user id, see at a glance whether they're already friends
(or can send a request, or are blocked), and drill into who a person's friends and mutual friends actually
are — all gated by privacy settings each player controls independently. It is engineered so every
cross-user action and every count re-derives authorization and visibility from the session on the server
(never a client-supplied id or a trusting client-side count), so a denied or hidden target always looks
identical to one that never existed, and so a "you have N mutual friends" number can never promise more than
what the same viewer can actually page through.

## Problem Solved

A social gaming platform needs a trustworthy, navigable social graph before lobbies, chat, or matchmaking
make sense. Revision 1 delivered the graph itself (requests, friendships, blocks, discovery,
request-privacy). Revision 2 makes that graph *reachable*: a composed search entry point, a canonical
profile identity every account can be linked to, a relationship-aware action bar, and paginated friend/
mutual-friend lists — each still bound by the same ownership, privacy, and abuse controls later modules
depend on.

## Architecture Overview

```
Browser
  └── FriendSummaryProvider (AppShell.tsx)
        ├── useFriendSummary() → { summary, loading, error, invalidate, retry }
        ├── Sidebar → badge (incomingRequestCount)
        ├── Topbar → PeopleSearchCombobox (WAI-ARIA combobox)
        ├── FriendsPage → tabs, all panels, mutations
        ├── DashboardPage → friends panel, pending count
        ├── SettingsPage → privacy (request/search/friends-list visibility) + block list
        ├── /search → SearchResultsPage (People live; Games/Public Lobbies labelled unavailable)
        └── /u/[username] → ProfilePage, (public) route group (PlayerIdentity, ProfileViewerContext-gated
              │                action bar; full AppShell if authenticated, minimal public header otherwise)
              ├── /u/[username]/friends → ProfileFriendsPage (cursor drill-down, (public) route group)
              └── /u/[username]/mutual-friends → ProfileMutualFriendsPage (cursor drill-down, (public) route group)

friendsApi.ts / peopleApi.ts / profileApi.ts ──→ apiFetch<T>() ──→ /api/friends/* | /api/people/* | /api/profile/*
                                                                          │
                                          FriendsController │ PeopleController │ ProfileController
                                          (auth + CSRF on mutations + per-endpoint rate limit)
                                                                          │
                                  FriendsService / PeopleService / ProfileService
                                  (invariants, cooldowns, privacy, viewer-context derivation, outbox staging)
                                                                          │
                                  FriendRepository / RetiredUsernameRepository ──→ PostgreSQL
                                  (expression-unique pair index, xmin, prefix-search indexes)
                                                                          │
                                  OutboxMessage/OutboxDelivery (same transaction as the aggregate write)
```

## Backend Flow

`FriendsController` under `/api/friends` (revision-1 contract, unchanged: summary, keyset-paged friend
list/requests/blocks, send/accept/decline/cancel/remove, discovery, suggestions, dismiss, block/unblock,
and now three-field privacy settings). `PeopleController` adds `GET /api/people/search` — authenticated
bounded prefix search over username/display-name with keyset pagination. `ProfileController` gains three
revision-2 reads alongside its existing Module-2-owned profile endpoints: `GET /api/profile/{username}`
(now unifying every denial into 404 `Profile.NotVisible`), `GET /api/profile/{username}/viewer-context`
(derives `relationshipState`/`allowedActions`/visible counts server-side), and
`GET/{username}/friends` + `GET/{username}/mutual-friends` (privacy-filtered cursor drill-downs).
`FriendsService`/`PeopleService`/`ProfileService` own the domain invariants; `FriendRepository`'s new query
methods apply the *same* visibility/suspension/block filter set to both a paged list and its matching count
so the two can never disagree. Two new additive migrations
(`AddProfilePrivacyAndRetiredUsernames`, `AddPeopleSearchAndSendCap`) add the settings columns, the
`retired_usernames` table, the durable send-cap columns on `friendships`, and two prefix-search indexes.

## Frontend Flow

- **Existing UI reused:** Sidebar, FriendsPage, DashboardPage, SettingsPage — logic wired in, no redesign.
- **Frontend integration points:** `friendsApi.ts` (revision-1 endpoints + updated settings shape),
  `friendsErrors.ts`, `FriendSummaryContext`, `peopleApi.ts` (new), `profileApi.ts` (extended),
  `PlayerIdentity.tsx` (new shared identity chip), `PeopleSearchCombobox.tsx` (new).
- **Mocks/placeholders replaced with real, honest behavior this revision:**
  - Ambiguous `/profile/{userId}` routing → canonical `/u/{username}` routing; `/profile/me` and the
    viewer's own id redirect, every other legacy id shows an honest "This link has moved" `EmptyState`
    linking to Friends (there is no backend UUID→username lookup endpoint, so no fabricated resolution is
    attempted).
  - Fake ELO/Level header chips and an online-presence status dot on profiles → removed entirely; the
    header shows only real identity (name, avatar, banner, bio, links).
  - Mock `ProfileOverview`/`PerformanceChart`/`MatchHistoryTable`/`AchievementsGrid`/`FavoriteGames`
    renderers → honest "Available in Module X" `EmptyState` placeholders per tab; no API calls made.
  - Duplicated ad-hoc avatar+name markup across FriendsPage/DashboardPage/AddFriendModal → one shared
    `PlayerIdentity` component.
  - Absent relationship action bar → server-derived `ProfileViewerContext.allowedActions`-gated buttons
    (Add friend / Accept / Decline / Cancel / Remove / Block / Unblock) wired to existing `friendsApi`
    methods, including cross-request-accept handling and just-in-time request-id lookup for Decline/Cancel.
  - No composed people-search entry point → an accessible topbar `PeopleSearchCombobox` (full WAI-ARIA
    combobox pattern) plus a `/search?type=people&q=...` results page; Games and Public Lobbies result
    groups are explicitly labelled unavailable (Modules 4/6 not yet built) rather than omitted or faked.
  - Display-only mutual-friends count → a real cursor-paginated `ProfileMutualFriendsPage` consuming
    `GET /api/profile/{username}/mutual-friends`, mirroring the existing friends drill-down's
    load-more/dedup pattern.
  - 2-user-only Playwright coverage → an expanded A/B/C/anonymous multi-context scenario, executed and
    passed against a live local stack (1/1, 25.7s — see `testing-report.md`).
- **Known, accepted limitations carried forward (not defects):** anonymous viewers never fetch
  `ProfileViewerContext` (the endpoint is `[Authorize]`-gated), so an anonymous visitor sees a plain,
  non-linked friend count instead of the `canViewFriends`-gated drill-down link.
- **Fixed during live E2E verification, not part of the original slice plan:** anonymous/
  unverified visitors were being redirected away from every `(app)`-group route by `ProtectedRoute`,
  including `Public`-visibility profiles the backend already served anonymously. Fixed by moving
  `/u/[username]`, `/u/[username]/friends`, and `/u/[username]/mutual-friends` into a new `(public)` Next.js
  route group whose layout renders the full `AppShell` for authenticated sessions or a minimal public header
  otherwise — made with explicit user sign-off (`AskUserQuestion` → "Fix it now"), validated by E2E step 7.

Key flows (search → profile → relationship action; friends/mutual-friends drill-down; privacy settings)
all call `invalidate()` or reload the affected panel — see the Mutation Invalidation Matrix below.

## Database/Domain Model Changes

- **Existing database impact:** additive only. Revision 1: `Friendship` (extended again this revision),
  `Block`, `UserFriendSettings`, `DismissedFriendSuggestion`, `OutboxMessage`, `OutboxDelivery`. Revision 2
  adds: `RetiredUsername` table; `SearchVisibility`/`FriendsListVisibility`/`PrivacyPolicyVersion` columns on
  `UserFriendSettings`; `LastSenderId`/`SendCountInWindow`/`SendWindowStartUtc` columns plus two prefix
  indexes on `users`.
- **Migrations added:** `20260709054351_AddProfilePrivacyAndRetiredUsernames` (privacy columns +
  `retired_usernames` table) and `20260709094629_AddPeopleSearchAndSendCap` (send-cap columns + prefix
  indexes).
- **Migration safety notes:** both are forward-only and additive; `Down()` on each drops only what `Up()`
  added. The `SearchVisibility` backfill in the first migration originally used a flat default (fixed —
  see below); the prefix-search indexes use raw-SQL `varchar_pattern_ops`/`text_pattern_ops`
  DDL (static, no injection surface) since EF cannot scaffold pattern-ops indexes.
- **Data preservation notes:** no existing data altered destructively; new columns are additive with
  defaults, and the `SearchVisibility` backfill (once corrected) only re-derives a value from data already
  on the row.
- **Destructive DB changes:** none.

## API Contract

- **Backend/API/Swagger alignment:** all 5 new/changed revision-2 endpoints carry
  `[SwaggerOperation]` + `[ProducesResponseType]`; documented in full in `api-reference.md`.
- **Frontend/API integration alignment:** `check-contract-drift.mjs` reports **DRIFT = 0** — 58 backend
  routes, 49 resolved frontend calls, all matched by path + verb. 5 `apiFetch` call sites use interpolated
  template-literal paths (`people/search` query string; `friends/requests` and `friends/blocks` query
  strings; `profile/{username}/friends` and `/mutual-friends`) that the script's regex heuristic cannot
  statically resolve, and are listed as "unresolved (dynamic)" rather than a real mismatch; each was manually
  verified by reading both the frontend call site and the backend controller route directly — all 5
  correctly target existing, already-implemented endpoints (the same pre-existing heuristic limitation
  already accepted for `GET /api/friends` in the revision-1 checkpoint).

## Validation And Error Handling

Domain errors surface as the canonical R12 error catalogue (unchanged from revision 1 — see
`api-reference.md`). No new error codes were introduced for the revision-2 profile/search family; every
denial reuses `Profile.NotVisible`, `Pagination.InvalidCursor`, `RateLimit.Exceeded`, or `Validation.Failed`.

## Authorization And Security Decisions

Every action and every count re-derives its result server-side from the session subject and object
membership, never a body-supplied actor id or a client-trusted count. Guessed or hidden targets return
**404 `Profile.NotVisible`** — never 403 — body- and latency-indistinguishable across
nonexistent/private/blocked-either-direction/deleted/suspended/banned. `BlockedByTarget` is never a
distinguishable `relationshipState`; the profile read 404s first.

The `--security=asvs-lite` review of the revision-2 delta
(`SimPle.Project/docs/security/audits/module-03-friends-social-graph.md`) found zero
Critical/High findings. Two Medium findings (M03-008: friend/mutual visible-counts computed with a narrower
privacy filter than their paged-list counterpart; M03-009: a migration backfill that ignored existing users'
current profile visibility) and two Low findings (M03-010: an intentional rate-limit budget split, confirmed
by product decision; M03-011: a missing explicit cache header on the anonymous profile branch) were opened
and have all since been **fixed (M03-008, M03-009, M03-011) or resolved (M03-010, product decision) and
verified** — see the security audit's "Fix Verification" section. All revision-1
findings (M03-001, M03-006, M03-007) were already fixed in the prior revision.

## Realtime/Socket.IO Flow If Applicable

Not applicable — real-time presence/online status is deferred to Module 7.

## State Management If Applicable

`FriendSummaryContext` (mounted once in `AppShell.tsx`) holds shared badge/count state across route
navigations, unchanged from revision 1. Each profile page independently fetches its own
`ProfileViewerContext` on mount (authenticated viewers only) rather than sharing it through a context, since
it is per-target rather than per-viewer-global state.

## Edge Cases Handled

- **Stale response suppression, debounced search, concurrent search guard, modal-reopen reset** — unchanged
  from revision 1 (FriendsPage panels, AddFriendModal).
- **Debounced people search:** `PeopleSearchCombobox` debounces input before querying, mirroring the
  discovery-search debounce pattern, with a sequence guard against out-of-order responses.
- **Legacy profile-id resolution:** `LegacyProfileRedirect` resolves `/profile/me` and the viewer's own id
  to the canonical route; any other id renders the honest "moved" state rather than guessing.
- **Cross-send race, decline/cancel cooldown boundary, accept-vs-block and remove-vs-block races, cursor
  tampering (including the new `PrivacyPolicyVersion`-bound profile-friends/mutual-friends cursors), and
  suggestion-dismiss idempotency/expiry** are handled server-side and proven on real Postgres (see
  `testing-report.md`).

### Mutation Invalidation Matrix

| Action | `invalidate()` | Reload friends | Reload incoming | Reload outgoing | Reload suggestions |
|--------|:---:|:---:|:---:|:---:|:---:|
| Accept request | ✓ | p1 | p1 | — | ✓ |
| Decline request | ✓ | — | p1 | — | ✓ |
| Cancel outgoing | ✓ | — | — | p1 | ✓ |
| Send (discovery/suggestion/search/profile) | ✓ | — | — | p1 | ✓ |
| Remove friend | ✓ | p1 | — | — | ✓ |
| Block from More / profile action bar | ✓ | p1 | p1 | p1 | ✓ |
| AddFriendModal sent | ✓ | — | — | p1 | ✓ |
| Dismiss suggestion | — | — | — | — | optimistic (rollback on failure) |
| Unblock (settings) | — | — | — | — | n/a |
| Profile relationship action (any) | — | — | — | — | profile page re-fetches its own `ViewerContext` |

## Design Tradeoffs

`FriendSummaryContext` still refreshes only on explicit invalidation, not on route change (unchanged
tradeoff from revision 1). Profile pages deliberately do **not** share `ProfileViewerContext` through a
global context — it is fetched fresh per profile visit, trading one extra request per navigation for
correctness (a stale cross-profile relationship state would be a worse bug than one extra fetch). Cursor
pages remain best-effort keyset pagination rather than offset-paginated, now additionally bound to
`PrivacyPolicyVersion` for the two new drill-downs so a visibility change can't silently mix pages computed
under two different rules.

## Files Changed And Why

**Backend** (`backend.json`): `PeopleController.cs`, `ProfileController.cs` (new/extended); `FriendsController.cs`
(settings shape); `PeopleService.cs`, `ProfileService.cs` (new/extended), `FriendsService.cs` (send-cap);
`FriendRepository.cs` (privacy-filter-aligned count queries), `RetiredUsernameRepository.cs`;
`Friendship.cs` (send-cap fields/methods), `RetiredUsername.cs`; `PublicIdentityDto.cs`,
`PeopleSearchResultDto.cs`, `ProfileViewerContextDto.cs`, `FriendSettingsDto.cs`/
`UpdateFriendSettingsRequestDto.cs`; migrations `20260709054351_AddProfilePrivacyAndRetiredUsernames`,
`20260709094629_AddPeopleSearchAndSendCap`; `Program.cs` (new rate-limiter policies + chained `GlobalLimiter`).

**Backend, found and fixed during live E2E verification** (`verification.json`):
`SimPle.Application/Common/Pagination/Cursor.cs` — `TryFromBase64Url` now checks `value is null` instead of
`string.IsNullOrEmpty`, fixing an incorrect rejection of a legitimate empty-string cursor component that
broke friends/mutual-friends "Load more" pagination in the common no-filter case; `ProfileService.cs` and
`appsettings.Development.json` also touched as part of the same verification pass.

**Frontend** (`frontend.json`): `peopleApi.ts`, `types.ts` (new); `profileApi.ts` (extended);
`PlayerIdentity.tsx`, `PeopleSearchCombobox.tsx` (new shared components); `ProfilePage.tsx`,
`ProfileFriendsPage.tsx`, `ProfileMutualFriendsPage.tsx`, `LegacyProfileRedirect.tsx`; `SearchResultsPage.tsx`,
`Topbar.tsx` (combobox mount), `Toast.tsx` (live-region status); `friendsApi.ts`/`friendsErrors.ts`/
`FriendsPage.tsx`/`AddFriendModal.tsx`/`DashboardPage.tsx`/`InviteFriendModal.tsx`/`SettingsPage.tsx`
(settings shape + shared identity component adoption); `vitest.config.ts` (excluded `tests/e2e/**`, fixing a
pre-existing gap that misloaded the 2 Playwright-only spec files under Vitest); E2E fixtures
`tests/e2e/module-03-friends.spec.ts`, `tests/e2e/seed-b-friends.mjs` (executed);
`.claude/config/module-e2e-manifest.json` flipped to `present`.

**Frontend, found and fixed during live E2E verification** (`verification.json`):
`app/(public)/layout.tsx` (new — renders full `AppShell` for authenticated sessions, minimal public header
otherwise), `app/(public)/u/[username]/page.tsx`, `.../friends/page.tsx`, `.../mutual-friends/page.tsx`
(moved out of `app/(app)/...` into the new `(public)` route group so `ProtectedRoute` no longer redirects
anonymous visitors away from `Public`-visibility profiles); `app/(app)/search/page.tsx` and
`app/(app)/profile/[userId]/page.tsx` (legacy-id/search routes, unchanged location).

## How To Read The Implementation

Start at `peopleApi.ts`/`profileApi.ts` (the new contracts), then `PeopleSearchCombobox.tsx` and
`ProfilePage.tsx` (the main new surfaces), then `PlayerIdentity.tsx` (the shared identity primitive
everything else composes). On the backend, start at `PeopleController.cs`/`ProfileController.cs`, then
`PeopleService.cs`/`ProfileService.cs` for the derivation logic (especially how `ProfileViewerContext` and
the visible-count fields are computed), then `FriendRepository.cs` to see the count/list filter-parity
pattern that M03-008's fix depends on.

## Future Improvements / Deferred Items

| Feature | Deferred to | Current state |
|---------|------------|---------------|
| Real-time online status | Module 7 | "Show online status" toggle hidden |
| Message button | Module 11 (chat) | Rendered `disabled` |
| Invite/Lobby button | Module 7 (lobby) | Rendered `disabled` |
| Share invite link | Module 7 | Rendered `disabled` |
| FriendsActivity sidecar | Module 11 | Static mock data |
| ELO/level on friend rows and profile header | Module 10 | Removed from UI (R5); DTOs unaffected |
| Games / Public Lobbies search result groups | Modules 4 / 6 | Explicitly labelled unavailable on `/search` |
| Legacy `/profile/{uuid}` resolution for non-owner ids | Later hardening | Shows an honest "moved" `EmptyState`; no backend UUID→username lookup endpoint exists yet |
| Anonymous viewer `canViewFriends` gating | Accepted, not deferred | Anonymous visitors see a plain friend count only, since `ProfileViewerContext` is authenticated-only by design |
| Notification delivery on outbox events | Module 11 | Events staged transactionally; no consumer/transport yet |
| Production review and final evidence sign-off | `/simple production-review module=3` | Live E2E already passed (1/1); production-review and final evidence remain |
| `mock/friends.ts` | Module 5/7 | Still imported by lobby/game surfaces; deletion deferred |

# Technical Flow - Module 06: Lobby & Matchmaking System

## Summary

Module 6 makes the create-lobby modal and the lobby page real: a signed-in player creates a lobby with real
settings, gets a real join code and link, invites real friends, and sees real seats and readiness state
instead of a hardcoded `SP-7F-29` and local component state. It also adds an honest Quick Match queue —
deterministic same-region rating bands that widen over 15/30/60 seconds, backed by a real worker that claims
tickets under row-level locking and commits assignments guarded by a partial unique index so no ticket is
ever assigned twice. What it deliberately does **not** do is create a playable match: Start and Quick
Match's execution path are both gated behind a Module 8 readiness probe that is not yet registered, so both
return an honest "not available yet" response today rather than inventing a room. This is the module's
central discipline — lobbies, invites, and tickets are all fully real, but the boundary where they would
hand off to a live match is a documented, tested, and visibly disabled seam, not a fabricated success.

## Problem Solved

Before this module, `/lobby/[lobbyId]` rendered entirely from local component state seeded by a hardcoded
lobby code, the Create Lobby modal navigated to that same fake code regardless of what was submitted, the
dashboard's pending-invites card displayed entirely fabricated data ("Priya Raman · Chess Lite · 1v1 ·
expires in 4:12") with a Decline button that had no handler at all, and clicking "Start match" once local
mock readiness said everyone was ready would navigate straight into the match room — silently inventing a
match that was never created anywhere. Module 6 replaces all of it with a real, persisted lobby/invite/
credential/matchmaking domain, while refusing to paper over the one real gap that remains: there is no match
runtime yet, so Start honestly says so instead of pretending.

## Architecture Overview

```
Browser
  ├── Topbar / Dashboard / Library → CreateLobbyModal → POST /api/lobbies
  ├── /lobby/{lobbyId}              → LobbyPage (seats, ready, settings, invites, credential)
  ├── /search (Public Lobbies tab)  → SearchResultsPage (GET /api/lobbies discovery)
  ├── /dashboard                    → active-lobby card + PendingInvitesCard
  ├── /games/{slug}                 → GameDetailPage (quick-match / create-lobby / invite-friend actions)
  ├── /profile/{username}           → ProfilePage (Invite to lobby, eligible friends only)
  └── QuickMatchModal               → POST /api/matchmaking/tickets, 2s poll GET .../tickets/{id}

lobbyApi.ts / matchmakingApi.ts ──→ apiFetch<T>() ──→ /api/lobbies/* , /api/matchmaking/*
                                                              │
                                          LobbiesController / MatchmakingController
                                            ([Authorize] + CSRF on every mutation)
                                                              │
                                            LobbiesService / MatchmakingService
                        (BoundedTransactionRetry-wrapped commands: capacity, block, revision,
                         capability, one-active-lobby-or-ticket, host authorization)
                                                              │
                                LobbyRepository / MatchmakingRepository ──→ PostgreSQL
                    (lobbies, lobby_members, lobby_invites, lobby_join_credentials,
                     lobby_start_requests, matchmaking_tickets, matchmaking_assignments,
                     game_capability_profiles)
                                                              │
                              OutboxDispatcher (first in the codebase) ──→ LobbyBlockHandler
                                        (reacts to M3's UserBlockedV1)
                                                              │
                    MatchingWorker (FOR UPDATE SKIP LOCKED claim) ──→ IMatchRuntimeProbe (M8, not
                    ExpiryWorker (lobby/ticket/credential sweep)       yet registered — dormant)
```

## Backend Flow

`LobbiesController` exposes 17 endpoints under `/api/lobbies` (create, get, discover, join, leave, ready,
settings, invite, revoke-invite, accept-invite, decline-invite, kick, credential-rotate, start,
my-invites, my-active, rematch) and `MatchmakingController` exposes 3 under `/api/matchmaking` (enqueue,
status, cancel) — 20 endpoints in total. Every route is `[Authorize]`-gated with the actor always derived
from the JWT `sub` claim; every mutation additionally requires the shared CSRF header. `LobbiesService` and
`MatchmakingService` own the domain commands, each wrapped in the new `BoundedTransactionRunner`
(`ILobbyCommandRunner`/`LobbyCommandRunner`): unlike the pre-existing `PostgresRetry.SaveChangesAsync`
(which retries only the save call, only on `40001`/`40P01`, and deliberately excludes `23505`), this reruns
the **entire** read-decide-write delegate on `23505`/`40001`/`40P01` with a bounded budget, then surfaces a
typed conflict — never a raw 500. This matters concretely for the last-seat join: losing the capacity race
must re-read the lobby to discover it is now full and return `Lobbies.Full`, not replay a decision made
against stale state. `LobbyRepository` enforces the domain's cross-cutting invariants through seven partial
unique indexes rather than application-level checks alone — one nonterminal `LobbyMember` per user across
all lobbies, one nonterminal `MatchmakingTicket` per user, one active `MatchmakingAssignment` per ticket, a
unique active join-code digest, one open start-request per lobby revision, and a public-discovery keyset
index scoped to `Open`+`Public` rows. The one-active-lobby-**or**-ticket rule is a genuinely cross-table
invariant — two filtered unique indexes on different tables cannot see each other — so it is additionally
enforced by a `pg_advisory_xact_lock` keyed per user inside the same transaction that performs the insert,
and re-checked at join, enqueue, assignment, and start rather than only once up front.

Matchmaking runs on a `MatchingWorker` `BackgroundService` that claims a bounded batch of candidate tickets
with `SELECT ... FOR UPDATE SKIP LOCKED` — the codebase's first use of that clause — so two workers never
block on or double-claim the same row, then commits a non-overlapping `MatchmakingAssignment` plus one
`MatchRequestedV1` outbox event in the same transaction. Because the row lock is transaction-scoped, a
worker crash mid-claim rolls back automatically and the ticket returns to `Queued`. `SKIP LOCKED` prevents
two workers from *contending* on one row, but it is not exclusivity by itself — a requeued ticket or a
serialization retry could still attempt a second assignment, so the actual correctness boundary is the
partial unique index on active assignment (`UNIQUE (TicketId) WHERE State = 'Active'`), verified by a
two-worker real-Postgres test asserting zero duplicates. The candidate-selection algorithm anchors on the
oldest queued ticket, restricts to groups whose rating range fits *every* member's current band (not just
the anchor's), and breaks ties by smallest rating range, then lowest summed distance from the anchor, then
earliest creation time, then lowest ticket id — the monotonic band widening (±100 → ±200 → ±400 at the
15s/30s/60s ticket-age boundaries) plus always-anchor-oldest is what prevents starvation; the 60-second
absolute deadline is the bound on worst-case wait, with expiry (not silent starvation) as the terminal
outcome. `GameCapabilityProfile`, a new additive table keyed by `(GameSlug, CapabilityVersion)`, is the
answer to a real capability gap: Module 4's `Game` has no time-control, tie-break, spectator-policy, or
`rated` concept — only slug, min/max players, and a mode string list. A lobby/ticket pins a
`(GameSlug, CapabilityVersion)` at creation; every mutating command re-validates that pin against both M4's
`Game` (must exist, `Lifecycle == Available`, non-contradictory bounds) and M5's
`IGameRegistry.TryResolve(slug, engineVersion)`, failing closed with `Lobbies.CapabilityDisabled` before
persistence if either has drifted. Join credentials (manual code and link token) are generated with ≥60 and
128 bits of entropy respectively, stored only as HMAC-SHA256 keyed digests, compared in constant time, and
revealed in plaintext only in the create/rotate response — a wrong code, an expired code, a rotated code,
and a closed lobby's code are all deliberately indistinguishable, returning the same `Lobbies.CredentialInvalid`.

Module 6 also builds the codebase's first outbox **dispatcher** (`OutboxProcessor`/`IOutboxHandler`), since
the existing `OutboxMessage`/`OutboxDelivery` infrastructure was producer-only before this module — M3 emits
`UserBlockedV1` but nothing ever consumed it. `LobbyBlockHandler` reacts to a new block inside an open
lobby: a non-host blocker leaves automatically, a host blocker removes the blocked member, both idempotent
and asynchronous per the brief. `TimeProvider` is introduced via DI, scoped strictly to Module 6-owned code
— the 66 pre-existing raw `DateTime.UtcNow` call sites across 27 files are left untouched, since fake-clock
coverage of the 15/30/60-second bands and the 2-hour/30-minute expiries is only provable with injected time,
and a half-done cross-cutting refactor was judged worse than a scoped one.

## Frontend Flow

- **Existing UI reused:** the existing `/lobby/[lobbyId]` route, the composed `/search` shell, dashboard
  cards, profile action buttons, game-detail entry-action rows, and the `Modal`/`Button` primitives — wired
  to real data, not redesigned.
- **Frontend integration points:** `features/lobby/{types.ts, lobbyApi.ts, lobbyErrors.ts}` (new),
  `features/matchmaking/{types.ts, matchmakingApi.ts, matchmakingErrors.ts}` (new),
  `components/lobby/CreateLobbyModal.tsx`, `components/lobby/QuickMatchModal.tsx` (new), `components/
  friends/InviteFriendModal.tsx`, `features/lobby/LobbyPage.tsx`, `features/dashboard/DashboardPage.tsx`,
  `features/games/GameDetailPage.tsx`, `features/search/SearchResultsPage.tsx`, `features/profile/
  ProfilePage.tsx`, `features/landing/LandingPage.tsx`.
- **Mocks/placeholders replaced with real, honest behavior this module:**
  - `CreateLobbyModal`'s hardcoded `router.push(ROUTES.lobby('SP-7F-29'))` at all three mount points
    (Topbar, Dashboard, Library) → a real `POST /api/lobbies` call and navigation to the real returned id.
  - The modal's fake `simple.gg/j/SP-7F-29` link and fabricated "Auto-expires 30m" chip → a real link token
    with a real 30-minute expiry from `LobbyCredentialDto`.
  - `LobbyPage.tsx`'s local `useState` seat array and in-memory "Toggle ready" → real members and readiness
    from `GET /api/lobbies/{id}` and `PUT .../ready`.
  - `LobbyPage.tsx`'s `SettingDropdown`s (time control, privacy, rated, region, tie-break, spectators),
    previously local state that was never persisted → real `PATCH .../settings`, capability-validated.
  - The invite panel's filtering of a mock `FRIENDS` import and a toast-only "Invite sent" → real friends
    via `friendsApi.getFriends`, real `POST .../invites`.
  - **Removed, not preserved:** `LobbyPage.tsx:104`'s `router.push(ROUTES.room(lobbyId))` once local mock
    readiness said everyone was ready — this invented a room that was never created anywhere. Replaced with
    an honestly disabled Start control naming Module 8 (**R5**, required reconciliation of a misleading
    mock, not a redesign).
  - `DashboardPage.tsx`'s Quick Match button, previously `router.push(ROUTES.games)` (navigated to the
    library and started no matchmaking at all) → opens the new `QuickMatchModal`, which creates a real
    ticket.
  - `DashboardPage.tsx`'s "Open active lobby" link, previously a hardcoded `ROUTES.lobby('SP-7F-29')` with
    no existence check → real `GET /api/lobbies/me/active`, hidden entirely when the caller has none.
  - `DashboardPage.tsx`'s `PendingInvitesCard`, previously **entirely fabricated** data with a
    Decline button that had no handler → real `GET /api/lobbies/me/invites` plus working accept/decline.
  - `InviteFriendModal.tsx`'s `send()`, previously toast-only with no API call → real `POST .../invites`;
    its friend-search half was already real (`friendsApi`, debounced, cursor-paginated) and is reused as-is.
  - `InviteFriendModal.tsx`'s hardcoded `https://simple.gg/j/SP-7F-29` copy-link → a real link token.
  - `SearchResultsPage.tsx`'s Public Lobbies tab, previously an `EmptyState "Available in Module 6"` → real
    bounded, authorized discovery via `GET /api/lobbies` plus a `See all` link; private/expired/full/blocked
    lobbies never appear and never affect totals or cursors.
  - `GameDetailPage.tsx`'s `DisabledActionRow`, used **unconditionally** before this module (no
    `status === 'enabled'` branch existed anywhere in the codebase) → a real enabled branch wired for
    `quick-match`, `create-lobby`, and `invite-friend`.
  - `ProfilePage.tsx:675`'s `<Button disabled>Invite (Module 6)</Button>` → enabled only for an eligible
    friend with an open host-owned lobby; absent (not just disabled) for self, non-friends, and blocked
    users, so it cannot reveal a private lobby to an ineligible target.
  - `LandingPage.tsx:92`'s "Cross-region matchmaking." marketing claim, which had no backing implementation
    → honest same-region language, pre-approved by the brief as a content correction, not a redesign.
  - `LobbyPage.tsx`'s `aiFill` toggle → wired to persist `aiFillRequested` on the lobby, but still cannot
    create an AI participant; ranked start is disabled when AI fill is requested.
  - `mock/lobbies.ts`'s unused `DEFAULT_LOBBY_SLOTS` and the local mock `LobbyPrivacy`/`SlotKind`/
    `LobbySlot` types in `types/index.ts` were deleted, replaced by real DTOs in `features/lobby/types.ts`.
- **Known, accepted limitations carried forward (not defects):** lobby chat (`LobbyPage.tsx`'s
  `DEFAULT_LOBBY_CHAT` import from `mock/lobbies.ts`) is left mocked and rendered as an honestly disabled
  panel naming Module 7 — it is not this module's to build. `GameRoomPage.tsx` is entirely untouched,
  owned by Module 8. The Quick Match modal's 2-second ticket-status poll is a genuinely new pattern in this
  codebase (the only prior `setInterval` was a client-side countdown in `GameRoomPage`); it composes the
  established cancelled-flag `useEffect` cleanup pattern with an interval cleared on unmount and on terminal
  ticket state.
- **Visual changes made:** none beyond the one new approved surface (the Quick Match queue-status modal,
  built from existing `Modal`/`Button` primitives) and the honest-disabled-state text for Start/chat/AI
  fill; no existing visual design was altered.

## Database/Domain Model Changes

- **Existing database impact:** additive only. Eight new tables: `lobbies`, `lobby_members`,
  `lobby_invites`, `lobby_join_credentials`, `lobby_start_requests`, `matchmaking_tickets`,
  `matchmaking_assignments`, `game_capability_profiles`. `game_capability_profiles` carries a foreign key to
  Module 4's `games.slug`, which required adding a new alternate key `AK_games_Slug` to that table — the
  only change to a pre-existing table, and it is additive (a new unique constraint on an already-unique
  column), not a data or shape change.
- **Migration added:** yes — one additive migration, `20260711195731_AddLobbyMatchmakingAndCapabilities`
  (`CreateTable`/`CreateIndex` for all eight tables, plus raw `Sql` for the seven partial unique indexes EF
  cannot express through its fluent filter API).
- **Migration safety notes:** forward-only and additive; `Down()` drops only what `Up()` added. Verified on
  real PostgreSQL, including every CHECK/UNIQUE/FK/partial-index behavior. A CHECK constraint
  (`ck_matchmaking_tickets_no_worker_while_queued`) was rewritten once during backend development after an
  integration test caught an over-restrictive first version — see `testing-report.md`.
- **Data preservation notes:** no Module 1-5 data altered; Module 3's and Module 4's tables are untouched
  except the additive `AK_games_Slug` key.
- **Destructive DB changes:** none.

## API Contract

- **Backend/API/Swagger alignment:** all 20 endpoints carry `[SwaggerOperation]` + `[ProducesResponseType]`;
  documented in full in `api-reference.md`.
- **Frontend/API integration alignment:** `check-contract-drift.mjs` reports **DRIFT = 0** (85 backend
  routes, 71 unique frontend calls after Module 6's additions, 5 unresolved dynamic paths — the same
  pre-existing regex-heuristic limitation already accepted for Modules 3 and 4, manually verified).

## Validation And Error Handling

Every mutating command accepts an idempotency key and an expected revision; a stale revision returns
`Lobbies.StaleRevision` with the current state rather than a 500 or a silently-applied stale write. A wrong,
expired, rotated, or closed-lobby credential all collapse to the identical `Lobbies.CredentialInvalid`, with
failed attempts throttled specifically to blunt code-guessing. Capacity, block, and
one-active-lobby-or-ticket checks all run **inside** the same transaction as the insert they gate — an
application-level pre-check alone would lose the race under concurrent load. `Start` and Quick Match's
worker execution both fail closed with `Lobbies.MatchRuntimeUnavailable` / `Matchmaking.RuntimeUnavailable`
(503) while no M8 consumer is registered, rather than either silently succeeding or crashing. See
`api-reference.md`'s Error Format table for the full 19-code catalogue.

## Authorization And Security Decisions

Every route requires a session; the actor is always the JWT `sub`, and every concrete action is authorized
against the target object's current membership/host role on every request, never a cached prior result. A
lobby, ticket, or invite id belonging to another user returns the identical privacy-safe not-found as a
truly missing id (BOLA/OWASP API1:2023) — confirmed by direct code read of both controllers during the
`--security=asvs-lite` review, not merely asserted. Public discovery is server-side filtered per caller
(blocks, privacy, state) before pagination, so a private or blocked-for-the-caller lobby can never leak
through a count or a cursor. The one-active-lobby-or-ticket and one-active-assignment-per-ticket invariants
are enforced by partial unique indexes plus, for the cross-table case, a `pg_advisory_xact_lock` — not by
application checks alone, which the module's own risk register identifies as insufficient under
concurrency. The `--security=asvs-lite` review
(`SimPle.Project/docs/security/audits/module-06-lobby-matchmaking-system.md`) covered both the backend phase
and a post-frontend phase and found **zero unwaived Critical/High/Medium findings** in either. One Low
finding is open per phase (M06-001: the join-failure throttle is per-instance in-memory, not shared across
horizontally scaled instances; M06-005: the join credential persists in browser `sessionStorage` and is not
cleared on leave/kick/close, bounded by same-origin storage and no XSS sink existing in the reviewed diff)
plus five Info findings, all recorded and deferred — see that document for full detail.

**Deviation R1 (error-code casing):** the brief specifies lowercase snake-case codes; the codebase's
established convention is PascalCase dot-namespaced (`Games.NotFound`, `Friends.RequestCooldown`). Module 6
follows house style — `Lobbies.*`/`Matchmaking.*` — documented before implementation, not discovered as an
inconsistency afterward.

**Deviation R7 (Start's check order):** the brief lists the M5 engine check before the M8 runtime check, but
taken literally that would make Start blame *this lobby's* configuration (`Lobbies.CapabilityDisabled`) for
what is actually a platform-wide absence of any match runtime, since zero product engines are registered
yet. Start checks M8's readiness probe first, so the honest, already-normative `Lobbies.MatchRuntimeUnavailable`
is what a caller sees today — pinned by a dedicated test
(`Start_WithNoEnginesInstalled_BlamesTheMissingRuntime_NotTheLobbysCapability`).

## Realtime/Socket.IO Flow If Applicable

Not applicable — Module 6 has no real-time surface. Lobby state changes are polled by page revisit/refresh;
Quick Match ticket status is polled every 2 seconds by the frontend, with the interval cleared on unmount
and on any terminal ticket state. Live delivery (SignalR) is explicitly Module 7's scope.

## State Management If Applicable

No new shared/global context. `LobbyPage.tsx` fetches and mutates its own lobby state per visit;
`QuickMatchModal.tsx` owns its own poll and ticket state locally, torn down on close or terminal state; the
dashboard's active-lobby card and pending-invites card each fetch independently rather than sharing a store,
consistent with Module 4's precedent that a stale cross-page cache would be a worse bug than one extra
request.

## Edge Cases Handled

- **Concurrent last-seat join:** the loser of the capacity race re-reads inside the whole-command retry and
  returns `Lobbies.Full`, not a stale success or a 500.
- **Credential oracle prevention:** wrong, expired, rotated, and closed-lobby codes are indistinguishable;
  failed attempts are throttled specifically.
- **Two-worker double-claim:** `FOR UPDATE SKIP LOCKED` prevents contention; the partial unique index on
  active assignment is the actual correctness boundary, proven by a real-Postgres two-worker test asserting
  zero duplicates.
- **Cross-table one-active-lobby-or-ticket:** re-checked at join, enqueue, assignment, and start (not just
  once), backed by a `pg_advisory_xact_lock` since two separate partial unique indexes cannot see each
  other.
- **Host leave:** deterministic transfer to the longest-tenured eligible joined human, user-id tie-break,
  lobby closes when none remain; the host cannot kick self or mutate a started lobby.
- **New block inside an open lobby:** the outbox `LobbyBlockHandler` removes/departs the blocked party
  asynchronously and idempotently, without requiring either party to be online.
- **Capability drift after lobby creation:** if the pinned `(gameSlug, capabilityVersion)` becomes inactive
  or M4/M5 drifts, the next mutating command fails closed with `Lobbies.CapabilityDisabled` before
  persistence, rather than allowing a now-invalid lobby to proceed.
- **Start with no match runtime:** honestly returns `Lobbies.MatchRuntimeUnavailable`, keeps the lobby
  `Open`, and never invents a room — enforced by a dedicated test, not just documentation.
- **Quick Match anti-starvation:** the oldest ticket always anchors the proposal search and its band only
  grows, so no ticket is indefinitely skipped in favor of easier newer matches; the 60-second deadline bounds
  worst-case wait with expiry as the terminal outcome.
- **Late cancel:** cancelling a ticket after a worker has already claimed it is not an error — it returns
  the ticket's current post-claim status (200).

## Design Tradeoffs

A new `game_capability_profiles` table (D2) was chosen over extending Module 4's `games` schema in place or
reusing `Game.LifecycleVersion` as a stand-in capability pin — it costs one additional additive table and
seeder, but keeps Module 4 owning what a game *is* while Module 6 owns what a lobby may *configure*, so a
future Module 9/10 capability extension does not have to touch Module 4's catalog. `BoundedTransactionRetry`
(R3) was added as new command-level infrastructure rather than extending `PostgresRetry` in place, since
`PostgresRetry.SaveChangesAsync` retries only the save call and existing callers rely on that narrower
behavior (`FriendRepository`/`GameRepository` catch `23505` locally as a meaningful domain outcome) —
changing its scope would have altered behavior those callers depend on. `TimeProvider` (R4) was scoped to
Module 6-owned code only rather than refactoring all 66 pre-existing `DateTime.UtcNow` call sites, since that
cross-cutting change has no mandate here and a half-finished refactor would be worse than a consistently
scoped one. Module 6 builds the codebase's first outbox dispatcher (D3) rather than deferring block-reaction
to a later module, since the brief requires idempotent reaction to `UserBlockedV1` inside an open lobby and
no consumer infrastructure existed to build it on top of — this gives Module 7/8/11 reusable dispatcher
machinery as a side effect, not the primary goal.

## Files Changed And Why

**Backend** (`backend.json`, ~95 files): `LobbiesController.cs`, `MatchmakingController.cs` (new);
`LobbiesService.cs`/`ILobbiesService.cs`, `MatchmakingService.cs`/`IMatchmakingService.cs` (new); domain
entities `Lobby.cs` (replacing the deleted orphaned stub — **R2**), `LobbyMember.cs`, `LobbyInvite.cs`,
`LobbyJoinCredential.cs`, `LobbyStartRequest.cs`, `MatchmakingTicket.cs`, `MatchmakingAssignment.cs`,
`GameCapabilityProfile.cs` (new); `LobbyDtos.cs`, `LobbyRequests.cs`, matchmaking DTOs (new);
`LobbyRepository.cs`/`ILobbyRepository.cs`, `MatchmakingRepository.cs` (new); `OutboxProcessor.cs`,
`IOutboxHandler.cs`, `LobbyBlockHandler.cs` (new, first dispatcher — **D3**); `BoundedTransactionRunner.cs`/
`ILobbyCommandRunner.cs` (new — **R3**); `MatchingWorker.cs`, `ExpiryWorker.cs` (new background services);
`IMatchRuntimeProbe.cs` (new, M8 readiness gate); EF configurations for all eight new tables plus the
`AK_games_Slug` addition to `Game`'s configuration; migration
`20260711195731_AddLobbyMatchmakingAndCapabilities`; `Program.cs` (DI registration, `TimeProvider`, new CLI
`--publish-game <slug>` flag added at verification for E2E seeding).

**Frontend** (`frontend.json`): `features/lobby/{types.ts, lobbyApi.ts, lobbyErrors.ts}`,
`features/matchmaking/{types.ts, matchmakingApi.ts, matchmakingErrors.ts}` (new); `CreateLobbyModal.tsx`,
`QuickMatchModal.tsx` (new), `InviteFriendModal.tsx`, `LobbyPage.tsx`, `DashboardPage.tsx`,
`GameDetailPage.tsx`, `SearchResultsPage.tsx`, `ProfilePage.tsx`, `LandingPage.tsx` (wired); `routes.ts`
(search type union widened to include `'lobbies'`); `mock/lobbies.ts` (dead `DEFAULT_LOBBY_SLOTS` removed,
`DEFAULT_LOBBY_CHAT` kept-deferred for Module 7); `types/index.ts` (mock lobby types removed);
`tests/e2e/module-06-lobby-matchmaking.spec.ts` (written this module, executed at verification).

**Fixed during live E2E verification** (`verification.json`): a game lifecycle-gating bug in the entry
actions' `gatingReason()` (was not checking `game.lifecycle === 'Available'`, fixed alongside adding the
`--publish-game` CLI flag needed to seed an `Available` game for the E2E run); two `.page-title` div→`<h1>`
accessibility fixes in `SearchResultsPage.tsx` and `DashboardPage.tsx` (continuing the sweep Module 4's
accessibility pass started but did not finish across all pages); the rest of the fixes made during
verification were confined to the E2E spec file itself (locator collisions, ready-up/reveal-code assumption
corrections) — see `testing-report.md`.

## How To Read The Implementation

Start at `features/lobby/lobbyApi.ts`/`types.ts` and `features/matchmaking/matchmakingApi.ts`/`types.ts`
(the contract), then `LobbyPage.tsx` and `QuickMatchModal.tsx` (the two main surfaces). On the backend,
start at `LobbiesController.cs`/`MatchmakingController.cs`, then `LobbiesService.cs` for the command/
capability-validation logic, then `LobbyRepository.cs` for the partial-unique-index query shapes, then
`MatchingWorker.cs` for the `FOR UPDATE SKIP LOCKED` claim loop and the band/tie-break algorithm, and finally
`OutboxProcessor.cs`/`LobbyBlockHandler.cs` for the dispatcher pattern.

## Future Improvements / Deferred Items

| Feature | Deferred to | Current state |
|---------|------------|---------------|
| Live match creation, the playable room, navigation into it | Module 8 | `Start` returns `Lobbies.MatchRuntimeUnavailable`; Quick Match execution returns `Matchmaking.RuntimeUnavailable`. **Blocking handoff item — only the post-M8 integration test may close it.** |
| Lobby and match chat | Module 7 | Rendered honestly disabled, names Module 7 |
| Live lobby/ticket updates without polling | Module 7 | 2-second poll; no push/SignalR yet |
| AI-filled seats | Module 9 | `aiFillRequested` stored and displayed; ranked start disabled when set; no AI participant is created |
| Real per-game rating | Module 10 | Every ticket records provisional `1200` / `provisional-1200-v1`; legacy `User.Elo` never substituted |
| Notifications for invite/lobby events | Module 11 | Not wired; the dashboard invites card is a direct query, not a notification |
| Registry Phase 2 slug conflict (carried from Module 4) | Open, awaiting user | `GameCapabilityProfile.GameSlug` is a second dependent on the unresolved `tetris-arena`/`falling-blocks-arena`-style naming decision |
| `run-module-e2e.mjs` Windows `spawnSync` invocation bug | Unowned, pre-existing | Worked around by invoking `npm run test:e2e -- <spec>` directly at verification |
| Sidebar's hardcoded placeholder "SP-7F-29" active-lobby link | Real pre-existing product defect, unowned by this module's scope | Found during verification; recorded, not fixed in this pass |
| Remaining `.page-title` div→`<h1>` accessibility sweep | Follow-up, unowned | Two of the remaining pages were fixed this module (`SearchResultsPage.tsx`, `DashboardPage.tsx`); others from Module 4's incomplete sweep remain |
| Production review and final evidence sign-off | `/simple production-review module=6` | This docs stage is in progress; production-review and final evidence remain |

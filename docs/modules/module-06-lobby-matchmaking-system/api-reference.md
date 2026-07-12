# API Reference - Module 06: Lobby & Matchmaking System

## Overview
- Existing UI reused: `Modal`/`Button` primitives, the existing `/lobby/[lobbyId]` route, the composed
  `/search` shell, dashboard cards, profile action buttons, and game-detail entry-action rows — wired to
  real data, not redesigned. One new approved surface: a Quick Match queue-status modal built from the
  existing `Modal` (focus trap + restore-on-close already present).
- Frontend integration points: `features/lobby/{types.ts, lobbyApi.ts, lobbyErrors.ts}`,
  `features/matchmaking/{types.ts, matchmakingApi.ts, matchmakingErrors.ts}`, `components/lobby/
  CreateLobbyModal.tsx`, `components/lobby/QuickMatchModal.tsx`, `components/friends/InviteFriendModal.tsx`,
  `features/lobby/LobbyPage.tsx`, `features/dashboard/DashboardPage.tsx`, `features/games/
  GameDetailPage.tsx`, `features/search/SearchResultsPage.tsx` (Public Lobbies tab), `features/profile/
  ProfilePage.tsx` (Invite action), `features/landing/LandingPage.tsx` (same-region copy correction).
- Existing database impact: additive only. Eight new tables: `lobbies`, `lobby_members`, `lobby_invites`,
  `lobby_join_credentials`, `lobby_start_requests`, `matchmaking_tickets`, `matchmaking_assignments`, and
  `game_capability_profiles`. No existing Module 1-5 table is altered or dropped; `game_capability_profiles`
  has a foreign key to Module 4's `games.slug` via a new alternate key (`AK_games_Slug`), read-only from
  Module 6's side.

## Base Route / Route Group
`/api/lobbies` and `/api/matchmaking`, source of truth `SimPLe.Backend/src/SimPle.Api/Controllers/
LobbiesController.cs` and `MatchmakingController.cs`. Authentication is cookie-based (`credentials:
'include'`); every route requires a signed-in session (`[Authorize]`, actor derived from the JWT `sub`
claim only — never from a request body or route id). Every state-changing endpoint additionally requires the
shared `X-Requested-With: XMLHttpRequest` CSRF header (missing → 400 `Auth.CsrfHeaderRequired`).

## Authentication And Authorization Requirements
Every route in both controllers is `[Authorize]`-gated; there is no anonymous read in Module 6 (unlike
Module 4's catalog). Ownership and host authorization are re-checked **on every request** against the
target lobby/ticket/invite's current state — never cached from a prior step. A lobby, ticket, or invite id
that exists but is not visible to the caller (another user's private lobby, another user's ticket, another
user's invite) returns the identical privacy-safe `Lobbies.NotFound` / `Matchmaking.TicketNotFound` as a
truly missing id — never a 403, which would confirm existence (OWASP API1:2023 BOLA). Host-only actions
(settings, invite, revoke, kick, credential rotate, start) return `Lobbies.Forbidden` for a joined non-host
member, distinct from the not-found case, since membership itself is already established at that point.

## Endpoint Summary Table

| # | Method | Path | Purpose | Auth | Notes |
|---|--------|------|---------|------|-------|
| 1 | POST | `/api/lobbies` | Create a lobby | Required + CSRF | Capability-validated against pinned `(gameSlug, capabilityVersion)` |
| 2 | GET | `/api/lobbies/{lobbyId}` | Get a lobby (member/authorized viewer) | Required | Privacy-safe 404 for foreign/private ids |
| 3 | GET | `/api/lobbies` | Public discovery, keyset on `(createdAt,id)` | Required | Only `Open`+`Public`+not-full+not-blocked results |
| 4 | POST | `/api/lobbies/join` | Join by credential (code or link token in body) | Required + CSRF | Credential in body, never the path |
| 5 | POST | `/api/lobbies/{lobbyId}/leave` | Leave a lobby | Required + CSRF | Triggers deterministic host transfer if host leaves |
| 6 | PUT | `/api/lobbies/{lobbyId}/ready` | Set own readiness | Required + CSRF | Host is implicitly ready, cannot toggle |
| 7 | PATCH | `/api/lobbies/{lobbyId}/settings` | Host: change settings | Required + CSRF | Resets readiness for all joined non-host humans |
| 8 | POST | `/api/lobbies/{lobbyId}/invites` | Host: invite a friend | Required + CSRF | M3 friendship required |
| 9 | DELETE | `/api/lobbies/{lobbyId}/invites/{inviteId}` | Host: revoke an invite | Required + CSRF | Immediate; a revoked invite cannot later be accepted |
| 10 | POST | `/api/lobbies/invites/{inviteId}/accept` | Invitee: accept | Required + CSRF | Runs the same bounded transaction as a credential join (R6) |
| 11 | POST | `/api/lobbies/invites/{inviteId}/decline` | Invitee: decline | Required + CSRF | — |
| 12 | POST | `/api/lobbies/{lobbyId}/kick` | Host: kick a member | Required + CSRF | Resets readiness for remaining members |
| 13 | POST | `/api/lobbies/{lobbyId}/credential/rotate` | Host: rotate join code + link | Required + CSRF | Old value invalidated immediately (`Generation` bump) |
| 14 | POST | `/api/lobbies/{lobbyId}/start` | Host: start the match | Required + CSRF | Returns `Lobbies.MatchRuntimeUnavailable` until M8 registers |
| 15 | GET | `/api/lobbies/me/invites` | My pending invites | Required | Backs the dashboard invites card and its badge count |
| 16 | GET | `/api/lobbies/me/active` | My active lobby or ticket | Required | Backs the dashboard "active lobby" card |
| 17 | POST | `/api/matches/{terminalMatchId}/rematch-lobbies` | Create a rematch lobby | Required + CSRF | New private lobby; nobody auto-joined or auto-ready |
| 18 | POST | `/api/matchmaking/tickets` | Enqueue a Quick Match ticket | Required + CSRF | One-active-lobby-or-ticket enforced |
| 19 | GET | `/api/matchmaking/tickets/{ticketId}` | Ticket status | Required | Polled every 2s by the frontend |
| 20 | DELETE | `/api/matchmaking/tickets/{ticketId}` | Cancel a ticket | Required + CSRF | Commits only while `Queued`; after claim returns current status (200, not an error) |

## Endpoints

### POST /api/lobbies
- Purpose: create a lobby with pinned game/capability settings.
- Request parameters: none (body-only).
- Request body: `gameSlug`, `capabilityVersion`, `privacy` (`Public`\|`Private`), `maxPlayers`,
  `timeControlId`, `rated`, `resolvedRegion` (or `Auto`, resolved server-side), `spectatorPolicy`
  (`Anyone`\|`FriendsOnly`\|`Disabled`), `tieBreakRuleId`, `aiFillRequested`, idempotency key.
- Validation rules: the pinned `(gameSlug, capabilityVersion)` must resolve to an active
  `GameCapabilityProfile`; `Game.Lifecycle` must be `Available` and its `MinPlayers`/`MaxPlayers`/modes must
  not contradict the profile (`Lobbies.CapabilityDisabled` otherwise, checked before persistence); `Auto`
  region resolves to the caller's allow-listed profile region, then the deployment default, and is stored as
  an explicit normalized value, never left as `Auto`; ranked start is rejected at creation if
  `aiFillRequested` is set.
- Success response: `201 LobbyDto` (revision 1, host implicitly ready, `expiresAtUtc` = now + 2h).
- Error responses: `400 Validation.Failed`, `409 Lobbies.CapabilityDisabled`, `409 Lobbies.AlreadyActive`
  (caller already has a joined lobby or queued ticket), `429 RateLimit.Exceeded`, `400
  Auth.CsrfHeaderRequired`.
- Authorization behavior: caller becomes host; no other actor can be named as host.
- Rate limiting / abuse notes: `lobby-create`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_Create")]`.
- Backend/API/Swagger alignment: verified by reading `LobbiesController.cs` directly against
  `LobbiesService.CreateAsync`.
- Frontend/API integration alignment: `lobbyApi.create()`, called from all three `CreateLobbyModal` mount
  points (Topbar, Dashboard, Library).
- Example request: `POST /api/lobbies { "gameSlug": "chess-lite", "capabilityVersion": 1, "privacy":
  "Private", "maxPlayers": 2, ... }`
- Example response: `{ "id": "<uuid>", "revision": 1, "state": "Open", "settings": {...}, "seats": [...],
  "host": {...}, "expiresAtUtc": "<ISO-8601>", "allowedActions": [...], "dependencyReadiness": {"m7": false,
  "m8": false, "m9": false} }`

### GET /api/lobbies/{lobbyId}
- Purpose: fetch a lobby the caller is authorized to view (member, or a public lobby).
- Request parameters: `lobbyId` (route).
- Request body: none.
- Validation rules: none beyond lookup.
- Success response: `200 LobbyDto`.
- Error responses: `404 Lobbies.NotFound` (missing, expired, private-and-unauthorized, or another user's
  lobby — all indistinguishable), `429 RateLimit.Exceeded`.
- Authorization behavior: member of the lobby, or any signed-in user for a `Public` lobby; a `Private`
  lobby returns the privacy-safe not-found to a non-member.
- Rate limiting / abuse notes: `lobby-read`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_Get")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.get(lobbyId)`, `LobbyPage.tsx`.
- Example request: `GET /api/lobbies/3f9a...`
- Example response: `{ "id": "3f9a...", "revision": 4, "state": "Open", "settings": {...}, "seats": [...],
  "host": {...} }`

### GET /api/lobbies
- Purpose: bounded, authorized public lobby discovery for the composed search "Public Lobbies" tab.
- Request parameters (query): `gameSlug` (optional filter), `limit` (default 24, max 50), `after` (opaque
  cursor).
- Request body: none.
- Validation rules: `limit` 1-50 (`Validation.Failed` otherwise); malformed cursor →
  `Pagination.InvalidCursor`.
- Success response: `200 CursorPage<LobbySummaryDto>` — only `Open`+`Public`+not-full+not-blocked lobbies;
  private, expired, full, and blocked-for-the-caller lobbies never appear and never affect totals or
  cursors.
- Error responses: `400 Validation.Failed`, `400 Pagination.InvalidCursor`, `429 RateLimit.Exceeded`.
- Authorization behavior: any signed-in user; per-caller M3 block filtering is applied server-side, not
  client-side.
- Rate limiting / abuse notes: `lobby-read`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_Discover")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.discover()`, `SearchResultsPage.tsx`'s Public Lobbies tab.
- Example request: `GET /api/lobbies?limit=24`
- Example response: `{ "items": [ { "id": "...", "gameSlug": "chess-lite", "seatsFilled": 1, "maxPlayers":
  2, "hostDisplayName": "...", ... } ], "nextCursor": null }`

### POST /api/lobbies/join
- Purpose: join a lobby using a manual code or link token.
- Request parameters: none (body-only).
- Request body: `code` or `linkToken` (one of), idempotency key.
- Validation rules: credential is compared as a keyed digest in constant time; a wrong code, an expired
  code, a rotated code, and a closed lobby's code all return the identical `Lobbies.CredentialInvalid` (no
  oracle); capacity, block, and one-active-lobby-or-ticket are re-checked inside the same transaction as the
  insert.
- Success response: `200 LobbyDto` with the caller now a joined member, readiness reset for all joined
  non-host humans.
- Error responses: `404 Lobbies.CredentialInvalid`, `409 Lobbies.Full`, `409 Lobbies.Closed`, `409
  Lobbies.Expired`, `403 Lobbies.Blocked`, `409 Lobbies.AlreadyActive`, `429 RateLimit.Exceeded` (join-code
  attempts throttled specifically, separate from the general `lobby-join` limit).
- Authorization behavior: any signed-in user holding a valid credential; using a credential does not extend
  the lobby's or credential's expiry.
- Rate limiting / abuse notes: `lobby-join`, plus a specific failed-attempt throttle on wrong codes.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_Join")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.joinByCredential()`.
- Example request: `POST /api/lobbies/join { "code": "4F7K-9QRT" }`
- Example response: `{ "id": "...", "revision": 5, "state": "Open", "seats": [...] }`

### POST /api/lobbies/{lobbyId}/leave
- Purpose: leave a lobby.
- Request parameters: `lobbyId` (route).
- Request body: idempotency key.
- Validation rules: a host leaving triggers deterministic transfer to the longest-tenured eligible joined
  human (user-id tie-break); the lobby closes if none remain.
- Success response: `200 LobbyDto` (or `204` if the caller's leave closed the lobby with no viewer left to
  return a body to — the frontend treats either as success).
- Error responses: `404 Lobbies.NotFound`, `409 Lobbies.Closed`, `429 RateLimit.Exceeded`.
- Authorization behavior: caller must be a joined member.
- Rate limiting / abuse notes: `lobby-write`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_Leave")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.leave()`, `LobbyPage.tsx`.
- Example request: `POST /api/lobbies/3f9a.../leave`
- Example response: `{ "id": "3f9a...", "revision": 6, "state": "Open", "host": {...} }`

### PUT /api/lobbies/{lobbyId}/ready
- Purpose: set the caller's own readiness.
- Request parameters: `lobbyId` (route).
- Request body: `isReady` (bool), expected revision, idempotency key.
- Validation rules: caller must be a joined non-host member (the host is implicitly ready and cannot toggle
  this); stale `revision` returns the current state rather than applying blind.
- Success response: `200 LobbyDto`.
- Error responses: `404 Lobbies.NotFound`, `409 Lobbies.StaleRevision`, `409 Lobbies.Closed`, `429
  RateLimit.Exceeded`.
- Authorization behavior: self only; no body/route user id is accepted.
- Rate limiting / abuse notes: `lobby-write`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_SetReady")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.setReady()`, `LobbyPage.tsx`.
- Example request: `PUT /api/lobbies/3f9a.../ready { "isReady": true, "revision": 6 }`
- Example response: `{ "id": "3f9a...", "revision": 7, "seats": [...] }`

### PATCH /api/lobbies/{lobbyId}/settings
- Purpose: host changes match settings.
- Request parameters: `lobbyId` (route).
- Request body: any subset of the creatable settings fields, expected revision, idempotency key.
- Validation rules: same capability cross-check as create; any match-affecting change resets readiness for
  all joined non-host humans.
- Success response: `200 LobbyDto`.
- Error responses: `404 Lobbies.NotFound`, `403 Lobbies.Forbidden` (non-host), `409 Lobbies.StaleRevision`,
  `409 Lobbies.CapabilityDisabled`, `409 Lobbies.Closed`, `429 RateLimit.Exceeded`.
- Authorization behavior: host only.
- Rate limiting / abuse notes: `lobby-write`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_UpdateSettings")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.updateSettings()`, `LobbyPage.tsx`'s `SettingDropdown`s.
- Example request: `PATCH /api/lobbies/3f9a.../settings { "rated": false, "revision": 7 }`
- Example response: `{ "id": "3f9a...", "revision": 8, "settings": {...} }`

### POST /api/lobbies/{lobbyId}/invites
- Purpose: host invites a friend.
- Request parameters: `lobbyId` (route).
- Request body: `inviteeUserId`, idempotency key.
- Validation rules: invitee must be an accepted M3 friend of the host and not blocked in either direction;
  invite expires in 30 minutes or when the lobby closes/starts.
- Success response: `201 LobbyInviteDto`.
- Error responses: `404 Lobbies.NotFound`, `403 Lobbies.Forbidden` (non-host), `403 Lobbies.Blocked`, `409
  Lobbies.Closed`, `429 RateLimit.Exceeded`.
- Authorization behavior: host only.
- Rate limiting / abuse notes: `lobby-invite`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_Invite")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.invite()`, `LobbyPage.tsx`'s invite panel,
  `InviteFriendModal.tsx`, `ProfilePage.tsx`'s Invite action.
- Example request: `POST /api/lobbies/3f9a.../invites { "inviteeUserId": "..." }`
- Example response: `{ "id": "<inviteId>", "lobbyId": "3f9a...", "state": "Pending", "expiresAtUtc":
  "<ISO-8601>" }`

### DELETE /api/lobbies/{lobbyId}/invites/{inviteId}
- Purpose: host revokes a pending invite.
- Request parameters: `lobbyId`, `inviteId` (route).
- Request body: none.
- Validation rules: revocation is immediate; a revoked invite cannot later be accepted
  (`RevokedInvite_CannotBeAccepted`).
- Success response: `204 No Content`.
- Error responses: `404 Lobbies.NotFound`, `403 Lobbies.Forbidden` (non-host), `429 RateLimit.Exceeded`.
- Authorization behavior: host only.
- Rate limiting / abuse notes: `lobby-write`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_RevokeInvite")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.revokeInvite()`.
- Example request: `DELETE /api/lobbies/3f9a.../invites/7c2b...`
- Example response: `204` empty body.

### POST /api/lobbies/invites/{inviteId}/accept
- Purpose: invitee accepts a pending invite and joins.
- Request parameters: `inviteId` (route).
- Request body: idempotency key.
- Validation rules: runs the same bounded transaction as a credential join — block re-check,
  one-active-lobby-or-ticket, capacity, readiness reset (**R6**, added during backend slice 6B: this route
  did not appear in the original spec draft's route table).
- Success response: `200 LobbyDto`.
- Error responses: `404 Lobbies.NotFound` (own or foreign invite id that is missing/revoked/expired — all
  privacy-safe not-found, per R6), `409 Lobbies.Full`, `409 Lobbies.Closed`, `403 Lobbies.Blocked`, `409
  Lobbies.AlreadyActive`, `429 RateLimit.Exceeded`.
- Authorization behavior: invitee only; another user's invite id is indistinguishable from a missing one.
- Rate limiting / abuse notes: `lobby-write`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_AcceptInvite")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.acceptInvite()`, `DashboardPage.tsx`'s
  `PendingInvitesCard`.
- Example request: `POST /api/lobbies/invites/7c2b.../accept`
- Example response: `{ "id": "3f9a...", "revision": 9, "seats": [...] }`

### POST /api/lobbies/invites/{inviteId}/decline
- Purpose: invitee declines a pending invite.
- Request parameters: `inviteId` (route).
- Request body: idempotency key.
- Validation rules: none beyond ownership and pending state.
- Success response: `204 No Content`.
- Error responses: `404 Lobbies.NotFound`, `429 RateLimit.Exceeded`.
- Authorization behavior: invitee only.
- Rate limiting / abuse notes: `lobby-write`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_DeclineInvite")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.declineInvite()`, `DashboardPage.tsx`'s
  `PendingInvitesCard`.
- Example request: `POST /api/lobbies/invites/7c2b.../decline`
- Example response: `204` empty body.

### POST /api/lobbies/{lobbyId}/kick
- Purpose: host removes a member.
- Request parameters: `lobbyId` (route).
- Request body: `memberUserId`, idempotency key.
- Validation rules: host cannot kick self; resets readiness for remaining joined non-host humans.
- Success response: `200 LobbyDto`.
- Error responses: `404 Lobbies.NotFound`, `403 Lobbies.Forbidden` (non-host or self-target), `409
  Lobbies.Closed`, `429 RateLimit.Exceeded`.
- Authorization behavior: host only.
- Rate limiting / abuse notes: `lobby-write`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_Kick")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.kick()`.
- Example request: `POST /api/lobbies/3f9a.../kick { "memberUserId": "..." }`
- Example response: `{ "id": "3f9a...", "revision": 10, "seats": [...] }`

### POST /api/lobbies/{lobbyId}/credential/rotate
- Purpose: host rotates the join code and link token.
- Request parameters: `lobbyId` (route).
- Request body: idempotency key.
- Validation rules: old credential is invalidated immediately (`Generation` bump, old row → `Rotated`);
  bounded collision retry on `23505`.
- Success response: `200 LobbyCredentialDto` — the **only** response that ever carries the plaintext code
  and link token.
- Error responses: `404 Lobbies.NotFound`, `403 Lobbies.Forbidden` (non-host), `429 RateLimit.Exceeded`.
- Authorization behavior: host only.
- Rate limiting / abuse notes: `lobby-write`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_RotateCredential")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.rotateCredential()`, `CreateLobbyModal.tsx`,
  `LobbyPage.tsx`, `InviteFriendModal.tsx`'s copy-link.
- Example request: `POST /api/lobbies/3f9a.../credential/rotate`
- Example response: `{ "code": "4F7K-9QRT", "linkToken": "...", "generation": 2, "expiresAtUtc":
  "<ISO-8601>" }`

### POST /api/lobbies/{lobbyId}/start
- Purpose: host starts the match.
- Request parameters: `lobbyId` (route).
- Request body: expected revision, idempotency key.
- Validation rules: validates, in one command, current revision, M3 blocks, membership, readiness, M4
  capabilities, **M8 runtime availability (checked first, per R7)**, and M5 engine availability. Commits
  exactly one `MatchRequestedV1` outbox event in the same transaction on success. Retrying a committed start
  returns its current request/result; retrying after a recorded recoverable failure creates a new request
  id.
- Success response: `200 LobbyDto` (state `Starting`) — **only reachable once M8 registers a consumer**.
- Error responses: `404 Lobbies.NotFound`, `403 Lobbies.Forbidden` (non-host), `409 Lobbies.StaleRevision`,
  `409 Lobbies.CapabilityDisabled`, `503 Lobbies.MatchRuntimeUnavailable` (**the only reachable outcome
  today** — no M8 consumer is registered), `429 RateLimit.Exceeded`.
- Authorization behavior: host only.
- Rate limiting / abuse notes: `lobby-write`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_Start")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.start()`; `LobbyPage.tsx` renders Start as an honestly
  disabled control naming Module 8 — no navigation is performed on this call today (**R5** removed the
  prior mock's `router.push(ROUTES.room(...))`).
- Example request: `POST /api/lobbies/3f9a.../start { "revision": 10 }`
- Example response (today): `{ "error": { "code": "Lobbies.MatchRuntimeUnavailable", "message": "..." } }`

### GET /api/lobbies/me/invites
- Purpose: the caller's pending invites, for the dashboard invites card and its badge count.
- Request parameters: `limit` (default 24, max 50), `after` (opaque cursor).
- Request body: none.
- Validation rules: `limit` 1-50; malformed cursor → `Pagination.InvalidCursor`.
- Success response: `200 CursorPage<LobbyInviteDto>` — the badge count and the list are backed by the same
  bounded query; no count without its drill-down.
- Error responses: `400 Validation.Failed`, `400 Pagination.InvalidCursor`, `429 RateLimit.Exceeded`.
- Authorization behavior: caller's own invites only.
- Rate limiting / abuse notes: `lobby-read`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_MyInvites")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.getMyInvites()`, `DashboardPage.tsx`'s
  `PendingInvitesCard`.
- Example request: `GET /api/lobbies/me/invites?limit=24`
- Example response: `{ "items": [ { "id": "...", "lobbyId": "...", "inviterDisplayName": "...", "gameSlug":
  "chess-lite", "expiresAtUtc": "<ISO-8601>" } ], "nextCursor": null }`

### GET /api/lobbies/me/active
- Purpose: the caller's single active lobby or matchmaking ticket, for the dashboard's active-lobby card.
- Request parameters: none.
- Request body: none.
- Validation rules: none (no input); relies on the one-active-lobby-or-ticket invariant to guarantee at
  most one result.
- Success response: `200 ActiveParticipationDto` (`kind: 'lobby' | 'ticket' | 'none'`).
- Error responses: `429 RateLimit.Exceeded`.
- Authorization behavior: caller's own state only.
- Rate limiting / abuse notes: `lobby-read`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_MyActive")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: `lobbyApi.getMyActive()`, `DashboardPage.tsx`'s active-lobby card
  (hidden when `kind === 'none'`).
- Example request: `GET /api/lobbies/me/active`
- Example response: `{ "kind": "lobby", "lobbyId": "3f9a..." }` or `{ "kind": "none" }`

### POST /api/matches/{terminalMatchId}/rematch-lobbies
- Purpose: create a new private lobby from a prior match's pinned settings, inviting the prior human
  participants.
- Request parameters: `terminalMatchId` (route).
- Request body: idempotency key.
- Validation rules: nobody is auto-joined or auto-ready; blocks are re-checked; the old match is never
  mutated by this call.
- Success response: `201 LobbyDto` (new lobby, `Private`, host = caller).
- Error responses: `404 Lobbies.NotFound` (unknown/foreign match id), `403 Lobbies.Blocked`, `429
  RateLimit.Exceeded`.
- Authorization behavior: caller must have been a participant in the terminal match.
- Rate limiting / abuse notes: `lobby-create`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Lobbies_CreateRematch")]`.
- Backend/API/Swagger alignment: `LobbiesController.cs`.
- Frontend/API integration alignment: not yet reachable from any UI surface — Module 8 owns the terminal
  match/result screen that will call this route.
- Example request: `POST /api/matches/9d1c.../rematch-lobbies`
- Example response: `{ "id": "<newLobbyId>", "revision": 1, "state": "Open", "privacy": "Private" }`

### POST /api/matchmaking/tickets
- Purpose: enqueue for Quick Match.
- Request parameters: none (body-only).
- Request body: `gameSlug`, `capabilityVersion`, `mode`, `playerCount`, `timeControlId`, `rated`,
  `resolvedRegion` (or `Auto`), idempotency key.
- Validation rules: same capability cross-check as lobby create; one-active-lobby-or-ticket enforced; rating
  is always provisional `1200` / `provisional-1200-v1` (M10 does not exist yet — the legacy `User.Elo`
  column is never substituted); ticket carries an absolute 60-second deadline.
- Success response: `201 MatchmakingTicketDto` (state `Queued`).
- Error responses: `400 Validation.Failed`, `409 Lobbies.CapabilityDisabled`, `409
  Matchmaking.AlreadyQueued`, `429 RateLimit.Exceeded`, `400 Auth.CsrfHeaderRequired`.
- Authorization behavior: caller only; ticket is always owned by the JWT `sub`.
- Rate limiting / abuse notes: `matchmaking-enqueue`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Matchmaking_Enqueue")]`.
- Backend/API/Swagger alignment: `MatchmakingController.cs`.
- Frontend/API integration alignment: `matchmakingApi.enqueue()`, `QuickMatchModal.tsx`,
  `DashboardPage.tsx`'s Quick Match action.
- Example request: `POST /api/matchmaking/tickets { "gameSlug": "chess-lite", "capabilityVersion": 1,
  "mode": "multiplayer", "playerCount": 2, "timeControlId": "blitz-5", "rated": true }`
- Example response: `{ "id": "<ticketId>", "state": "Queued", "enqueuedAtUtc": "<ISO-8601>",
  "deadlineAtUtc": "<ISO-8601>", "band": 100 }`

### GET /api/matchmaking/tickets/{ticketId}
- Purpose: ticket status, polled every 2 seconds by the frontend until M7 supplies live delivery.
- Request parameters: `ticketId` (route).
- Request body: none.
- Validation rules: none beyond lookup.
- Success response: `200 MatchmakingTicketDto` — reflects current `state` (`Queued`\|`Claimed`\|`Matched`\|
  `Requeued`\|`Failed`\|`Cancelled`\|`TimedOut`) and current widened `band`.
- Error responses: `404 Matchmaking.TicketNotFound` (privacy-safe; another user's ticket id lands here),
  `429 RateLimit.Exceeded`.
- Authorization behavior: ticket owner only.
- Rate limiting / abuse notes: `matchmaking-status`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Matchmaking_GetStatus")]`.
- Backend/API/Swagger alignment: `MatchmakingController.cs`.
- Frontend/API integration alignment: `matchmakingApi.getStatus()`, the `QuickMatchModal.tsx` 2-second poll
  (interval cleared on unmount and on terminal state).
- Example request: `GET /api/matchmaking/tickets/8b3e...`
- Example response: `{ "id": "8b3e...", "state": "Queued", "band": 200, "enqueuedAtUtc": "<ISO-8601>",
  "deadlineAtUtc": "<ISO-8601>" }`

### DELETE /api/matchmaking/tickets/{ticketId}
- Purpose: cancel a queued ticket.
- Request parameters: `ticketId` (route).
- Request body: idempotency key.
- Validation rules: commits only while `Queued`; after a worker claim, the call does not fail — it returns
  the ticket's current status.
- Success response: `200 MatchmakingTicketDto` (either now `Cancelled`, or the current post-claim state if
  the cancel arrived too late — `Matchmaking.CancelTooLate` is a **200**, not an error).
- Error responses: `404 Matchmaking.TicketNotFound`, `429 RateLimit.Exceeded`.
- Authorization behavior: ticket owner only.
- Rate limiting / abuse notes: `matchmaking-write`.
- Swagger/OpenAPI notes: `[SwaggerOperation(OperationId = "Matchmaking_Cancel")]`.
- Backend/API/Swagger alignment: `MatchmakingController.cs`.
- Frontend/API integration alignment: `matchmakingApi.cancel()`, `QuickMatchModal.tsx`'s Cancel button.
- Example request: `DELETE /api/matchmaking/tickets/8b3e...`
- Example response: `{ "id": "8b3e...", "state": "Cancelled" }`

## Data Models / DTOs

```typescript
LobbyPrivacy = 'Public' | 'Private';
LobbyState = 'Open' | 'Starting' | 'Started' | 'Closed' | 'Expired';
SpectatorPolicy = 'Anyone' | 'FriendsOnly' | 'Disabled';
LobbyMemberState = 'Joined' | 'Left' | 'Kicked';
LobbyInviteState = 'Pending' | 'Accepted' | 'Revoked' | 'Expired';
TicketState = 'Queued' | 'Claimed' | 'Matched' | 'Requeued' | 'Failed' | 'Cancelled' | 'TimedOut';

LobbySettingsDto = {
  gameSlug: string; capabilityVersion: number; privacy: LobbyPrivacy; maxPlayers: number;
  timeControlId: string; rated: boolean; resolvedRegion: string; spectatorPolicy: SpectatorPolicy;
  tieBreakRuleId: string; aiFillRequested: boolean;
}

LobbySeatDto = {
  userId: string; username: string; displayName: string; avatarUrl: string | null;
  state: LobbyMemberState; isReady: boolean; joinedAtUtc: string; // ISO 8601
}

LobbyDto = {
  id: string; revision: number; state: LobbyState; settings: LobbySettingsDto;
  seats: LobbySeatDto[]; host: LobbySeatDto; expiresAtUtc: string;
  allowedActions: string[]; // e.g. 'leave' | 'setReady' | 'updateSettings' | 'invite' | 'start' ...
  dependencyReadiness: { m7: boolean; m8: boolean; m9: boolean };
}

LobbySummaryDto = {
  id: string; gameSlug: string; seatsFilled: number; maxPlayers: number;
  hostDisplayName: string; rated: boolean; createdAtUtc: string;
}

LobbyInviteDto = {
  id: string; lobbyId: string; inviterUserId: string; inviterDisplayName: string;
  gameSlug: string; state: LobbyInviteState; expiresAtUtc: string; respondedAtUtc: string | null;
}

// The ONLY DTO that ever carries a plaintext credential — create/rotate responses only.
LobbyCredentialDto = { code: string; linkToken: string; generation: number; expiresAtUtc: string; }

ActiveParticipationDto =
  | { kind: 'lobby'; lobbyId: string }
  | { kind: 'ticket'; ticketId: string }
  | { kind: 'none' };

MatchmakingTicketDto = {
  id: string; state: TicketState; band: 100 | 200 | 400;
  enqueuedAtUtc: string; deadlineAtUtc: string;
}

CursorPage<T> = { items: T[]; nextCursor: string | null; }
```

## Error Format
Envelope: `{ error: { code, message, retryAfterUtc? } }` (via `ApiErrorResponse`/`MapError`, the same
convention as every other controller in the app).

| Code | HTTP | Meaning |
|------|------|---------|
| `Lobbies.NotFound` | 404 | Privacy-safe. Missing, expired, private-and-unauthorized, or another user's lobby/invite — all indistinguishable. |
| `Lobbies.Full` | 409 | Capacity reached (last-seat loser of a concurrent join). |
| `Lobbies.Closed` | 409 | Terminal lobby rejects the mutation. |
| `Lobbies.Expired` | 409 | Past `expiresAtUtc`. |
| `Lobbies.Blocked` | 403 | An M3 block exists between the actor and a joined human. |
| `Lobbies.StaleRevision` | 409 | Expected revision does not match; returns current state, not a 500. |
| `Lobbies.Forbidden` | 403 | Actor is a member but not the host, for a host-only action. |
| `Lobbies.AlreadyActive` | 409 | One-active-lobby-or-ticket invariant violated. |
| `Lobbies.CapabilityDisabled` | 409 | Pinned `(gameSlug, capabilityVersion)` is stale/inactive, or M4/M5 has drifted. |
| `Lobbies.MatchRuntimeUnavailable` | 503 | M8 has not registered a consumer — Start is honestly unavailable. |
| `Lobbies.CredentialInvalid` | 404 | Deliberately indistinguishable from wrong / expired / rotated / closed. |
| `Matchmaking.TicketNotFound` | 404 | Privacy-safe; another user's ticket id lands here. |
| `Matchmaking.AlreadyQueued` | 409 | One-active-lobby-or-ticket invariant violated. |
| `Matchmaking.TicketExpired` | 409 | Past the 60s absolute deadline. |
| `Matchmaking.CancelTooLate` | 200 | Not an error — a cancel arriving after worker claim returns current status. |
| `Matchmaking.RuntimeUnavailable` | 503 | Queue execution disabled pending M8 (unreachable today — see Security Considerations). |
| `Validation.Failed` | 400 | Request shape/range/allow-list violation. |
| `Pagination.InvalidCursor` | 400 | Forged, malformed, or query-shape-mismatched cursor. |
| `RateLimit.Exceeded` | 429 | With `Retry-After` + `retryAfterUtc`. |
| `Auth.CsrfHeaderRequired` | 400 | Missing `X-Requested-With` header on a mutating call. |

## Security Considerations
Every route requires a session; the actor is always the JWT `sub`, never a body/route-supplied user id, so
BOLA/BOPLA overposting cannot target another account's lobby, ticket, or invite. A foreign or missing id
resolves to the identical privacy-safe not-found in both controllers — confirmed by direct code read
(`LobbiesController.cs`, `MatchmakingController.cs`) during the `--security=asvs-lite` review. Join
credentials are stored only as keyed (HMAC) digests, compared in constant time, revealed in plaintext only
at creation/rotation, and never appear in logs, events, or as a resource identifier; a wrong/expired/rotated
code and a closed lobby all return the same `Lobbies.CredentialInvalid`, with failed attempts throttled
specifically to prevent code-guessing. The one-active-lobby-or-ticket invariant and the
one-active-assignment-per-ticket invariant are enforced by partial unique indexes, not application checks
alone — verified on real PostgreSQL under concurrent load (zero duplicate assignment across two competing
workers). `Start` and Quick Match's execution path are both gated behind an M8 runtime-availability probe
and are dormant in production; `Lobbies.MatchRuntimeUnavailable` and `Matchmaking.RuntimeUnavailable` are
the only reachable outcomes for those two behaviors until Module 8 registers a consumer — this is a
documented platform-completeness gap, not a defect, and is recorded as a blocking M8 handoff item.

The `--security=asvs-lite` review (`SimPle.Project/docs/security/audits/module-06-lobby-matchmaking-system.md`)
covered both the backend phase and a post-frontend phase and found **zero unwaived Critical/High/Medium
findings** in either. One Low finding is open per phase (M06-001: per-instance in-memory join-failure
throttle, does not share state across horizontally scaled instances; M06-005: join credential persisted in
browser `sessionStorage`, not cleared on leave/kick/close) plus five Info findings (M06-002 through M06-004,
M06-006, M06-007) — all recorded, deferred, and non-blocking; see that document for full detail.

## Related Tests
Backend: 862/862 unit tests, 375/375 integration tests (including real-PostgreSQL migration, concurrency,
and race-condition suites — zero duplicate matchmaking assignment across two competing workers under `FOR
UPDATE SKIP LOCKED`). Frontend: `npm run test` (Vitest) 243/243 passing; `node scripts/check-contract-drift.mjs`
reports `DRIFT=0`. Live E2E: `module-06-lobby-matchmaking.spec.ts` passed 2/2 against a live local stack
(private lobby creation, second-user join, both ready, Start verified honestly unavailable, Quick Match
enqueue and cancel), with the shared axe accessibility fixture reporting zero violations. Full detail in
`testing-report.md`.

## Last Verified Command
Backend: `dotnet build SimPle.sln` (0 errors, 0 new warnings), `dotnet test tests/SimPle.UnitTests` (862/862),
`dotnet test tests/SimPle.IntegrationTests` (375/375, real PostgreSQL). Frontend: `npx tsc --noEmit`,
`npm run lint` (clean), `npx vitest run` (243/243), `node scripts/check-contract-drift.mjs` (`DRIFT=0`).
Live E2E: `npm run test:e2e -- tests/e2e/module-06-lobby-matchmaking.spec.ts` against local backend `:5147`
+ frontend `:3000` + real PostgreSQL — 2 passed.

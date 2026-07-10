# Security Audit - Module 3: Friends & Social Graph

Date: 2026-07-05 (backend re-audit, revision 1); frontend scope added 2026-07-06; M03-006/M03-007 fixed
2026-07-06; revision-2 delta reviewed 2026-07-09 (this pass); **M03-008, M03-009, M03-011 fixed and
M03-010 resolved by product decision on 2026-07-10** — see "Fix Verification (2026-07-10)" below.

## Scope

**This pass (2026-07-09, `--security=asvs-lite`, `--fix` not requested)** reviews only the **revision-2
backend delta** (Steps 2A+2B) on branch `feature/module-03-friends-social-graph`: independent
`SearchVisibility`/`FriendsListVisibility` settings + `PrivacyPolicyVersion`, `RetiredUsername`, bounded
people search (`GET /api/people/search`), the reconciled unified `Profile.NotVisible` 404 on
`GET /api/profile/{username}`, the new `GET /api/profile/{username}/viewer-context`,
`GET /api/profile/{username}/friends`, `GET /api/profile/{username}/mutual-friends` endpoints, the
per-account-target send cap (3/day), the chained per-IP people-search/discovery cap (120/hour), and the two
new migrations. The prior revision-1 surface (`/api/friends/*` send/accept/decline/cancel/remove/block/
unblock, discovery, suggestions, settings) is **not** re-reviewed here — see "Revision-1 summary" below; it
already passed a clean audit and this slice did not touch that code path except where noted (settings
update validator, `Friendship` entity extended with send-cap fields).

**Backend source reviewed (this pass):**
- `SimPle.Api/Controllers/PeopleController.cs`, `ProfileController.cs`, `FriendsController.cs` (settings
  endpoint only), `Program.cs` (rate-limiter policy table + middleware order)
- `SimPle.Application/People/Services/PeopleService.cs`, `Profiles/Services/ProfileService.cs`,
  `Friends/Services/FriendsService.cs` (send-cap + settings paths only)
- `SimPle.Infrastructure/Persistence/Repositories/FriendRepository.cs` (new query methods),
  `RetiredUsernameRepository.cs`
- `SimPle.Domain/Friends/Friendship.cs` (`UserFriendSettings`, send-cap fields/methods),
  `SimPle.Domain/Profiles/RetiredUsername.cs`
- Migrations `20260709054351_AddProfilePrivacyAndRetiredUsernames`, `20260709094629_AddPeopleSearchAndSendCap`
- `SimPle.Shared/Common/PublicIdentityDto.cs`
- Tests read as evidence (not re-run this pass): `PeopleEndpointsTests.cs`, `ProfileEndpointsTests.cs`,
  `ProfilePrivacyMigrationSmokeTests.cs`, `FriendsPostgresConcurrencyTests.cs` (EXPLAIN sections),
  `FriendsMigrationSmokeTests.cs`, `PeopleServiceTests.cs`, `ProfileServiceTests.cs`,
  `FriendsServiceTests.cs`

**Threat playbook:** `docs/security/threat-playbooks/friends-social-graph.md`,
`authorization-idor-bola.md`, `owasp-api-top-10.md`, `rate-limiting-abuse.md` (profile tags: idor, bola,
privacy, abuse).
**Spec / contract:** `docs/specs/module-03-friends-social-graph-spec-r2.md` (authoritative for this pass);
`docs/module-requirements/module-03-friends-social-graph.md` (brief, wins on conflict).
**Backend evidence:** `docs/ai-workflow/evidence/checkpoints/module-03-friends-social-graph/backend.json`
(runId `run-2026-07-09T08-25-57-362Z-...`, 321/321 unit + 224/224 real-Postgres integration, 0 skipped).

`--fix` was **not** requested this pass — no product code was changed by this review.

## Assessment Type

ASVS-lite (mandatory minimum for this module; not downgraded). Not a white-box pentest.

## Authorization Statement

Local authorized project-only review. No external systems, production services, real secrets, or real user
data were used.

## Executive Summary

The revision-2 delta correctly implements its highest-risk items: BOLA is re-derived from the JWT `sub` on
every new endpoint (never a body/query id); the mass-assignment surface stays minimal (`SearchVisibility`,
`FriendsListVisibility`, `FriendRequestPrivacy` only, all private-set domain state); `BlockedByTarget` never
leaks as a distinguishable `relationshipState`; the account-target send cap (3/day) is a genuine durable
counter on the `Friendship` row that survives remove/re-send cycles; rate-limiter middleware order is
correctly `UseAuthentication() → UseRateLimiter() → UseAuthorization()`; cursor binding correctly rejects
cross-query/cross-target/cross-policy-version reuse with 400 `Pagination.InvalidCursor`; `RetiredUsername`
is never joined into search/discovery and has no FK (survives account deletion); the new raw-SQL migration
DDL is static (no injection surface); and the correlated mutual-count subquery has dedicated `EXPLAIN`
evidence proving index usage with no sequential scan (`FriendsPostgresConcurrencyTests.cs`, not a gap as
initially suspected during this review).

**Two Medium findings** were confirmed by direct code inspection (not merely inferred): the friend/mutual
**visible-count** fields (`ProfileViewerContextDto.VisibleFriendCount`/`VisibleMutualFriendCount`, and
people-search's per-result mutual count) are computed by count queries that apply a **narrower** privacy
filter than the paged list queries backing the same UI surface — a documented risk-register item (brief
risk #10: "Friend-list visibility can leak through counts/cursors") that recurred in the new mutual-count
path (M03-008). Separately, the `AddProfilePrivacyAndRetiredUsernames` migration backfills
**every** existing `user_friend_settings` row with `SearchVisibility = "Everyone"` regardless of the row's
owner's current `ProfileVisibility`, contradicting the spec's explicit migration-default rule ("search
defaults to match current profile eligibility") — an existing `Private`-profile user becomes searchable
(minimal identity only) immediately after this migration runs, with no opt-in (M03-009). Two Low/Info items
are also recorded (M03-010, M03-011). **No Critical or High findings.** Nothing here blocked module
completion under the workflow's Critical/High gate; both Medium findings were nonetheless real,
evidence-backed contract violations and have since been **fixed and verified on 2026-07-10** — see "Fix
Verification (2026-07-10)" below.

## Severity Summary Table

| Severity | Count | Notes |
|---|---:|---|
| Critical | 0 | |
| High | 0 | |
| Medium | 0 | 2 opened this pass, both **fixed and verified 2026-07-10** — M03-008 (visible-count privacy-filter divergence), M03-009 (migration backfill ignores existing `ProfileVisibility`) |
| Low | 0 | 2 opened this pass — M03-010 **resolved 2026-07-10 by product decision** (discovery/people-search account budget intentionally independent, no code change), M03-011 **fixed and verified 2026-07-10** (anonymous profile response now sets explicit `Cache-Control`) |
| Info | 5 | see Deferred Issues (carried) / Reviewer Notes |

(Severity Summary Table intentionally keeps the template's Critical/High/Medium/Low zero-row convention for
counts that gate release; see "Findings" for the actual open-item counts by ID, consistent with how the
2026-07-06 pass reported open findings before they were fixed.)

## OWASP Mapping

- **OWASP Top 10 web:** A01 Broken Access Control (BOLA re-derivation, block precedence, count-filter
  divergence M03-008); A04 Insecure Design (send-cap abuse throttle, cursor binding); A05 Security
  Misconfiguration (rate-limiter registration + middleware order, cache-header gap M03-011).
- **OWASP API Security Top 10:** API1 Broken Object Level Authorization (viewer-context/friends/
  mutual-friends all actor- and membership-scoped → 404); API3 Broken Object Property Level Authorization
  (minimal allow-listed settings DTO; `PublicIdentityDto` has no profile-content fields); API4 Unrestricted
  Resource Consumption (send cap, chained people-search/discovery per-IP + per-account limits, M03-010 notes
  a budget-sizing nuance); API6 Unrestricted Access to Sensitive Business Flows / privacy leakage (M03-008,
  M03-009 — both are information-disclosure-via-aggregate/default findings, not access-control bypasses).
- WebSocket/Socket.IO checklist: not applicable (no realtime surface in this delta).

## Methodology

Authorized static code review of the two new controllers, two new/changed application services, the
extended `FriendRepository`, the new `RetiredUsernameRepository`, the extended `Friendship`/
`UserFriendSettings` domain entities, both new migrations (`Up`/`Down`), and the rate-limiter policy table
and middleware pipeline in `Program.cs`. Every claim below was checked against the actual source (file:line)
rather than taken from the implementing session's own checkpoint narrative; two findings (M03-008, M03-009)
were confirmed by tracing the exact LINQ predicates in each count query against its sibling paged-list query
and against the migration's hardcoded `defaultValue`. Did not re-run the disposable-Postgres suite (backend
checkpoint's 224/224 real-Postgres run from the same day is treated as current evidence since no product
code changed in this pass); did re-verify that the `EXPLAIN`-based translation/index-usage tests the
checkpoint cites actually exist and cover the new queries by grep + read.

## Module Architecture Reviewed

- **Existing UI reused:** n/a to this pass — backend-only slice; frontend (Steps 4A/4B) not yet built.
- **Frontend integration points:** n/a this pass.
- **Existing database impact:** additive only. `AddProfilePrivacyAndRetiredUsernames` adds 3 columns to
  `user_friend_settings` (all with server defaults) and a new `retired_usernames` table (unique
  `NormalizedUsername`, no FK to `users`, by design). `AddPeopleSearchAndSendCap` adds 3 columns to
  `friendships` (`LastSenderId`/`SendCountInWindow`/`SendWindowStartUtc`, all nullable/defaulted) and two
  raw-SQL pattern-ops indexes (`ix_users_normalizedusername_pattern`, `ix_users_displayname_upper_pattern`)
  for prefix search.
- **Migration added:** yes — both migrations above.
- **Migration safety notes:** forward-only, additive; `Down()` on both drops only what `Up()` added. **But**
  see M03-009 — the `SearchVisibility` backfill `defaultValue: "Everyone"` is uniform across all existing
  rows rather than conditional on each row's owning user's `ProfileVisibility`, which is a behavioral
  (privacy-default) defect even though it is not a *destructive* one.
- **Data preservation notes:** no destructive operation in either `Up()` path; existing rows keep their
  `FriendRequestPrivacy` and gain new columns with defaults.
- **Destructive DB changes:** none.
- **Backend/API/Swagger alignment:** all 5 new endpoints carry `[SwaggerOperation]` +
  `[ProducesResponseType]` (verified: `PeopleController.cs:27-29`, `ProfileController.cs:96-98,113-116,
  130-132,152-155`); `dotnet build` XML-doc generation check passed per backend checkpoint.
  `api-reference.md` is deliberately not yet updated (gated behind full-module approval per 2A/2B
  checkpoints) — this is a known, tracked deferral, not a finding.
- **Frontend/API integration alignment:** n/a — no frontend code exists for this delta yet.

## Threat Model

Primary new risks this pass (per spec-r2 "Security, privacy, and abuse controls" + brief risk register):
search/profile enumeration, friend-list graph scraping via count/list divergence, privacy-default
regression at migration time, cache cross-viewer leakage, and BOLA on the new relationship/list reads.

**Attack scenarios considered**

| Scenario | Verdict |
|---|---|
| Read another user's `viewer-context`/friends/mutual-friends by supplying someone else's id in the body | Not possible — viewer identity comes only from JWT `sub` (`ProfileController.cs` `TryGetUserId`); target comes only from the `{username}` route segment, resolved server-side |
| Guess a hidden/nonexistent/blocked/private/suspended username on any of the 4 profile-family reads | Identical `Profile.NotVisible` 404 for all — membership/visibility work (`probeId = user?.Id ?? Guid.Empty`) runs uniformly before the visibility branch (`ProfileService.cs:64-84,95-116,187-214,248-275`) |
| Enumerate accounts by profile/viewer-context/friends/mutual-friends response **timing** | Structurally uniform-work shape (see above); **not independently timing-tested for these 4 new endpoints** — flagged as an unverified item, not a confirmed gap |
| See `BlockedByTarget` as a distinguishable state anywhere | Not possible — profile read 404s outright when the target has blocked the viewer; viewer-context only ever emits `Self/BlockedBySelf/Friends/OutgoingPending/IncomingPending/None` |
| Overpost `state`/`domainVersion`/`requestCycleId`/timestamps via the settings-update body | Not possible — `UpdateFriendSettingsRequestDto` carries only `FriendRequestPrivacy`/`SearchVisibility`/`FriendsListVisibility`; all `Friendship`/`UserFriendSettings` state is private-set, mutated only through domain methods |
| Re-send a friend request to the same target faster than 3/day after the edge is removed (cooldown reset via Remove) | Blocked — `LastSenderId`/`SendWindowStartUtc`/`SendCountInWindow` persist on the same unordered-pair row across a remove→re-request cycle, independent of the `NextRequestAllowedAt` cooldown reset (`Friendship.cs:88-94,135-158`) |
| Infer the existence/count of a target's hidden (private/blocked/suspended) friends or mutuals by comparing the reported count to the enumerable page | **Confirmed possible — M03-008.** `GetVisibleFriendCountAsync` omits the `Visibility != Private` filter its sibling page query applies; `GetMutualFriendCountAsync` (and `SearchPeopleAsync`'s per-result mutual count) apply no privacy filter at all |
| A user who set their profile Private before 2026-07-09 becomes discoverable via `people/search` after the migration runs, without changing any of their own settings | **Confirmed possible — M03-009.** Migration backfill hardcodes `SearchVisibility="Everyone"` for every existing row |
| A shared cache in front of the API serves one visitor's cached anonymous profile response to a cookie-bearing request or vice versa | Low current risk — no `ResponseCaching`/`OutputCache` middleware is registered in `Program.cs`, so there is no live shared-cache surface today; but the anonymous branch of `GetPublicProfile` sets no `Cache-Control`/`Vary` at all (M03-011), which is a latent gap once a CDN/reverse-proxy cache is introduced |
| Retired username reveals it used to belong to someone (identity-link hijack reconnaissance) | Not possible — `RetiredUsernameRepository` exposes only `IsRetiredAsync`/`AddAsync`; never joined into search/discovery; a retired handle 404s generically like a never-existed one |
| SQL injection via the new raw-SQL migration DDL or the new repository query paths | Not possible — migration SQL is static (`CREATE INDEX ... varchar_pattern_ops`/`text_pattern_ops`, no interpolation); all query code is EF LINQ, parameterized |

## Findings

Continuing the module's existing numbering (`M03-001` through `M03-007` are revision-1 findings, all
resolved/fixed — see "Revision-1 summary").

### M03-008 - Friend/mutual visible-counts computed with a narrower privacy filter than their own paged lists

- **Severity:** Medium
- **Status:** Fixed 2026-07-10 (verified)
- **ASVS ref / OWASP:** V4.3 / API1 Broken Object Level Authorization (count aggregation is a data-exposure
  variant of BOLA — a hidden object's existence leaks through an aggregate even though the object itself is
  correctly hidden from the list); brief risk register item #10 ("Friend-list visibility can leak through
  counts/cursors").
- **Affected asset:**
  - `FriendRepository.GetVisibleFriendCountAsync` (`SimPLe.Backend/src/SimPle.Infrastructure/Persistence/
    Repositories/FriendRepository.cs:65-82`) filters blocked-either-direction and suspended candidates, but
    **omits** `Visibility != ProfileVisibility.Private`, which its sibling page query
    `GetVisibleFriendsPageAsync` (`FriendRepository.cs:187-228`, filter at line 203) **does** apply. Feeds
    `ProfileViewerContextDto.VisibleFriendCount` for non-self viewers
    (`SimPle.Backend/src/SimPle.Application/Profiles/Services/ProfileService.cs:167`).
  - `FriendRepository.GetMutualFriendCountAsync` (`FriendRepository.cs:50-63`) applies **no** filter at
    all — no block check, no private check, no suspended check — while its sibling page query
    `GetVisibleMutualFriendsPageAsync` (`FriendRepository.cs:230-266`, filters at lines 247-252) applies all
    three. Feeds `ProfileViewerContextDto.VisibleMutualFriendCount` (`ProfileService.cs:170`) shown to any
    authenticated non-self viewer, and the same unfiltered shape recurs in `SearchPeopleAsync`'s per-result
    `MutualCount` subquery (`FriendRepository.cs:297-300`), shown to strangers in people-search results.
- **Description:** The spec's Matrix D and the brief's own risk register both require that hidden
  (private-profile, blocked, suspended) candidates be filtered **before** count, order, and cursor
  construction, and that a reported count never exceed what the paired list actually discloses. Here the
  count and the list disagree: the count over-reports relative to what a caller can actually page through.
- **How it could be exploited, written safely:** An authenticated viewer reads
  `visibleMutualFriendCount = N` (or `visibleFriendCount = N`) from `viewer-context` or a people-search
  result, then pages the corresponding `/friends` or `/mutual-friends` endpoint and finds fewer than `N`
  entries. The delta discloses the existence and approximate number of hidden (private-profile, blocked, or
  suspended) friends/mutual connections that the platform's own privacy/sanction rules say should be
  invisible to that viewer. This is an aggregate information leak, not an identity leak (no names/ids of the
  hidden users are exposed) — hence Medium rather than High.
- **Evidence:** Line references above; confirmed by direct side-by-side read of each count query against
  its sibling page query, not inferred from test names.
- **Fix implemented (2026-07-10):** `GetVisibleFriendCountAsync`, `GetMutualFriendCountAsync`, and
  `SearchPeopleAsync`'s inline mutual-count projection in `FriendRepository.cs` now apply the identical
  visibility/suspension/block predicate set as their sibling paged-list queries
  (`GetVisibleFriendsPageAsync`/`GetVisibleMutualFriendsPageAsync`), so a reported count can no longer exceed
  what the same viewer can actually page through.
- **Verification after fix:** Unit suite re-run (202/202, mocked repository) plus a live Playwright E2E run
  against real PostgreSQL exercising the new correlated-subquery LINQ end-to-end (translates correctly,
  returns the expected results — `docs/ai-workflow/evidence/checkpoints/module-03-friends-social-graph/
  security.json`). Postgres-gated translation/`EXPLAIN` tests remain locally skipped
  (`MIGRATION_TEST_CONNECTION_STRING` not set in this environment, and constructing it would require reading
  a real `.env` credential, which project policy forbids); the live E2E run is the secret-safe substitute for
  this pass.
- **Residual risk:** Closed for the reviewed code paths. A regression test asserting
  `visibleFriendCount == page.Count` (across full pagination) and
  `visibleMutualFriendCount == mutualPage.Count` for a seeded mixed-visibility viewer is still recommended as
  a longer-term guard but is not required to close this finding.

### M03-009 - Migration backfills `SearchVisibility = Everyone` for all existing users regardless of their current `ProfileVisibility`

- **Severity:** Medium
- **Status:** Fixed 2026-07-10 (verified)
- **ASVS ref / OWASP:** V8.3 (data protection / sensitive data in transit… here: privacy-default
  correctness); OWASP API3 (property-level exposure via an incorrect default) / A01.
- **Affected asset:** `SimPLe.Backend/src/SimPle.Infrastructure/Migrations/
  20260709054351_AddProfilePrivacyAndRetiredUsernames.cs:29-35` —
  `migrationBuilder.AddColumn<string>(name: "SearchVisibility", ..., defaultValue: "Everyone")` applies
  uniformly to **every existing row** in `user_friend_settings`, with no conditional mapping from the row's
  owning `User.Visibility`.
- **Description:** Both the module brief (`docs/module-requirements/module-03-friends-social-graph.md`:
  "Migrated adults retain current profile/request behavior; search defaults to match current profile
  eligibility and friends-list visibility defaults to `Friends`") and spec-r2 ("Migration defaults: search =
  match current profile eligibility; friends-list = `Friends`") explicitly require the `SearchVisibility`
  backfill to derive from each user's **existing** `ProfileVisibility`, not a single constant. The
  `FriendsListVisibility` backfill correctly uses the constant `"Friends"` default per spec (that part of
  the rule has no per-user mapping requirement); only the `SearchVisibility` backfill is wrong. Confirmed
  `UserFriendSettings.CreateDefault` (`SimPle.Domain/Friends/Friendship.cs:190-197`, used only for *new*
  settings rows) is fine on its own — it pairs with the *new-user* default `ProfileVisibility.Public`
  (`SimPle.Domain/Users/User.cs:34`), so `Public → Everyone` is internally consistent for brand-new
  accounts. The defect is specific to the migration's one-size-fits-all backfill of **pre-existing** rows.
- **How it could be exploited, written safely:** Any account that had already set `ProfileVisibility =
  Private` (or `FriendsOnly`) before this migration is applied becomes discoverable via
  `GET /api/people/search` (minimal identity: username/displayName/initials/color/avatarUrl — no profile
  content) immediately after the migration runs, without the user taking any action or being notified. This
  silently narrows a privacy choice the user already made.
- **Evidence:** Migration file line above; confirmed the only test touching this path,
  `ProfilePrivacyMigrationSmokeTests.Migration_BackfillsExistingSettingsRows_WithValidEnumDefaults`
  (`SimPLe.Backend/tests/SimPle.IntegrationTests/Profiles/ProfilePrivacyMigrationSmokeTests.cs:155-202`),
  only asserts the backfilled value deserializes to a valid enum member (`SearchVisibility.Everyone`) — it
  seeds a single default-`Visibility` (`Public`) user and does not assert correctness relative to a
  `Private`-profile existing user, so it would not catch this defect even though it exercises the exact code
  path.
- **Fix implemented (2026-07-10):** `20260709054351_AddProfilePrivacyAndRetiredUsernames.Up()` now runs a
  corrective `migrationBuilder.Sql` `UPDATE` immediately after the `AddColumn` default, re-deriving
  `SearchVisibility` per existing user's current `ProfileVisibility`
  (`Public → Everyone`, `FriendsOnly → FriendsOfFriends`, `Private → Nobody`), matching spec-r2's "search
  defaults to match current profile eligibility" rule literally.
- **Verification after fix:** The equivalent `UPDATE` was also applied directly to the already-migrated
  local dev database so its state matches what the corrected migration produces on a fresh apply; the
  enum-mapping correctness was checked directly against the `CASE` expression above (one row updated per
  affected user, no errors). Not re-validated via a from-scratch migration run this pass
  (`ProfilePrivacyMigrationSmokeTests`/`FriendsMigrationSmokeTests` remain skipped locally for the same
  `MIGRATION_TEST_CONNECTION_STRING`/`.env` reason as M03-008).
- **Residual risk:** Closed for the migration logic itself. This project has no real pre-existing user data
  (pre-production/portfolio project), so no backfill of real data was at risk; a from-scratch migration run
  against a disposable Postgres container is still recommended before this is treated as fully
  regression-proof, but is not required to close this finding.

### M03-010 - Discovery and people-search per-account budgets are two independent 30/min windows, not one shared 30/min budget

- **Severity:** Low
- **Status:** Resolved 2026-07-10 (product decision — no code change)
- **ASVS ref / OWASP:** API4 Unrestricted Resource Consumption.
- **Affected asset:** `SimPLe.Backend/src/SimPle.Api/Program.cs:255,258` —
  `options.AddPolicy("friend-discovery", ... FriendWindow(context, "fdsc", 30, TimeSpan.FromMinutes(1)))` and
  `options.AddPolicy("people-search", ... FriendWindow(context, "psrc", 30, TimeSpan.FromMinutes(1)))` are
  two separately-keyed fixed windows (`fdsc:` vs `psrc:` partition prefixes).
- **Description:** The brief states "exact discovery and people search **share** 30/minute/account plus
  120/hour/IP" — most naturally read as one combined 30/min budget across both routes. As implemented, an
  account can issue 30 discovery calls **and** 30 people-search calls in the same minute (60/min combined),
  bounded only by the shared 120/hour/IP `GlobalLimiter` (`Program.cs:263-279`), which does correctly chain
  across both paths.
- **How it could be exploited, written safely:** Doubles the effective per-account request budget across
  the two enumeration-risk routes relative to the most literal reading of the spec; the per-IP hourly
  ceiling remains an effective backstop, so this is a budget-sizing nuance, not a missing control.
- **Evidence:** Lines above.
- **Resolution (2026-07-10):** Confirmed directly with the product owner that the two-independent-windows
  design is intentional — `friend-discovery` (exact lookup) and `people-search` (prefix search) serve
  different purposes and are meant to carry separate 30/min/account budgets, backstopped by the shared
  120/hour/IP `GlobalLimiter` either way. No code change made. Documented explicitly in `api-reference.md`'s
  Rate Limiting section per the suggested fix's first option.
- **Residual risk:** Low — bounded by the per-IP hourly cap; accepted as the intended design.

### M03-011 - Anonymous public-profile response sets no explicit `Cache-Control`/`Vary` header

- **Severity:** Low
- **Status:** Fixed 2026-07-10 (verified)
- **ASVS ref / OWASP:** V8.x cache control; A05 Security Misconfiguration.
- **Affected asset:** `SimPLe.Backend/src/SimPle.Api/Controllers/ProfileController.cs:109` —
  `if (requesterId.HasValue) Response.Headers.CacheControl = "private, no-store";` only sets a header on the
  authenticated branch; the anonymous branch of `GetPublicProfile` sets none.
- **Description:** Spec-r2 requires "Shared caches may store only anonymous Public base-profile fields with
  visibility/version in the key... Visibility/block/sanction/username changes invalidate affected public
  profile/search entries after commit." No `ResponseCaching`/`OutputCache` middleware is registered anywhere
  in `Program.cs` (grepped, no matches), so there is **no live shared-cache surface in this application
  today** — current risk is zero. But the missing explicit header/`Vary: Cookie` is a latent gap: if a
  CDN/reverse-proxy cache is later placed in front of this route (the module registry lists CloudFront/S3
  prod as a deferred infra dependency elsewhere in this project), a response with no `Cache-Control` could be
  cached by a default policy and served across cookie-bearing/anonymous boundaries without the isolation the
  spec calls for.
- **How it could be exploited, written safely:** Not exploitable in the current deployment (no cache layer
  exists to poison). Recorded as a forward-looking gap against the written contract.
- **Evidence:** Line above; grep of `Program.cs` for `ResponseCaching`/`OutputCache` returned no matches.
- **Fix implemented (2026-07-10):** The anonymous branch of `GetPublicProfile` (`ProfileController.cs`) now
  sets an explicit `Cache-Control: public, max-age=30` plus `Vary: Cookie`; the authenticated branch is
  unchanged (`private, no-store`, now also carrying `Vary: Cookie`).
- **Verification after fix:** Validated via a direct `curl` smoke test against the live backend: an
  anonymous request returns the new anonymous-branch header; an authenticated request (between an unblocked
  pair) returns the unchanged `private, no-store` header.
- **Residual risk:** Closed. No live shared-cache middleware exists yet, so this closes the latent gap ahead
  of any future CDN/reverse-proxy introduction.

## Fix Verification (2026-07-10)

A follow-up pass fixed and verified all four findings opened above, ahead of the frontend slice reading
these counts. Evidence checkpoint:
`docs/ai-workflow/evidence/checkpoints/module-03-friends-social-graph/security.json`
(runId `run-2026-07-09T16-12-20-678Z-...`, timestamp 2026-07-10T02:05:00.000Z). Changed files:
`FriendRepository.cs` (M03-008), `20260709054351_AddProfilePrivacyAndRetiredUsernames.cs` (M03-009),
`ProfileController.cs` (M03-011); M03-010 required no code change (product decision). Commands run this
pass: `dotnet build` (exit 0), `dotnet test tests/SimPle.UnitTests --filter
"FullyQualifiedName~Friends|FullyQualifiedName~People|FullyQualifiedName~Profile"` (exit 0, 202/202), a live
Playwright E2E run against the real local backend + PostgreSQL exercising the corrected correlated-subquery
LINQ (exit 0), a manual re-derivation `UPDATE` against local dev Postgres equivalent to a fresh apply of the
fixed migration (exit 0), and a `curl` smoke test of the anonymous vs. authenticated `Cache-Control`/`Vary`
headers on `GET /api/profile/{username}` (matched expected values). This session independently re-read the
three changed source files against the fix descriptions above (not merely trusting the checkpoint narrative)
and confirmed each fix is present in the current codebase with an inline comment referencing its finding ID.
Zero open findings above Info remain for the revision-2 delta.

## Revision-1 summary (historical, resolved — not re-reviewed this pass)

The 2026-07-05/06 backend + frontend passes found zero Critical/High findings across the original
`/api/friends/*` surface. Two non-blocking findings were opened and **fixed same-session**:

| ID | Severity | Fix | Status |
|---|---|---|---|
| M03-007 | Low | `BlockUserResult` stripped to `Outcome`/`BlockedUserId`/`BlockedAt` — no target identity fields returned on the block-response path regardless of target visibility. | Fixed 2026-07-06 |
| M03-006 | Medium | `FriendsService` now emits structured `Security: ...` log lines for send/cross-accept/accept/decline/cancel/remove/block/unblock, matching Module 1's `AuthService` convention. | Fixed 2026-07-06 |
| M03-001 | Info (was Low) | Block-existence inference on the friend-request surface resolved by unifying denial responses to `Profile.NotVisible` 404. | Resolved on Module 3 surface |

Full narrative, evidence commands, and reviewer notes for these are preserved in this file's git history
(the pre-2026-07-09 version of this document) and in
`docs/ai-workflow/evidence/checkpoints/module-03-friends-social-graph/security.json` (revision-1 checkpoint,
immutable). This pass does not re-verify or re-claim that evidence; it is cited as background only.

## Fixed Issues Summary

No fixes were made this pass (`--fix` not requested). See "Revision-1 summary" above for the module's prior
fixed issues (M03-006, M03-007), which remain fixed and out of scope for this pass.

## Deferred Issues

| ID / Item | Severity | Owner | Rationale |
|---|---|---|---|
| M03-008 — visible-count/paged-list privacy-filter divergence | Medium | Fixed 2026-07-10 | Closed — see "Fix Verification (2026-07-10)". |
| M03-009 — migration backfill ignores existing `ProfileVisibility` | Medium | Fixed 2026-07-10 | Closed — see "Fix Verification (2026-07-10)". |
| M03-010 — discovery/people-search budgets not literally shared | Low | Resolved 2026-07-10 | Product decision — independent budgets are intentional; no code change. |
| M03-011 — anonymous profile response has no explicit `Cache-Control` | Low | Fixed 2026-07-10 | Closed — see "Fix Verification (2026-07-10)". |
| Latency-indistinguishability of the 4 new profile-family reads is untested | Info | Later slice | Structurally uniform-work (same code path for hidden vs. absent), but no dedicated timing assertion exists for these endpoints the way discovery had in revision 1. |
| Secondary rate caps beyond this slice (carried from revision-1) | Info | Already addressed | Revision-1 deferred the 3/day send cap and IP-chained discovery cap; both are now implemented and verified in this slice (see Threat Model / Executive Summary) — carried note updated, not re-opened. |
| Test-toolchain transitive High advisories (`System.Net.Http`/`System.Text.RegularExpressions` 4.3.0) | Info | Test hygiene | Unchanged from revision-1; present only in test projects, not shipped. |
| User-existence oracle via block/dismiss (200/204 vs 404 keyed by GUID) | Info | Accepted (carried from revision-1) | GUIDs are non-enumerable; negligible. |

## Tests/Security Checks Run

This pass performed **static code review only** (`--fix` not requested; no product code changed). No new
test commands were executed. The following evidence was read and cross-checked against source, not
re-executed:

```text
# Backend checkpoint evidence relied upon (same day, unchanged since):
# docs/ai-workflow/evidence/checkpoints/module-03-friends-social-graph/backend.json
dotnet build SimPle.sln                                                                   # exit 0
dotnet test tests/SimPle.UnitTests (321/0/0)                                               # exit 0
dotnet test tests/SimPle.IntegrationTests --filter PeopleEndpointsTests|ProfileEndpointsTests (in-memory, 70/0/0)   # exit 0
MIGRATION_TEST_CONNECTION_STRING=... dotnet test --filter FriendsMigrationSmokeTests (real Postgres, 15/0/0)        # exit 0
MIGRATION_TEST_CONNECTION_STRING=... dotnet test --filter FriendsPostgresConcurrencyTests (real Postgres, 11/0/0)   # exit 0
MIGRATION_TEST_CONNECTION_STRING=... dotnet test tests/SimPle.IntegrationTests (real Postgres, full suite, 224/0/0, 0 skipped)  # exit 0

# This pass's own verification greps/reads (2026-07-09):
grep -n "GetVisibleFriendCountAsync|GetMutualFriendCountAsync|GetVisibleFriendsPageAsync|GetVisibleMutualFriendsPageAsync" FriendRepository.cs
grep -n "Cache-Control|no-store|requesterId.HasValue" ProfileController.cs
grep -n "ResponseCaching|OutputCache|AddResponseCaching" Program.cs                        # no matches — confirms no live cache layer
grep -n "CreateDefault|SearchVisibility =|FriendsListVisibility =" Domain/**/*.cs
grep -n "CanSend\(|RecordSend\(|SendCapExceeded|TimeSpan.FromDays" FriendsService.cs
grep -n "EXPLAIN|ix_users_normalizedusername_pattern|..." FriendsPostgresConcurrencyTests.cs   # confirmed EXPLAIN coverage exists for new indexes + mutual-count subquery
```

Corroborating security-relevant NuGet advisory scan (unchanged since 2026-07-05, no new dependencies added
in this slice's changed-files list): production projects clean; two High advisories remain in
`SimPle.UnitTests`/`SimPle.IntegrationTests` only (transitive, not shipped).

## Files Changed

- `SimPle.Project/docs/security/audits/module-03-friends-social-graph.md` (this audit — rewritten this pass
  to add the revision-2 delta review; revision-1 content condensed into "Revision-1 summary"; updated
  2026-07-10 to record the M03-008/009/010/011 fix verification).
- `SimPLe.Backend/src/SimPle.Infrastructure/Persistence/Repositories/FriendRepository.cs` (M03-008 fix,
  2026-07-10).
- `SimPLe.Backend/src/SimPle.Infrastructure/Migrations/20260709054351_AddProfilePrivacyAndRetiredUsernames.cs`
  (M03-009 fix, 2026-07-10).
- `SimPLe.Backend/src/SimPle.Api/Controllers/ProfileController.cs` (M03-011 fix, 2026-07-10).

No product code was changed by the 2026-07-09 static-review pass itself; the three files above were changed
in the 2026-07-10 fix-and-verify follow-up.

## Final Security Status

- **Critical / High (production):** none.
- **Open:** none above Info. M03-008 (Medium) and M03-009 (Medium) were opened this pass and **fixed and
  verified 2026-07-10**; M03-011 (Low) was opened this pass and **fixed and verified 2026-07-10**; M03-010
  (Low) was opened this pass and **resolved 2026-07-10 by product decision** (no code change required).
- **Blocks module completion?** No.
- **Backend security review (revision-2 delta):** complete, including fix verification. **Frontend security
  review:** not covered by this document's static pass (Steps 4A/4B shipped after this pass was written) —
  see `technical-flow.md`/`testing-report.md` for the frontend implementation and test evidence.
- **Module 3 overall security-ready:** revision-1 surface remains security-ready (unconditional). The
  revision-2 backend delta is now security-ready as well — zero open findings above Info remain. Live E2E
  execution against a fully seeded local stack has since run and passed (1/1, 25.7s, 2026-07-10 — see
  `verification.json` and `testing-report.md`); production review and final evidence sign-off are still
  outstanding before the module as a whole is declared complete (see `docs/ai-workflow/project-state.md`).

## Reviewer Notes

**For a non-specialist reviewer:** this pass reviewed only the *new* things Module 3 revision 2 adds: search,
a richer profile-relationship view, and drill-down friend/mutual lists.

1. **The core access-control pattern from revision 1 held up under the new surface** — every new endpoint
   still figures out who you are from your login session, never from anything you send in the request, and a
   request for someone else's hidden data still comes back as a generic "not found."
2. **Two real gaps were found this pass, both about numbers being more honest than the actual list — both
   are now fixed (2026-07-10):**
   - The "you have N mutual friends" / "N friends" counts shown to another person could be **higher** than
     what that person could actually page through, because the count math forgot to apply the same
     private/blocked/suspended filters the list itself uses. Fixed by applying the identical filter set to
     both the count and the list.
   - A separate bug in the database migration: everyone's "who can find me in search" setting was reset to
     "everyone" when the migration ran, even for people who had already made their profile Private. Fixed by
     re-deriving each existing user's search setting from their current profile visibility instead of a flat
     default.
3. **Two smaller, low-risk notes, both closed 2026-07-10:** the anti-spam budget for search/discovery is
   split into two separate 30-per-minute buckets rather than one shared bucket — confirmed with the product
   owner that this split is intentional, not a bug; and the public profile page now sets an explicit caching
   header on its anonymous branch, closing a latent gap ahead of any future CDN/reverse-proxy cache.
4. **Nothing here was a "someone can break in" bug** — no Critical or High findings were ever open. The two
   Medium items were privacy-hygiene issues (over-reporting a count, over-broad search discoverability by
   default); both are now fixed and independently re-verified against the current source code.
5. **What was double-checked, not just taken on faith:** the send-limit (3 friend requests per day to the
   same person), the rate-limiter setup order, the search-cursor tampering protection, and the "does this
   database query actually use an index" proof were all independently re-read against the source code, not
   just copied from the implementing session's own notes.

# Testing Report - Module 07: Real-Time Presence, Lobby Updates & Chat

## Test Strategy
Three sessions produced this module's evidence: a backend build (split into M07-B1 transport/presence/auth
and M07-B2 chat/events/retention), a frontend build (M07-F1), and a live-stack verification pass. Each
backend slice carried its own unit and real-PostgreSQL integration tests; a `--security=asvs-lite` review ran
twice — once against the backend alone, once again after the frontend existed, since chat delivery and chat
history are two separate code paths that needed independent scrutiny. The frontend slice added Vitest
coverage for the composer, presence hook, reconnect/resync handling, and message dedupe, plus a contract-drift
check against the real backend route table. Verification then ran a live, no-mock Playwright E2E spec
against a real local backend, frontend, and PostgreSQL instance, with the shared axe accessibility fixture
attached, and used a fix-and-rerun loop rather than reporting a first failing attempt as final. This
docs-stage pass writes up evidence already produced by those sessions; no new test command was run while
authoring this document.

## Coverage Target
90%+ line/branch coverage is the project's advisory target. It is not a merge gate — a lower number does not
block completion, and a higher number does not excuse skipping edge cases the test matrix calls out. No
coverage percentage was invented for this report; only what is directly evidenced below is stated.

## Coverage Result
No single aggregate coverage percentage was recorded across the module's sessions; a coverage report was
generated during the M07-B2 backend session (`--collect:"XPlat Code Coverage"`) but no summary percentage was
captured in the evidence reviewed for this document, consistent with this project's advisory (not enforced)
coverage policy. Reported instead, by exact source, are the pass/fail counts below.

**Backend test counts across sessions (reported per source rather than merged into one number, since they
were captured at different points as more tests were added — see the note at the end of this section):**

| Source | Command context | Result |
|---|---|---|
| `m07-b2-checkpoint-report.md` | Full backend suite with coverage collection, real Postgres, mid M07-B2 session | Unit 955/955, Integration 400/400 |
| Backend security review (`security.json` / audit doc), targeted filter | `RealtimeHubTests\|ChatServiceTests\|ChatRetentionHoldRaceTests\|ChatEndpointsTests` | Unit 22/22, Integration 17/17 passed, 5 skipped (already independently verified passing in the immediately preceding B2 session) |
| Backend security review, post-fix targeted re-run | Same filter, after 3 findings fixed | Unit 23/23, Integration 9/9 |
| Backend security review, full-suite re-run (twice) | `dotnet test` against the whole solution, this session | Unit 956/956 both times (0 regressions); Integration 294 passed / 107 failed both times — a pre-existing local PostgreSQL credential mismatch in the review environment, confirmed unrelated to Module 7 code, with zero of the 107 failures in any Realtime/Chat test class |
| Post-frontend security review (`frontend-security.json`), targeted filter | `ChatServiceTests\|RealtimeHubTests\|ChatEndpointsTests`, after the M07-008 fix | Unit 24/24, Integration 18/18 |
| Verification session (`verification.json`) | `dotnet test SimPLe.Backend/SimPle.sln --no-build`, after the domain-bug and `LobbyRealtimeHandler` fixes | 294 passed, 0 failed, 107 Testcontainers-gated integration tests skipped in that pass |
| Operations gate (`operations.json`), same overall session as verification | Full unit suite only, separate command | 962/962 passed, 0 failed |

A note on the numbers above rather than a silent reconciliation: the "294" figure appears in two different
places in the evidence — the security review's full-suite re-run (294 **passed**, 107 **failed** due to a
local credential problem) and the later verification session (294 **passed**, 0 failed, 107 **skipped** via
Testcontainers gating). These are two different runs, in two different sessions, using two different
mechanisms to arrive at a very similar-looking number (a login failure vs. a deliberate skip), and the
evidence does not state that they are the same 107 tests or the same underlying cause. Rather than
collapsing this into a single tidy sentence, it is reported here exactly as each source states it. The most
current, most complete number for the full backend unit suite is `operations.json`'s **962/962**; the module
does not have a single authoritative "everything at once, freshly re-run" combined unit+integration count in
its evidence, and this report does not manufacture one.

**Real-PostgreSQL-specific suites:** `ChatRetentionHoldRaceTests` (the moderation-hold-vs-cleanup-sweep race)
ran in isolation during the M07-B2 session, 5/5 passed, against a real local PostgreSQL instance
(`MIGRATION_TEST_CONNECTION_STRING` set), not an in-memory substitute. `ChatIdempotencyPostgresTests` is
named in the approved spec's test matrix and is covered within the 400/400 integration total reported by
`m07-b2-checkpoint-report.md`; no isolated pass count for it specifically was found in the evidence reviewed,
so it is not separately claimed here.

**Frontend:** `npx vitest run` — **264/264** passing, 26 test files (`m07-f1-checkpoint-report.md`). `npx tsc
--noEmit` clean. `npx eslint` clean (`--max-warnings=0`), after two ESLint errors found and fixed in
`RealtimeConnectionProvider.tsx` during this session. `node scripts/check-contract-drift.mjs`: **DRIFT=0**,
87 backend routes, 72 unique frontend calls, 0 unresolved mismatches. `npm run build`: clean, 19 routes.

**Live E2E:** `module-07-realtime-chat.spec.ts` — **1 passed, 0 failed**, against a live local stack (real
backend on `:5147`, real frontend on `:3000`, real PostgreSQL, no mocks), with the shared axe accessibility
fixture reporting zero violations on the pages it exercised. Two earlier attempts in the same verification
session did not pass — see Bugs Found During Testing below for what those attempts actually caught, since
they were not simply flaky retries.

## Commands Run
```bash
# Backend (M07-B1 + M07-B2 sessions)
dotnet build SimPLe.Backend/SimPle.sln --no-restore
dotnet test SimPLe.Backend/SimPle.sln --collect:"XPlat Code Coverage"
  # Unit 955/955, Integration 400/400 (real Postgres, MIGRATION_TEST_CONNECTION_STRING set)
dotnet test SimPLe.Backend/SimPle.sln --filter "FullyQualifiedName~ChatRetentionHoldRaceTests" --no-build
  # 5/5 passed, isolated, real Postgres
node scripts/check-contract-drift.mjs
  # DRIFT=0 (87 backend routes, 71 unique frontend calls -- before the frontend slice existed)

# Backend security review (--security=asvs-lite, backend phase)
dotnet test SimPLe.Backend/SimPle.sln \
  --filter "FullyQualifiedName~RealtimeHubTests|ChatServiceTests|ChatRetentionHoldRaceTests|ChatEndpointsTests" \
  --no-restore
  # Unit 22/22, Integration 17/17 passed, 5 skipped
# -- 3 findings fixed: M07-001 (Medium), M07-002 (Low), M07-003 (Low) --
# fix-verification re-run, same filter: Unit 23/23, Integration 9/9
dotnet build SimPLe.Backend/SimPle.sln --no-restore
  # 0 errors after fix
# full-suite re-run, twice (this session):
  # Unit 956/956 both times, 0 regressions
  # Integration 294 passed / 107 failed both times -- pre-existing local Postgres credential
  # mismatch in the review environment, unrelated to Module 7 code; zero failures in
  # Realtime/Chat test classes specifically

# Frontend (M07-F1 session)
npx tsc --noEmit -p tsconfig.json
  # clean
npx eslint <changed files> --max-warnings=0
  # 2 errors found and fixed in RealtimeConnectionProvider.tsx; clean after fix
npx vitest run
  # 264/264 passing, 26 test files
node scripts/check-contract-drift.mjs
  # DRIFT=0 (87 backend routes, 72 unique frontend calls)
npm run build
  # clean, 19 routes

# Post-frontend security review (--security=asvs-lite)
dotnet build SimPLe.Backend/SimPle.sln --no-restore
  # 0 errors, 0 warnings
dotnet test SimPLe.Backend/SimPle.sln \
  --filter "FullyQualifiedName~ChatServiceTests|RealtimeHubTests|ChatEndpointsTests" --no-build
  # 24/24 unit, 18/18 integration (after M07-008 fix + its regression test)

# Verification (live local stack)
node scripts/check-contract-drift.mjs
  # DRIFT=0 (87 backend routes, 72 unique frontend calls, re-confirmed)
dotnet build SimPLe.Backend/SimPle.sln
  # 0 errors, 0 warnings (after Lobby.cs + LobbyRealtimeHandler.cs fixes)
dotnet test SimPLe.Backend/SimPle.sln --no-build
  # 294 passed, 0 failed, 107 skipped (Testcontainers-gated tests not run this pass)
node scripts/run-module-e2e.mjs --modules 7
  # 2 attempts blocked by stale e2e-user-a/e2e-user-b lobby state from a prior run;
  # final attempt: 1 passed, 0 failed, axe scan clean

# Operations gate (same overall session as verification)
dotnet build SimPLe.Backend/SimPle.sln
  # 0 errors
dotnet test SimPLe.Backend/SimPle.sln
  # full unit suite, 962/962 passed, 0 failed
dotnet run --project SimPLe.Backend/src/SimPle.Api (background) && curl http://localhost:5147/health
  # 200
curl http://localhost:3000
  # 200
```

## Unit Tests
Backend unit coverage follows the approved spec's test matrix: presence-registry precedence aggregation and
Away/Offline timing against a fake clock (not wall-clock sleeps); `ChatBodyNormalizer` normalization/length/
control-character rules; `ChatProfanityFilter` deny-list matching; `LobbyRealtimeHandler`'s watermark
suppression and same-revision collapsing logic; the authorization matrix for
`LobbyScopeAuthorizer`/`NullMatchScopeAuthorizer` (member, non-member, suspended, blocked-in-either-direction,
public-lobby-any-authenticated-user); and `AuthService.LogoutAsync`'s session-family revoke behavior. Exact
pass counts and their source sessions are in the Coverage Result table above.

## Integration Tests
Real-PostgreSQL integration coverage (not SQLite/in-memory substitutes) includes: the hub happy path
(connect, subscribe, send, receive); chat history cursor pagination correctness including block-filtered
pages; the migration `20260717001316_AddChatAndRealtimeActivation` applying cleanly against a real instance;
`ChatRetentionHoldRaceTests` (5/5, isolated run) proving the atomic, row-locked delete never silently drops a
message under a concurrent hold; and the idempotent-send unique-constraint behavior named in the spec's test
matrix as `ChatIdempotencyPostgresTests`, covered within the 400/400 integration total rather than isolated
separately in the evidence reviewed.

## Security/Authorization Tests
The `--security=asvs-lite` review ran in two phases, both summarized here without duplicating the full
finding-by-finding detail that lives in
`SimPle.Project/docs/security/audits/module-07-realtime-presence-chat.md` (out of scope for this docs
pass). Backend phase: 1 Medium (**M07-001**, unfiltered chat group broadcast let a blocked co-member still
receive chat) and 2 Low (**M07-002** connection-lease leak on a faulted connect, **M07-003** missing-`Origin`
header bypassing the allowlist) findings, all fixed and covered by a fix-verification re-run (23/23 unit,
9/9 integration). Post-frontend phase: 1 Medium (**M07-008**, the REST chat-history route lacked the block
filter the realtime path already had), fixed and covered by a regression re-run (24/24 unit, 18/18
integration); **M07-005** (output encoding) was independently confirmed **passing**, not left open. **Zero
unwaived Critical/High findings** in either phase. Three Info findings remain open and non-blocking, recorded
rather than hidden: **M07-004** (profanity filter is intentionally simple, Module 12 is the real backstop),
**M07-006** (positive security-event logging is thinner than the brief's full list), and **M07-007** (the
out-of-scope `OutboxDispatcherWorker` fix was sanity-checked only, not deep-reviewed).

## Frontend Tests If Applicable
264/264 Vitest tests passing across 26 files, covering: `ChatPanel` composer behavior (Enter sends,
Shift+Enter inserts a newline, IME composition never submits early), message list dedupe/stable-key
rendering, `usePresence` across the 5 precedence levels, `RealtimeConnectionProvider`'s reconnect/backoff
handling and epoch-change resync trigger, and removal of every hard-coded presence literal across the 5
de-mocked screens. `npx tsc --noEmit` and lint both clean; production build clean at 19 routes.

## Realtime Tests If Applicable
The live-stack Playwright E2E spec (`module-07-realtime-chat.spec.ts`) is the module's realtime-specific
proof: two authenticated browser contexts in the same lobby, live presence dots updating on each side, a
multiline chat message (composed with Shift+Enter) observed exactly once by both participants, a
disconnect/mutate/reconnect sequence that converges correctly rather than showing stale state, and the
shared axe accessibility fixture attached throughout with zero violations reported in the final passing run.

## Database/Migration Checks
Migration `20260717001316_AddChatAndRealtimeActivation` applied cleanly against a real local PostgreSQL
instance (verified, not assumed from SQLite/in-memory behavior); it is additive only — three new tables,
no existing table altered or dropped. `ChatRetentionHoldRaceTests` specifically exercises the
retention-sweep-vs-hold concurrency scenario against real Postgres row locking rather than an in-process
lock, since the atomicity guarantee this module relies on only means something at the database level.

## Backend/API/Swagger Alignment
`Swagger_DescribesChatHistoryAndDeleteRoutes` passed, confirming both REST routes are represented in the
generated OpenAPI document. Hub methods and events are not representable in Swagger/OpenAPI by nature of the
transport; they are documented directly in `api-reference.md` instead, and this is stated there as "not
applicable" per this project's documentation style rather than left as a silent gap.

## Frontend/API Integration Alignment
`node scripts/check-contract-drift.mjs` reported **DRIFT=0** at every checked point: 87 backend routes
against 71 unique frontend calls mid-backend-session (before the frontend slice added a caller for chat
history), then 87 against 72 in the frontend session and again, re-confirmed, in the verification session.
Zero unresolved mismatches at every check.

## Edge Cases Tested
Duplicate send retry (same `clientCommandId`) returning the original message rather than creating a
duplicate; blocked-sender exclusion on both the realtime delivery path and the REST history path;
membership/suspension/block state changes taking effect on the very next authorization check rather than
only the next reconnect; a lobby closing or expiring while members are still joined (the domain bug below);
a missed or duplicated `LobbyChanged` hint self-healing via revision comparison or `ResyncRequired`; and an
excessive `ReportActivity` call being silently ignored rather than erroring.

## Bugs Found During Testing
- **Outbox activation-watermark race (M07-B2 backend session):** a handler's watermark was captured lazily,
  on its first delivered message, which could cause a first-ever delivery to replay a lobby's entire
  historical event backlog. Fixed with an eager `ActivateAllHandlersAsync` called at dispatcher startup. This
  fix touched `OutboxDispatcherWorker.cs`, outside Module 7's declared file-ownership boundary — disclosed
  as an explicit exception rather than worked around, and recorded as sanity-checked-only (not deep-reviewed)
  in the security disposition (**M07-007**).
- **`SeatCard` never called `usePresence` (M07-F1 frontend session):** lobby seat presence dots were rendered
  from a static prop, not live data. Found and fixed during the frontend session, before it ever reached
  verification.
- **Two ESLint errors in `RealtimeConnectionProvider.tsx` (M07-F1 frontend session):** found and fixed before
  the frontend session's lint gate passed clean.
- **Chat delivery block-filter gap on the REST history route (post-frontend security review, M07-008):** the
  realtime send path had already been fixed to exclude blocked senders (M07-001); the REST history endpoint
  had not received the equivalent fix. Found, fixed, and covered by a regression test.
- **Domain bug: stranded `LobbyMember` state on lobby close/expiry (verification session):**
  `Lobby.CloseInternal` and `Lobby.TryExpire` never released `LobbyMember.State`, permanently blocking
  affected players from rejoining any lobby. Fixed with `Lobby.ReleaseAllJoinedMembers(nowUtc)`, called from
  both paths. A follow-on bug in `LobbyRealtimeHandler`'s `LobbyClosed` case (a reference to a nonexistent
  `JoinedMembers` property instead of `Members`) was found and fixed in the same pass.
- **Two accessibility defects (verification session):** `LobbyPage.tsx` was missing a page `<h1>`;
  `ChatPanel.tsx`'s placeholder text failed color contrast. Both caught by the shared axe fixture and fixed
  before the E2E spec's final passing run.
- **Stale test-account lobby state (verification session, E2E harness, not shipped code):** two attempts at
  running the E2E spec failed because the `e2e-user-a`/`e2e-user-b` accounts still held state from a prior
  run's lobby. This is the root cause behind the "E2E spec self-cleanup" item in Remaining
  Untested/Deferred Items below — it was worked around this session, not fixed at the source.
- **A real, unrelated account (`mohannad`) was found to hold an identically-corrupted orphaned lobby-membership
  row** — the same class of defect the `Lobby.ReleaseAllJoinedMembers` fix addresses, but on data that
  predates this module's fix. This was noted and explicitly **not** touched during verification, since
  modifying a real account's data was outside the scope authorized for that session. The project owner has
  since authorized a scoped, one-off, local-dev-only release of that row; as of this evidence it has **not
  yet been executed**.

## Fixes Made After Test Failures
Every fix above (M07-001/002/003/008 from the two security review phases, the outbox activation-watermark
race, the `SeatCard` presence wiring, the two ESLint errors, the `Lobby`/`LobbyRealtimeHandler` domain bug,
and the two accessibility defects) was followed by a targeted or full re-run confirming the fix and checking
for regressions before the module was considered complete — none of these fixes were merged on the basis of
"should work now" without a passing re-run. The E2E spec's final passing run came only after the domain bug
and both accessibility fixes were in place; nothing was marked passing based on an earlier failing attempt.

## Remaining Untested/Deferred Items
- Match-scope chat/updates: no test exists yet because `NullMatchScopeAuthorizer` has no real behavior to
  test until Module 8 supplies an adapter.
- Moderation evidence copy and the 2-year retention domain: deferred to Module 12; `ChatMessageHold` is
  schema-only this module.
- Live suspension-enforcement trigger: `User.IsAccountSuspended()` is checked everywhere already, but no live
  path calls `User.Suspend()` yet, so there is nothing to end-to-end test for that trigger in this module.
- Multi-instance/backplane behavior: explicitly out of scope; nothing in this module's evidence attempts to
  test a two-process deployment, since one is not supported yet.
- E2E spec self-cleanup: the spec does not remove its own test lobby afterward; owner-tracked as P2, due
  before Module 14's CI work, not a blocker to this module's local completion.
- One-off release of the real `mohannad` account's pre-existing orphaned lobby-membership row: owner-
  authorized, local-dev-only, **not yet executed** as of this evidence; not part of this module's shipped
  code and not a blocker to this module's local completion.
- Positive security-event logging depth (**M07-006**) and the out-of-scope outbox fix's deep review
  (**M07-007**): both open, non-blocking Info findings, tracked in the security audit rather than resolved
  here.
- A single, authoritative "everything re-run together, right now" combined backend unit+integration count
  does not exist in this module's evidence; see the note in Coverage Result.
- Hosted CI, container build, and staging deployment: explicitly out of scope for this module, owned by
  Module 14.

## Final Status
Module 7's backend, both security review phases, frontend, and live-stack verification are all complete and
pass on their own evidence: 962/962 backend unit tests (`operations.json`), zero unwaived Critical/High
security findings across two review phases with every Medium/Low finding fixed and regression-tested,
264/264 frontend Vitest tests with `DRIFT=0` contract alignment, and a live no-mock E2E pass with a clean
accessibility scan — reached only after a real fix-and-rerun loop that caught one genuine domain bug and two
genuine accessibility defects, not a first-attempt pass. That is the honest, complete picture of the
module's **functional** readiness.

Its **process** evidence has a real, disclosed gap: the formal ordered stage-checkpoint chain
(`docs/ai-workflow/evidence/checkpoints/module-07-realtime-presence-chat/index.json`) has only the
`planning` stage registered — 1 of 8 possible stages. The root cause is that the backend security-review
stage ran on Sonnet 5 instead of the manifest-routed Opus for that assurance-sensitive stage, which meant it
could not be formally chained in; every later stage (frontend-security, verification) inherited the same
"cannot chain onto a missing prior index" condition as a result. This is recorded in
`production-review.json`'s `ownerDecisions.formalCheckpointChain`: the project owner **explicitly waived**
backfilling that ordered chain for Module 7. The underlying `security.json`, `frontend-security.json`, and
`verification.json` checkpoint files themselves exist, are internally valid, and record real, passing
evidence — what is missing is only their ordered registration in `index.json`, a process/tooling gap, not a
claim that the underlying work did not happen or did not pass.

Two further items are owner-tracked follow-ups, explicitly **not** blockers to this push: the E2E spec's own
lack of self-cleanup (P2, scheduled before Module 14's CI work), and the scoped, owner-authorized, local-dev-
only release of the real `mohannad` account's pre-existing orphaned lobby-membership row, which as of this
evidence has not yet been executed and is not part of this module's shipped code.

Taken together: Module 7 is **functionally, locally complete**. `releaseEligible` stays **false** regardless
of the process waiver above, pending Module 14's CI/container/staging foundation — this module was never
claimed as release-eligible on its own, and nothing in this report should be read as changing that.

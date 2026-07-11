# Testing Report - Module 05: Game Hosting Architecture

## Test Strategy
Every test name/namespace contains `GameHost` so the whole suite runs under one filter:
`dotnet test --filter "FullyQualifiedName~GameHost"`. Because Module 5 is a pure, deterministic library with
no HTTP or database surface, the strategy leans on unit and property-style tests (100 repeated determinism
runs, fixed-seed RNG checks, serializer fail-closed cases) plus a small integration layer that exercises the
exact in-process boundary Module 8 will call, a startup-time catalog-compatibility check, a no-EF-delta
assertion, and a two-process golden-vector hash comparison in place of browser E2E.

## Coverage Target
90%+ meaningful module coverage (advisory target, not a guarantee).

## Coverage Result
Percentage coverage was not collected this session; pass/fail counts and the explicit test list below are the
verified evidence. The `[SimPle.Domain]SimPle.Domain.GameHost.*` line was removed from
`coverage.unit.runsettings` specifically so this module's real logic (PCG32, envelopes) is included in future
coverage runs rather than excluded by stale tooling config.

## Commands Run
- `dotnet build SimPLe.Backend/SimPle.sln` — 0 errors, 0 warnings (full-solution, re-confirmed at the backend,
  verification, and this docs-authoring pass).
- `dotnet test --filter "FullyQualifiedName~GameHost"` — **189/189 passed** (177 unit + 12 integration),
  confirmed at both the backend and verification checkpoints.
- `dotnet test SimPLe.Backend/SimPle.sln --filter "FullyQualifiedName~GameHost"` run in **two independently
  launched processes** (the D3 cross-process determinism proof) — both passed 189/189; the recorded
  `golden-vector-manifest.generated.json` was byte-identical between the two runs across all 10 vector
  hashes.
- Full solution suite (unaffected by Module 5, recorded for context): 589/589 unit passing, 231 integration
  passed / 52 skipped (the pre-existing real-Postgres group, which skips without a live database — Module 5
  adds no database test).
- `node scripts/check-contract-drift.mjs` — `DRIFT=0`, 64 backend routes, 52 unique frontend calls, unchanged
  from Module 4's checkpoint, confirming Module 5 introduces no route or client-call surface.
- `grep -rniE "BinaryFormatter|SoapFormatter|NetDataContractSerializer|LosFormatter|ObjectStateFormatter"
  --include=*.cs SimPLe.Backend/src` (excluding tests) — zero hits, run during the security review.

## Unit Tests
`SimPLe.Backend/tests/SimPle.UnitTests/GameHost/` — 177 tests passing, covering:
- Registry (`GameRegistryTests`): `TryResolve` hit/miss, duplicate-key startup failure, no latest-version
  fallback on an unknown `engineVersion`.
- Non-generic adapter boundary (`HostedGameDefinitionAdapterTests`).
- Metadata validation (`GameDefinitionMetadataTests`), envelopes (`GameStateEnvelopeTests`,
  `GameCommandEnvelopeTests`, `PlayerViewEnvelopeTests`), transitions (`EngineTransitionTests`), contexts
  (`GameHostContextsTests`), and all 13 `EngineErrorCode` values (`EngineErrorCodeTests`).
- Determinism: pure-input non-mutation and 100 repeated determinism runs against the `HiddenTokenDraft`
  reference definition.
- RNG (`Pcg32Tests`): pinned against the **published PCG32 reference vector** for `srandom(42, 54)`
  (`0xa15c02b7, 0x7b47f409, ...`) rather than the implementation's own prior output, so a refactor that stays
  internally self-consistent but drifts from the published reference is still caught. RNG-advances-only-on-
  accept and stale/repeated command handling are also covered.
- Hidden-view non-interference: a private hand never appears in another seat's or the spectator's projection.
- Size limits (`EngineLimitsTests`): payload/state/view/event batch, player count, event count.
- Cancellation at each loop boundary and the timeout-to-`Engine.ExecutionBudgetExceeded` mapping
  (`GameHostInvokerTests`).
- Terminal-result stability and replay.
- Serializer fail-closed cases (`GameHostJsonContextTests`): CLR `$type`/`$id` gadget, unknown/renamed
  discriminator, cross-definition discriminator, out-of-order/duplicate discriminator, and a
  trailing-bytes/second-JSON-document payload — each returns the typed error rather than activating a type
  or partially materializing state.
- Golden vectors (`GoldenVectors/GoldenVectorTests`, `GoldenVectorManifestTests`): initial envelope, accepted/
  rejected commands, every seat + spectator view, terminal result, corrupt checksum, unsupported version — 10
  committed language-neutral JSON vectors.
- Benchmark (`Benchmark/GameHostBenchmarkTests`, deviation D3): the 10,000-command reference workload after
  warm-up, recording p50/p95/p99, allocations, and sizes via an in-repo Stopwatch harness.
- Catalog validator core (`CatalogEngineCompatibilityValidatorTests`): matching/mismatched `CatalogGameSnapshot`
  fixtures per deviation D1.
- Reference engine correctness (`Reference/HiddenTokenDraftDefinitionTests`).

One real bug was found by a test and fixed in product code during this module's implementation:
`PlayerViewEnvelope.Create` originally set the private projection with a ternary
(`hasPrivateView ? privateView.ToArray() : null`). Because `ReadOnlyMemory<byte>` has an implicit conversion
from `byte[]` and `null` also converts to `byte[]`, the conditional's natural type resolved to
`ReadOnlyMemory<byte>` — so the null branch produced an **empty** memory that then lifted to `HasValue =
true`. A spectator's `PrivateView` came back present-but-empty instead of absent, and any downstream
`is not null` check would have misread that as "this viewer has private data." Fixed by replacing the
ternary with a plain typed assignment (a cast alone would not have fixed it). Caught by
`PlayerViewEnvelopeTests.Create_ForASpectator_YieldsOnlyThePublicProjection`.

## Integration Tests
`SimPLe.Backend/tests/SimPle.IntegrationTests/GameHost/` — 12 tests passing, covering:
- **M8 boundary** (`GameHostCompositionRootTests`): boots the real `SimPle.Api` composition root, resolves
  `IGameHostInvoker`/`IGameRegistry` via DI, and plays a full match lifecycle through the DI-resolved
  invoker. Also covers the zero-registered-engines boot case.
- **Catalog validation** (`GameHostCatalogValidationStartupTests`): a matched/compatible catalog row boots
  the host normally; a drifted row (extra mode, wider player bounds) fails the host closed at startup.
- **No-EF-delta** (`GameHostNoEfDeltaTests`): asserts the real `AppDbContext` EF model has no GameHost entity
  type/`DbSet`, and the committed `Migrations/` directory has no GameHost migration.
- **Serializer hardening** (`GameHostSerializerHardeningTests`): the out-of-order-discriminator payload
  exercised through the DI-resolved `IGameHostInvoker` boundary, not just the codec in isolation.

New test infrastructure: `GameHostTestWebApplicationFactory` (mirrors the existing `Auth/
TestWebApplicationFactory` pattern), adding an `IGameRegistry` override and an `OpenDbContext()` escape hatch
to seed the shared-by-name InMemory database *before* `WebApplicationFactory` triggers host build — necessary
because `Program.cs`'s catalog-compatibility check runs during host construction, before any post-boot
DI-resolved seeding would be visible to it.

## Security/Authorization Tests
Covered above under serializer fail-closed cases and the M8-boundary/catalog-validation integration tests.
There is no HTTP authorization surface to test directly (Module 5 has no controller), so the security review
(`--security=asvs-lite`) instead independently verified all 11 threat-table controls from the spec against
source with file:line evidence — client authority/actor-seat spoofing, illegal commands, hidden-state/seed
disclosure, unsafe deserialization, type/plugin confusion, replay, state/payload bombs, algorithmic
exhaustion, exception leakage, checksum misuse, and plugin trust — plus 3 extra ASVS-lite checks (startup
fail-fast, the `PlayerViewEnvelope` null/empty fix above, no HTTP/DB coupling in the GameHost tree). Zero
unwaived Critical/High/Medium findings; 1 Low + 2 Info recorded and deferred (see `api-reference.md`'s
Security Considerations section and the canonical audit at
`SimPle.Project/docs/security/audits/module-05-game-hosting-architecture.md`).

## Frontend Tests If Applicable
- Existing UI reused: not applicable — no frontend file is touched.
- Frontend integration points tested: not applicable.
- Visual changes made: none.

## Realtime Tests If Applicable
Not applicable — Module 5 has no SignalR/WebSocket dependency.

## Database/Migration Checks
- Existing database impact: none.
- Migration added: no.
- Migration safety notes: not applicable.
- Data preservation notes: not applicable — `GameHostNoEfDeltaTests` proves the EF model snapshot and
  migration inventory are unchanged, which is the module's actual contract in place of a real-PostgreSQL test
  pass (real-PostgreSQL verification is recorded `not_applicable` by design, not skipped as a gap).
- Destructive DB changes: none.

## Backend/API/Swagger Alignment
Not applicable — no controller, route, or Swagger entry exists for this module.

## Frontend/API Integration Alignment
Not applicable — `check-contract-drift.mjs` confirms 0 new routes and 0 new frontend calls (64/52, unchanged
from Module 4's own checkpoint counts).

## Edge Cases Tested
Duplicate/unknown registration at startup; explicit old/new engine version selection with no latest-fallback;
unsupported state schema; corrupt checksum; malformed/trailing/unknown JSON; every discriminator-confusion
variant (CLR `$type`/`$id` gadget, unknown, renamed, cross-definition, out-of-order/duplicate); NaN/overflow
in numeric fields; oversized payload/state/view/event batch; wrong game slug; command-id repeat; stale/future
revision; illegal actor/seat/turn; hidden/spectator view isolation; a rejected command preserving prior bytes
and RNG state; a terminal command; result replay; fixed-seed replay; cancellation at each loop boundary;
execution-budget timeout; a plugin exception; catalog mismatch (zero/matching/mismatched product
definitions); host restart from a golden envelope; and process-to-process golden-vector hash stability.

## Bugs Found During Testing
The `PlayerViewEnvelope.Create` null-vs-empty spectator-projection bug described under Unit Tests above — the
only product-code bug found and fixed during this module's test-writing.

## Fixes Made After Test Failures
`PlayerViewEnvelope.Create`'s private-projection assignment was changed from a ternary expression (whose
natural type silently coerced `null` into an empty `ReadOnlyMemory<byte>`) to a plain typed assignment, so a
spectator's `PrivateView` correctly reports absent (`HasValue: false`) rather than present-but-empty.

## Remaining Untested/Deferred Items
- Coverage percentage was not measured this session (pass/fail counts only, per the STYLE guide's advisory-
  target framing).
- In-process isolation for hostile plugins remains an explicit non-goal and documented residual risk — the
  execution budget and code review are the only guards, not a sandbox.
- Speculative schema upcaster chains are deferred until a real prior golden vector and an ADR justify one.
- Browser E2E is recorded `not_applicable` — Module 5 has no browser surface; the two-process
  `dotnet test --filter "FullyQualifiedName~GameHost"` run is the manifest-mandated substitute and has been
  executed and passed as described above.

## Final Status
All Module 5 test evidence needed for the `docs` stage checkpoint is verified and consistent across the
backend, security, and verification checkpoints: 189/189 `GameHost`-filtered tests (177 unit + 12
integration) passing, byte-identical two-process golden-vector hashes across all 10 vectors, benchmark
acceptance criteria met with wide margin (p95 = 0.0293 ms against a < 25 ms budget; max single-command
latency = 12.1803 ms against a <= 100 ms soft budget), zero unwaived Critical/High/Medium security findings,
and a proven no-EF-model/migration-delta state. Production review and canonical final evidence remain
outstanding — see `docs/ai-workflow/project-state.md` for the next action.

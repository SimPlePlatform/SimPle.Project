# API Reference - Module 05: Game Hosting Architecture

## Overview
- Existing UI reused: Not applicable — Module 5 has no browser surface. It ships no page, component, or
  route change; Module 4's catalog UI (including its honestly-disabled Play/Quick-Match/Invite/Create-Lobby
  actions) is untouched.
- Frontend integration points: Not applicable — no frontend package is touched. `check-contract-drift.mjs`
  reports the same route/call counts before and after this module (64 backend routes, 52 unique frontend
  calls), confirming zero new client-facing surface.
- Existing database impact: None. Module 5 adds no EF entity, `DbSet`, table, JSONB column, or migration.
  `GameHostNoEfDeltaTests` asserts the live `AppDbContext` model has no GameHost entity type and the
  committed `Migrations/` directory has no GameHost migration.

## Base Route / Route Group
Not applicable — Module 5 exposes no HTTP route, controller, or SignalR hub. It is an internal, in-process
plugin contract consumed by code, not by network callers. The registration surface below is a compiled-in
composition-root wiring, not a route group.

## Authentication And Authorization Requirements
Not applicable at the HTTP layer — there is nothing to authenticate against. Authority is enforced one layer
up: `GameCommandEnvelope` carries a server-bound actor user id and seat that the future match host (Module 8)
derives from authenticated session membership; Module 5's own contracts never read or trust a client-supplied
actor/seat field, and no envelope type accepts one from request input.

## Endpoint Summary Table
Not applicable — no HTTP endpoints exist. The table below documents the internal, non-generic host boundary
that a future in-process caller (Module 8) uses instead of an HTTP client.

| # | Boundary member | Purpose | Caller | Notes |
|---|---|---|---|---|
| 1 | `IGameRegistry.TryResolve(slug, engineVersion)` | Resolve a registered game definition by immutable key | In-process (Module 8) | Typed hit/miss; an unknown `engineVersion` never falls back to the latest version |
| 2 | `IHostedGameDefinition.CreateInitialState(setup)` | Build the initial `GameStateEnvelope` from one server-supplied 128-bit seed | In-process | Seed is split into `PCG32-v1` `initstate`/`initseq`; commands never supply or reset it |
| 3 | `IGameHostInvoker.ApplyCommand(state, command)` | Validate and apply one command inside size/budget/redaction guards | In-process | Returns `EngineTransition`; a rejection carries no next state, no events, no revision advance |
| 4 | `IGameHostInvoker.ProjectView(state, viewer)` | Produce a viewer-specific `PlayerViewEnvelope` | In-process | Spectators receive only the explicit spectator projection, never a default full-state serialization |
| 5 | `IHostedGameDefinition.EvaluateResult(state)` | Return the immutable terminal-result candidate once state is `Terminal` | In-process | Same candidate every call; "exactly once" delivery is Module 8's responsibility, not Module 5's |
| 6 | `ICatalogEngineCompatibilityValidator.Validate(...)` | Compare every registered product definition's metadata against a `CatalogGameSnapshot` derived from Module 4's catalog | Application startup | Zero product engines is a valid Phase 1 state; a mismatch fails startup, not a request |

## Endpoints
Not applicable — there are no HTTP endpoints to document per-route. The boundary members above are the
closest equivalent; each is a plain C# method call, not a network request, and none has a status code, a
route template, or a Swagger entry.

## Data Models / DTOs
These are internal wire contracts (not HTTP DTOs), all under `SimPLe.Backend/src/SimPle.Domain/GameHost/`
unless noted:

- `GameDefinitionMetadata` — `slug`, `engineVersion` (positive int), `stateSchemaVersion` (positive int),
  `minPlayers`/`maxPlayers` (1–8), supported modes (validated against Module 4's
  `GameCatalogAllowLists.Modes` rather than a parallel allow-list), and capability flags (hidden-information,
  spectator-view, AI, timer, ranked, deterministic-replay).
- `GameStateEnvelope` — game slug, engine version, state schema version, revision, RNG algorithm/version,
  server-only `Pcg32State` seed/cursor, serialized state bytes, and a SHA-256 checksum computed over those
  exact bytes. The checksum is an integrity check, not an authenticity or authorization control.
- `GameCommandEnvelope` — command UUID, expected revision, server-bound actor user id and seat (never
  populated from client-controlled input in Module 5's own contracts), a stable command discriminator, and
  the serialized payload.
- `EngineTransition` (non-generic; the shape Module 8 consumes) and `EngineDecision` (typed; what a
  definition returns internally) — accepted flag, stable client-safe rejection code/details, prior/next
  revision, next state envelope when accepted, versioned public/private game events, and an optional
  terminal candidate. Both types enforce in their constructors that a rejection carries no next state, no
  events, and no revision advance.
- `PlayerViewEnvelope` — revision, viewer role/seat, public projection, an optional authorized private
  projection, and a view schema version.
- `TerminalResultCandidate` — the immutable terminal-result payload `EvaluateResult` returns once
  `EngineState` is `Terminal`.
- `EngineState` — enum `InProgress | Terminal` only; Module 5 does not model the fuller
  `Created/Active/Paused/Completed/Aborted` match lifecycle, which belongs to Module 8.
- `EngineLimits` (`SimPLe.Backend/src/SimPle.Domain/GameHost/EngineLimits.cs`) — the hard caps as named
  constants: command payload ≤ 16 KiB, serialized state ≤ 256 KiB, player/spectator view ≤ 256 KiB, game-event
  batch ≤ 64 KiB, at most 8 players, at most 128 emitted events per command; soft execution budget 100 ms,
  cancellation requested at 500 ms, +50 ms cooperative grace period.
- `CatalogGameSnapshot` (`SimPLe.Backend/src/SimPle.Application/GameHost/Services/CatalogGameSnapshot.cs`) —
  the minimal slug/player-bounds/modes shape the compatibility validator compares against; a composition-root
  adapter maps Module 4's real `Game` aggregate into this snapshot rather than the validator depending on
  `Game` directly (documented deviation D1 in the reconciliation ledger).

## Error Format
Not applicable as an HTTP error envelope — there is no response body format because there is no response.
Failures instead surface as one of 13 stable `EngineErrorCode` values (`Engine.UnknownGame`,
`Engine.UnknownVersion`, `Engine.UnsupportedStateVersion`, `Engine.CorruptState`,
`Engine.InvalidCommandType`, `Engine.InvalidCommand`, `Engine.IllegalActor`, `Engine.StaleRevision`,
`Engine.PayloadTooLarge`, `Engine.StateTooLarge`, `Engine.Cancelled`, `Engine.ExecutionBudgetExceeded`,
`Engine.PluginFailure`), each carried on the boundary return type rather than thrown as an unmapped
exception. `GameHostInvoker` maps any plugin exception to `Engine.PluginFailure` and logs the mapped code,
duration, and sizes — never the exception object's message/stack, state bytes, command payload, seed/RNG
state, or hidden projection.

## Security Considerations
- **Allow-listed, fail-closed serialization.** The codec (`GameHostJsonContext`, UTF-8 `System.Text.Json`)
  uses a pinned resolver, allow-listed string `JsonDerivedType` discriminators,
  `UnknownDerivedTypeHandling.FailSerialization`, `IgnoreUnrecognizedTypeDiscriminators` disabled,
  `AllowOutOfOrderMetadataProperties` disabled, and rejects unknown members on command/state input. No
  `BinaryFormatter`, `SoapFormatter`, `NetDataContractSerializer`, `LosFormatter`, or `ObjectStateFormatter`
  is referenced anywhere in `src/` (confirmed by grep during the security review). A CLR `$type` gadget
  payload, an unknown/renamed discriminator, and a cross-definition discriminator each fail closed with a
  typed error rather than activating a type.
- **Type/plugin confusion.** The non-generic `HostedGameDefinition` adapter deserializes only the concrete
  state/command/view types supplied by its own registered typed definition; it never resolves a CLR type
  name from input and never uses reflection-based arbitrary activation.
- **Size and execution budget enforcement.** `GameHostInvoker` checks payload/state/view/event-batch sizes
  both before and after every definition call, and enforces the 100 ms soft / 500 ms cancel / +50 ms grace
  execution budget via cooperative cancellation.
- **Plugin trust boundary (residual risk, documented not mitigated).** Only reviewed assemblies compiled
  into the application may register a definition — no upload, filesystem discovery, reflection scan of
  arbitrary assemblies, Roslyn scripting, JavaScript execution, or external plugin process is accepted.
  Trusted in-process code cannot be hard-preempted; a plugin that ignores its cancellation token is a release
  blocker caught by test/review, not a runtime-recoverable condition.
- **Startup fail-fast.** A duplicate `(slug, engineVersion)` registration and a catalog/engine capability
  mismatch both fail application startup rather than surfacing at call time; zero registered product engines
  is an intentionally valid Phase 1 startup state.
- Independent `--security=asvs-lite` review recorded 3 non-blocking findings, zero unwaived Critical/High/
  Medium: full plugin exception objects are logged server-side (Low, defense-in-depth only — every engine is
  trusted compiled-in code today), `[JsonPolymorphic]` fail-closed handling is configured per-attribute
  rather than solution-wide (Info), and `state.StateBytes` has no explicit size pre-check immediately before
  deserialization on the `ApplyCommand`/`ProjectView` path specifically, though creation-time and post-call
  size enforcement elsewhere still bounds it (Info). See
  `SimPle.Project/docs/security/audits/module-05-game-hosting-architecture.md`.

## Related Tests
- Unit (`SimPLe.Backend/tests/SimPle.UnitTests/GameHost/`): registry, adapter, metadata, all 13 error codes,
  pure-input non-mutation, 100 repeated determinism runs, RNG-advances-only-on-accept, stale/repeat command
  handling, hidden-view non-interference, every size limit, cancellation at each loop boundary, terminal
  result stability/replay, and serializer fail-closed cases (`GameHostJsonContextTests`,
  `GoldenVectors/GoldenVectorTests`, `Pcg32Tests`, `PlayerViewEnvelopeTests`, `GameHostInvokerTests`,
  `CatalogEngineCompatibilityValidatorTests`, plus the `HiddenTokenDraftDefinitionTests` reference-engine
  suite).
- Integration (`SimPLe.Backend/tests/SimPle.IntegrationTests/GameHost/`): `GameHostCompositionRootTests` (the
  exact M8 boundary through the real DI container), `GameHostCatalogValidationStartupTests` (matched/
  mismatched/zero-engine catalog startup), `GameHostNoEfDeltaTests` (no EF model/migration delta),
  `GameHostSerializerHardeningTests` (fail-closed discriminator/gadget cases through the DI-resolved
  invoker).
- Golden vectors (`GameHost/GoldenVectors/`): 10 committed language-neutral JSON vectors covering initial
  envelope, accepted/rejected commands, every seat + spectator view, terminal result, corrupt checksum, and
  unsupported version — SHA-256-identical across two independently launched `dotnet test` processes.

## Last Verified Command
`dotnet test SimPLe.Backend/SimPle.sln --filter "FullyQualifiedName~GameHost"` — see
`testing-report.md` for full pass counts and the two-process determinism run.

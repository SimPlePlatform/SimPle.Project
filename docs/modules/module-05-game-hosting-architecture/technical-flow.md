# Technical Flow - Module 05: Game Hosting Architecture

## Summary
Module 5 gives every future game a single, typed way to plug into SimPle without touching HTTP, the database,
or SignalR. A game author implements one interface — create the starting state, apply a command, show each
player their own view, and report when the match is over — and the platform handles the rest: safe
serialization, a deterministic random number generator, size limits, and startup checks that stop an
incompatible game from ever going live. Nothing here is reachable from a browser; it is the internal
rulebook-and-referee layer that Module 8 will call once real matches exist.

## Problem Solved
Before this module, the only "game hosting" code in the repository was three stub files that had never been
implemented, wired into dependency injection, persisted, or tested — an `object`-typed engine interface, a
premature match-lifecycle model, and a registry with no concrete implementation. Building Module 8 (match
rooms) or any Phase 2 game directly against that surface would have meant inventing serialization and
determinism rules ad hoc, per game, with no shared safety net. Module 5 replaces the stubs with one reviewed
contract so every future game gets the same guarantees for free: byte-for-byte determinism, a fail-closed
codec, hidden-state isolation, and enforced size/time budgets.

## Architecture Overview
Clean Architecture placement, mirroring Module 4's `Games` layout:

- **Domain (`src/SimPle.Domain/GameHost/`)** — pure contracts with zero dependency on Application,
  Infrastructure, Api, EF Core, HTTP, or SignalR: `IGameDefinition<TState,TCommand,TPlayerView>`,
  `GameDefinitionMetadata`, the envelope types (`GameStateEnvelope`, `GameCommandEnvelope`,
  `PlayerViewEnvelope`), `EngineTransition`/`EngineDecision`, `EngineErrorCode`, `EngineLimits`,
  `EngineState`, `GameEvent`, `TerminalResultCandidate`, `GameHostContexts`, and `Pcg32` (the `PCG32-v1`
  reference generator).
- **Application (`src/SimPle.Application/GameHost/`)** — host machinery with no HTTP/database dependency:
  `GameHostJsonContext` (the allow-listed codec), `HostedGameDefinition` (the non-generic adapter that is the
  exact boundary Module 8 will call), `GameRegistry` (`TryResolve(slug, engineVersion)`), `GameHostInvoker`
  (the size/budget/redaction boundary), and `CatalogEngineCompatibilityValidator` (compares registered
  engines against a Module-4-derived snapshot).
- **Api (`src/SimPle.Api/Program.cs`)** — the composition root: an explicit, currently empty product-engine
  registration list, plus a fail-fast startup check between `builder.Build()` and `app.Run()` that rejects a
  duplicate `(slug, engineVersion)` or a catalog/engine mismatch before the application starts serving
  traffic. Zero registered product engines is a valid, intentionally-supported Phase 1 state.

## Backend Flow
1. **Registration (startup).** The composition root in `Program.cs` builds a list of `IHostedGameDefinition`
   adapters (empty in Phase 1) and hands it to `GameRegistry`. Startup checks for duplicate `(slug,
   engineVersion)` keys and runs `CatalogEngineCompatibilityValidator` against every entry in Module 4's
   catalog; either failure stops the application from starting, never surfaces as a runtime error later.
2. **Resolution.** A future caller (Module 8) asks `IGameRegistry.TryResolve(slug, engineVersion)` for the
   adapter. An unknown or outdated version never silently falls back to the latest — it is a typed miss.
3. **Initial state.** The caller supplies one server-chosen, cryptographically random 128-bit match seed.
   `Pcg32` splits it into the reference PCG32 64-bit `initstate` and `initseq` (high 64 bits → `initstate`,
   low 64 bits → `initseq` — a normative split that must never change) and the adapter's
   `CreateInitialState` produces the first `GameStateEnvelope`, with the seed/cursor stored only in the
   server-only portion of that envelope.
4. **Command application.** `GameHostInvoker.ApplyCommand` checks the incoming command's size, deserializes
   it through the pinned, allow-listed codec, evaluates it inside the cooperative cancellation budget, checks
   outgoing sizes, and returns an `EngineTransition`. A rejection carries no next state, no events, and no
   revision advance — bytes and RNG state are untouched.
5. **Viewer projection.** `GameHostInvoker.ProjectView` produces a `PlayerViewEnvelope` scoped to one viewer's
   role/seat; spectators receive only the definition's explicit spectator projection, never a default
   full-state serialization.
6. **Terminal result.** Once `EngineState` is `Terminal`, `EvaluateResult` returns the same immutable
   `TerminalResultCandidate` on every call. Module 5 does not claim "exactly once" delivery — that is Module
   8's job once it persists a unique result/outbox row.

## Frontend Flow
Not applicable. Module 5 touches no file under `SimpLe.Frontend`. `check-contract-drift.mjs` reports the same
route/call counts as before this module (64 backend routes, 52 frontend calls), and Module 4's catalog UI —
including the honestly-disabled Play/Quick-Match/Invite/Create-Lobby actions naming their real owning modules
— is unchanged.

## Database/Domain Model Changes
- Existing database impact: none.
- Migration added: no.
- Migration safety notes: not applicable — no migration exists for this module.
- Data preservation notes: not applicable — Module 5 is deliberately pure/in-memory and persists nothing.
  `GameHostNoEfDeltaTests` asserts the live `AppDbContext` model has no GameHost entity/`DbSet` and the
  committed `Migrations/` directory has no GameHost migration, proving the intended no-delta state rather
  than assuming it.
- Destructive DB changes: none.

## API Contract
- Backend/API/Swagger alignment: not applicable — Module 5 adds no controller, route, or Swagger entry.
- Frontend/API integration alignment: not applicable — no frontend call exists to align against; see the
  contract-drift figures above.

## Validation And Error Handling
Every failure mode returns one of 13 stable `EngineErrorCode` values on the boundary return type rather than
throwing an unmapped exception: unknown game/version, unsupported state schema, corrupt checksum, invalid
command type/content, illegal actor, stale revision, oversized payload/state, cancellation, execution-budget
overrun, and a catch-all `Engine.PluginFailure` for any exception a definition throws. `GameHostInvoker` maps
every plugin exception to `Engine.PluginFailure` and logs only the mapped code, duration, and sizes — never
the exception's message/stack, state bytes, command payload, seed/RNG state, or hidden projection.

## Authorization And Security Decisions
Module 5 carries no authentication or authorization boundary of its own — there is no HTTP layer to enforce
one against. Instead it enforces the *contract* that keeps a future authorization boundary meaningful:
`GameCommandEnvelope`'s actor/seat fields are documented as server-bound and are never read from or trusted
against client-controlled input inside Module 5's own code (Module 8 is the layer that will derive them from
authenticated session membership). The codec is allow-listed and fail-closed (`UnknownDerivedTypeHandling.
FailSerialization`, no `BinaryFormatter`/`SoapFormatter`/`NetDataContractSerializer`/`LosFormatter`/
`ObjectStateFormatter` anywhere in `src/`, confirmed by grep during the security review), and the checksum on
`GameStateEnvelope` is explicitly documented as an integrity check, never an authenticity or authorization
control. Full findings: `SimPle.Project/docs/security/audits/module-05-game-hosting-architecture.md`
(`--security=asvs-lite`, zero unwaived Critical/High/Medium; 1 Low + 2 Info deferred, none blocking).

## Realtime/Socket.IO Flow If Applicable
Not applicable. Module 5 has no SignalR/WebSocket dependency; realtime transport is Module 7's concern and
Module 8 will be the caller that eventually sits between a hub and this module's boundary.

## State Management If Applicable
Not applicable on the frontend (no UI). On the backend, "state" is the `GameStateEnvelope` byte payload the
caller passes in and receives back — Module 5 holds no state of its own between calls; every boundary method
is a pure function of its inputs.

## Edge Cases Handled
Duplicate/unknown registration at startup; explicit old/new engine version selection with no latest-fallback;
unsupported state schema; corrupt checksum; malformed/trailing/unknown JSON; discriminator confusion
(unknown, renamed, cross-definition, out-of-order/duplicate, and CLR `$type`/`$id` gadget payloads — each
fails closed with a typed error rather than activating a type or partially materializing state);
oversized payload/state/view/event batch; wrong game slug; stale/future/repeated command revisions; illegal
actor/seat; hidden/spectator view isolation (a private hand never appears in another seat's or the
spectator's projection — the earlier `PlayerViewEnvelope` null-vs-empty bug described below is exactly this
class of edge case); rejected commands preserving prior bytes and RNG state; terminal-result stability and
replay; cancellation at bounded loop checkpoints and the timeout-to-`Engine.ExecutionBudgetExceeded` mapping;
plugin exceptions; catalog mismatch (zero/matching/mismatched product definitions); and process-to-process
golden-vector hash stability.

## Design Tradeoffs
- **Typed generic contract + non-generic adapter, not one interface.** `IGameDefinition<TState,TCommand,
  TPlayerView>` lets a game author write fully typed rules code, while `HostedGameDefinition` erases the
  generic parameters behind one boundary Module 8 can call without knowing every game's concrete types. The
  cost is one extra layer of indirection per call; the benefit is that Module 8 never needs a generic method
  or reflection to reach an arbitrary game.
- **In-repo Stopwatch benchmark, not BenchmarkDotNet (deviation D3).** The brief required a fixed-workload
  benchmark but not a specific tool. A minimal Stopwatch harness avoids a new package dependency; the
  tradeoff is a less statistically rigorous measurement than a dedicated benchmarking library would give, so
  results are read as pass/fail against the 25 ms p95 / 100 ms soft-budget acceptance line, not as
  publication-grade percentile science.
- **Catalog-compatibility validator takes a minimal snapshot, not Module 4's `Game` aggregate directly
  (deviation D1).** Depending on `Game` directly would have coupled Module 5's unit tests to Module 4's
  construction invariants just to build mismatched fixtures. A thin `CatalogGameSnapshot` plus a
  composition-root adapter keeps the validator's core testable in isolation while still comparing against
  Module 4's real slug/player-bounds/capability metadata at the only place it matters — application startup.
- **In-process trust, not sandboxing, for plugins.** Only compiled-in, reviewed assemblies may register a
  definition; there is no filesystem discovery, reflection scan, scripting, or external process. This is
  cheaper and simpler than a real sandbox but means a plugin that ignores its cancellation token cannot be
  hard-preempted — the execution budget and code review are the only guards, and an offending plugin is
  documented as a release blocker, not a runtime-recoverable condition.

## Files Changed And Why
- `src/SimPle.Domain/GameHost/*.cs` (13 new files) — the pure contracts: metadata, envelopes, transition/
  decision types, error codes, limits, state enum, events, contexts, and the `PCG32-v1` generator. Zero
  infrastructure dependency so any future game author can implement against Domain alone.
- `src/SimPle.Application/GameHost/Serialization/GameHostJsonContext.cs` and
  `Services/{GameRegistry,HostedGameDefinition,GameHostInvoker,CatalogEngineCompatibilityValidator,
  CatalogGameSnapshot}.cs` plus their interfaces — the host machinery: the allow-listed codec, the registry,
  the non-generic adapter, the size/budget/redaction boundary, and catalog compatibility.
- `src/SimPle.Application/DependencyInjection.cs`, `src/SimPle.Api/Program.cs` — composition-root wiring and
  the startup fail-fast check (duplicate key, catalog mismatch), placed between `builder.Build()` and
  `app.Run()` alongside the existing `--seed-game-catalog` branch.
- `src/SimPle.Domain/GameHost/IGameEngine.cs`, `GameSession.cs` — **deleted**. Zero real references existed
  (confirmed by full-solution grep during planning); `Lobby.GameSessionId` is a bare `Guid` with no type
  dependency and `NotificationKind.MatchResult` is an unrelated enum member, both left untouched.
- `src/SimPle.Application/GameHost/Services/IGameRegistry.cs` — **rewritten** from `GetEngine(string)` (with
  an implicit latest-version fallback) to `TryResolve(slug, engineVersion)` with no fallback, per the brief's
  mandatory legacy-stub disposition table.
- `coverage.unit.runsettings` — removed the stale `[SimPle.Domain]SimPle.Domain.GameHost.*` coverage
  exclusion so Module 5's real logic (PCG32, envelopes) is actually measured; the adjacent
  `SimPle.Domain.Games.*` exclusion (Module 4's concern) was left alone.
- `tests/SimPle.UnitTests/GameHost/**`, `tests/SimPle.IntegrationTests/GameHost/**` — the full unit/
  integration suite described in `testing-report.md`, including the test-only `HiddenTokenDraft` reference
  engine and 10 committed golden-vector JSON files.

## How To Read The Implementation
Start at `src/SimPle.Domain/GameHost/IGameDefinition.cs` to see the four methods a game author implements,
then `tests/SimPle.UnitTests/GameHost/Reference/HiddenTokenDraftDefinition.cs` for a complete, if minimal,
worked example (2–4 seats, a shuffled token deck, private hands, draw/pass commands). From there,
`src/SimPle.Application/GameHost/Services/HostedGameDefinition.cs` shows the non-generic adapter boundary,
and `GameHostInvoker.cs` shows the size/budget/redaction guards wrapped around every call into it. Program.cs
around the `--seed-game-catalog` branch shows the startup fail-fast wiring. The golden vectors under
`tests/SimPle.UnitTests/GameHost/GoldenVectors/` are the most compact end-to-end illustration of what a real
match's envelope bytes look like.

## Future Improvements / Deferred Items
- A concrete state-schema upcaster is deferred until a real prior golden vector and an ADR justify one;
  speculative upcaster chains were explicitly out of scope for this module.
- In-process isolation for plugins remains a documented residual risk, not a control — process-level sandboxing
  for hostile plugins was an explicit non-goal.
- The catalog registry's Phase 2 slug conflict (`tetris-arena`/`connect-four`/`wordle-with-friends` versus the
  Module 4 brief's neutral replacement slugs) is a carried-forward open item from Module 4; it does not block
  Module 5, but Module 5's `(slug, engineVersion)` keys for future Phase 2 engines must use the resolved
  neutral slugs once that conflict is settled.
- Module 8 (match rooms) is the first real consumer of this module's boundary and will be the module that
  turns the `not_applicable` browser-E2E status into an actual player-facing flow.

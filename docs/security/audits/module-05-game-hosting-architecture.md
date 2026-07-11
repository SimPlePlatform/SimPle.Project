# Security Audit - Module 05: Game Hosting Architecture

Date: 2026-07-11

## Scope

Backend-only review of the Module 5 typed game-host contract layer: `src/SimPle.Domain/GameHost/`
(pure contracts, envelopes, `PCG32-v1` RNG), `src/SimPle.Application/GameHost/Serialization/`
(allow-listed `System.Text.Json` codec) and `Services/` (`GameRegistry`, `HostedGameDefinition`
adapter, `GameHostInvoker`, `CatalogEngineCompatibilityValidator`), DI wiring in
`src/SimPle.Application/DependencyInjection.cs`, and the composition-root fail-fast check in
`src/SimPle.Api/Program.cs` (between `builder.Build()` and `app.Run()`). No HTTP route, SignalR hub,
EF entity/table/migration, or product game engine exists in this module; zero engines are registered
in production DI (`Program.cs:81`, `Array.Empty<IHostedGameDefinition>()`) — the intentionally
supported Phase 1 state.

## Assessment Type
ASVS-lite + OWASP API input/resource-consumption checks (brief-mandated minimum depth for Module 5;
see `docs/module-requirements/module-05-game-hosting-architecture.md` and
`docs/specs/module-05-game-hosting-architecture-spec.md`'s Security Threat Checklist).

Review phase: backend

## Authorization Statement
Local authorized project-only review. No external systems, production services, real secrets, or real
user data were used.

## Executive Summary
Zero unwaived Critical/High/Medium findings. All 11 threat-table controls from the approved spec were
independently verified against the current source (not just the doc's claim), plus three extra
ASVS-lite checks (startup fail-fast, the previously-fixed `PlayerViewEnvelope` null/empty bug, and
absence of HTTP/DB coupling in the GameHost tree). Three non-blocking Info/Low observations were
recorded, none of which are exploitable given the module's trusted-compiled-in-plugin threat model.
Review combined an independent `security-reviewer` subagent pass with main-session spot verification
of the highest-stakes claims (banned-serializer grep, `EngineLimits` constants, the
`PlayerViewEnvelope` fix, and the `Program.cs` fail-fast wiring) by reading the primary source
directly.

## Severity Summary Table

| Severity | Count | Notes |
|---|---:|---|
| Critical | 0 | |
| High | 0 | |
| Medium | 0 | |
| Low | 1 | M05-001 |
| Info | 2 | M05-002, M05-003 |

## OWASP Mapping
- OWASP Top 10 web: A08:2021 Software and Data Integrity Failures (deserialization safety — verified
  controlled); A09:2021 Security Logging and Monitoring Failures (M05-001).
- OWASP API Security Top 10: API8:2023 Security Misconfiguration (input size/type allow-listing —
  verified controlled).
- WebSocket/Socket.IO checklist: not applicable — no realtime transport in Module 5.

## Methodology
Read-only source review (no product code changed). A `security-reviewer` subagent independently read
every file in scope and verified each row of the spec's threat-control table with file:line evidence,
plus three additional ASVS-lite checks. The orchestrating session then independently re-verified the
highest-stakes claims by reading `PlayerViewEnvelope.cs`, `EngineLimits.cs`, and the `Program.cs`
fail-fast block directly, and re-ran the banned-serializer grep across `src/` (excluding tests) —
zero hits for `BinaryFormatter`/`SoapFormatter`/`NetDataContractSerializer`/`LosFormatter`/
`ObjectStateFormatter`. No test suite was re-run this session (prior backend-checkpoint evidence
already covers 189/189 GameHost tests passing); this review is source-level, not a re-execution pass.

## Module Architecture Reviewed
- Existing UI reused: not applicable — no browser surface (`not_applicable` per brief).
- Frontend integration points: none.
- Existing database impact: none. `GameHostNoEfDeltaTests` (prior evidence) asserts zero EF entity/
  DbSet/migration delta; this review's grep of `src/SimPle.Application/GameHost` for `DbContext`
  confirms no direct coupling outside the `Program.cs` composition-root catalog read.
- Migration added: no.
- Migration safety notes: not applicable.
- Data preservation notes: not applicable.
- Destructive DB changes: none.
- Backend/API/Swagger alignment: not applicable — no public route.
- Frontend/API integration alignment: not applicable.

## Threat Model
See `docs/specs/module-05-game-hosting-architecture-spec.md` Security Threat Checklist (Step 3) for
the authoritative table; threats covered: client authority/actor-seat spoofing, illegal commands,
hidden-state/seed disclosure, unsafe deserialization, type/plugin confusion, replay, state/payload
bombs, algorithmic exhaustion, exception leakage, checksum misuse, and plugin trust. Combined with
`docs/security/threat-playbooks/game-engine-deserialization.md` (required local playbook for
Modules 5/8/9).

## Findings

### M05-001 - Plugin exception object logged in full server-side
- Severity: Low
- Affected asset: `src/SimPle.Application/GameHost/Services/GameHostInvoker.cs` (~line 198, the
  catch block that maps a thrown plugin exception to a redacted `PluginFailure` result)
- Description: the caught exception is passed whole to `LogError(inner, …)`. The client-facing
  result is correctly redacted (typed error code only), but a poorly written *trusted, compiled-in*
  definition could embed state/command bytes in an exception message, which would then land in
  server-side structured logs.
- How it could be exploited, written safely: not exploitable by an external actor — all definitions
  are trusted, compiled-in code reviewed before shipping (no upload/reflection/dynamic loading path
  exists per M05's plugin-trust control). This is a defense-in-depth gap against a *buggy* future
  first-party engine, not an attacker-controlled path.
- Evidence: `GameHostInvoker.cs:185-200` (subagent citation, independently spot-checked pattern by
  reading the surrounding catch/redact logic).
- Fix implemented: none (deferred, non-blocking).
- Verification after fix: not applicable.
- Residual risk: accepted. Recommend a future hardening pass (M8 or a GameHost follow-up) log only
  `inner.GetType().Name` plus the existing non-content metadata, not the full exception object, so a
  future engine bug can't leak state bytes into logs by accident.

### M05-002 - `[JsonPolymorphic]` fail-closed behavior is per-attribute, not global
- Severity: Info
- Affected asset: `src/SimPle.Application/GameHost/Serialization/GameHostJsonContext.cs`
- Description: `System.Text.Json`'s `UnknownDerivedTypeHandling.FailSerialization` is set per
  `[JsonPolymorphic]`-annotated type hierarchy, not as a solution-wide default. A future trusted game
  author who configures `FallBackToNearestAncestor` on their own command/state hierarchy would locally
  weaken the type/plugin-confusion control (#5 in the threat table) for that engine only.
- Evidence: current `GameHostJsonContext.cs` codec-level options confirmed fail-closed
  (`UnmappedMemberHandling.Disallow`, `NumberHandling.Strict`, no `IgnoreUnrecognizedTypeDiscriminators`,
  `AllowOutOfOrderMetadataProperties` disabled) — this finding is about a hypothetical future engine
  author's own type declarations, not the current codec.
- Fix implemented: none (informational; engines are trusted/reviewed code, not attacker input).
- Residual risk: accepted. Recommend adding this to the future engine-authoring guideline/checklist
  referenced by the brief (not a Module 5 code change).

### M05-003 - `state.StateBytes` not size-pre-checked before deserialize in `ApplyCommand`/`ProjectView`
- Severity: Info
- Affected asset: `src/SimPle.Application/GameHost/Services/HostedGameDefinition.cs`
- Description: incoming serialized state is deserialized before an explicit size check on that
  specific call path (size is enforced at state-creation time and after each mutating call, and the
  checksum-gate runs before deserialize).
- Evidence: `HostedGameDefinition.cs:145-148` (checksum gate precedes use); `GameHostInvoker.cs:37,67`
  (creation/post-call size enforcement per the threat-table row #7 verification).
- Fix implemented: none.
- Residual risk: accepted. State is server-authoritative and capped at 256 KiB at every point it is
  produced, so an oversized `StateBytes` value cannot originate from this module's own write path;
  this is a completeness note, not an exploitable gap, given M5's closed trust boundary.

## Fixed Issues Summary
None required this review — zero Critical/High/Medium findings.

## Deferred Issues
M05-001, M05-002, M05-003 (all Low/Info, see above; none block module completion per
`_shared-quality-baseline.md`'s "Critical or High verified findings block completion" rule).

## Tests/Security Checks Run
- Source-level verification of all 11 threat-table controls (client authority, illegal commands,
  hidden-state/seed disclosure, unsafe deserialization, type/plugin confusion, replay, state/payload
  bombs, algorithmic exhaustion, exception leakage, checksum misuse, plugin trust) — PASS on all 11.
- Extra ASVS-lite checks: startup catalog-compatibility fail-fast (PASS, `Program.cs:326-360`),
  `PlayerViewEnvelope` null-vs-empty spectator bug re-verified fixed (PASS, `PlayerViewEnvelope.cs:80-82`),
  no HTTP/DB coupling inside the GameHost Application tree (PASS).
- Solution-wide grep for banned serializers (`BinaryFormatter`/`SoapFormatter`/
  `NetDataContractSerializer`/`LosFormatter`/`ObjectStateFormatter`) in `src/` — zero hits.
- `EngineLimits.cs` constants independently read and confirmed to match the brief's hard defaults
  (16 KiB command / 256 KiB state / 256 KiB view / 64 KiB event batch / 8 players / 128 events).
- No test suite was re-executed this session; prior backend-checkpoint evidence
  (`docs/ai-workflow/evidence/checkpoints/module-05-game-hosting-architecture/backend.json`) already
  records 189/189 GameHost-filtered tests (177 unit + 12 integration) passing, including the
  serializer-hardening and no-EF-delta suites this review relied on as evidence.

## Files Changed
None — review-only, no `--fix` requested, no product code modified.

## Final Security Status
Backend phase: **CLOSED, zero unwaived Critical/High**. `securityGate`: unwaivedCritical 0,
unwaivedHigh 0, waivedCritical 0, waivedHigh 0, waiverReferences []. Post-frontend phase: not
applicable — Module 5 has no browser surface (per module-stage-manifest.json, only 6 checkpoint
stages apply to Module 5, with no `frontend-security` stage).

## Reviewer Notes
The pre-existing audit document at this path was a stale pre-implementation placeholder describing a
completely different planned architecture (on-demand Docker container provisioning, resource quotas,
network egress restrictions) that was never built — Module 5 was re-scoped during planning to a pure
in-process typed plugin-contract layer with no container/infrastructure surface at all. That
placeholder is superseded in full by this document. The container/Docker-provisioning risks it named
do not apply to what was actually implemented and are not carried forward as open items.

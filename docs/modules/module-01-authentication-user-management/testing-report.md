# Testing Report - Module 01: Authentication & User Management

## Test Strategy
Backend logic is covered by xUnit unit + integration tests (against an in-memory host via
`TestWebApplicationFactory`); frontend auth pages by Vitest + type/lint/build checks.

## Coverage Target
90%+ meaningful module coverage (advisory).

## Coverage Result
Implemented Auth scope (application services, validators, domain entities, infrastructure services,
controller, middleware, OpenAPI) measures **~95% line coverage**, using the `coverage.unit.runsettings` scope
that excludes EF migrations, unimplemented stubs, and DI bootstrapping. (Whole-backend coverage including
unimplemented modules would be ~25–30% and is not meaningful.)

## Commands Run
```powershell
cd backend
dotnet build
dotnet test tests/SimPle.UnitTests/SimPle.UnitTests.csproj --no-build
dotnet test tests/SimPle.UnitTests/SimPle.UnitTests.csproj --collect:"XPlat Code Coverage" --settings coverage.unit.runsettings --results-directory ./coverage-unit-scoped
```
`dotnet build`: 0 warnings, 0 errors.

## Unit Tests
100 unit tests: `PasswordHasherTests` (salts, PHC, verify, rehash), `TokenServiceTests` (JWT identity/expiry,
random refresh, deterministic hashes), `AuthServiceTests` (register conflicts, login errors, lockout,
suspension, rehash, refresh rotation/replay, logout/-all, current-user, email verification, password reset,
Google flows incl. email-verified check), `LoginRequestValidatorTests`, `GoogleTokenValidationServiceTests`,
`CaptchaVerificationServiceTests`, `UserEntityTests`, `SharedUtilityTests`. Module-1 finalization added
`AccountSecurityTests` (20 unit).

## Integration Tests
45 integration methods: HTTP status + cookie issuance for all 12 auth endpoints, CSRF enforcement, rate
limiting (429), refresh replay (401 + family revocation), logout/-all, safe user DTO (no hashes/tokens),
generic exception output, OpenAPI security scheme, DB token-ownership FKs + unique hash indexes. Finalization
added `AccountSecurityEndpointsTests` (14 integration: change-password/email, sessions list/revoke,
delete-account).

## Security/Authorization Tests
CSRF-header enforcement, rate-limit thresholds, refresh-replay family revocation, safe-output (no secret
leakage), suspension, and account-security ownership (a user cannot revoke another user's sessions) are all
covered above.

## Frontend Tests If Applicable
- Existing UI reused: yes (auth pages).
- Frontend integration points tested: `authApi`, auth provider, component-level auth logic (47 Vitest tests,
  5 files).
- Visual changes made: none.
```powershell
cd frontend
npx tsc --noEmit    # 0 errors
npm run lint        # 0 errors (a few pre-existing warnings in mock/profile files)
npm run build       # passes
```

## Realtime Tests If Applicable
Not applicable.

## Database/Migration Checks
- Existing database impact: foundational tables.
- Migration added: yes (`InitialAuth`, `AddGoogleOAuth`, account-security).
- Migration safety notes: token ownership FKs + unique hashed-token indexes; refresh rotation guarded by
  `xmin` optimistic concurrency.
- Data preservation notes: foundational.
- Destructive DB changes: none.

## Backend/API/Swagger Alignment
Development Swagger documents the cookie + CSRF workflow; OpenAPI security scheme covered by an integration
test.

## Frontend/API Integration Alignment
`authApi` in `lib/api-client.ts` matches documented routes/verbs.

## Edge Cases Tested
Register conflicts, generic login errors, lockout, suspension, rehash-on-login, refresh rotation + replay,
Google email-verified check, CAPTCHA fail-closed.

## Bugs Found During Testing
None recorded blocking; build clean.

## Fixes Made After Test Failures
None outstanding.

## Remaining Untested/Deferred Items
- Migrations not yet applied to a real PostgreSQL instance for these tests (integration uses an in-memory
  host); a full end-to-end browser smoke depends on a running PostgreSQL with `InitialAuth` + `AddGoogleOAuth`
  applied.
- Concurrent refresh rotation (two simultaneous requests, same token) not covered by an automated test —
  noted as a known risk in the security docs (guarded in code by `xmin`).

## Final Status
Backend green (100 unit + 45 integration; ~95% scoped coverage), frontend type/lint/build clean + 47 Vitest
tests. Real-PostgreSQL E2E smoke and the concurrent-rotation test remain. Locally verified + PR-ready, not
deployed.

# Auth Testing Report

Date: 2026-05-28

## Commands Run

```powershell
cd backend
dotnet build
dotnet test tests/SimPle.UnitTests/SimPle.UnitTests.csproj --no-build
dotnet test tests/SimPle.UnitTests/SimPle.UnitTests.csproj --collect:"XPlat Code Coverage" --settings coverage.unit.runsettings --results-directory ./coverage-unit-scoped
```

`dotnet build` passed with 0 warnings and 0 errors.

**Module 1 finalization (module-01-auth-finalization):** 120 unit tests, 59 integration
tests. Added `AccountSecurityTests` (20 unit) and `AccountSecurityEndpointsTests`
(14 integration) covering change-password, change-email, sessions list, session
revoke, and delete-account.

## What The Tests Cover

**Unit tests (100):**
- `PasswordHasherTests`: unique salts, PHC format, matching/failing verification, rehash detection.
- `TokenServiceTests`: JWT identity/expiry/validation, random refresh tokens, deterministic hashes.
- `AuthServiceTests`: register conflicts, login errors, configurable lockout, suspension check, password
  rehash, refresh rotation/replay, logout, logout-all, current-user mapping, email verification,
  password reset, Google OAuth flows including email-verified check.
- `LoginRequestValidatorTests`: empty fields, max length, CAPTCHA check.
- `GoogleTokenValidationServiceTests`: invalid/expired tokens handled without 500 errors.
- `CaptchaVerificationServiceTests`: server-side form submission and fail-closed handling.
- `UserEntityTests`: domain behaviour — lockout, suspension, initials, Google linking, etc.
- `SharedUtilityTests`: Result, Error, PagedResult, PaginationParams, shared DTOs.

**Integration tests (45 methods):**
- HTTP status codes and cookie issuance for all 12 auth endpoints.
- CSRF header enforcement.
- Rate limiting (429 after threshold).
- Refresh token replay detection (401 + family revocation).
- Logout and logout-all.
- Safe user DTO output (no hashes, no token values).
- Generic exception response (no internal detail).
- OpenAPI security scheme documentation.
- Database model — token ownership foreign keys and unique hash indexes.

## Coverage

Coverage measured with the `coverage.unit.runsettings` scoped runsettings file,
which excludes EF migrations, unimplemented domain stubs, and DI bootstrapping
from the denominator. The implemented Auth scope (application services, validators,
domain entities, infrastructure services, controller, middleware, OpenAPI) measures
approximately **95% line coverage**.

Full backend coverage including all unimplemented modules would be around 25–30%
and is not a useful number — those modules have no tests yet because they have no
implementation.

## Frontend Validation

```powershell
cd frontend
npx tsc --noEmit    # 0 errors
npm run lint        # 0 errors, a few existing warnings in mock/profile files
npm run build       # passes
```

Frontend unit/component tests use Vitest. The `src/__tests__/` folder contains
test files; run them with `npm test` or `npx vitest`.

## Remaining Test Gaps

- Migrations have not been applied to a real PostgreSQL instance; integration tests
  use an in-memory SQLite host via `TestWebApplicationFactory`.
- Concurrent refresh token rotation (two simultaneous requests with the same token)
  is not tested. This is noted as a known risk in the security docs.
- No end-to-end browser smoke test yet — requires a running PostgreSQL database
  with `InitialAuth` and `AddGoogleOAuth` migrations applied.

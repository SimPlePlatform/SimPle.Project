# Auth Security Audit

Date: 2026-05-28
Module version: `feature/auth-phase-1`

## Scope And Method

Source review, building the solution, running unit/integration tests, running
coverage, and checking the generated EF migrations. No external system was
attacked. Review covered: application service behaviour, token and password
infrastructure, API endpoints, cookie/auth middleware, database mapping,
email/verification flows, Google OAuth flow, security headers, and test suite.

## Controls Reviewed

| Control | Status |
|---|---|
| Argon2id hashing and fixed-time verification | Implemented and tested |
| JWT lifetime and refresh token hash storage | Implemented and tested |
| Refresh rotation and replay response | Implemented and tested |
| HttpOnly/SameSite/Secure cookie policy | Implemented; Secure outside development |
| CSRF header requirement | Implemented and tested |
| Login error safety and lockout | Implemented and tested |
| Account suspension enforcement | Implemented |
| Rate limiting per remote IP | Implemented and tested |
| Safe DTO/error responses | Implemented and tested |
| CORS | Explicit origin with credentials |
| Email verification token lifecycle | Implemented: hashed, single-use, 24h expiry |
| Password reset token lifecycle | Implemented: hashed, single-use, 1h expiry, revokes sessions |
| Google OAuth — JWKS validation + aud + email_verified | Implemented |
| Security response headers | Implemented: nosniff, no-frame, referrer, permissions, HSTS on HTTPS |
| CAPTCHA verification | Implemented server-side for login and register |
| Hardcoded URLs in email templates | Fixed — now use configured AppUrl |
| Migration | Two migrations generated; not applied to live PostgreSQL |
| Local secret workflow | Ignored generated `.env`, tracked template/script |
| OpenAPI contract | Cookie/CSRF schemes and response schemas tested |

## Findings And Fixes Applied

| Severity | Finding | Resolution |
|---|---|---|
| Medium | Configurable lockout options existed but domain logic used fixed values. | Login failure now passes configured threshold and duration. |
| Medium | JWT bearer options captured base settings too early. | Bearer validation now consumes validated runtime `JwtSettings`. |
| Medium | Rate limiter was shared per policy, not per IP. | Limits partitioned by remote IP. |
| Medium | No HTTP security response headers. | Added `SecurityHeadersMiddleware` with nosniff, DENY, referrer-policy, permissions, HSTS. |
| Medium | `IsSuspended` flag existed on User entity but was never checked at login. | Suspension checked in `LoginAsync` and `GoogleLoginAsync`. |
| Medium | Google OAuth did not check the `email_verified` claim before linking accounts. | Tokens with unverified email now rejected. |
| Low | Hardcoded `simple.gg` URLs in welcome and password-changed email templates. | Now use `_options.AppUrl` from configuration. |
| Low | Swagger rate-limit descriptions did not match actual code limits. | Updated to match: register 3/min, login 5/min, refresh 10/min, etc. |
| Low | Core endpoint and error paths lacked tests. | 100 unit + 45 integration tests added. |
| Medium | Token scaffold tables lacked ownership constraints and indexes. | EF configurations added with cascading foreign keys and unique hash indexes. |
| Low | Swagger described bearer auth rather than actual cookie flow. | Cookie/CSRF OpenAPI schemes added. |
| Medium | Anonymous auth endpoints had no human challenge against automated abuse. | reCAPTCHA v2 verified server-side on register and login. |
| Informational | Real Google Client ID committed in `.env.example`. | Replaced with `REPLACE_WITH_GOOGLE_OAUTH_CLIENT_ID` placeholder. |
| Informational | Empty `Class1.cs` scaffold files in all four projects. | Deleted. |
| Informational | Dead comment-only files (`IJwtService.cs`, `RegisterUserCommand.cs`, `AuthTokensDto.cs`). | Deleted. |
| Informational | Stale `// TODO:` comments in `EmailVerificationToken.cs` and `PasswordResetToken.cs`. | Removed. |

## Remaining Risks

| Severity | Risk | Recommended treatment |
|---|---|---|
| Medium | Concurrent refresh calls may not be transactionally atomic. | Add concurrency test and use optimistic concurrency (EF row version) or a database-level lock before scale-out. |
| Medium | PostgreSQL migration not applied in this environment. | Install Docker Desktop, run `docker compose -f compose.auth.yml up -d`, run `dotnet ef database update`, and perform browser smoke test. |
| Medium | No security event/audit logging. | Add structured logging for login, logout, failed attempts, password changes — without recording secrets or tokens. |
| Medium | Token table cleanup missing. | Add a background job or scheduled task to purge expired and revoked tokens. |
| Low | Proxy deployments distort remote IP rate-limit keys. | Configure `UseForwardedHeaders` with a trusted proxy list at deployment. |
| Low | No HaveIBeenPwned password check. | The current block-list covers common cases; HIBP API would be stronger. |
| Informational | `frontend-dev.log` at repo root. | Covered by `*.log` in `.gitignore`; will not be committed, but can be deleted locally. |

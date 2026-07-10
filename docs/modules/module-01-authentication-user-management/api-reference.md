# API Reference - Module 01: Authentication & User Management

## Overview
- Existing UI reused: login, register, forgot/reset password, email verification, Google Sign-In, account
  settings pages.
- Frontend integration points: `lib/api-client.ts` (`authApi`), the auth provider (`/me` on startup + refresh).
- Existing database impact: foundational — users, refresh-token families, verification/reset tokens.

## Base Route / Route Group
`/api/auth`. All POST endpoints require the header `X-Requested-With: XMLHttpRequest` (CSRF defense).
Validation failures return `400`; unexpected exceptions return a generic `500`. In Development the OpenAPI
document is at `/swagger/v1/swagger.json` and Swagger UI at `/swagger` (defines `accessCookie` and
`csrfHeader`).

## Authentication And Authorization Requirements
Sessions are cookie-based (HttpOnly access + refresh). `register`/`login` are anonymous but require a
server-verified reCAPTCHA v2 `captchaToken` (`400 Auth.CaptchaFailed` on rejection). Account-security
endpoints require the access cookie and act only on the authenticated user's own account/sessions.

## Endpoint Summary Table

| Method | Path | Purpose | Auth | Main errors |
|---|---|---|---|---|
| GET | `/api/auth/check-email` | Check if an email is registered | Anonymous | 400 missing, 429 |
| POST | `/api/auth/register` | Create account + session cookies | Anonymous | 400 validation/CSRF/CAPTCHA, 409, 429 |
| POST | `/api/auth/login` | Authenticate + session cookies | Anonymous | 400, 401 credentials/lockout/suspended, 429 |
| GET | `/api/auth/me` | Current user | Access cookie | 401, 404 |
| POST | `/api/auth/refresh` | Rotate refresh token | Refresh cookie | 400 CSRF, 401 expired/replayed, 429 |
| POST | `/api/auth/logout` | Revoke current session | Optional cookie | 400 CSRF |
| POST | `/api/auth/logout-all` | Revoke all sessions | Access cookie | 400 CSRF, 401 |
| POST | `/api/auth/verify-email` | Consume verification token (also confirms email change) | Anonymous | 400 CSRF/invalid |
| POST | `/api/auth/resend-verification` | Resend verification | Access cookie | 400 CSRF/cooldown, 401, 429 |
| POST | `/api/auth/forgot-password` | Request reset link (always 204) | Anonymous | 400 CSRF/validation, 429 |
| POST | `/api/auth/reset-password` | Consume reset token, set password | Anonymous | 400 CSRF/invalid/validation, 429 |
| POST | `/api/auth/google` | Sign in/register via Google ID token | Anonymous | 400 CSRF, 401 invalid, 429 |
| POST | `/api/auth/change-password` | Change password (revokes sessions) | Access cookie | 400, 401 |
| POST | `/api/auth/change-email` | Request email change via verification | Access cookie | 400, 401, 409 |
| GET | `/api/auth/sessions` | List active sessions | Access cookie | 401 |
| DELETE | `/api/auth/sessions/{id}` | Revoke a specific own session | Access cookie | 401, 403 |
| DELETE | `/api/auth/account` | Delete account (password confirm) | Access cookie | 400, 401 |

## Endpoints
Grouped detail — registration (`check-email`, `register`), session (`login`, `me`, `refresh`, `logout`,
`logout-all`), email verification (`verify-email`, `resend-verification`), password reset
(`forgot-password`, `reset-password`), Google OAuth (`google`), and account security (`change-password`,
`change-email`, `sessions`, `sessions/{id}`, `account`). Request bodies: register
`{ username, email, password, confirmPassword, captchaToken }`; login `{ emailOrUsername, password,
captchaToken }`; verify/reset take single-use `{ token, ... }`; google `{ idToken }`.

## Data Models / DTOs
`UserDto`: `id`, `username`, `displayName`, `email`, `initials`, `color`, `role`, `isEmailVerified`,
`createdAt`. Never includes password hashes, raw tokens, lockout state, or internal session data.

## Error Format
All error bodies: `{ "error": { "code": "...", "message": "..." } }`. Rate-limit rejections use
`Auth.RateLimitExceeded`. Validation rules: username 3–30 (letters/numbers/underscore/hyphen); email ≤254,
valid format; password 8–128 with ≥2 of upper/lower/number/special + common-weak-phrase block-list; CAPTCHA
required and verified server-side on login/register.

Rate limits per IP: check-email 20/min, register 3/min, login 5/min, refresh 10/min, resend-verification
3/5min, forgot-password 3/10min, reset-password 5/10min, google 10/min. Login failures also trigger account
lockout (default 10 attempts, 15-minute lockout).

## Security Considerations
Argon2id password hashing; refresh tokens stored only as hashes with family-based replay revocation; HttpOnly
`SameSite=Lax` cookies (access 15 min all routes, refresh 7 days scoped to `/api/auth`); CSRF header on all
POSTs; credentialed CORS restricted to the configured origin; defensive response headers (nosniff, DENY,
Referrer-Policy, Permissions-Policy, HSTS). Google ID tokens validated against Google JWKS with `aud` and
`email_verified` checks; no client secret stored.

## Related Tests
100 unit + 45 integration (backend) covering status/cookies/CSRF/rate-limit/refresh-replay/safe-output/
OpenAPI/DB ownership; 47 frontend Vitest tests. See `testing-report.md`.

## Last Verified Command
`dotnet test` (backend) and `cd frontend && npx tsc --noEmit && npm run lint && npm run build`.

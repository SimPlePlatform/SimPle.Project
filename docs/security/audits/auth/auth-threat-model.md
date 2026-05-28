# Auth Threat Model

Date: 2026-05-28

## Assets Protected

- User passwords and password hashes.
- Authenticated account access.
- Access and refresh sessions.
- Email verification tokens and password reset tokens.
- User identity fields returned by the API.
- JWT signing key and database connection credentials.
- reCAPTCHA secret key and one-time browser challenge responses.
- Google OAuth client ID (public but scoped to configured origins).

## Attackers Considered

- An unauthenticated internet client guessing credentials.
- A script attempting to register many accounts automatically.
- A malicious site trying to make authenticated requests with a logged-in user's cookies.
- An attacker who obtains a stale or rotated refresh token.
- A script-injection attacker attempting to read browser storage.
- A reviewer, log reader, or monitoring system that should not see secrets.
- An attacker who obtains a password reset or email verification link.

## Trust Boundaries And Entry Points

- Browser ↔ API: all `/api/auth/*` endpoints and cookies.
- API ↔ database: users and hashed token tables.
- API ↔ Google JWKS: token validation for Google OAuth.
- API ↔ Google reCAPTCHA: verification for login and register.
- Configuration: JWT signing key and PostgreSQL connection string must come from
  environment or secret manager, not committed files.

## Sensitive Data

Passwords, password hashes, raw refresh tokens, verification tokens, reset
tokens, JWT cookies, signing keys, database passwords, reCAPTCHA secrets, and
auth failure state are sensitive and must not appear in logs, error responses,
or client-visible JSON.

## Main Risks And Mitigations

| Risk | Mitigation |
|---|---|
| Password database theft | Argon2id with random salt; upgrade detection on login |
| Credential guessing | Per-IP rate limits + account lockout |
| Automated register/login abuse | reCAPTCHA v2 verified server-side before any auth processing |
| User enumeration at login | Generic error message; dummy hash path for missing users |
| User enumeration at forgot-password | Always returns 204 |
| Stolen/replayed refresh token | Hashed storage, rotation, family revocation |
| Cookie-based CSRF | SameSite=Lax + required custom request header |
| Script token extraction via XSS | HttpOnly cookies; tokens never in JSON response or localStorage |
| Cross-origin credential misuse | Explicit CORS origin with credentials; no wildcard |
| Internal error exposure | Global generic exception middleware |
| DTO/entity leakage | API returns explicit `UserDto` only |
| Token row orphaning | Token tables require user foreign key with cascade delete |
| Clickjacking | `X-Frame-Options: DENY` on all responses |
| MIME sniffing | `X-Content-Type-Options: nosniff` on all responses |
| HTTPS downgrade | `Strict-Transport-Security` on HTTPS connections |
| Suspended account access | Suspension checked before token issuance in all login paths |
| Unverified Google email linking | `email_verified` flag checked before account linking |
| Email verification token abuse | Argon2id hashed, 24h expiry, single-use |
| Password reset token abuse | Argon2id hashed, 1h expiry, single-use, revokes all sessions |

## Remaining Risks

| Risk | Status |
|---|---|
| Concurrent refresh race condition | Not hardened with atomic compare-and-swap. Low risk for single-instance; review before scale-out. |
| Migration not applied to live database | Docker/PostgreSQL not installed here. |
| No security event logging | Auth events not written to audit log. |
| Token table accumulates expired rows | No purge job yet. |
| Proxy IP distortion | `RemoteIpAddress` used directly; needs `UseForwardedHeaders` in production. |

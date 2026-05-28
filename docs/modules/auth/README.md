# Authentication

Authentication is the first working backend module in SimPle. It gives the later
friends, lobby, chat, and game features a trustworthy answer to: "which user is
making this request?"

## Implemented

- Registration with normalized unique email and username checks.
- Login by email or username with generic credential errors and account lockout.
- Short-lived JWT access tokens and rotating refresh token sessions.
- Session logout, logout from all sessions, and current-user lookup.
- Email verification — single-use token (24-hour expiry), send and resend.
- Password reset — request by email (always returns 204, prevents enumeration),
  single-use token (1-hour expiry), reset revokes all sessions.
- Google OAuth — ID token flow via Google Identity Services. The server validates
  the signed JWT against Google's public JWKS endpoint. Existing email accounts
  are linked automatically. No client secret is stored.
- Argon2id password hashing, account lockout, request validation, CSRF header
  checks, explicit credentialed CORS, per-IP rate limiting, suspension enforcement,
  and safe generic exception responses.
- Defensive HTTP response headers on every response.
- PostgreSQL EF migrations including token ownership foreign keys and indexed
  token hashes.
- Development Swagger/OpenAPI documentation for the cookie and CSRF workflow.
- Setup script and local PostgreSQL Compose definition.
- Next.js login, register, forgot password, reset password, email verification,
  and Google Sign-In UI wired to the Auth API.
- Cookie-backed browser session loading, protected app routes, sign-out, and
  authenticated-user redirects without token storage in JavaScript.
- Google reCAPTCHA v2 Checkbox on login and registration, with server-side
  token verification and backend-only secret configuration.
- Structured security event logging for all key auth events (register, login,
  refresh, logout-all, password reset, email verification, Google login) — no
  passwords, tokens, or cookies written to logs.
- Optimistic concurrency on refresh token rotation using PostgreSQL `xmin`:
  simultaneous refresh requests race on the token row; the loser returns
  `Auth.InvalidToken`.
- `TokenCleanupService` background job: runs every 6 hours, deletes tokens that
  are both expired and revoked/superseded (1-day retention buffer).
- `ForwardedHeadersOptions` configured for reverse-proxy deployments: only
  loopback is trusted by default, configurable via `Infrastructure:KnownProxies`.
- `DevBypassToken` option on `RecaptchaOptions` lets the development environment
  skip Google reCAPTCHA verification without exposing test keys in source.
- GitHub Actions CI pipeline: backend (build/test/vuln-scan) and frontend
  (tsc/lint/build/test/audit) jobs on every push to `main` and `feature/**`.

## API Endpoints

| Endpoint | Purpose |
|---|---|
| `GET /api/auth/check-email` | Check whether an email is already registered |
| `POST /api/auth/register` | Create account, issue session cookies |
| `POST /api/auth/login` | Authenticate, issue session cookies |
| `GET /api/auth/me` | Return current user (access cookie required) |
| `POST /api/auth/refresh` | Rotate refresh token, issue new cookies |
| `POST /api/auth/logout` | Revoke current session |
| `POST /api/auth/logout-all` | Revoke all sessions for this user |
| `POST /api/auth/verify-email` | Consume single-use email verification token |
| `POST /api/auth/resend-verification` | Issue a new email verification message |
| `POST /api/auth/forgot-password` | Request password reset link |
| `POST /api/auth/reset-password` | Consume reset token and update password |
| `POST /api/auth/google` | Sign in or register with a Google ID token |

## Security Shape

Passwords are stored only as Argon2id PHC strings. Access and refresh values are
sent in `HttpOnly` cookies; the database stores only a SHA-256 hash of each
high-entropy refresh token. Refresh rotation keeps a token family ID, so replay
of a rotated token revokes that session family. State-changing Auth POSTs require
`X-Requested-With: XMLHttpRequest` as a CSRF defense in addition to
`SameSite=Lax` cookies.

Email verification and password reset tokens are stored as Argon2id hashes,
expire after 24 hours and 1 hour respectively, and are single-use. Password
reset invalidates all existing refresh sessions.

Google ID tokens are validated server-side against Google's public JWKS
endpoint. The `email_verified` claim is checked before any account linking.

## Tests

The backend has unit tests for hashing, JWT/token behavior, validation, service
flows, domain logic, and shared types — **100 unit tests total**. Integration
tests cover HTTP status codes, cookies, CSRF enforcement, rate limiting, refresh
replay, logout, safe output, exception handling, OpenAPI, and database ownership
mapping — **45 integration tests**.

Frontend auth pages are type-checked and lint-checked via `npx tsc --noEmit` and
`npm run lint`. Vitest covers component-level auth logic with **47 tests across 5 files**.

## Readiness And Later Work

For local use, run `backend/scripts/Initialize-AuthEnvironment.ps1`; it creates
an ignored `.env` with random development JWT and PostgreSQL credentials. Then
start PostgreSQL using `backend/compose.auth.yml`, apply the migrations, and open
Swagger at `/swagger`. For the browser client, copy
`frontend/.env.local.example` to `.env.local`, run the frontend, and exercise
register, sign-in, refresh-on-load, protected navigation, and sign-out.

A full local end-to-end smoke test still depends on applying the migration to a
running PostgreSQL database. The integration tests use an in-memory SQLite host.

To enable CAPTCHA and Google OAuth locally, configure development keys in the
ignored `backend/src/SimPle.Api/.env` and `frontend/.env.local` files.

Remaining work before production hardening:
- Configure ASP.NET Core Data Protection key persistence (Redis or a shared volume)
  when running multiple API instances or behind a load balancer.
- Configure production reCAPTCHA and Google OAuth credentials via environment secrets.
- Set `Infrastructure:KnownProxies` in production to the actual reverse-proxy IPs.

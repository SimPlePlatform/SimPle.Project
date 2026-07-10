# Technical Flow - Module 01: Authentication & User Management

## Recruiter-Facing Summary

Authentication is SimPle's foundation: it gives every later feature (friends, lobbies, chat, games) a
trustworthy answer to "which user is making this request?" It implements cookie-based JWT auth with a
15-minute access token and rotating 7-day refresh tokens, Argon2id password hashing, email verification,
password reset, Google OAuth, CSRF and rate-limit defenses, account lockout, and full account-security
self-service — with no token ever stored in browser JavaScript.

## Problem Solved

A social platform must authenticate users safely and resist the common attacks (credential stuffing, token
replay, CSRF, account enumeration) before any social feature is trustworthy. This module delivers that.

## Architecture Overview

Clean Architecture: `AuthController` (Api) → `AuthService` (Application) → domain entities → Infrastructure
(hashing, token, email, Google, CAPTCHA services) → PostgreSQL. The Next.js app keeps only safe `UserDto`
data in React state and relies on HttpOnly cookies for the actual credentials.

## Backend Flow

- **Register:** validate fields + reCAPTCHA (verified with Google first), normalize email/username for
  duplicate checks, hash password with Argon2id, store user, send verification email async, issue session
  cookies.
- **Login:** verify CAPTCHA; identical failure message for missing/wrong user (dummy hash comparison reduces
  timing leaks); failed attempts increment lockout; suspended → 401; success resets lockout, optionally
  upgrades the hash, stores a new hashed refresh token, writes access+refresh cookies.
- **Refresh:** refresh cookie is sent only to `/api/auth`; server hashes and looks up the stored value,
  revokes and replaces it in the same family; replay of a revoked token revokes the whole family.
- **Logout / logout-all:** logout is idempotent (204 without a session); logout-all revokes all of the
  user's sessions.
- **Email verification / password reset:** single-use tokens stored as Argon2id hashes (24 h / 1 h expiry);
  forgot-password always returns 204 (no enumeration); reset revokes all sessions and emails a notice.
- **Google OAuth:** validate the ID token against Google's JWKS, check `aud` and `email_verified`, then
  link-or-provision; issue the same HttpOnly cookie session. No client secret stored.
- **Account security:** change-password (revokes sessions), change-email (verify new address before switch),
  list/revoke own sessions (cannot touch others'), delete-account (password confirm, revokes + deletes).

## Frontend Flow
- Existing UI reused: login, register, forgot/reset, verify-email, Google Sign-In, account settings.
- Frontend integration points: `lib/api-client.ts` (`authApi`); the auth provider calls `/me` on startup and
  attempts one refresh rotation on expiry.
- Visual changes made: none (logic wiring only).

## Database/Domain Model Changes
- Existing database impact: foundational tables — users, refresh-token families, verification/reset tokens.
- Migration added: yes (`InitialAuth`, `AddGoogleOAuth`, account-security additions).
- Migration safety notes: token ownership foreign keys and unique hashed-token indexes; optimistic
  concurrency on refresh rotation via PostgreSQL `xmin`.
- Data preservation notes: foundational module.
- Destructive DB changes: none (delete-account is a user-initiated data action, not a schema change).

## API Contract
- Backend/API/Swagger alignment: Development Swagger documents the cookie + CSRF workflow; all endpoints
  annotated. See `api-reference.md`.
- Frontend/API integration alignment: `authApi` matches the documented routes/verbs.

## Validation And Error Handling
Field validation (username/email/password rules), CAPTCHA verification, and typed error codes with a generic
`{ error: { code, message } }` body. Unexpected exceptions return a generic 500 with no internal detail.

## Authorization And Security Decisions
Passwords stored only as Argon2id PHC strings; refresh tokens stored only as hashes; replay of a rotated
token revokes the session family; CSRF header required on state-changing POSTs on top of `SameSite=Lax`;
credentialed CORS limited to the configured origin; defensive response headers on every response; structured
security-event logging (no passwords/tokens/cookies logged).

## Realtime/Socket.IO Flow If Applicable
Not applicable.

## State Management If Applicable
The frontend auth provider holds `UserDto` in React state only; credentials live solely in HttpOnly cookies.
Authenticated visitors are redirected away from `/login` and `/register`; `(app)` pages render after session
loading resolves.

## Edge Cases Handled
Account enumeration (uniform responses + always-204 forgot-password), refresh replay (family revocation),
concurrent refresh rotation (loser gets `Auth.InvalidToken` via `xmin`), suspended accounts, lockout,
resend/verify cooldowns, Google account linking vs provisioning. Background `TokenCleanupService` prunes
expired+revoked tokens every 6 h (1-day retention buffer).

## Design Tradeoffs
Cookie-based sessions (not localStorage tokens) trade a little client convenience for immunity to
JS-token theft. Uniform failure messages trade precise UX errors for enumeration resistance.

## Files Changed And Why
`AuthController`, `AuthService`, domain `User`/token entities, Infrastructure services (PasswordHasher,
TokenService, Google/CAPTCHA/email), middleware (security headers, rate limiting), and the Next.js auth pages
+ provider.

## How To Read The Implementation
Start at `AuthController` (endpoints) → `AuthService` (orchestration) → Infrastructure services (hashing,
tokens, Google). Frontend: `lib/api-client.ts` `authApi` and the auth provider.

## Future Improvements / Deferred Items
- Configure ASP.NET Core Data Protection key persistence (Redis/shared volume) for multi-instance runs.
- Production reCAPTCHA + Google OAuth credentials via environment secrets; set `Infrastructure:KnownProxies`
  to the real reverse-proxy IPs.
- End-to-end browser smoke depends on applying migrations to a running PostgreSQL (integration tests use an
  in-memory host).

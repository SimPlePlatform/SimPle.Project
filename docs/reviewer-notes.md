# SimPle — Reviewer Notes

*For the developer's own use. Explains the project, key decisions, and likely interview questions.*

---

## What Is SimPle?

SimPle is a multiplayer online game platform. Players can log in, browse a game library,
create or join lobbies, play games against each other or against AI, and track their
stats and achievements. Think Steam meets a browser-based board game hub.

The backend is ASP.NET Core 8 (C#) in a Clean Architecture structure. The frontend is
Next.js 14 with the App Router. The database is PostgreSQL via EF Core.

Right now, Module 1 and Module 2 are implemented for local/backend/frontend scope. Module 2 profile media uses local MinIO for development through S3-compatible storage configuration while preserving AWS S3 as the production target. Later modules still have visible placeholder UI in places and are not wired yet.

---

## Architecture In One Paragraph

The backend is split into four projects:

- **SimPle.Domain** — pure business entities (`User`, `RefreshToken`, etc.) with no
  framework dependencies.
- **SimPle.Application** — use-case services (`AuthService`), DTOs, FluentValidation
  validators, and interfaces that the infrastructure must implement.
- **SimPle.Infrastructure** — EF Core repositories, Argon2 password hasher, JWT token
  service, Google OAuth validator, reCAPTCHA verifier, and SMTP email sender.
- **SimPle.Api** — ASP.NET controllers, middleware, OpenAPI/Swagger config, and the DI
  wiring in `Program.cs`.

The rule is: outer layers depend on inner layers. The domain knows nothing about
databases. The application knows nothing about HTTP. This keeps the core logic testable
without spinning up a server.

---

## How Auth Works — The Short Version

1. The user submits email + password + reCAPTCHA token.
2. The server verifies the reCAPTCHA with Google, checks the password against an Argon2id
   hash, and issues two HttpOnly cookies:
   - **access cookie** — 15-minute HS256 JWT, used on every API call.
   - **refresh cookie** — 7-day rotating token, stored hashed in the database.
3. When the access token expires, the browser hits `/api/auth/refresh`. The server checks
   the refresh token, issues a new pair, and revokes the old one.
4. If someone replays a used refresh token (possible if it was stolen), the server detects
   the old token, revokes the entire session family, and forces the user to log in again.
5. Google OAuth uses the ID token flow: the browser gets a JWT from Google Identity
   Services and sends it to the server. The server validates it against Google's public
   JWKS endpoint and checks `aud` (our client ID) and `email_verified`.

---

## Key Security Decisions And Why

### Argon2id for passwords
Argon2id is the OWASP-recommended password hashing algorithm as of 2024. It is
memory-hard (64 MiB per hash), making large-scale brute-force attacks expensive even
with GPUs. SHA-256 and bcrypt are alternatives but Argon2id is stronger.

### HttpOnly cookies, not localStorage
Tokens stored in `localStorage` or `sessionStorage` can be read by any JavaScript on
the page, including injected scripts (XSS). HttpOnly cookies cannot be read by JavaScript
at all. This is the primary XSS token-theft mitigation.

### Refresh token family revocation
Rotating refresh tokens are susceptible to a race condition: if an attacker steals a
refresh token before it is rotated, they can use the original while the legitimate user
uses the rotated one. By tracking tokens in "families", any use of a token that is
already rotated immediately revokes the whole family — ending the attacker's session.

### SHA-256 for refresh token storage
The raw refresh token (32 random bytes) only ever lives in the browser cookie. The
database stores a SHA-256 hash. If the database is breached, the attacker gets hashes
of random values — they cannot reverse them to valid tokens.

### CSRF header requirement
Even with `SameSite=Lax` cookies, requiring the `X-Requested-With: XMLHttpRequest`
header on all state-changing POSTs ensures that plain HTML form submissions from third
sites cannot trigger auth actions. A simple browser form cannot set custom headers.

### reCAPTCHA on login and register
reCAPTCHA v2 is verified server-side before any database work is done. This blocks
automated credential stuffing and mass-registration scripts.

---

## What Is Not Yet Done

- Modules 3-15 are not implemented. Module 2 profile media, visibility, external web profiles, and Gamer/Developer profile type are implemented locally with MinIO support, but production CloudFront delivery and deployed AWS S3 verification remain planned.
- No production database has been applied (PostgreSQL/Docker required).
- No CI pipeline exists yet.
- No security event logging (logins, password resets, bans are not written to an audit log).
- No token cleanup job (expired rows accumulate in the database).
- No multi-factor authentication.
- No admin role or moderation features.

---

## Interview Q&A

**Q: Why Clean Architecture? Isn't it overkill for a hobby project?**

A: The main benefit here is testability. The `AuthService` tests run in under a second
with no database, no HTTP server, and no third-party calls — they just mock the
interfaces. For a project where security is important, being able to test every auth path
in isolation is worth the extra project structure.

---

**Q: Walk me through what happens when a user resets their password.**

A: The user submits their email at `/api/auth/forgot-password`. The server always
returns 204 regardless of whether the email exists (to prevent account enumeration). If
the email exists, it generates a random token, stores a SHA-256 (actually Argon2id) hash
in the database with a 1-hour expiry, and emails the user a link containing the raw token.
The user clicks the link, the frontend sends the token and the new password to
`/api/auth/reset-password`. The server hashes the received token, finds the matching
database row, verifies it has not expired and has not been used, sets the new password,
marks the token as used, and revokes all existing refresh tokens — so every other active
session is logged out.

---

**Q: How does the refresh token rotation work? What stops someone from replaying a token?**

A: Each token belongs to a family. When a refresh token is used, the server creates a
new token in the same family and marks the old one as used. If the server sees a token
that is already marked as used (i.e. someone is replaying a rotated token), it revokes
every token in that family — this ends both the attacker's session and the legitimate
user's session. The user has to log in again, but the attacker cannot continue.

---

**Q: Why is `X-XSS-Protection: 0` set? Shouldn't it be turned on?**

A: The `X-XSS-Protection` header was a feature of older IE/Chrome that triggered a
built-in XSS filter. That filter is now removed from all modern browsers, and setting
it to `1; mode=block` was found to actually introduce new XSS vulnerabilities in some
older browsers. The current OWASP recommendation is to set it to `0` (disabled) and
rely on `Content-Security-Policy` instead.

---

**Q: What would you add next for production readiness?**

A: In priority order:
1. `UseForwardedHeaders` so rate limiting uses the real client IP behind a proxy.
2. Security event logging (login success/failure, password reset, suspension).
3. Token table cleanup job (cron or hosted service deleting expired rows).
4. NuGet and npm vulnerability scanning in CI.
5. Redis-backed rate limiting for multi-instance deployments.

---

**Q: Why use FluentValidation instead of Data Annotations?**

A: FluentValidation rules are easier to unit-test (each validator can be instantiated
and called directly), easier to read (each rule is a method call rather than an
attribute), and easier to extend with async rules (like the future HaveIBeenPwned
password check). Data annotations are fine for simple cases but FluentValidation scales
better when validation logic becomes non-trivial.

---

**Q: What is the difference between the access token cookie and the refresh token cookie?**

A: The access token is a short-lived JWT (15 minutes) scoped to all API paths. Every
authenticated request sends it automatically. The refresh token is a long-lived opaque
random value (7 days) stored hashed in the database, scoped only to `/api/auth`. It is
only sent when the access token expires and the browser calls the refresh endpoint. This
limits the window in which the refresh token can be intercepted.

---

**Q: What is account lockout and how does it work?**

A: After a configurable number of failed login attempts (default 5), the user's account
is locked for a configurable duration (default 15 minutes). The lockout state is stored
in the `User` row — no external cache is required. The check happens before the password
is verified, so a locked user cannot consume Argon2 CPU time even if they supply the
correct password.

---

**Q: How is Google OAuth implemented?**

A: The browser uses Google Identity Services to obtain an ID token (a JWT signed by
Google). The user never sees a client secret — that only lives on the server. The
frontend sends the ID token to `/api/auth/google`. The server fetches Google's public
JWKS, validates the token signature, checks the `aud` claim matches the configured
Google Client ID, and checks `email_verified` is true. If all checks pass, the server
finds or creates a local user account and issues the same access+refresh cookie pair
used for email/password login.

---

**Q: Why is `SameSite=Lax` used instead of `SameSite=Strict`?**

A: `Strict` would prevent the cookies from being sent on any cross-site navigation,
including clicking a link from another site. That would log users out whenever they
navigate to the site from a search result or email link. `Lax` allows cookies on
top-level GET navigations but blocks them on cross-site POSTs and subresource loads.
Combined with the `X-Requested-With` header requirement, CSRF is still blocked.

---

## Files A Reviewer Should Look At First

| File | Why |
|---|---|
| [backend/src/SimPle.Api/Controllers/AuthController.cs](../backend/src/SimPle.Api/Controllers/AuthController.cs) | All auth HTTP endpoints |
| [backend/src/SimPle.Application/Auth/Services/AuthService.cs](../backend/src/SimPle.Application/Auth/Services/AuthService.cs) | All auth business logic |
| [backend/src/SimPle.Infrastructure/Auth/Argon2PasswordHasher.cs](../backend/src/SimPle.Infrastructure/Auth/Argon2PasswordHasher.cs) | Password hashing implementation |
| [backend/src/SimPle.Infrastructure/Auth/JwtTokenService.cs](../backend/src/SimPle.Infrastructure/Auth/JwtTokenService.cs) | JWT and refresh token logic |
| [backend/src/SimPle.Domain/Users/User.cs](../backend/src/SimPle.Domain/Users/User.cs) | User domain entity |
| [backend/src/SimPle.Api/Program.cs](../backend/src/SimPle.Api/Program.cs) | Application configuration and DI wiring |
| [backend/src/SimPle.Api/Controllers/ProfileController.cs](../backend/src/SimPle.Api/Controllers/ProfileController.cs) | Module 2 profile, visibility, media, and external link endpoints |
| [backend/src/SimPle.Application/Profiles/Services/ProfileService.cs](../backend/src/SimPle.Application/Profiles/Services/ProfileService.cs) | Profile business logic, profile type, external links, and S3 object-key handling |
| [backend/tests/SimPle.UnitTests/Auth/AuthServiceTests.cs](../backend/tests/SimPle.UnitTests/Auth/AuthServiceTests.cs) | 41 unit tests for the auth service |
| [backend/tests/SimPle.IntegrationTests/Auth/AuthEndpointsTests.cs](../backend/tests/SimPle.IntegrationTests/Auth/AuthEndpointsTests.cs) | 43 integration tests for the HTTP endpoints |
| [docs/security/audits/module-01-authentication-user-management.md](security/audits/module-01-authentication-user-management.md) | Full security audit of Module 1 |

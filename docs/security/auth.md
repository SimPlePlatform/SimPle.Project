# Authentication Security

## Password Storage

Passwords are hashed with Argon2id using a random 16-byte salt and encoded as a
PHC string. Parameters: 64 MiB memory, 3 iterations, parallelism 1, 32-byte
result. Verification uses fixed-time comparison (`CryptographicOperations.FixedTimeEquals`).
The PHC format allows a successful login to replace older hashes when parameters
change in future.

Each stored hash includes its own random salt; there is no shared "pepper" in
`.env`. The `.env` contains the JWT signing key and database credential only.

## Tokens And Cookies

The access token is an HS256 JWT valid for 15 minutes. The refresh token is 32
random bytes (256 bits) valid for 7 days. The raw value only exists in the
browser cookie; storage uses its SHA-256 hash. SHA-256 is appropriate here
because the source value is already 256-bit random — there is no dictionary
attack surface as there is with passwords.

Both cookies are `HttpOnly` and `SameSite=Lax`. Outside development they are
also `Secure`. The refresh cookie path is `/api/auth`, limiting where browsers
send it. The frontend keeps only a safe `UserDto` in React state and never copies
token values to `localStorage` or `sessionStorage`.

## Rotation And Replay

Every refresh call consumes and revokes the old refresh token, then issues a new
one in the same family. Presenting a revoked token is treated as a possible
replay attack and causes all tokens in that family to be revoked immediately.

## Email Verification And Password Reset

Verification and reset tokens are generated as 32 bytes of random data, stored
as Argon2id hashes, and are single-use. Verification tokens expire after 24
hours; reset tokens expire after 1 hour. Resend is rate-limited with a per-user
60-second cooldown. The forgot-password endpoint always returns 204 regardless of
whether the email is registered, preventing account enumeration. Successful
password reset revokes all active refresh sessions and sends a security
notification email.

## Google OAuth

The ID token flow is used: the browser obtains a signed JWT from Google Identity
Services and the server validates it using Google's public JWKS keys. The `aud`
claim is verified against the configured client ID. The `email_verified` flag is
checked before any account linking or provisioning. The Google client secret is
never used, requested, or stored. Raw Google credentials are never persisted.

## CSRF, CORS, And Abuse Controls

All state-changing Auth POST endpoints require `X-Requested-With: XMLHttpRequest`.
Combined with `SameSite=Lax`, this blocks normal cross-site form submission.
CORS permits credentials only for the explicitly configured frontend origin.

Rate limits by remote IP: register 3/min, login 5/min, refresh 10/min, google
10/min, resend-verification 3/5min, forgot-password 3/10min, reset-password
5/10min. Account lockout applies after the configured threshold (default 10
attempts, 15-minute lockout). Suspended accounts cannot authenticate regardless
of credentials.

## CAPTCHA Protection

Registration and login require a Google reCAPTCHA v2 Checkbox response. The
public site key is exposed only to the Next.js widget via
`NEXT_PUBLIC_RECAPTCHA_SITE_KEY`. The secret key lives only in backend runtime
configuration (`Recaptcha__SecretKey`). The API posts the one-time browser
response, the server secret, and the remote IP to Google's `siteverify` endpoint
before any auth processing. Missing, rejected, expired, or unverifiable CAPTCHA
responses fail closed.

## Security Response Headers

Every response includes: `X-Content-Type-Options: nosniff`, `X-Frame-Options:
DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `X-XSS-Protection: 0`,
`Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()`, and
`Strict-Transport-Security` on HTTPS connections.

## Concurrent Refresh Hardening

Simultaneous refresh requests that both present the same token race on the
PostgreSQL `xmin` system column (set via `UseXminAsConcurrencyToken()`). The
first writer wins; the second receives `DbUpdateConcurrencyException` and
`RefreshAsync` returns `Auth.InvalidToken`. No migration is required because
`xmin` is a built-in PostgreSQL row-version column.

## Security Event Logging

`AuthService` logs structured `ILogger` messages for every key auth event:
register, login (success and each failure mode), token replay, concurrent
conflict, logout-all, email verification, password reset request, password reset
completion, and Google login. No passwords, tokens, cookies, or session IDs
appear in any log message — only safe identifiers (UserId, Ip, FamilyId,
attempt counts).

## Token Cleanup

`TokenCleanupService` (a `BackgroundService`) runs every 6 hours and deletes
tokens that are both expired **and** revoked/superseded, keeping a 1-day
retention window for incident investigation. Configuration is in
`appsettings.json` under `TokenCleanup` (`Interval`, `RetentionPeriod`).

## Proxy-Aware IP Forwarding

`ForwardedHeadersOptions` is configured in `Program.cs` to process
`X-Forwarded-For` and `X-Forwarded-Proto` only from trusted proxies.
Loopback addresses are trusted by default. Production proxy IPs are
configurable via `Infrastructure:KnownProxies` in appsettings (accepts IP
addresses and CIDR ranges). `UseForwardedHeaders()` runs first in the
middleware pipeline so the rate limiter always sees the real client IP.

## Known Limitations And Remaining Work

- **Data Protection key persistence**: ASP.NET Core Data Protection keys are
  stored in-process by default. Multi-instance or load-balanced deployments
  must configure a shared key store (Redis, distributed file share, or a
  cloud secret manager) before running more than one API pod.
- **Production secrets**: The `.env` file is for local development only.
  Production should use the deployment environment's secret manager.
- **Production CAPTCHA and OAuth credentials**: Set `Recaptcha__SecretKey`,
  `Jwt__SecretKey`, and `Google__ClientId` via environment secrets; never
  commit real values.

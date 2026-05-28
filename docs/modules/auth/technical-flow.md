# Authentication Flow

## Register

The API validates username, email, password strength, password confirmation, and
the reCAPTCHA v2 browser response. The CAPTCHA is verified with Google before any
account work. `AuthService` normalizes email and username for duplicate checks,
hashes the password with Argon2id, stores the user, and sends a verification
email asynchronously. A session is issued immediately via HttpOnly cookies.

## Login

The user submits an email or username, password, and reCAPTCHA v2 response. The
CAPTCHA is verified first. Existing and missing users receive the same failure
message; the missing-user path runs a dummy hash comparison to reduce timing
differences. Failed attempts increment an account lockout counter. Suspended
accounts receive a 401 regardless of credentials. A successful login resets the
lockout counter, optionally upgrades an old password hash to current parameters,
stores a new hashed refresh token, and writes access and refresh tokens into
HttpOnly cookies.

## Refresh

The browser sends the refresh cookie only to `/api/auth` paths. The server hashes
the raw cookie value and looks up the stored hash. An active token is revoked and
replaced with a new token in the same family. If an already-revoked token is
submitted again, the entire family is revoked and the user must sign in again.

## Logout And Logout-All

Logout revokes the current refresh token and deletes both cookies. It is
idempotent — calling it without a valid session still returns 204.
Logout-all requires an access-token-authenticated user and revokes all of that
user's stored refresh sessions.

## Current User

`GET /api/auth/me` requires the access cookie. JWT authentication verifies the
signature, issuer, audience, and expiry; the endpoint then loads the user and
returns `UserDto`. The frontend auth provider calls `/me` on app startup. If the
access token has expired, the provider attempts one refresh rotation. If no valid
session exists, the user is redirected to login.

## Email Verification

After registration, the API sends a verification email with a single-use token
embedded as `?token=` in the link. The token is stored as an Argon2id hash in
the database. Clicking the link calls `POST /api/auth/verify-email` with the raw
token; the server hashes it, looks it up, marks it used, and marks the user
verified. Tokens expire after 24 hours. The resend endpoint enforces a 60-second
per-user cooldown on top of the IP rate limit.

## Password Reset

`POST /api/auth/forgot-password` accepts an email and always returns 204 — even
if the address is not registered — to prevent account enumeration. When the
address is found, any existing reset tokens are invalidated and a new single-use
token (1-hour expiry) is sent by email. `POST /api/auth/reset-password` validates
the token, updates the password with a fresh Argon2id hash, revokes all refresh
sessions for that account, and sends a security notification email.

## Google OAuth

The browser loads Google Identity Services and displays a sign-in button. After
the user selects a Google account, GIS returns a signed JWT credential. The
frontend posts it to `POST /api/auth/google`. The backend validates the token
against Google's public JWKS endpoint, checks the `aud` claim against the
configured client ID, and checks that `email_verified` is true.

Account resolution:
1. If a user already linked to this Google ID exists — sign in directly.
2. If a password account with the same email exists — link the Google ID and
   sign in.
3. Otherwise — provision a new account. The username is derived from the Google
   given name with random digits appended if taken. Email is pre-verified.

The session is issued as HttpOnly cookies, identical to the password login flow.
No Google client secret is used or stored.

## Cookies And Request Protection

The access cookie is short-lived (15 minutes) and scoped to all API routes. The
refresh cookie lasts 7 days and is restricted to `/api/auth`. Both are HttpOnly,
`SameSite=Lax`, and `Secure` outside development. Browser JavaScript never sees
the token values.

All Auth POST endpoints require `X-Requested-With: XMLHttpRequest`. A normal
cross-site form cannot add a custom header, so this blocks cross-site form
submissions of cookie-authenticated actions. CORS permits credentials only from
the explicitly configured frontend origin.

## Security Response Headers

Every response includes:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `X-XSS-Protection: 0`
- `Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()`
- `Strict-Transport-Security` (HTTPS connections only)

## Frontend Integration

The Next.js app keeps only safe `UserDto` data in React state. `credentials:
'include'` on all fetch calls lets the browser send HttpOnly cookies; the
frontend never reads or copies token values. Mutating auth calls include the CSRF
header. Authenticated visitors are redirected away from `/login` and `/register`.
Pages inside the `(app)` layout render only after session loading resolves.

## Interview Explanation

"I built cookie-based JWT authentication with a 15-minute access token and
rotating 7-day refresh tokens. Passwords use Argon2id. Refresh tokens are stored
only as SHA-256 hashes in the database — the raw value only exists in the browser
cookie. Replaying a rotated token invalidates the entire session family. I added
email verification, password reset with single-use tokens, Google OAuth via the
ID token flow, CSRF header checks, per-IP rate limits, account lockout, and
defensive HTTP response headers. The frontend never puts any token in localStorage
or sessionStorage."

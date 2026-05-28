# Auth Attack Checklist

Date: 2026-05-28

| Check | Status | Evidence or note |
|---|---|---|
| SQL injection | Addressed by design | EF Core parameterized repositories; no raw SQL in Auth |
| Weak password hashing | Checked | Argon2id PHC hashes, unique salts, fixed-time comparison, tests |
| User enumeration — login | Checked | Generic error message; missing-user path runs dummy hash work |
| User enumeration — forgot password | Checked | Always returns 204 regardless of email existence |
| Brute force | Checked | CAPTCHA, account lockout, per-IP rate limits |
| Credential stuffing basics | Checked | CAPTCHA on login, rate limiting, generic output |
| Refresh token replay | Checked | Rotation + family revocation; unit and integration tests |
| Token theft via XSS/localStorage | Checked | Tokens in HttpOnly cookies; never returned as JSON; no localStorage usage |
| CSRF | Checked | POST header requirement tested; SameSite=Lax cookie strategy |
| Session fixation | Checked | Fresh random refresh family and token on each login |
| Insecure cookies | Checked | HttpOnly, SameSite=Lax, path scoping; Secure outside development |
| Account suspension bypass | Checked | Suspension checked in LoginAsync and GoogleLoginAsync before token issuance |
| Email verification token abuse | Checked | Argon2id hashed, 24-hour expiry, single-use, cooldown on resend |
| Password reset token abuse | Checked | Argon2id hashed, 1-hour expiry, single-use, invalidates old tokens, revokes sessions |
| Google OAuth — unverified email | Checked | `email_verified` claim required before account linking or provisioning |
| Google OAuth — wrong audience | Checked | `aud` claim verified against configured client ID |
| Mass assignment | Checked | Record DTOs mapped explicitly to service/entity creation |
| Sensitive data exposure — responses | Checked | UserDto only; exception middleware tests |
| Sensitive data exposure — config | Checked | Ignored generated `.env`; placeholder example files |
| Verbose error leakage | Checked | Generic exception middleware; test coverage |
| Rate-limit bypass basics | Partially checked | Per-IP limits tested; proxy/forwarded-IP configuration remains for production |
| Missing authorization | Checked | `/me`, `logout-all`, `resend-verification` require access cookie; OpenAPI reflects it |
| Insecure CORS | Checked | One configured origin with credentials; no wildcard |
| CAPTCHA bypass | Checked | Login and register verify browser tokens server-side before any auth processing |
| Clickjacking | Checked | `X-Frame-Options: DENY` on all responses |
| MIME sniffing | Checked | `X-Content-Type-Options: nosniff` on all responses |
| Missing HSTS | Checked | `Strict-Transport-Security` set on HTTPS connections |
| Hardcoded URLs in emails | Fixed | Welcome and password-changed emails now use configured `AppUrl` |
| Real credential in example file | Fixed | Google Client ID placeholder in `.env.example` |

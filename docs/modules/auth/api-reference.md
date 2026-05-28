# Auth API Reference

All POST endpoints require the request header
`X-Requested-With: XMLHttpRequest`. Validation failures return `400`; unexpected
exceptions return a generic `500` response.

`POST /api/auth/register` and `POST /api/auth/login` additionally require a
one-time `captchaToken` produced by a Google reCAPTCHA v2 Checkbox widget. The
API verifies it server-side and returns `400 Auth.CaptchaFailed` when Google
does not accept the response.

In Development, the live OpenAPI document is available at
`/swagger/v1/swagger.json` and Swagger UI at `/swagger`. Swagger defines
`accessCookie` for protected endpoints and `csrfHeader` for all Auth POST
endpoints; set the CSRF value to `XMLHttpRequest` before executing POST calls.

## Endpoints

### Registration

| Method and path | Request body | Success | Auth | Main errors |
|---|---|---|---|---|
| `GET /api/auth/check-email` | `?email=` query param | `204` if available, `409` if taken | Anonymous | `400` missing email, `429` limit |
| `POST /api/auth/register` | `{ username, email, password, confirmPassword, captchaToken }` | `201` `UserDto` + cookies | Anonymous | `400` validation/CSRF/CAPTCHA, `409` duplicate, `429` limit |

### Session

| Method and path | Request body | Success | Auth | Main errors |
|---|---|---|---|---|
| `POST /api/auth/login` | `{ emailOrUsername, password, captchaToken }` | `200` `UserDto` + cookies | Anonymous | `400` validation/CSRF/CAPTCHA, `401` credentials/lockout/suspended, `429` limit |
| `GET /api/auth/me` | None | `200` `UserDto` | Access cookie | `401`, `404` |
| `POST /api/auth/refresh` | None; refresh cookie | `200` `UserDto` + rotated cookies | Refresh cookie | `400` CSRF, `401` expired/replayed, `429` limit |
| `POST /api/auth/logout` | None | `204` | Optional cookie | `400` CSRF |
| `POST /api/auth/logout-all` | None | `204` | Access cookie | `400` CSRF, `401` |

### Email Verification

| Method and path | Request body | Success | Auth | Main errors |
|---|---|---|---|---|
| `POST /api/auth/verify-email` | `{ token }` | `204` | Anonymous | `400` CSRF/invalid token |
| `POST /api/auth/resend-verification` | None | `204` | Access cookie | `400` CSRF/cooldown, `401`, `429` limit |

### Password Reset

| Method and path | Request body | Success | Auth | Main errors |
|---|---|---|---|---|
| `POST /api/auth/forgot-password` | `{ email }` | `204` always | Anonymous | `400` CSRF/validation, `429` limit |
| `POST /api/auth/reset-password` | `{ token, newPassword, confirmNewPassword }` | `204` | Anonymous | `400` CSRF/invalid token/validation, `429` limit |

### Google OAuth

| Method and path | Request body | Success | Auth | Main errors |
|---|---|---|---|---|
| `POST /api/auth/google` | `{ idToken }` | `200` `UserDto` + cookies | Anonymous | `400` CSRF, `401` invalid token, `429` limit |

## UserDto

`id`, `username`, `displayName`, `email`, `initials`, `color`, `role`,
`isEmailVerified`, `createdAt`. Does not include password hashes, raw tokens,
lockout state, or any internal session data.

All error bodies use `{ "error": { "code": "...", "message": "..." } }`.
Rate-limit rejections use `Auth.RateLimitExceeded`.

## Validation Rules

- **Username**: 3–30 characters, letters/numbers/underscore/hyphen only.
- **Email**: non-empty, valid format, at most 254 characters.
- **Registration password**: 8–128 characters, at least 2 of: uppercase,
  lowercase, numbers, special characters. A short block-list rejects the most
  common weak phrases.
- **Reset password**: same rules as registration password.
- **Login identifier**: non-empty, at most 254 characters.
- **CAPTCHA token**: non-empty on login and register; verified server-side.

## Rate Limits (per remote IP)

| Endpoint | Limit |
|---|---|
| `check-email` | 20 / minute |
| `register` | 3 / minute |
| `login` | 5 / minute |
| `refresh` | 10 / minute |
| `resend-verification` | 3 / 5 minutes |
| `forgot-password` | 3 / 10 minutes |
| `reset-password` | 5 / 10 minutes |
| `google` | 10 / minute |

Beyond rate limits, login failures trigger account lockout after the configured
threshold (default 10 attempts, 15-minute lockout).

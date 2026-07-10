# API Reference - Module 02: User Profile & Social Identity

## Overview
- Existing UI reused: profile page, profile settings, avatar/banner media, links, interests.
- Frontend integration points: `profileApi` (`lib/api-client.ts` + feature module), storage upload flow.
- Existing database impact: additive profile columns + `username_change_requests` + `profile_external_links`.

## Base Route / Route Group
`/api/profile`. All state-changing endpoints require `X-Requested-With: XMLHttpRequest`; authentication uses
HttpOnly cookies.

## Authentication And Authorization Requirements
`/me*` endpoints act only on the authenticated user. Public profile (`GET /{username}`) is returned only when
visibility allows the requester. Object keys for media are backend-generated and must belong to the
authenticated user.

## Endpoint Summary Table

| Method | Path | Purpose | Auth |
|---|---|---|---|
| GET | `/api/profile/me` | Own profile | Cookie |
| PUT | `/api/profile/me` | Update display name, bio, region, status, visibility, profile type, legacy URLs | Cookie |
| GET | `/api/profile/{username}` | Public profile (visibility-gated) | Optional |
| PUT | `/api/profile/me/username` | Immediate monthly username change, else create/update pending request | Cookie |
| POST/GET/PUT/DELETE | `/api/profile/me/username-change-request` | Manage pending username request | Cookie |
| GET/PUT | `/api/profile/me/links` | Read/replace external links | Cookie |
| GET/PUT | `/api/profile/me/interests` | Read/replace interest tags | Cookie |
| POST | `/api/profile/me/avatar/upload-url` | Presigned avatar upload URL | Cookie |
| POST | `/api/profile/me/avatar/confirm` | Confirm avatar object | Cookie |
| DELETE | `/api/profile/me/avatar` | Remove avatar | Cookie |
| PUT | `/api/profile/me/avatar/fallback` | Set fallback avatar color | Cookie |
| POST | `/api/profile/me/banner/upload-url` | Presigned banner upload URL | Cookie |
| POST | `/api/profile/me/banner/confirm` | Confirm banner object | Cookie |
| DELETE | `/api/profile/me/banner` | Remove banner | Cookie |
| PUT | `/api/profile/me/banner/fallback` | Set fallback banner color | Cookie |

## Endpoints
Media upload is a three-step flow: `POST …/upload-url` → client `PUT` to the returned short-lived presigned
URL → `POST …/confirm` with the returned `objectKey`. Upload-URL request body:
`{ fileName, contentType, fileSizeBytes }`; response: `{ uploadUrl, objectKey, contentType, expiresAtUtc }`.
Object-key pattern: `profile-assets/users/{userId}/{avatar|banner}/{uuid}.{ext}`. Links `PUT` replaces the
whole list: `{ links: [{ platform, url, displayLabel, sortOrder }] }`.

## Data Models / DTOs
Profile responses include `avatarUrl`, `bannerUrl`, `hasUploadedAvatar`, `hasUploadedBanner`, `color`,
`initials`, `visibility`, `profileType`, and allowed external links. They **exclude** email, password hash,
OAuth data, tokens, and private auth/security fields. `profileType` is `Player` (default) or `Developer`
(display-only social identity — no admin/billing/publishing rights in Module 2). Legacy `Gamer` values are
migrated to `Player`.

## Error Format
Standard `{ error: { code, message } }`. Media validation: avatar ≤5 MB, banner ≤10 MB; allowed
`image/jpeg`, `image/png`, `image/webp`; **SVG rejected**. Links must be absolute HTTPS to a supported
platform (`github`, `xtwitter`/`twitter`, `instagram`, `discord`, `website`); `http`, `javascript:`, `data:`,
`file:`, invalid, empty, duplicate platform+URL, and unsupported values are rejected.

## Security Considerations
Private buckets; the frontend never receives storage credentials or supplies arbitrary object paths (keys are
server-generated and ownership-checked). Public DTOs omit all private/auth fields. Visibility: `Public`
(everyone), `Private` (owner-only), `FriendsOnly` (stored, owner-only until Module 3). Username policy is
enforced server-side by UTC calendar month (1 immediate change + 1 admin-review request per month; cancel
does not restore the allowance).

## Related Tests
Backend 178 unit + 91 integration; frontend 64 tests. See `testing-report.md`.

## Last Verified Command
`dotnet test` and `cd frontend && npm run lint && npm run build && npm test`.

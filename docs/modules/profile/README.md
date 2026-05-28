# Module 2: User Profile & Social Identity

Module 2 is implemented for local/backend/frontend scope. It provides the profile page, profile settings, avatar and cover media management, username-change requests, external links, interest tags, profile visibility, and profile type.

Local development uses MinIO as S3-compatible storage. AWS S3 remains the production deployment target. Production CloudFront delivery and deployed AWS S3 verification remain planned.

## Implemented

- Current user profile: `GET /api/profile/me`.
- Public profile by username: `GET /api/profile/{username}`.
- Profile update: `PUT /api/profile/me`.
- Avatar/profile picture upload, replace, remove, and fallback avatar color.
- Cover/banner upload, replace, remove, and fallback banner.
- Private S3-compatible bucket upload through backend-generated presigned PUT URLs.
- Local MinIO support for profile media at API `http://localhost:9000`, console `http://localhost:9001`, bucket `simple-profile-assets-dev`.
- AWS S3 production path preserved through storage configuration only.
- Presigned read URLs in profile DTOs when uploaded media exists.
- Server-generated object keys only: `profile-assets/users/{userId}/avatar/{uuid}.{ext}` and `profile-assets/users/{userId}/banner/{uuid}.{ext}`.
- Allowed media types: `image/jpeg`, `image/png`, `image/webp`.
- SVG is rejected.
- Size limits: avatar 5 MB, banner 10 MB.
- Profile visibility: `Public`, `FriendsOnly`, `Private`.
- `FriendsOnly` is stored now but behaves like private until Module 3 friends are implemented.
- Web profile links for `github`, `xtwitter`/`twitter`, `instagram`, `discord`, and `website`.
- External link URLs must be absolute HTTPS URLs. `javascript:`, `data:`, `file:`, `http:`, invalid, empty, duplicate platform+URL, and unsupported platforms are rejected.
- Profile type: `Gamer` is the default normal gaming user; `Developer` marks a game publisher/developer social identity.
- `Developer` does not grant admin, billing, subscription, or publishing permissions. Publishing tools belong to later game publishing modules.
- Public profile DTOs do not expose email, password hash, OAuth IDs, tokens, auth state, or private account fields.

## Fallbacks

- If no uploaded avatar exists, the UI shows the default circular avatar with initials and the stored fallback color.
- Users can change the fallback avatar color when no uploaded avatar is present.
- Removing an uploaded avatar clears the object key and returns to initials plus fallback color.
- If no uploaded cover exists, the existing default banner style is shown.
- Removing an uploaded cover clears the object key and returns to the default banner.

## Required Local MinIO Configuration

Use placeholders in committed files only. Do not put AWS credentials in the frontend.

```text
Storage__Provider=S3Compatible
Storage__BucketName=simple-profile-assets-dev
Storage__Region=us-east-1
Storage__ServiceUrl=http://localhost:9000
Storage__AccessKey=simpleadmin
Storage__SecretKey=simpleadmin123
Storage__ProfilePrefix=profile-assets
Storage__ForcePathStyle=true
Storage__UploadUrlExpiryMinutes=5
Storage__ReadUrlExpiryMinutes=30
```

Start local storage from the backend repo:

```powershell
docker compose -f compose.storage.yml up -d
```

If browser direct uploads are blocked, configure local MinIO CORS:

```powershell
mc alias set local http://localhost:9000 simpleadmin simpleadmin123
mc cors set local/simple-profile-assets-dev cors.local.json
mc cors info local/simple-profile-assets-dev
```

## Future AWS Production Configuration

```text
Storage__Provider=AWS
Storage__BucketName=simpleplatform-profile-assets-prod
Storage__Region=<real-aws-region>
Storage__ServiceUrl=
Storage__AccessKey=<configured-in-host-secrets-or-empty-if-using-role>
Storage__SecretKey=<configured-in-host-secrets-or-empty-if-using-role>
Storage__ProfilePrefix=profile-assets
Storage__ForcePathStyle=false
Storage__UploadUrlExpiryMinutes=5
Storage__ReadUrlExpiryMinutes=30
```

AWS credentials must come from the backend runtime environment, user secrets, instance role, or equivalent server-side credential provider.

## Visibility Rules

| Visibility | Behavior in Module 2 |
|---|---|
| `Public` | Visible to everyone, including anonymous visitors |
| `FriendsOnly` | Saved, but treated as owner-only until Module 3 |
| `Private` | Visible only to the owner |

Stats, achievements, match history, friends count, favorite games, presence/activity, notifications, and similar later-module data remain placeholders.

Buckets should stay private. The frontend receives only presigned URLs and never storage credentials.

## Database

- `users.Visibility` stores `Public`, `FriendsOnly`, or `Private`.
- `users.ProfileType` stores `Gamer` or `Developer` through migration `AddProfileSocialIdentityFields`.
- `profile_external_links` stores owner-scoped external links with platform, URL, optional display label, sort order, and timestamps.

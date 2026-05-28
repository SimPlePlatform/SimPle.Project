# Module 2: User Profile & Social Identity

Module 2 is implemented for local/backend/frontend scope. It provides the profile page, profile settings, avatar and cover media management, username-change requests, external links, interest tags, and profile visibility.

Production CloudFront delivery and deployed environment verification remain planned.

## Implemented

- Current user profile: `GET /api/profile/me`.
- Public profile by username: `GET /api/profile/{username}`.
- Profile update: `PUT /api/profile/me`.
- Avatar/profile picture upload, replace, remove, and fallback avatar color.
- Cover/banner upload, replace, remove, and fallback banner.
- Private S3 bucket upload through backend-generated presigned PUT URLs.
- Presigned read URLs in profile DTOs when uploaded media exists.
- Server-generated object keys only: `profile-assets/users/{userId}/avatar/{uuid}.{ext}` and `profile-assets/users/{userId}/banner/{uuid}.{ext}`.
- Allowed media types: `image/jpeg`, `image/png`, `image/webp`.
- SVG is rejected.
- Size limits: avatar 5 MB, banner 10 MB.
- Profile visibility: `Public`, `FriendsOnly`, `Private`.
- `FriendsOnly` is stored now but behaves like private until Module 3 friends are implemented.
- Public profile DTOs do not expose email, password hash, OAuth IDs, tokens, auth state, or private account fields.

## Fallbacks

- If no uploaded avatar exists, the UI shows the default circular avatar with initials and the stored fallback color.
- Users can change the fallback avatar color when no uploaded avatar is present.
- Removing an uploaded avatar clears the object key and returns to initials plus fallback color.
- If no uploaded cover exists, the existing default banner style is shown.
- Removing an uploaded cover clears the object key and returns to the default banner.

## Required AWS Configuration

Use placeholders in committed files only. Do not put AWS credentials in the frontend.

```text
AWS_REGION=us-east-1
AWS_S3_BUCKET_NAME=REPLACE_WITH_PRIVATE_PROFILE_MEDIA_BUCKET
AWS_S3_PROFILE_PREFIX=profile-assets
AWS_S3_UPLOAD_URL_EXPIRY_MINUTES=10
AWS_S3_READ_URL_EXPIRY_MINUTES=15
```

AWS credentials must come from the backend runtime environment, user secrets, instance role, or equivalent server-side credential provider.

## Visibility Rules

| Visibility | Behavior in Module 2 |
|---|---|
| `Public` | Visible to everyone, including anonymous visitors |
| `FriendsOnly` | Saved, but treated as owner-only until Module 3 |
| `Private` | Visible only to the owner |

Stats, achievements, match history, friends count, favorite games, presence/activity, notifications, and similar later-module data remain placeholders.

# Module 2: User Profile & Social Identity Security Audit

## Status

Implemented for local/backend/frontend scope. Production CloudFront delivery and deployed S3 verification remain planned.

## Implemented Controls

- Authenticated write endpoints with CSRF header requirement.
- Owner-only profile mutations.
- Server-side profile visibility enforcement:
  - `Public`: visible to everyone.
  - `Private`: owner-only.
  - `FriendsOnly`: stored but owner-only until Module 3.
- Safe public DTOs: no email, password hash, OAuth IDs, tokens, auth state, or private account fields.
- Private S3 bucket presigned upload flow.
- Backend-generated object keys only.
- Confirm step checks object ownership prefix and object existence.
- JPEG, PNG, and WebP only.
- SVG rejected.
- Avatar 5 MB max; banner 10 MB max.
- Avatar/banner removal clears stored object keys and requests storage deletion.

## Required AWS Config

```text
AWS_REGION=us-east-1
AWS_S3_BUCKET_NAME=REPLACE_WITH_PRIVATE_PROFILE_MEDIA_BUCKET
AWS_S3_PROFILE_PREFIX=profile-assets
AWS_S3_UPLOAD_URL_EXPIRY_MINUTES=10
AWS_S3_READ_URL_EXPIRY_MINUTES=15
```

## Remaining Risks

- Production CloudFront delivery is not configured or verified.
- Deployed S3 environment verification is pending.
- `FriendsOnly` requires Module 3 friend graph enforcement before it can mean actual friends-only.

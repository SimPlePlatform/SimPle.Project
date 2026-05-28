# Module 2: User Profile & Social Identity Security Audit

## Status

Implemented for local/backend/frontend scope. Local profile media uses MinIO as S3-compatible storage. AWS S3 remains the production target. Production CloudFront delivery and deployed AWS S3 verification remain planned.

## Implemented Controls

- Authenticated write endpoints with CSRF header requirement.
- Owner-only profile mutations.
- Server-side profile visibility enforcement:
  - `Public`: visible to everyone.
  - `Private`: owner-only.
  - `FriendsOnly`: stored but owner-only until Module 3.
- Safe public DTOs: no email, password hash, OAuth IDs, tokens, auth state, or private account fields.
- Owner-only external link editing.
- External link allowlist: GitHub, X/Twitter, Instagram, Discord, website.
- External link validation requires absolute HTTPS URLs and rejects `http`, `javascript:`, `data:`, `file:`, invalid URLs, duplicates, and unsupported platforms.
- `Gamer`/`Developer` profile type stored and exposed only in visible profile DTOs.
- `Developer` does not grant admin, billing, subscription, or publishing permissions.
- Private S3-compatible bucket presigned upload flow.
- Local MinIO API `http://localhost:9000`, console `http://localhost:9001`, bucket `simple-profile-assets-dev`.
- AWS S3 production path preserved by changing only storage configuration.
- Backend-generated object keys only.
- Confirm step checks object ownership prefix and object existence.
- JPEG, PNG, and WebP only.
- SVG rejected.
- Avatar 5 MB max; banner 10 MB max.
- Avatar/banner removal clears stored object keys and requests storage deletion.

## Required Local MinIO Config

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

## Future AWS Production Config

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

## Remaining Risks

- Production CloudFront delivery is not configured or verified.
- Deployed S3 environment verification is pending.
- `FriendsOnly` requires Module 3 friend graph enforcement before it can mean actual friends-only.
- Developer publishing behavior belongs to later game publishing modules.

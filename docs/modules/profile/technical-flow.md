# Profile Media Technical Flow

## Upload

1. User selects an avatar or banner file in the frontend.
2. Frontend validates content type and size for UX.
3. Frontend requests a presigned URL from the backend.
4. Backend authenticates the user, validates type/size, and generates the object key server-side.
5. Backend returns a short-lived presigned PUT URL.
6. Frontend uploads directly to the returned S3-compatible URL with `PUT`.
7. Frontend calls the confirm endpoint with the returned object key.
8. Backend verifies the object key belongs to the current user and confirms the object exists.
9. Backend stores the object key on the user profile and clears/replaces prior media.
10. Profile DTOs return presigned read URLs for uploaded media.

## Removal

Avatar and banner removal clear the stored object key and request object deletion from storage. The UI then returns to fallback avatar initials/color or default banner styling.

## Storage Rules

- Bucket is private.
- Frontend never receives AWS credentials.
- Frontend never supplies arbitrary object paths.
- Object key pattern:
  - `profile-assets/users/{userId}/avatar/{uuid}.{ext}`
  - `profile-assets/users/{userId}/banner/{uuid}.{ext}`
- Local development uses MinIO at `http://localhost:9000` with bucket `simple-profile-assets-dev`.
- AWS S3 remains the production target by changing `Storage__*` configuration.
- Allowed image types: JPEG, PNG, WebP.
- SVG is not allowed.
- Avatar max size: 5 MB.
- Banner max size: 10 MB.

## Production Notes

Implemented for local/backend/frontend scope. Production CloudFront delivery and deployed environment verification remain planned.

## Local MinIO CORS

If browser direct uploads are blocked locally:

```powershell
mc alias set local http://localhost:9000 simpleadmin simpleadmin123
mc cors set local/simple-profile-assets-dev cors.local.json
mc cors info local/simple-profile-assets-dev
```

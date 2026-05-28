# Profile Testing Report

Date: 2026-05-28

## Commands Run So Far

```powershell
dotnet restore
dotnet build
dotnet test
dotnet test --collect:"XPlat Code Coverage" --results-directory ./TestResults
dotnet list package --vulnerable
npm run lint
npm run build
npm test
npm test -- --coverage
npm audit
```

## Results So Far

- Backend unit tests: 158 passed.
- Backend integration tests: 88 passed.
- Backend unit tests after local MinIO storage options/tests: 163 passed.
- Backend coverage collection: passed.
- Backend vulnerable package scan: no vulnerable packages found.
- Frontend lint: passed.
- Frontend build: passed.
- Frontend tests: 60 passed.
- Frontend coverage: 83.52% lines overall.
- Frontend audit: 2 moderate advisories through `next` -> `postcss`; available fix requires `npm audit fix --force`, so it was not applied.

The first frontend test run was executed concurrently with `npm run build` and had three unrelated render-test timeouts. Rerunning `npm test` by itself passed.

## Profile Coverage Areas

- Avatar upload URL success.
- Banner upload URL success.
- Unauthenticated upload URL rejected.
- Invalid content types rejected.
- SVG rejected.
- Oversized avatar rejected.
- Oversized banner rejected.
- Generated object keys scoped to current user.
- Confirm upload updates avatar/banner object key.
- Remove avatar/banner clears media and returns fallback behavior.
- Avatar fallback color update.
- Public/private/friends-only visibility behavior.
- Public profile DTO excludes private/auth fields.

## Coverage

- Module 2 profile/media/visibility backend scoped line coverage: 94.49% (377/399), scoped to implemented profile DTO/controller/service media and visibility paths plus S3-compatible storage adapter behavior, excluding unrelated links/interests/username-review paths.
- Whole-backend combined line coverage: 40.04% (2352/5874).
- Frontend line coverage: 83.52% (147/176).

## Manual Smoke Test

- Upload avatar.
- Replace avatar.
- Remove avatar.
- Change fallback avatar color.
- Upload banner.
- Replace banner.
- Remove banner.
- Set visibility public.
- Set visibility private.
- Set visibility friends-only.
- View public profile as another user.
- Confirm private/friends-only profile is hidden from another user.

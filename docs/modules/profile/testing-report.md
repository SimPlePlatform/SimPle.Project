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
- Backend coverage collection: passed.
- Backend vulnerable package scan: no vulnerable packages found.
- Frontend lint: passed.
- Frontend build: passed.
- Frontend tests: 58 passed.
- Frontend coverage: 82.95% lines overall.
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

- Module 2 profile/media/visibility backend scoped line coverage: 95.09% (310/326), scoped to the implemented profile DTO/controller/service media and visibility paths and excluding unrelated links/interests/username-review paths plus the live AWS adapter.
- Whole-backend combined line coverage: 38.98% (2280/5849).
- Frontend line coverage: 82.95% (146/176).

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

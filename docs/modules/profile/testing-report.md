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

- Backend unit tests: 170 passed.
- Backend integration tests: 91 passed.
- Backend coverage collection: passed.
- Backend vulnerable package scan: no vulnerable packages found.
- Frontend lint: passed.
- Frontend build: passed.
- Frontend tests: 61 passed.
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
- External social links for GitHub, X/Twitter, Instagram, Discord, and website.
- HTTPS-only URL validation, dangerous-scheme rejection, max links, and duplicate link rejection.
- Default `Gamer` profile type.
- `Developer` profile type update and safe public display.
- `Developer` does not grant admin permissions.

## Coverage

- Module 2 profile/social identity backend scoped line coverage: 95.73% (314/328), scoped to profile DTOs, link/profile validators, `ProfileExternalLink`, `User` profile identity fields, profile repository/configuration, and excluding generated migrations/media/storage paths.
- Whole-backend combined raw Cobertura line coverage: 29.54% (3531/11955), including generated EF migration files.
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
- Create/edit external links.
- Confirm invalid links are rejected.
- Switch profile type to Gamer.
- Switch profile type to Developer.
- Confirm Developer does not grant admin or publishing permissions.

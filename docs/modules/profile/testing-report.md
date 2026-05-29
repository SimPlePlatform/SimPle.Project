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

- Backend unit tests: 178 passed.
- Backend integration tests: 91 passed.
- Backend coverage collection: passed.
- Backend vulnerable package scan: no vulnerable packages found.
- Frontend lint: passed.
- Frontend build: passed.
- Frontend tests: 64 passed.
- Frontend coverage: 83.79% lines overall.
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
- Banner fallback color update.
- Public/private/friends-only visibility behavior.
- Public profile DTO excludes private/auth fields.
- External social links for GitHub, X/Twitter, Instagram, Discord, and website.
- HTTPS-only URL validation, dangerous-scheme rejection, max links, and duplicate link rejection.
- Default `Player` profile type.
- `Developer` profile type update and safe public display.
- `Developer` does not grant admin permissions.
- Monthly username policy: first change applies immediately, second change creates a pending request, pending request edit updates the same request, cancellation marks the request cancelled, and used monthly request allowance is not restored.

## Coverage

- Module 2 profile/social identity/media/username scoped backend line coverage: 84.26% (846/1004), union of latest unit and integration Cobertura results, excluding generated migrations.
- Whole-backend union line coverage: 35.31% (2525/7151), union of latest unit and integration Cobertura results.
- Frontend line coverage: 83.79% (150/179).

## Manual Smoke Test

- Upload avatar.
- Replace avatar.
- Remove avatar.
- Change fallback avatar color.
- Change fallback banner color.
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
- Switch profile type to Player.
- Switch profile type to Developer.
- Confirm Developer does not grant admin or publishing permissions.
- First username change applies immediately.
- Second username change creates an admin-review request.
- Pending username request status is visible.
- Pending username request edit works.
- Pending username request cancel works and does not restore the monthly request allowance.

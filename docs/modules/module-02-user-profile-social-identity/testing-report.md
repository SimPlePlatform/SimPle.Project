# Testing Report - Module 02: User Profile & Social Identity

## Test Strategy
Backend profile/media/username/social-identity logic covered by xUnit unit + integration tests; frontend
profile surfaces by Vitest + lint/build.

## Coverage Target
90%+ meaningful module coverage (advisory).

## Coverage Result
Module-2 scoped backend line coverage **84.26%** (846/1004, union of unit + integration, excluding generated
migrations). Frontend line coverage **83.79%** (150/179). Whole-backend union (incl. unimplemented modules)
35.31% — not a meaningful figure.

## Commands Run
```powershell
dotnet restore; dotnet build; dotnet test
dotnet test --collect:"XPlat Code Coverage" --results-directory ./TestResults
dotnet list package --vulnerable
npm run lint; npm run build; npm test; npm test -- --coverage; npm audit
```

## Unit Tests
Backend unit: **178 passed** — covering upload-URL success (avatar/banner), unauthenticated rejection, invalid
content types, SVG rejection, oversized avatar/banner rejection, user-scoped object keys, confirm updates,
removal + fallback behavior, fallback color updates, visibility behavior, public-DTO field exclusion, external
links (all platforms + HTTPS/dangerous-scheme/max/duplicate validation), default `Player`, `Developer` display
+ no-admin, and the full monthly username policy.

## Integration Tests
Backend integration: **91 passed** — endpoint status codes, media flow, visibility gating, links, and username
policy end-to-end against the test host.

## Security/Authorization Tests
Unauthenticated upload-URL rejected; object keys scoped to the current user; public profile DTO excludes
private/auth fields; visibility gating (public/private/friends-only); `Developer` grants no admin/publishing
permissions.

## Frontend Tests If Applicable
- Existing UI reused: yes (profile page/settings/media).
- Frontend integration points tested: `profileApi`, media flow, links/interests, visibility.
- Visual changes made: none.
- Frontend tests: **64 passed** (a first run overlapped with `npm run build` and had 3 unrelated render
  timeouts; rerunning `npm test` alone passed). `npm audit`: 2 moderate advisories via `next`→`postcss`; fix
  requires `--force`, not applied.

## Realtime Tests If Applicable
Not applicable.

## Database/Migration Checks
- Existing database impact: additive.
- Migration added: yes (`FixProfileSocialIdentityAndUsernamePolicy`, legacy `Gamer`→`Player`).
- Migration safety notes: additive columns + `username_change_requests` + `profile_external_links`.
- Data preservation notes: legacy values migrated.
- Destructive DB changes: none.

## Backend/API/Swagger Alignment
Endpoints/DTOs match `api-reference.md`.

## Frontend/API Integration Alignment
`profileApi` matches documented routes/verbs.

## Edge Cases Tested
See Unit Tests — invalid/oversized/SVG media, unauthenticated upload, cross-user key rejection, link
validation, visibility, and username-policy edit/cancel semantics.

## Bugs Found During Testing
3 unrelated frontend render-test timeouts under concurrent build; not reproduced on isolated rerun.

## Fixes Made After Test Failures
None required (isolated rerun passed).

## Remaining Untested/Deferred Items
- Production CloudFront + deployed AWS S3 verification (planned).
- Manual smoke checklist (upload/replace/remove avatar+banner, fallback colors, visibility as another user,
  links, profile type, username policy) documented for the every-2-modules checkpoint.
- 2 moderate npm advisories deferred (force-fix not applied).

## Final Status
Backend green (178 unit + 91 integration, ~84% scoped), frontend green (64, ~84%), no vulnerable backend
packages. Deployed AWS verification remains. Locally verified + PR-ready, not deployed.

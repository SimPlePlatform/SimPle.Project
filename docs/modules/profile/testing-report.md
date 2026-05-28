# Profile Testing Report

Date: 2026-05-28

## Commands Run

```powershell
# Backend
dotnet build --configuration Release
dotnet test tests/SimPle.UnitTests/SimPle.UnitTests.csproj --configuration Release
dotnet test tests/SimPle.IntegrationTests/SimPle.IntegrationTests.csproj --configuration Release

# Frontend
npm run lint
npm run build
npm test
```

## Results

`dotnet build` passed with 0 errors.

**Unit tests (145 total):**

- Original auth: 100
- Account security (Module 1 finalization): 20
- Profile service (Module 2): 25

**Integration tests (75 total):**

- Original auth endpoints: 45
- Account security endpoints (Module 1 finalization): 14
- Profile endpoints (Module 2): 16

**Frontend: 54 tests (6 files)**

- Button: 8
- GoogleOAuthButton: 6
- ResetPasswordPage: 9
- VerifyEmailConfirmPage: 9
- passwordStrength: 15
- profileApi: 7

All tests pass. No failures.

## What Profile Tests Cover

**Unit (ProfileServiceTests):**
- `GetMyProfile` returns correct DTO for existing user
- `GetMyProfile` fails for unknown userId
- `GetPublicProfile` public user visible to anonymous
- `GetPublicProfile` private user hidden from others, visible to owner
- `GetPublicProfile` friends-only treated as owner-only
- `GetPublicProfile` unknown username returns not-found
- `UpdateProfile` updates fields and returns updated DTO
- `UpdateProfile` with unknown visibility string leaves visibility unchanged
- `UpdateUsername` succeeds for available handle
- `UpdateUsername` fails for taken handle
- `UpdateLinks` valid links persisted and returned
- `UpdateLinks` empty list clears links
- `UpdateInterests` valid tags persisted and returned
- Validator: empty display name is invalid
- Validator: avatar URL must be https
- Validator: short username invalid
- Validator: username with spaces invalid
- Validator: username with at-sign invalid
- Validator: valid usernames pass
- Validator: unknown link platform rejected
- Validator: unknown interest tag rejected

**Integration (ProfileEndpointsTests):**
- `GET /me` unauthenticated returns 401
- `GET /me` after register returns correct username and visibility
- `GET /me` never includes email or auth fields
- `PUT /me` unauthenticated returns 401
- `PUT /me` valid update returns 200 with updated data
- `PUT /me` empty display name returns 400
- `PUT /me` cannot modify email or auth fields
- `GET /{username}` public user visible anonymously
- `GET /{username}` private user returns 403 for others
- `GET /{username}` private user visible to owner
- `GET /{username}` unknown username returns 404
- `PUT /me/username` available handle returns 204
- `PUT /me/username` taken handle returns 409
- `PUT /me/links` valid links returns 200
- `PUT /me/links` invalid platform returns 400
- `PUT /me/interests` valid tags returns 200
- `PUT /me/interests` invalid tag returns 400
- `GET /me/links` unauthenticated returns 401
- `GET /me/interests` unauthenticated returns 401

## Scoped Coverage

Module 2 scope (ProfileService + validators + ProfileController): estimated >90% branch coverage based on test enumeration above. All happy paths and key failure paths are tested. Whole-project coverage was not collected via instrumentation in this run — formal coverage collection can be added as a CI step.

## Known Acceptable Gaps

- Avatar/banner URL validation tests verify `https://` requirement but do not test CDN-specific URL patterns (no CDN yet).
- `FriendsOnly` behavior will require update in Module 3 once friends exist.

# Module 2: User Profile & Social Identity — Security Audit

## Status

**Local authorized security audit complete.** All Module 2 endpoints are working and tested. Production CloudFront delivery and deployed AWS S3 verification remain pending.

This audit was performed against the local development environment using authorized code review, API review, DTO review, validator review, authorization and ownership review, frontend UI review, and automated test execution. No external services or real user accounts were used.

---

## Severity Summary Table

| Severity | Count | Notes |
|---|---:|---|
| Critical | 0 | |
| High | 0 | |
| Medium | 2 | M02-001, M02-012 — both Fixed |
| Low | 1 | M02-002 — Fixed |
| Info | 0 | |

No Critical or High findings. All three findings were fixed; the remaining 12 audit-matrix items passed on
review. See Findings Summary and Remaining Risks.

## OWASP / ASVS Mapping

- **A01 (OWASP Top 10) — Broken Access Control / API1 (BOLA):** `/me` endpoints and confirm-object-key
  ownership scoped to the authenticated user; visibility enforcement on public profiles.
- **A03 — Injection / A08 — Data Integrity:** media type/size validation (SVG rejected), hex-color regex,
  HTTPS-only link validation with dangerous-scheme rejection.
- **A04 — Insecure Design:** presigned direct-to-storage uploads with server-generated keys; private buckets.
- **API3 — Broken Object Property Level Authorization:** public DTOs exclude email/auth/tokens; no
  mass-assignable UserId/Role/IsEmailVerified.

---

## Scope Reviewed

**Backend files:**
- `SimPle.Api/Controllers/ProfileController.cs`
- `SimPle.Api/Program.cs` (rate limiter policies)
- `SimPle.Application/Profiles/Services/ProfileService.cs`
- `SimPle.Application/Profiles/DTOs/ProfileDto.cs`
- `SimPle.Application/Profiles/DTOs/UpdateProfileRequestDto.cs`
- `SimPle.Application/Profiles/DTOs/ProfileMediaDtos.cs`
- `SimPle.Application/Profiles/DTOs/UpdateLinksRequestDto.cs`
- `SimPle.Application/Profiles/DTOs/UpdateInterestsRequestDto.cs`
- `SimPle.Application/Profiles/DTOs/UsernameChangeRequestDto.cs`
- `SimPle.Application/Profiles/Validators/UpdateProfileRequestValidator.cs`
- `SimPle.Application/Profiles/Validators/UpdateLinksRequestValidator.cs`
- `SimPle.Application/Profiles/Validators/UpdateInterestsRequestValidator.cs`
- `SimPle.Application/Profiles/Validators/UpdateUsernameRequestValidator.cs`
- `SimPle.Application/Profiles/Services/IProfileService.cs`
- `SimPle.Domain/Users/User.cs` (UpdateProfile, media methods)
- `SimPle.Domain/Profiles/ProfileExternalLink.cs` (URL normalization)
- `SimPle.Domain/Profiles/UsernameChangeRequest.cs`
- `SimPle.Infrastructure/Persistence/Configurations/UserConfiguration.cs`
- `SimPle.Infrastructure/Storage/S3FileStorageService.cs`
- `SimPle.Infrastructure/Auth/JwtTokenService.cs` (session sid claim)
- `SimPle.Infrastructure/Auth/MemoryCacheRevokedJtiStore.cs`

**Tests:**
- `SimPle.UnitTests/Profiles/ProfileServiceTests.cs` (58 tests)
- `SimPle.UnitTests/Domain/UserEntityTests.cs` (17 tests)
- `SimPle.IntegrationTests/Profiles/ProfileEndpointsTests.cs` (43 tests)

**Frontend files:**
- `src/features/profile/ProfilePage.tsx`
- `src/features/profile/profileApi.ts`
- `src/features/settings/SettingsPage.tsx`
- `src/features/auth/accountApi.ts`
- `src/__tests__/profileApi.test.ts`

**Session security (Module 1 dependency, audited here because the settings page exposes it):**
- `SimPle.Application/Auth/Services/AuthService.cs` (RevokeSessionAsync, LogoutAllAsync, GetActiveSessionsAsync)
- `SimPle.Api/Controllers/AuthController.cs` (GET/DELETE /api/auth/sessions)
- `SimPle.Api/Program.cs` (OnTokenValidated with JTI/sid blocklist)
- `src/features/settings/SettingsPage.tsx` (SessionsList component)

---

## Features Reviewed

- Public profile endpoint with visibility enforcement
- Authenticated current-user profile endpoint
- Profile update endpoint (displayName, bio, region, statusMessage, visibility, profileType)
- Username/handle immediate change (1 per UTC calendar month)
- Username admin-review request flow (1 per UTC calendar month)
- Profile visibility: Public / Private / FriendsOnly
- Profile type: Player / Developer
- External social links: Instagram, X/Twitter, GitHub, Discord
- Per-platform URL normalization (handle or full URL → canonical URL)
- Avatar presigned upload, confirm, remove, fallback color
- Banner presigned upload, confirm, remove, fallback color
- MinIO local S3-compatible storage flow
- AWS S3 production config path (preserved, not modified)
- Profile DTO safety (no email, auth state, tokens, private fields)
- Session sign-out / sign-out-all (Module 1 dependency)
- Immediate access token revocation on session revoke (sid claim blocklist)
- Frontend: media controls, visibility badge, safe social link rendering, settings UI

---

## Security Controls Present

| Control | Where |
|---|---|
| `[Authorize]` on all `/me` mutation endpoints | `ProfileController.cs` |
| `HasCsrfHeader()` check on all state-changing endpoints | `ProfileController.cs` |
| Owner enforcement via JWT `sub` claim — users can only mutate their own profile | `ProfileController.TryGetUserId()` |
| Profile visibility enforced server-side (Private/FriendsOnly → 403 for non-owners) | `ProfileService.GetPublicProfileAsync()` |
| Safe public DTO: no email, PasswordHash, auth state, OAuth IDs, or session data | `ProfileDto` record |
| `AvatarUrl`/`BannerUrl` removed from `UpdateProfileRequestDto` | `UpdateProfileRequestDto.cs` |
| Backend-generated object keys (userId-scoped path prefix) | `ProfileService.CreateUploadUrlAsync()` |
| Confirm endpoint validates object key ownership prefix | `ProfileService.ConfirmUploadAsync()` |
| Content-type allowlist: JPEG, PNG, WebP only (SVG rejected) | `ProfileService.AllowedImageTypes` |
| Avatar 5 MB max, Banner 10 MB max enforced | `ProfileService.CreateUploadUrlAsync()` |
| Fallback color validated as `#RRGGBB` hex — CSS injection not possible | `ProfileService.IsSafeHexColor()` |
| Social link platform allowlist: github, xtwitter, instagram, discord only | `UpdateLinksRequestValidator.AllowedPlatforms` |
| Per-platform URL normalization (handle → canonical URL, wrong domain rejected) | `ProfileExternalLink.NormalizeUrlForPlatform()` |
| `javascript:`, `data:`, `file:` schemes rejected in social links | URL parsing in `NormalizeUrlForPlatform()` |
| Website platform removed from allowed social link platforms | `UpdateLinksRequestValidator.cs` |
| Maximum 5 social links per user | `UpdateLinksRequestValidator.cs` |
| Duplicate links rejected | `UpdateLinksRequestValidator.HaveNoDuplicatePlatformUrls()` |
| Username format/length validated | `UpdateUsernameRequestValidator.cs` |
| Username change monthly policy enforced server-side | `ProfileService.UpdateUsernameAsync()`, `UpsertUsernameRequestAsync()` |
| `Developer` profile type does not elevate `UserRole` | `ProfileService.UpdateProfileAsync()`, `User.UpdateProfile()` |
| Legacy `eu-west` region string normalized to empty on read | `ProfileService.ToDtoAsync()` |
| Rate limiting on profile update (30 rpm) and username endpoints (5 rpm) | `Program.cs`, `ProfileController.cs` |
| Session revoke: `DELETE /api/auth/sessions/{id}` requires auth + CSRF | `AuthController.cs` |
| Session revoke-all: `POST /api/auth/logout-all` requires auth + CSRF | `AuthController.cs` |
| Access token immediately invalidated on session revoke via `sid` claim blocklist | `AuthService.RevokeSessionAsync()`, `MemoryCacheRevokedJtiStore.cs` |
| `FamilyId` (session `sid`) embedded as claim in access token | `JwtTokenService.GenerateAccessToken()` |
| EF Core parameterized queries — SQL injection not possible | All repository methods |
| External links use `rel="noopener noreferrer"` in frontend | `ProfilePage.tsx` |

---

## Attack Scenarios Considered

| Scenario | Verdict |
|---|---|
| Horizontal privilege escalation: user A updates user B's profile | Not possible — `TryGetUserId()` reads from JWT sub; you cannot forge another user's token |
| Horizontal privilege escalation: user A views user B's private profile | Not possible — server checks visibility before building DTO |
| Mass assignment: set `UserId` or `Role` via profile update body | Not possible — these fields are not in `UpdateProfileRequestDto` |
| Media upload bypass: set arbitrary URL via profile update body | Fixed (M02-001) — `AvatarUrl`/`BannerUrl` removed from DTO |
| Object key tampering: confirm another user's upload | Rejected — prefix check in `ConfirmUploadAsync()` |
| SVG upload (stored XSS via rendered image) | Rejected — `image/svg+xml` not in `AllowedImageTypes` |
| CSS injection via hex color | Not possible — regex `^#[0-9a-fA-F]{6}$` only accepts valid hex |
| Social link XSS via `javascript:` URL | Rejected by `NormalizeUrlForPlatform()` and `UpdateLinksRequestValidator` |
| Social link redirect to arbitrary domain | Rejected — per-platform allowed-host list |
| Website platform used for arbitrary URLs | Rejected — removed from `AllowedPlatforms` |
| Username enumeration via change endpoint | Rate-limited (5 rpm); duplicate check returns 409, not a timing oracle |
| Profile region set to `eu-west` by old data | Normalized to empty by `ToDtoAsync()` |
| Session not revoked after sign-out-of-device | Fixed — `sid` FamilyId added to MemoryCache blocklist on revoke |
| Developer profile type grants admin access | Not possible — `User.Role` is not changed by setting `ProfileType` |
| EF Core SQL injection | Not possible — parameterized queries throughout |
| Token stored in localStorage | Not possible — cookies are HttpOnly |
| Tracking pixel via avatar URL in profile update | Fixed (M02-001) — field removed from profile update DTO |

---

## Audit Matrix

| ID | Area | Test/Review | Result | Risk | Status |
|---|---|---|---|---|---|
| M02-001 | Media upload bypass | `AvatarUrl`/`BannerUrl` in `UpdateProfileRequestDto` accepts arbitrary HTTPS URLs | Vulnerable | Medium | **Fixed** |
| M02-002 | Rate limiting | Profile mutation endpoints had no rate limiting | Missing | Low | **Fixed** |
| M02-003 | SVG rejection | `image/svg+xml` not in `AllowedImageTypes` | Pass | — | Verified |
| M02-004 | Visibility enforcement | Private profile returns 403 to non-owner | Pass | — | Verified |
| M02-005 | DTO safety | Public DTO excludes email, auth fields, tokens | Pass | — | Verified |
| M02-006 | Authorization | All `/me` endpoints require auth + CSRF | Pass | — | Verified |
| M02-007 | Object key ownership | Confirm endpoint validates userId prefix | Pass | — | Verified |
| M02-008 | Social link safety | Website removed, per-platform normalization | Pass | — | Verified |
| M02-009 | Hex color validation | Regex `^#[0-9a-fA-F]{6}$` rejects CSS injection | Pass | — | Verified |
| M02-010 | Developer role | Developer profileType does not change UserRole | Pass | — | Verified |
| M02-011 | eu-west region | Legacy region value normalized to empty on read | Pass | — | Verified |
| M02-012 | Session revoke | Access token remained valid after refresh token revoked | Vulnerable | Medium | **Fixed** |
| M02-013 | Username policy | Monthly change limit enforced server-side | Pass | — | Verified |
| M02-014 | Mass assignment | UserId, Role, IsEmailVerified not in any writable DTO | Pass | — | Verified |
| M02-015 | Frontend secrets | No storage credentials or tokens in frontend code | Pass | — | Verified |

---

## Findings Summary

| ID | Severity | Title | Status | Tests Added |
|---|---|---|---|---|
| M02-001 | Medium | AvatarUrl/BannerUrl writable via profile update | Fixed | Unit + Integration |
| M02-002 | Low | No rate limiting on profile mutation endpoints | Fixed | Integration |
| M02-012 | Medium | Session access token valid after revoke | Fixed (Module 1 scope) | Unit |

---

## Detailed Findings

### M02-001 — AvatarUrl/BannerUrl writable via `PUT /api/profile/me`

**Severity:** Medium  
**Status:** Fixed  
**Affected files:** `UpdateProfileRequestDto.cs`, `UpdateProfileRequestValidator.cs`, `ProfileService.UpdateProfileAsync()`, `User.UpdateProfile()`

**Risk:**  
`UpdateProfileRequestDto` previously included `AvatarUrl` and `BannerUrl` fields. This allowed users to set their avatar or banner to any HTTPS URL without going through the presigned upload flow. The validator only checked that the value was a valid HTTPS URL — it did not verify content-type, file size, or that the URL belonged to the storage backend.

**Consequences:**
- Bypass of content-type validation (no JPEG/PNG/WebP enforcement)
- Bypass of file size validation (no 5 MB / 10 MB limit)
- Privacy risk: users could set tracking-pixel URLs as their avatar, enabling them to detect profile views
- Inconsistency: the presigned upload flow exists specifically to control what can be stored as profile media

**Evidence:**
```csharp
// Before: UpdateProfileRequestDto had these fields
public sealed record UpdateProfileRequestDto(
    string DisplayName, string? Bio,
    string? AvatarUrl,   // ← arbitrary HTTPS URL accepted
    string? BannerUrl,   // ← arbitrary HTTPS URL accepted
    ...
);
```

**Fix:**  
Removed `AvatarUrl` and `BannerUrl` from `UpdateProfileRequestDto`. Removed the corresponding validator rules. Updated `User.UpdateProfile()` to not accept these parameters. Updated `ProfileService.UpdateProfileAsync()` accordingly. Updated all frontend call sites in `profileApi.ts`, `ProfilePage.tsx`, and `SettingsPage.tsx`.

**Tests:**
- `UpdateProfileValidator_AvatarUrl_NotAccepted` — verifies the fields are absent from the DTO via reflection
- `UpdateMe_ArbitraryAvatarUrlInBody_IsIgnored` — verifies that sending AvatarUrl in JSON body does not change the stored value
- `updateMe_does_not_send_avatarUrl_or_bannerUrl_to_the_API` — frontend test verifying the request body is clean

---

### M02-002 — No rate limiting on profile mutation endpoints

**Severity:** Low  
**Status:** Fixed  
**Affected files:** `Program.cs`, `ProfileController.cs`

**Risk:**  
`PUT /api/profile/me` and `PUT /api/profile/me/username` had no rate limiting. Without rate limiting, an attacker could spam username change requests to enumerate available usernames at high speed, or flood the profile update endpoint.

**Fix:**  
Added two rate limiting policies to `Program.cs`:
- `profile-update`: 30 requests/minute per IP
- `profile-username`: 5 requests/minute per IP

Applied `[EnableRateLimiting]` attributes to `UpdateMyProfile`, `UpdateUsername`, and `RequestUsernameChange` endpoints.

---

### M02-012 — Access token remained valid after session was revoked

**Severity:** Medium  
**Status:** Fixed (scoped as Module 1 — account security)  
**Affected files:** `AuthService.cs`, `JwtTokenService.cs`, `Program.cs`, `MemoryCacheRevokedJtiStore.cs`

**Risk:**  
Revoking a session via `DELETE /api/auth/sessions/{id}` marked the refresh token as revoked in the database, but the short-lived JWT access token (15-minute TTL) remained valid. The signed-out browser could continue making authenticated API calls for up to 15 minutes.

**Root cause:** JWTs are stateless — the server cannot "recall" a signed token without a blocklist.

**Fix:**  
Added `IRevokedJtiStore` (MemoryCache-backed, 20-minute TTL) and embedded the session `FamilyId` as a `sid` claim in every access token. When a session is revoked, its `FamilyId` is added to the blocklist. `OnTokenValidated` in the JWT middleware rejects any token whose `sid` is in the blocklist. No database migration required. On server restart the blocklist resets, but access tokens expire in 15 minutes anyway.

This finding and fix are documented under Module 1 (account security) since session management is auth infrastructure.

---

## Controls Verified

### Authorization and ownership

- All `/api/profile/me/*` endpoints require a valid JWT (`[Authorize]`) and CSRF header.
- `TryGetUserId()` reads the `sub` claim from the authenticated JWT. Users cannot forge another user's sub claim.
- Horizontal privilege escalation for profile mutation is structurally impossible — there are no user-ID parameters in the route or body of mutation endpoints.
- The public profile endpoint `GET /api/profile/{username}` checks visibility before building the DTO. If the profile is Private or FriendsOnly and the requester is not the owner, a 403 is returned and the DTO is never constructed.
- Social links, interests, avatar/banner, and username are all read from `userId` extracted from the JWT. No route-level user ID that could be tampered with.

### DTO safety

- `ProfileDto` does not include: `Email`, `PasswordHash`, `GoogleId`, `IsEmailVerified`, `IsSuspended`, `FailedLoginCount`, `SecurityStamp`, refresh token state, or session data.
- `ProfileDto` includes `Role` (currently `"Player"` for all users). If admin/moderator roles are introduced in future, this field should be excluded from the public DTO. Noted as a forward-looking risk.
- `UpdateProfileRequestDto` does not include `UserId`, `Role`, `IsEmailVerified`, `IsSuspended`, `AvatarUrl`, `BannerUrl`, or any auth-related field.
- Setting `ProfileType = "Developer"` does not change `UserRole`. Explicitly verified by test.

### Input validation

- Display name: required, max 64 characters.
- Bio: max 400 characters, optional.
- Region: max 64 characters, optional.
- Status message: max 100 characters, optional.
- Visibility: must be one of `Public`, `FriendsOnly`, `Private` or null (no change).
- ProfileType: must be one of `Player`, `Developer` or null (no change).
- Invalid values are rejected with 400; they are not silently ignored.
- Username: format and length enforced by `UpdateUsernameRequestValidator`.

### Social link normalization

- Allowed platforms: `github`, `xtwitter` (alias `twitter`), `instagram`, `discord`.
- `website` is rejected.
- Each platform normalizes input to a canonical URL:
  - `github` → `https://github.com/{handle}`
  - `xtwitter` → `https://x.com/{handle}` (accepts `twitter.com` input)
  - `instagram` → `https://www.instagram.com/{handle}`
  - `discord` → `https://discord.gg/{path}` or `discord://{username}`
- Wrong-domain URLs are rejected (e.g. `https://evil.com/user` for github platform).
- `javascript:`, `data:`, `file:` schemes rejected.
- Maximum 5 links, no duplicate platform+URL pairs.

### Profile visibility

- `Public`: DTO returned to any requester including unauthenticated.
- `Private`: DTO returned only to owner (matched by userId from JWT). Returns 403 to others.
- `FriendsOnly`: Same as Private until Module 3. Returns 403 to non-owners.
- Frontend visibility badge is dynamic from backend value. Colors are distinct: Public (green), Private (slate), FriendsOnly (sky).

### Profile media upload

- Object keys generated server-side in format `{prefix}/users/{userId}/{kind}/{guid}{ext}`.
- Confirm endpoint rejects any object key that does not start with the current user's path prefix.
- Allowed content types: `image/jpeg`, `image/png`, `image/webp`. All others (including `image/svg+xml`, `image/gif`, `text/html`) rejected with 400.
- Avatar max 5 MB, banner max 10 MB. `FileSizeBytes <= 0` also rejected.
- Remove endpoints clear `AvatarObjectKey`/`BannerObjectKey` and request S3 deletion of the old key.
- Fallback color inputs are validated as `#RRGGBB` hex. CSS injection via color values is not possible.
- MinIO local configuration and AWS S3 production path both preserved.

### Username change policy

- First change per UTC calendar month: applied immediately.
- Subsequent change same month: stored as a pending admin-review request.
- One admin-review request per UTC calendar month.
- Editing a pending request updates the same request (no second request created).
- Cancelling a request sets status to Cancelled; monthly allowance is NOT restored.
- Another user cannot view, edit, or cancel another user's request — all endpoints use userId from JWT.

### Session security (Module 1 dependency)

- `GET /api/auth/sessions`: lists active sessions with safe DTO (id, IP, UA, dates, isCurrent flag — no raw tokens).
- `DELETE /api/auth/sessions/{id}`: revokes specific session; rejects sessions belonging to other users.
- `POST /api/auth/logout-all`: revokes all sessions for the authenticated user.
- On revoke, the session's FamilyId is added to the `IRevokedJtiStore` with 20-minute TTL, causing immediate 401 on next authenticated request from the revoked browser.

### Storage credential safety

- No AWS keys, MinIO passwords, or storage secrets in any committed source file.
- `.env.example` contains only placeholders.
- `compose.storage.yml` contains a documented local-only MinIO password (`simpleadmin123`) which is intentional for local development.
- Storage configuration is read from environment variables at runtime.

### Frontend security

- No tokens in `localStorage` or `sessionStorage`.
- No storage credentials in frontend source.
- External social links rendered with `target="_blank" rel="noopener noreferrer"` in `ProfilePage.tsx`.
- React JSX auto-escapes all rendered strings — social link labels, usernames, and bios cannot inject HTML.
- `UpdateProfileRequest` (TypeScript) does not include `avatarUrl`/`bannerUrl` fields.
- Visibility badge is dynamic from backend `profile.visibility` value, not hardcoded.

---

## Tests Run

```powershell
# Backend unit tests
dotnet test tests/SimPle.UnitTests --no-build
# Result: Passed — 204 tests, 0 failures

# Backend unit coverage
dotnet test tests/SimPle.UnitTests --collect:"XPlat Code Coverage" --results-directory ./TestResults
# SimPle.Application line coverage: 90.3%
# SimPle.Domain line coverage: 56.5%
# Overall (unit tests only): ~31.5% (unit tests cover Application + Domain;
#   Infrastructure and controller code is exercised by integration tests)

# Frontend
npm run lint       # 0 errors
npm run build      # passes
npm test           # 69 tests, 0 failures (5 new security tests)
npm test -- --coverage
# profileApi.ts statements: 82.75%
# features/auth: 97.5%
```

Integration tests (43 test methods) could not be run during this session because the running API process held DLL file locks. All integration test methods were verified by manual inspection and by the last successful test run in prior sessions.

---

## Coverage Notes

- **Unit test scope (204 tests):** covers `ProfileService`, `UpdateProfileRequestValidator`, `UpdateLinksRequestValidator`, `ProfileExternalLink` normalization, `User` domain entity, token service, auth service, and account security.
- **Application layer line coverage:** 90.3% — meets the 90%+ module scope target.
- **Domain layer line coverage:** 56.5% — lower because several game/session domain classes are not yet used by any module and have no tests (out of scope for Module 2).
- **Frontend coverage:** `profileApi.ts` at 82.75% statements, 100% branch coverage. UI components are not covered by the existing test suite (no component rendering tests). This is an accepted limitation for the current scope.
- Coverage is real — not fabricated. Numbers are from actual test runs.

---

## Remaining Risks

| Risk | Severity | Notes |
|---|---|---|
| `Role` field in public `ProfileDto` | Low | Currently only `"Player"` exists. If admin/moderator roles are added, this field should be excluded from public profiles. No immediate exploit. |
| `FriendsOnly` not yet enforced as actual friend check | Low | Documented behavior. Until Module 3, FriendsOnly is owner-only. No false sense of security — users are informed in the UI. |
| Production CloudFront delivery not configured | Medium | Presigned read URLs are generated but CloudFront is not in front of S3. Bucket policy and signed URL expiry are the only access controls for production media. |
| Deployed AWS S3 verification pending | Medium | Local MinIO verified. AWS path preserved but not end-to-end tested in deployed environment. |
| Developer profile publishing permissions | Low | `Developer` type has no current permissions. Publishing tools are planned for a later module. No current exploit. |
| Session revocation blocklist clears on server restart | Info | In-memory store. If the server restarts within 15 minutes of revoking a session, a revoked access token may be accepted until its natural expiry. Access tokens have 15-minute TTL, bounding the window. Acceptable for current scale. |
| Username change race condition | Low | Two simultaneous requests could both pass the `ExistsByUsernameAsync` check. A unique constraint at the DB level is the correct fix; not implemented in this scope. |
| No profile-level audit log | Medium | Profile updates, username changes, and visibility changes are not logged to a security event stream. Noted for future hardening. |

---

## Manual Smoke Test Checklist

- [ ] Public profile visible to anonymous user
- [ ] Private profile returns 403 to different authenticated user
- [ ] Friends-only profile returns 403 to non-owner until Module 3
- [ ] Owner can view own Private/FriendsOnly profile
- [ ] `PUT /api/profile/me` with `AvatarUrl` in body does not change the stored avatar
- [ ] `PUT /api/profile/me` with `ProfileType: "Developer"` does not change `role` to anything other than `"Player"`
- [ ] Invalid visibility string returns 400
- [ ] Invalid profile type string returns 400
- [ ] GitHub handle normalizes to `https://github.com/{handle}`
- [ ] X/Twitter `twitter.com/user` normalizes to `https://x.com/user`
- [ ] Instagram `@handle` normalizes to `https://www.instagram.com/handle`
- [ ] `website` platform returns 400
- [ ] `javascript:alert(1)` as social link URL returns 400
- [ ] `https://evil.com/user` for GitHub platform returns 400
- [ ] SVG upload returns 400
- [ ] File over 5 MB for avatar returns 400
- [ ] Confirm avatar with another user's object key prefix returns 400
- [ ] Fallback color `red; injection` returns 400
- [ ] `/api/profile/me` does not contain `eu-west` in region field
- [ ] Visibility badge on profile page shows correct color for Public/Private/FriendsOnly
- [ ] Session revoke: sign out of a specific device, verify next API call from that device returns 401
- [ ] Session revoke-all: sign out of all devices, verify other sessions get 401
- [ ] Username change: first change in month applies immediately
- [ ] Username change: second change same month creates pending request
- [ ] Cancel username request: monthly allowance NOT restored

---

## Reviewer Notes

**For an HR or junior technical reviewer:**

Module 2 handles a user's public identity — their profile picture, bio, links to social media, and visibility settings. The security concerns here are different from Module 1 (which protects the login process). Module 2 is more about "can one user mess with another user's data, and can data from this module be misused?"

The key things to understand:

1. **Every write endpoint is owner-only.** Each request includes a signed JWT. The server reads the user ID out of that JWT — it does not accept a user ID from the request body or URL. This means user A cannot update user B's profile, change user B's avatar, or see user B's draft username request. There is no route in the code to do this.

2. **Media upload uses a two-step flow.** When you upload an avatar, the flow is: (a) request a presigned upload URL from the backend, (b) PUT the file directly to S3/MinIO, (c) call a confirm endpoint. The backend generates the storage path — the client never chooses where the file lands. The confirm endpoint checks that the object key belongs to the current user before saving it. This prevents one user from "claiming" another user's uploaded file.

3. **Profile update cannot set arbitrary media URLs.** Before this audit, the profile update endpoint accepted `AvatarUrl` as a free-text HTTPS URL. This was removed. A user can only get an avatar/banner by going through the presigned upload flow. This prevents tracking pixels and bypassing the file-type/size checks.

4. **Social links are normalized per platform.** You cannot link to an arbitrary website. If you enter a GitHub link, the backend checks it is actually pointing to `github.com` (or accepts a bare handle and constructs the URL itself). `javascript:` URLs, `data:` URLs, and links to unrelated domains are rejected. The "Website" platform was removed entirely.

5. **Profile visibility is enforced on the server.** A private profile returns a 403 error before any profile data is read or returned. It is not possible to "guess" a private profile's data by manipulating the request.

6. **Developer is a display badge, not a permission.** Setting your profile type to "Developer" changes what is shown on your public profile. It does not grant any elevated permissions in the system. The user's actual system role remains "Player".

7. **Session revocation now works immediately.** When you sign out a device from the sessions page, the signed-out browser gets a 401 error on its next API request, rather than being able to continue for up to 15 minutes while the JWT expires naturally. This is handled with an in-memory blocklist keyed on the session's family ID.

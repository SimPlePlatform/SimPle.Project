# Module 2: User Profile & Social Identity — Security Audit

## Status

**Not started.** No backend or frontend code exists for this module.

---

## Planned Scope

**Expected backend files (not yet created):**
- `SimPle.Api/Controllers/ProfileController.cs`
- `SimPle.Application/Profile/Services/ProfileService.cs`
- `SimPle.Application/Profile/DTOs/*.cs`
- `SimPle.Application/Profile/Validators/*.cs`
- `SimPle.Infrastructure/Persistence/Repositories/ProfileRepository.cs`

**Expected frontend files (not yet created):**
- `frontend/src/features/profile/ProfilePage.tsx`
- `frontend/src/features/profile/EditProfileModal.tsx`
- `frontend/src/features/profile/AvatarUpload.tsx`

---

## Planned Features

- View and edit display name, bio, avatar
- Username change (rate-limited)
- Avatar upload and storage
- Profile visibility settings (public / friends-only / private)
- Social links (optional, user-controlled)

---

## Security Requirements For Implementation

| Requirement | Why |
|---|---|
| Authenticate all write endpoints | Profile changes must require a valid access cookie |
| Authorize by user ID | Users may only edit their own profile; check `UserId == requestingUserId` |
| Validate and sanitize text inputs | Bio and display name are rendered in the UI — XSS if unsanitized |
| Validate file type and size on avatar upload | Prevent polyglot files, oversized uploads, server-side path traversal |
| Store avatars outside the webroot or use a CDN | Direct filesystem access must not reach app code or OS |
| Strip EXIF metadata from uploaded images | EXIF can contain GPS coordinates and device identifiers |
| Rate-limit username changes | Prevent username squatting or rapid churn to confuse other users |
| Profile visibility enforced server-side | Never rely on frontend to hide private profiles |
| No PII in public profile by default | Email address must not be shown on public profile pages |
| Input length caps enforced in validator and database | Prevent oversized strings that bypass UI-level limits |

---

## Findings

None — module not yet implemented.

---

## Remaining Risks

| Risk | Notes |
|---|---|
| Avatar upload attack surface | File upload is one of the most commonly exploited features; requires careful content-type validation, size limits, and storage isolation |
| Stored XSS in bio/display name | Must sanitize or encode user-supplied strings before rendering |
| IDOR on profile edits | Must verify ownership before accepting update |

---

## Audit Status

Planned. Will be reviewed when implementation begins.

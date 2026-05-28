# Module 2: User Profile & Social Identity

Module 2 gives every registered user a public social identity: a profile page, a handle, a bio, avatar and banner images, a region, a custom status message, configurable visibility, external social links, and game-interest tags. It also wires the existing profile and settings UI to the real backend.

---

## Implemented

- **Current-user profile endpoint** `GET /api/profile/me` — returns the full profile DTO for the authenticated user including all fields, links, and interests.
- **Profile update** `PUT /api/profile/me` — updates display name, bio, avatar URL, banner URL, region, status message, and visibility. Owner-only.
- **Username/handle change** `PUT /api/profile/me/username` — changes the handle with uniqueness enforcement. Returns 409 on conflict.
- **Public profile** `GET /api/profile/{username}` — respects visibility rules:
  - **Public** — visible to anyone, authenticated or not.
  - **Private** — visible to the owner only; others get 403.
  - **FriendsOnly** — treated as owner-only until Module 3 friends are implemented.
- **External social links** `GET/PUT /api/profile/me/links` — store links to GitHub, Twitter, Instagram, Discord, YouTube, Twitch, LinkedIn, and personal websites. Up to 8 links. Replace-all update (send the full desired list).
- **Game interest tags** `GET/PUT /api/profile/me/interests` — up to 6 tags from a fixed allowed set: `board-games`, `word-games`, `puzzle-games`, `strategy-games`, `arcade-games`, `casual-games`, `card-games`, `trivia`.
- **Profile fields on the User entity** — `StatusMessage` and `ProfileVisibility` added to the existing `User` entity. Existing fields (DisplayName, Bio, AvatarUrl, BannerUrl, Region, Color, Initials, Level, Elo, Role) were already present and reused.
- **EF Core migration** `AddUserProfiles` — adds `status_message` and `visibility` columns to `users`, and creates `profile_external_links` and `profile_interest_tags` tables with FK/unique constraints.
- **Frontend: ProfilePage** wired to `GET /api/profile/me` (own profile) and `GET /api/profile/{username}` (public profile). Edit mode saves via `PUT /api/profile/me`. Stats, match history, achievements, and friends remain as placeholders pending Modules 3/10.
- **Frontend: SettingsPage profile card** wired to real profile load and save.
- **Frontend: Topbar and Sidebar** already used `useAuth()` which provides real name/initials/color from the auth session — no extra wiring needed.
- Safe DTOs throughout — no email, password hash, OAuth tokens, or security fields exposed in profile responses.

---

## Profile Fields

| Field | Required | Max length | Notes |
|---|---|---|---|
| `username` | Yes | 30 | Letters, digits, `_`, `.`, `-` only. Unique. |
| `displayName` | Yes | 64 | Shown everywhere as the primary name. |
| `bio` | No | 400 | Freeform about text. |
| `avatarUrl` | No | 512 | Must be a valid `https://` URL. |
| `bannerUrl` | No | 512 | Must be a valid `https://` URL. |
| `region` | No | 64 | Free text (e.g. "EU-West", "NA-East"). |
| `statusMessage` | No | 100 | Custom text status, separate from real-time presence. |
| `visibility` | Yes | — | `Public` \| `FriendsOnly` \| `Private`. Default: `Public`. |
| `color` | No | — | Avatar accent color. Set at registration, not exposed for update in Module 2. |
| `initials` | No | — | Derived from display name. |
| `level`, `elo` | No | — | Game statistics, not updated via profile endpoints. |
| `role` | No | — | Platform role (`Player`, `Moderator`, `Admin`). Not updatable via profile. |

---

## External Links

Allowed platforms: `github`, `twitter`, `instagram`, `discord`, `website`, `youtube`, `twitch`, `linkedin`.

Each link has: `platform`, `url` (valid absolute URL), optional `displayLabel`, `sortOrder`.

Max 8 links per user. The `PUT` endpoint replaces the full list.

---

## Interest Tags

Fixed allowed set: `board-games`, `word-games`, `puzzle-games`, `strategy-games`, `arcade-games`, `casual-games`, `card-games`, `trivia`.

Max 6 per user. The `PUT` endpoint replaces the full list.

---

## Visibility Rules

| Visibility | Who can see |
|---|---|
| `Public` | Everyone, including unauthenticated visitors |
| `FriendsOnly` | Owner only (until Module 3 implements friends) |
| `Private` | Owner only |

Non-owner access to a non-public profile returns `403 Forbidden`.

---

## Ownership Rules

- All `PUT` and `GET me` endpoints require a valid JWT access cookie.
- The backend extracts `userId` from the JWT `sub` claim.
- A user can only update their own profile — no admin override in Module 2.

---

## Remaining Limitations

- Avatar and banner images are stored as URLs only. Real file upload/CDN storage is future work (post-Module 2).
- `FriendsOnly` visibility is enforced as owner-only until Module 3 (Friends & Social Graph) is implemented.
- The profile route (`/profile/[userId]`) uses the ID parameter to load profiles; public profiles are fetched by username. A routing update to use usernames in URLs directly is planned.
- Stats (matches, win rate, ELO history), match history, achievements, and friends count on the profile page remain placeholder values. They will be wired in Modules 3, 8, and 10.

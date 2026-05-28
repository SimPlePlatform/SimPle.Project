# Profile API Reference

Base path: `/api/profile`

All state-changing endpoints require `X-Requested-With: XMLHttpRequest` (CSRF defense).

---

## GET /api/profile/me

Returns the authenticated user's full profile.

**Auth:** Required.

**Response 200:**
```json
{
  "userId": "uuid",
  "username": "myhandle",
  "displayName": "My Name",
  "bio": "About me",
  "avatarUrl": "https://...",
  "bannerUrl": null,
  "statusMessage": "Playing chess",
  "region": "EU-West",
  "color": "#F0394B",
  "initials": "MN",
  "visibility": "Public",
  "role": "Player",
  "level": 3,
  "elo": 1240,
  "joinedAt": "2026-01-01T00:00:00Z",
  "links": [
    { "id": "uuid", "platform": "github", "url": "https://github.com/me", "displayLabel": null, "sortOrder": 0 }
  ],
  "interests": ["board-games", "puzzle-games"]
}
```

**Note:** Email, password hash, OAuth tokens, and security fields are never returned.

---

## PUT /api/profile/me

Update the authenticated user's profile fields.

**Auth:** Required. CSRF header required.

**Body:**
```json
{
  "displayName": "My Name",
  "bio": "About me",
  "avatarUrl": "https://cdn.example.com/avatar.png",
  "bannerUrl": null,
  "region": "NA-East",
  "statusMessage": "Playing chess",
  "visibility": "Public"
}
```

**Response 200:** Updated `ProfileDto`.

**Response 400:** Validation error (empty display name, invalid URL, unknown visibility).

---

## PUT /api/profile/me/username

Change the authenticated user's username/handle.

**Auth:** Required. CSRF header required.

**Body:**
```json
{ "username": "newhandle" }
```

**Response 204:** Success.

**Response 400:** Validation error (too short, invalid chars).

**Response 409:** Username already taken.

---

## GET /api/profile/{username}

Get a public profile by username.

**Auth:** Optional (unauthenticated requests can view public profiles).

**Response 200:** `ProfileDto`.

**Response 403:** Profile is private or friends-only and the requester is not the owner.

**Response 404:** Username not found.

---

## GET /api/profile/me/links

Get the authenticated user's external links.

**Auth:** Required.

**Response 200:** Array of `ExternalLinkDto`.

---

## PUT /api/profile/me/links

Replace the authenticated user's external links (full replace).

**Auth:** Required. CSRF header required.

**Body:**
```json
{
  "links": [
    { "platform": "github", "url": "https://github.com/me", "displayLabel": null, "sortOrder": 0 }
  ]
}
```

Allowed platforms: `github`, `twitter`, `instagram`, `discord`, `website`, `youtube`, `twitch`, `linkedin`.

Max 8 links. Send an empty array to clear all links.

**Response 200:** Updated array of `ExternalLinkDto`.

**Response 400:** Invalid platform or URL.

---

## GET /api/profile/me/interests

Get the authenticated user's game interest tags.

**Auth:** Required.

**Response 200:** Array of strings, e.g. `["board-games", "puzzle-games"]`.

---

## PUT /api/profile/me/interests

Replace the authenticated user's interest tags (full replace).

**Auth:** Required. CSRF header required.

**Body:**
```json
{ "interests": ["board-games", "strategy-games"] }
```

Allowed values: `board-games`, `word-games`, `puzzle-games`, `strategy-games`, `arcade-games`, `casual-games`, `card-games`, `trivia`.

Max 6 tags. Send an empty array to clear all interests.

**Response 200:** Updated array of strings.

**Response 400:** Unknown interest tag.

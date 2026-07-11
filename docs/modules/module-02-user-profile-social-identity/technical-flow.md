# Technical Flow - Module 02: User Profile & Social Identity

## Summary

The profile system is a player's public identity on SimPle: avatar and banner media, display info, external
links, interests, profile visibility, a Player/Developer identity flag, and a fair username-change policy.
Media uploads use backend-issued presigned URLs to a private S3-compatible bucket (MinIO locally, AWS S3 in
production), so the browser uploads directly without ever holding storage credentials or choosing object
paths.

## Problem Solved

Players need a rich, safe public identity — with user-generated media — without exposing storage credentials
or private account data, and without letting username churn break the social graph.

## Architecture Overview

Clean Architecture profile services back a storage abstraction (`Storage__Provider` = `S3Compatible` for
local MinIO, `AWS` for production) that issues short-lived presigned PUT/GET URLs. The frontend treats every
URL as opaque.

## Backend Flow
- **Media upload:** frontend requests a presigned URL → backend authenticates, validates type/size, generates
  the object key server-side → returns a short-lived PUT URL → frontend `PUT`s the file → confirm endpoint
  verifies the key belongs to the user and that the object exists → key stored on the profile, prior media
  replaced → DTOs return presigned read URLs.
- **Removal:** clears the stored key, requests object deletion, and returns to fallback initials/color (avatar)
  or fallback banner color. Fallback hex colors are editable only when uploaded media is absent.
- **Social identity:** external links edited only via authenticated owner endpoints (supported-platform set,
  absolute-HTTPS only, dangerous schemes rejected, max-count + duplicate guards). Visibility checked before
  returning a public profile. `profileType` stored as `Player`/`Developer` (Developer is display-only).
- **Username policy:** tracked by UTC month — first change applies immediately; after that the same request
  creates/updates one pending admin-review request; cancel marks it cancelled without restoring the allowance.

## Frontend Flow
- Existing UI reused: profile page + settings + media components.
- Frontend integration points: `profileApi`, the presigned-upload flow, links/interests editors.
- Visual changes made: none beyond wiring; unknown region/location shows a neutral fallback (no hardcoded
  location).

## Database/Domain Model Changes
- Existing database impact: additive.
- Migration added: yes (`FixProfileSocialIdentityAndUsernamePolicy` migrates legacy `Gamer` → `Player`).
- Migration safety notes: additive columns (`Visibility`, `ProfileType`, `BannerFallbackColor`,
  `LastUsernameImmediateChangeYear/Month`, `LastUsernameAdminRequestYear/Month`) + new tables
  `username_change_requests`, `profile_external_links`.
- Data preservation notes: legacy string values migrated, not dropped.
- Destructive DB changes: none.

## API Contract
- Backend/API/Swagger alignment: documented in `api-reference.md`.
- Frontend/API integration alignment: `profileApi` matches documented routes/verbs.

## Validation And Error Handling
Media type/size validation (SVG rejected), link platform/URL validation (HTTPS-only, dangerous schemes
rejected, dedupe), and server-side username-policy enforcement.

## Authorization And Security Decisions
Private buckets; server-generated, ownership-checked object keys; the frontend never receives storage
credentials. Public DTOs omit email/password-hash/OAuth/tokens/private fields. `FriendsOnly` behaves
owner-only until Module 3.

## Realtime/Socket.IO Flow If Applicable
Not applicable.

## State Management If Applicable
Standard React state; media state reflects `hasUploadedAvatar`/`hasUploadedBanner` + fallback colors.

## Edge Cases Handled
Oversized/invalid/SVG uploads rejected; unauthenticated upload-URL rejected; object key must belong to the
user; duplicate/invalid links rejected; visibility gating for public profiles; monthly username limits and
pending-request edit/cancel semantics.

## Design Tradeoffs
Presigned direct-to-storage uploads (vs proxying bytes through the API) reduce backend load and keep
credentials server-side, at the cost of a two-step confirm handshake. Storing `FriendsOnly` before friends
exist keeps the schema stable for Module 3.

## Files Changed And Why
Profile controller + application services, storage abstraction, domain profile fields, `username_change_requests`
and `profile_external_links` entities, and the Next.js profile page/settings/media components.

## How To Read The Implementation
Start at the profile controller → profile services → storage abstraction. Frontend: `profileApi` + the media
upload components.

## Future Improvements / Deferred Items
- Production CloudFront delivery + deployed AWS S3 verification remain planned.
- Local storage config (placeholders only, never real creds): `Storage__Provider=S3Compatible`,
  `Storage__ServiceUrl=http://localhost:9000`, bucket `simple-profile-assets-dev`, started with
  `docker compose -f compose.storage.yml up -d`; if browser uploads are blocked, set MinIO CORS via
  `mc cors set local/simple-profile-assets-dev cors.local.json`. Production switches `Storage__*` to `AWS`
  with credentials from the host/user-secrets/instance role.
- Stats, achievements, match history, presence, and notifications on the profile remain later-module
  placeholders.

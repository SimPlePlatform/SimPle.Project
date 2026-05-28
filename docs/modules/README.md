# SimPle Modules

This folder records backend modules as they become usable and testable.

| Module | Status | Notes |
|---|---|---|
| [Authentication](auth/README.md) | Fully implemented | Cookie sessions, email verification, password reset, Google OAuth, account security settings, tests |
| [User Profile & Social Identity](profile/README.md) | Fully implemented | Public profile, visibility rules, external links, interest tags, settings UI wired, tests |

All other modules are planned. See the root README for the full roadmap.

Local end-to-end verification of the Auth module requires PostgreSQL to be
running and the migrations applied. See the Auth module README for setup steps.

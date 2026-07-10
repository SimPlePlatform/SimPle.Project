# Module 12: Moderation & Admin Dashboard — Security Audit

## Status

**Not started.** No backend or frontend code exists for this module.

---

## Planned Scope

**Expected backend files (not yet created):**
- `SimPle.Api/Controllers/AdminController.cs`
- `SimPle.Application/Admin/Services/ModerationService.cs`
- `SimPle.Domain/Users/SuspensionRecord.cs`

---

## Planned Features

- Admin dashboard: user management, ban/suspend, view reports
- User reporting (report a player for behaviour)
- Content moderation (flag and remove chat messages)
- Audit log of admin actions

---

## Security Requirements For Implementation

| Requirement | Why |
|---|---|
| Admin endpoints behind a dedicated admin role | A separate `Admin` claim or role must be required; do not rely on user ID checks alone |
| Admin role not self-assignable | Role assignment must be done out-of-band (database seeding or migration), not via an API call |
| All admin actions audit-logged | Who did what and when; logs must be append-only and not modifiable by admins themselves |
| Reason required for bans and suspensions | Provides accountability and a defensible record |
| Paginate user and report lists | Unbounded admin queries against the full user table are a DoS risk |
| Rate-limit bulk admin operations | Prevent accidental or malicious mass-ban of thousands of users in one request |
| Separation of duties for irreversible actions | Permanent bans or data deletion should require a second admin confirmation |
| No PII displayed beyond what is necessary | Admin views should not show password hashes, raw tokens, or other internal secrets |
| Admin session invalidation on role revocation | If an admin's role is revoked, their active sessions must be terminated |

---

## Findings

None — module not yet implemented.

---

## Remaining Risks

| Risk | Notes |
|---|---|
| Privilege escalation | Any code path that allows a non-admin to set their own role is critical |
| Admin account takeover | Admin accounts should require MFA once that feature exists |
| Audit log tampering | If admins can delete their own audit entries, accountability is lost |

---

## Audit Status

Planned. Will be reviewed when implementation begins. This is a high-risk module — admin access must be airtight.

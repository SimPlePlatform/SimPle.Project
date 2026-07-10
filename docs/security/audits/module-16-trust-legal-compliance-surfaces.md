# Module 16: Trust, Legal & Compliance Surfaces — Security Audit

## Status

**Not started.** No backend or frontend code exists for this module.

---

## Planned Scope

**Expected backend files (not yet created):**
- `SimPle.Api/Controllers/LegalController.cs`
- `SimPle.Api/Controllers/DataExportController.cs`
- `SimPle.Application/Compliance/Services/DataExportService.cs`
- `SimPle.Domain/Compliance/UserConsent.cs`
- `SimPle.Domain/Compliance/DataExportRequest.cs`

---

## Planned Features

- Terms of Service / Privacy Policy / cookie-consent pages and versioned consent recording
- Public accessibility statement, help/FAQ, and changelog pages
- Consolidated self-service "download my data" export (aggregates existing per-module export data)
- Settings entry point linking to Module 1's existing account-deletion flow

---

## Security Requirements For Implementation

| Requirement | Why |
|---|---|
| Export download links are signed and time-boxed | Prevents indefinite/replayable access to a personal-data bundle |
| At most one in-flight export request per user | Prevents storage/queue abuse via repeated requests |
| Export authenticated and rate-limited | The bundle contains personal data and must not be requestable by another user or scraped |
| Export respects an active Module 12 legal/moderation hold on deletion, not on the export itself | GDPR right of access is not suspended by an internal hold; only deletion is |
| Consent is versioned per published policy | Re-consent must be required after a policy republish; stale consent must never be presented as current |
| No card or payment data in the export bundle | Payment card data never touches the SimPle server (Module 13 boundary) |

---

## Findings

None — module not yet implemented.

---

## Remaining Risks

| Risk | Notes |
|---|---|
| Export-bundle replay | A signed download URL that is not tightly time-boxed could leak data if shared or cached |
| Consent-version drift | Failing to invalidate prior consent on a policy republish silently violates the point of versioned consent |
| Legal-hold conflation | Blocking export (not just deletion) during a moderation hold would incorrectly deny a user's own data |

---

## Audit Status

Planned. Will be reviewed when implementation begins.

# Security Notes

Security documents record the controls that are implemented, what was checked, and what still needs work.
They are review notes, not a claim that an application is unbreakable.

## Module security audits (canonical)
Per-module audits live at `audits/module-XX-<slug>.md`, all following the same template (Severity Summary
Table, OWASP/ASVS mapping, findings numbered `M<NN>-###`). Index + status: [audits/README.md](audits/README.md).

- [Module 1 — Authentication & User Management](audits/module-01-authentication-user-management.md)
- [Module 2 — User Profile & Social Identity](audits/module-02-user-profile-social-identity.md)
- [Module 3 — Friends & Social Graph](audits/module-03-friends-social-graph.md)

## Auth deep-dive (supplementary)
- [Authentication security design](auth.md)
- [Auth threat model](audits/auth/auth-threat-model.md)
- [Auth security audit](audits/auth/auth-security-audit.md)
- [Auth attack checklist](audits/auth/auth-attack-checklist.md)
- [Auth local testing notes](audits/auth/auth-pentest-notes.md)

# Module 14: Security Testing & Production Readiness — Security Audit

## Status

**In progress.** This module is a cross-cutting concern, not a feature module.
It covers production hardening items that apply to the whole application.

---

## Scope

This module tracks security concerns that span multiple feature modules or that
are infrastructure-level rather than feature-level.

---

## Current State (as of 2026-05-28)

### What is in place

| Control | Status |
|---|---|
| Unit test suite (100 tests) | Passing |
| Integration test suite (45 tests) | Passing (last successful run; blocked by running API during this audit) |
| Frontend TypeScript type check | Passing — 0 errors |
| Frontend ESLint | Passing — 0 errors (3 errors fixed during this audit) |
| Frontend production build | Passing |
| NuGet vulnerability scan (manual) | Run — MailKit moderate vuln found and fixed (4.9.0 → 4.17.0) |
| npm audit (manual) | Run — 2 moderate PostCSS advisories in Next.js transitive deps; no safe upgrade path |
| NuGet vulnerability scan in CI | Not configured |
| npm audit in CI | Not configured |
| SAST / static analysis | Not configured |
| Dependency review in CI | Not configured |
| Secret scanning in CI | Not configured |
| Container image scanning | Not applicable yet |
| DAST / black-box testing | Not performed |
| Production database applied | Not yet (Docker not installed) |
| End-to-end browser smoke test | Not yet (requires live DB + reCAPTCHA keys) |

### NuGet findings (2026-05-28)

| Package | Old version | New version | Severity | Advisory |
|---|---|---|---|---|
| MailKit | 4.9.0 | 4.17.0 | Moderate (fixed) | GHSA-9j88-vvj5-vhgr |

### npm audit findings (2026-05-28)

| Package | Severity | Advisory | Fix available |
|---|---|---|---|
| postcss (transitive via next) | Moderate | GHSA-qx2v-qp2m-jg93 | `npm audit fix --force` would downgrade Next.js to v9 — not safe |

The PostCSS advisory relates to CSS stringify output. It does not affect auth tokens, cookies, or user data. It is a risk in the build toolchain, not in production request handling.

---

## Production Hardening Checklist

| Item | Priority | Status |
|---|---|---|
| `UseForwardedHeaders` or YARP proxy config for correct client IP | High | Not done |
| PostgreSQL migration applied and tested | High | Not done |
| Stripe and Google secrets in a secret manager, not .env | High | Not done |
| Security event / audit log | Medium | Not done |
| Token table purge job (expired rows) | Medium | Not done |
| NuGet vulnerability scan in CI pipeline | Medium | Not done |
| npm audit in CI pipeline | Medium | Not done |
| SAST tool (e.g. Semgrep, CodeQL) | Medium | Not done |
| Rate limiter with Redis backend (for multi-instance) | Medium | Not done |
| Refresh token concurrent update with database-level lock | Low | Not done |
| HTTPS enforced at proxy/CDN level (HSTS preload) | Medium | Not done |
| Structured logging with correlation IDs | Low | Not done |
| Health check endpoint authenticated or IP-restricted | Low | Not done |
| Browser smoke test (register → login → verify → reset) | High | Not done |

---

## Remaining Risks (cross-cutting)

| Risk | Severity | Notes |
|---|---|---|
| No CI security gates | Medium | Vulnerable packages could be merged without detection |
| No audit log | Medium | Auth events (login, password reset, suspend) are not logged |
| Expired token rows accumulate | Medium | No purge job; table grows indefinitely |
| Proxy IP configuration | Medium | `RemoteIpAddress` is used directly; must configure `UseForwardedHeaders` before production |
| Concurrent refresh race | Low | Not atomic; low risk for single instance |
| No MFA | Low | Noted for future roadmap |
| No DAST | Low | Black-box testing has not been performed against a live instance |

---

## Audit Status

Ongoing. Updated as each feature module reaches production readiness.

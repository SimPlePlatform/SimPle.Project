# GitHub hardening checklist (manual, no cost)

Complete these steps in each public SimPle repository: `SimPLe.Backend`, `SimpLe.Frontend`, and
`SimPle.Project`. They change account/repository settings, so they cannot safely be completed by the
workflow or committed as code. GitHub Actions is free for public repositories; none of these steps needs a
cloud provider, a credit card, or a secret.

Record the completion date and Settings-page URL in a private note or a release checklist. Do not put
recovery codes, tokens, secrets, or security-alert details in a public issue, screenshot, or LinkedIn post.

## 1. Protect your GitHub account

1. Open GitHub → profile picture → **Settings** → **Password and authentication**.
2. Enable two-factor authentication. An authenticator app or a passkey is preferable to SMS.
3. Download recovery codes and store them in a password manager or another private offline location.
4. Confirm you can sign out and recover access before treating this step as complete.

This reduces the chance that someone who learns your password can push code or change repository settings.

## 2. Turn on repository security features

Repeat this in each repository: **Settings** → **Security** → **Code security and analysis** (GitHub's
labels can differ slightly by account type).

1. Enable **Dependabot alerts**. GitHub will notify you when a dependency is known to be vulnerable.
2. Enable **Dependabot security updates**. GitHub can open a proposed update pull request when a safe update
   is available.
3. Enable **Secret scanning** and **push protection**. Push protection warns or blocks a commit that appears
   to contain a credential. It is not a reason to put test credentials in source control.
4. Enable **CodeQL default setup** if GitHub offers it for the repository language, or wait for the
   reviewed CodeQL workflow delivered in the relevant backend/frontend repository. Verify that the first
   analysis has actually completed; an enabled toggle is not a clean result.

If a feature is unavailable in the interface, record `Unavailable on this plan/account` rather than marking
it complete. Never bypass a push-protection alert by committing a real credential.

## 3. Add a `main` branch ruleset

In each repository, open **Settings** → **Rules** → **Rulesets** → **New branch ruleset**.

1. Name it `protect-main`, set enforcement to **Active**, and target the default branch `main`.
2. Require a pull request before merging. For a solo portfolio project, set required approvals to **0** so
   you keep a reviewable PR trail without needing a second account.
3. Block force pushes and branch deletion.
4. After the repository's own CI workflow has passed once on `main`, require its exact status checks. Do not
   select a similarly named check from another repository. The backend, frontend, and Project orchestration
   checks are independent.
5. Do not enable automatic bypasses for routine work. If GitHub requires the repository owner to retain an
   emergency bypass, use it only for documented recovery and record why.

Rulesets protect history and make CI gates meaningful. They do not make unrun CI pass.

### Required status checks after the DevOps foundation is pushed

The PR/deletion/force-push rules are not enough on their own: the `protect-main` ruleset must also contain a
**Require status checks to pass** rule. Add the following primary job only after the updated workflow has run
successfully once in that repository, so GitHub can offer the exact check name:

| Repository | Select this check in the `protect-main` ruleset |
|---|---|
| `SimPLe.Backend` | `CI / Build, test, package, and container smoke` |
| `SimpLe.Frontend` | `CI / Build, test, package, and container smoke` |
| `SimPle.Project` | `CI / Validate delivery configuration` |

Do not require the attest-only jobs: they deliberately run only after the main validation job has passed.
After saving each ruleset, from the workspace root run:

```powershell
node scripts/check-github-hardening.mjs
```

This read-only checker confirms repository-visible settings and fails if a required status-check rule is still
missing. GitHub deliberately does not expose recovery codes, and the current CLI token may not expose alert
details, so 2FA/recovery-code ownership remains a manual confirmation.

## 4. Verify and publish only safe evidence

1. Open the **Actions** and **Security** tabs. Confirm each expected workflow has a real completed run and
   review any alerts.
2. Keep the public run URL, commit SHA, workflow name, and outcome in release evidence. Keep screenshots
   cropped so they contain no secret values, email addresses, or alert payloads.
3. If a dependency/security alert remains, report its severity, owner, review date, and mitigation in the
   relevant private or public security record—never label the project secure merely because scanning exists.

## Completion record

Use one row per repository:

| Repository | 2FA owner confirmed | Dependabot | Secret scanning/push protection | CodeQL run URL | `main` ruleset | Date / notes |
|---|---:|---:|---:|---|---:|---|
| SimPLe.Backend | ☐ | ☐ | ☐ |  | ☐ |  |
| SimpLe.Frontend | ☐ | ☐ | ☐ |  | ☐ |  |
| SimPle.Project | ☐ | ☐ | ☐ |  | ☐ |  |

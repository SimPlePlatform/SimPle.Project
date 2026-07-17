# DevOps evidence hub

This folder is the permanent, public record of how SimPle is built and reviewed. It is intentionally
evidence-led: a document or workflow is not proof that a cloud deployment, CI run, security scan, or
backup restore has happened.

## Current truthful status

| Area | Status |
|---|---|
| Modules 1–4 | Completed locally and merged, with module-level evidence in this repository |
| Modules 5–6 | Locally complete; hosted CI, portable-staging, and deployment evidence is deferred to Module 14 |
| Modules 7–13 | Planned or in progress; no cloud resource should be created for normal module work |
| Module 14 delivery foundation | Repository-owned implementation added; full portable-staging and hosted-CI evidence is still pending |
| Cloud deployment | Not created and not claimed |

Read the [portable staging guide](../../ops/staging/README.md), the
[GitHub hardening checklist](github-hardening-checklist.md), the
[release-evidence guide](release-evidence.md), and the
[GitHub Pages guide](github-pages.md), and the
[Azure student deployment runbook](azure-student-deployment.md) before describing the project publicly.

## Evidence levels

Keep these independent in every release note and LinkedIn post:

| Field | It means | It does not mean |
|---|---|---|
| `LocalComplete` | Required local checks for the exact candidate were recorded | Hosted CI or a deployed environment passed |
| `CiVerified` | The exact committed release tuple passed hosted CI | Portable staging or cloud deployment passed |
| `PortableStagingVerified` | The exact tuple passed documented disposable Compose staging checks | A public cloud environment is available |
| `DeploymentVerified` | A human-approved cloud environment was checked against that tuple | High availability, scale-out, or perpetual hosting |

The project is a **portfolio demo / single-instance system** until a separately evidenced change says
otherwise. Do not call it "production ready," "highly available," or deployed based only on this folder.

## What recruiters can inspect

- Module documentation, technical flows, test reports, and security audits under `docs/modules/` and
  `docs/security/`.
- The source-controlled local staging topology under `ops/staging/`.
- A no-secret static overview under `portfolio/`, suitable for GitHub Pages after the repository owner
  enables Pages manually.
- Future release evidence under `docs/releases/<release-id>/`, where every passing check must identify the
  backend, frontend, and Project SHAs plus image digests.

The static portfolio is a navigation aid, not a replacement for source records or CI artifacts.

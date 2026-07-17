# Release evidence guide

Use this guide after Modules 7–13 are complete and Module 14 has created real build, migration, scan,
SBOM, provenance, and E2E artifacts. It deliberately does **not** authorize a cloud deployment or let a
lower evidence level imply a higher one.

## Release tuple

Every release record must name the exact:

```text
(backendSha, frontendSha, projectSha, migrationHead, backendImageDigest, frontendImageDigest)
```

Do not use a workspace-root SHA: the workspace root is not a Git repository. A local dirty candidate also
needs deterministic source-tree digests for all modified/approved-untracked files; it cannot be described
as CI-verified before those exact changes are committed and CI has run.

## Required record for each check

For tests, scans, migrations, backup/restore, container smoke, E2E, SBOM, provenance, and human review,
record the tool/version/configuration, tuple hash, command, start time, exit code, environment, result,
limitations, and durable evidence location. `Skipped`, `Unknown`, or scan-service outage is a blocker—not a
pass.

Store durable Project-repository evidence at:

```text
docs/releases/<release-id>/module-14-release-evidence.json
```

CI run URLs and expiring CI artifacts are supporting links, not the only evidence copy. Append a new release
record when CI or deployment results arrive; do not overwrite a prior local record to make it look stronger.

## Minimum honest release wording

Good: “The exact release tuple passed local checks and portable staging; hosted CI and cloud deployment are
recorded separately.”

Not acceptable: “Production-ready,” “fully deployed,” “secure,” or “highly available” without the specific
human-approved evidence that supports that claim. Phase 1 remains single-instance until the project designs,
implements, and tests a distributed realtime/data-protection/rate-limit architecture.

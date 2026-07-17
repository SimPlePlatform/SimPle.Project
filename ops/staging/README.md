# Portable staging topology (Module 14 skeleton)

This directory is a **single-instance, local portable-staging topology**. It is not a cloud deployment,
does not create an account or resource, and has not yet been verified against a release tuple. The current
backend and frontend images do not provide the Module 14 image/job contracts yet, so this is deliberately a
safe wiring skeleton rather than a command that can honestly be called "ready".

## What it will run after Module 14 image work

```text
browser -- http://localhost:8080 --> Caddy --> frontend
                                      |  \-> backend (/api/*, /hubs/*, /health/*)
                                      \----> MinIO (storage.localhost only)

backend --> PostgreSQL
backend --> MinIO through storage.localhost
```

Only Caddy publishes a host port, and only on `127.0.0.1`. PostgreSQL, the MinIO console, the backend,
and the frontend are private to the Compose network. The MinIO gateway hostname lets browser presigned
uploads work locally without publishing the MinIO port; its CORS file permits only `http://localhost:8080`.

The app/API/hub share one browser origin. `storage.localhost` is a local media endpoint for presigned S3
requests, not an authentication origin and not a model for a public deployment. A later B2/S3 deployment
must restrict its CORS policy to the deployed app origin.

## What must be supplied before it can run

1. Module 14 must first publish hardened backend and frontend images for the exact reviewed
   backend/frontend commits. The backend image also runs the explicit one-shot migration/seed jobs below.
   Both images must be recorded as `image@sha256:...` values in a release tuple; do not substitute mutable
   tags as evidence.
2. The backend image must expose process-only `GET /health/live` and dependency-aware
   `GET /health/ready`. Its Dockerfile owns the actual health check because Compose must not assume a shell
   exists in a hardened runtime image.
3. The backend image must implement the two explicit commands used here: `--apply-migrations` and idempotent
   `--seed`. Neither job is allowed to start automatically with the app.
4. The frontend image must be built with `NEXT_PUBLIC_API_URL` set to the empty string so current frontend
   API calls resolve to same-origin `/api/...`; setting that environment variable at container start is not
   enough for a Next.js public variable.
5. The image hardening work must prove non-root execution, read-only root filesystems, writable temp paths,
   graceful shutdown, and no secret in layers. Compose removes Linux capabilities and blocks privilege gain,
   but cannot prove a sibling repository image satisfies that contract.

## Beginner-safe local sequence

1. Install Docker Desktop and start it. This is local software; it does not need an Azure, Neon, B2, or
   payment-provider account.
2. From this directory, copy the template: `Copy-Item .env.example .env`.
3. Replace every `replace_before_use` value in `.env` on your own computer. Generate two different random
   32+ character values for `JWT_SECRET_KEY` and `LOBBY_CREDENTIAL_KEY`. `.env` is ignored by Git.
4. Replace all three application image references with the matching immutable digests from the reviewed
   release tuple. Also pin the PostgreSQL, MinIO, MinIO client, and Caddy image references to approved
   digests before a verification run.
5. Validate only the configuration shape first:

   ```powershell
   docker compose --env-file .env -f compose.yaml config
   ```

6. Once the Module 14 migrator exists, bring up dependencies and run jobs explicitly, one at a time:

   ```powershell
   docker compose --env-file .env -f compose.yaml up -d postgres minio minio-init
   docker compose --env-file .env -f compose.yaml --profile jobs run --rm migrate
   docker compose --env-file .env -f compose.yaml --profile jobs run --rm seed
   docker compose --env-file .env -f compose.yaml up -d backend frontend caddy
   ```

7. Verify `GET /health/live`, then `GET /health/ready`, through Caddy. Run the release's browser E2E suite
   against `http://localhost:8080`. Record the exact images, command output, timestamps, and result in
   release evidence; a successful `up` alone is not a verification result.
8. Remove disposable local data only when you intend to: `docker compose --env-file .env -f compose.yaml down -v`.
   This deletes the local PostgreSQL and MinIO volumes. It must never be pointed at cloud resources.

## Explicit boundaries

- There is one backend instance. Do not scale it or enable a second replica: Phase 1 realtime has no
  Redis/Azure SignalR backplane or distributed presence design.
- This directory contains no Azure, Neon, Backblaze, Google, Gmail, Stripe, or real user configuration.
- Provider fakes/test settings belong in a local `.env` or CI secret store, never in this repository.
- A future cloud deployment needs separate Bicep/OIDC, Azure Container Apps ingress, TLS, object-storage CORS,
  a human approval, and deployment evidence. It is intentionally out of scope for this skeleton.

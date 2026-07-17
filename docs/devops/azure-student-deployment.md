# Azure student demo: beginner runbook

This is the human-operated part of the delivery foundation. Complete it only after Modules 7-13 are
finished and their normal module workflow has produced its final configuration checklist. It creates real
external accounts, so this repository intentionally cannot perform these steps for you.

The target is an honest **portfolio demo / single-instance** deployment:

```text
browser (one HTTPS origin)
  -> Azure Container Apps ingress -> Caddy -> frontend (localhost:3000)
                                           -> backend + SignalR (localhost:8081)
  -> Neon PostgreSQL (TLS)
  -> private Backblaze B2 bucket (short-lived signed media URLs)
```

The public evidence hub remains GitHub Pages/source documentation even if the student Azure resources are
later stopped or disabled. Do not describe this as highly available or production-ready.

## Guardrails before creating any account

1. Finish the [GitHub hardening checklist](github-hardening-checklist.md) in all three repositories.
2. Do **not** add a credit/debit card or upgrade to a paid plan. If any provider demands one for the private
   demo path below, stop there and keep using local Compose staging instead.
3. Store values only in the GitHub environment and Azure Container App secrets described below. Never put a
   production value in `.env`, `appsettings*.json`, a commit, an Actions log, a screenshot, or LinkedIn.
4. A budget is an alert, not a spending kill switch. Azure evaluates budget cost periodically; it can arrive
   after usage. Keep `minReplicas: 0`, `maxReplicas: 1`, and stop the Container App when you are not
   demonstrating it.

## 1. Create the no-card accounts

### Azure for Students

1. Go to [Azure for Students](https://azure.microsoft.com/en-us/free/students/) while signed in with your
   student email. Azure states that it has no card requirement and includes student credit; read the offer
   shown for your country before accepting it.
2. In the Azure portal, open **Cost Management + Billing**. Create one monthly budget scoped to the future
   `rg-simple-portfolio` resource group with an amount of **USD 50** (or your local equivalent).
3. Azure budget thresholds are percentages, not fixed-dollar fields, and the minimum threshold is greater
   than zero. Create actual-cost email alerts at **1%** (the closest practical early warning), **20%**
   (USD 10 of a USD 50 budget), and **100%** (USD 50). Also watch Azure's student-credit notifications.
4. Create resource group `rg-simple-portfolio` in the same region you plan to use for Neon. Create a
   **Container Apps environment** in that group. Use Consumption, not a dedicated workload profile. Enable
   log collection only if you understand the student's credit impact; it is useful evidence, but it is not
   a guarantee of $0 usage.
5. Copy the Container Apps environment resource ID from **Properties**. It starts with
   `/subscriptions/.../resourceGroups/rg-simple-portfolio/providers/Microsoft.App/managedEnvironments/...`.

Azure Container Apps supports a zero minimum replica count; the Bicep template deliberately caps this demo
at one replica. Never add a second backend replica until the distributed realtime, rate-limit, and data
protection design is implemented and tested.

### Neon PostgreSQL

1. Create a [Neon Free](https://neon.com/pricing) account and a project. The current Free plan advertises
   no card requirement; keep it on Free.
2. Create a database such as `simple_demo` in the region closest to the Azure Container Apps environment.
3. Copy the supplied **direct** TLS connection string for a schema-owner/deployment user. Keep its SSL mode;
   do not add `Trust Server Certificate=true`.
4. Create a separate `simple_app` login role for the running API. Give it only `CONNECT`, schema `USAGE`,
   table `SELECT/INSERT/UPDATE/DELETE`, and sequence `USAGE/SELECT/UPDATE` rights. Set matching default
   privileges so a future migration grants the same rights to new tables/sequences.
5. Keep two values: `MIGRATION_DATABASE_CONNECTION_STRING` for the schema owner and
   `DATABASE_CONNECTION_STRING` for `simple_app`. The Bicep init migration/seed jobs use the former; the
   running backend uses the latter. Never place either connection string in a repository.

Before a real release, rehearse restore in a **new Neon branch/database**: restore the backup/point-in-time
copy, point a disposable Compose staging run at it, and run the read-only smoke plus the relevant E2E
checks. Record the timestamp and outcome in release evidence. Do not restore over the demo database.

### Backblaze B2 media storage

1. Create a [B2 S3-compatible account](https://www.backblaze.com/sign-up/s3). Its current signup page says
   no card is required. B2 pricing includes the first 10 GB of storage, but do not rely on that as a hard
   cap: stay below it and watch the B2 Caps & Alerts/Billing pages.
2. Enable **B2 Cloud Storage**, then create a uniquely named **private** bucket, for example
   `simple-demo-profile-media-<random-suffix>`. Do not create a public bucket: Backblaze documents extra
   payment-history/card requirements for a first public bucket, and SimPle does not need one.
3. Add a lifecycle rule that removes unfinished/hidden upload remnants promptly. Keep profile-media storage
   small and manually check the storage cap after every demo upload batch.
4. Create an application key restricted to this one bucket (and, if the console supports it, the
   `profile-assets/` prefix). Grant only the S3 operations the SDK needs: list, read, write, and delete.
   Copy the key ID and secret **once** into a password manager; revoke and recreate it if you lose it.
5. Add a bucket CORS rule with exactly one allowed origin: the final HTTPS Container Apps origin. Allow only
   the required signed upload/read methods and headers; never use `*`.
6. Record the bucket name, region, and S3 endpoint as GitHub variables. Treat key ID and secret as secrets.

### Google OAuth, reCAPTCHA, and Gmail SMTP

The Azure URL is not known until a harmless bootstrap revision exists, so do these after the first successful
Azure deployment below.

1. In Google Cloud Console, create a **Web application** OAuth client. For this app's Google Identity popup
   flow, add the exact `https://<Container-App-FQDN>` as an **Authorized JavaScript origin**. Do not use a
   wildcard, HTTP, an IP address, or a trailing path. The current implementation uses the popup credential
   callback, not a redirect URI.
2. In the reCAPTCHA console, make a separate production v2 key pair and add only that hostname. Keep
   `localhost` in a separate development key; do not disable domain validation.
3. For the demo sender Gmail account, turn on 2-Step Verification and create one named App Password (for
   example `SimPle portfolio demo`). Configure `smtp.gmail.com`, port **587**, the sender address as
   username/from address, and the generated app password. Never use SMTP port 25. Revoke the App Password
   after the demo if no longer needed.
4. Build/publish a new frontend image after changing the public Google Client ID or reCAPTCHA site key:
   Next.js embeds `NEXT_PUBLIC_*` values at build time. The public site key/client ID is not a secret, but
   it should still be set as a GitHub environment variable rather than committed.

Use Mailtrap or another non-delivery SMTP sink only for local portable staging. Do not use a real Gmail app
password in Compose.

## 2. Set up GitHub image publishing

The three manual workflows below push digest-addressed images to GitHub Container Registry (GHCR):

| Repository | Workflow | Image |
|---|---|---|
| `SimPLe.Backend` | **Publish immutable backend image** | `ghcr.io/simpleplatform/simple-backend` |
| `SimpLe.Frontend` | **Publish immutable frontend image** | `ghcr.io/simpleplatform/simple-frontend` |
| `SimPle.Project` | **Publish immutable gateway image** | `ghcr.io/simpleplatform/simple-gateway` |

For the frontend repository, create the `azure-demo` GitHub environment and add these **environment
variables** before publishing the final image:

| Name | Value |
|---|---|
| `NEXT_PUBLIC_GOOGLE_CLIENT_ID` | Google web client ID |
| `NEXT_PUBLIC_RECAPTCHA_SITE_KEY` | production reCAPTCHA site key |

For each repository, run its publish workflow only for a green `main` commit. Open the resulting GHCR
package settings and make the package **public** so Azure Container Apps can pull it without a registry
password. Copy the exact `image@sha256:...` digest from the workflow summary; never use only the `sha-...`
tag. The workflow creates a GitHub provenance attestation for that digest; link it in release evidence.

## 3. Configure GitHub OIDC and the Project environment

Do this in `SimPle.Project` after the Azure resource group/environment exist.

1. Azure portal -> **Microsoft Entra ID** -> **App registrations** -> **New registration**. Name it
   `simple-github-deploy`; no client secret and no redirect URI are needed.
2. Copy its **Application (client) ID** and **Directory (tenant) ID**. Copy the Azure subscription ID from
   **Subscriptions**.
3. In `rg-simple-portfolio` -> **Access control (IAM)** -> **Add role assignment**, grant that application
   **Contributor** at the resource-group scope. Do not grant Owner or subscription-wide access.
4. In the app registration -> **Federated credentials** -> **Add credential** -> **GitHub Actions deploying
   Azure resources**. Set organization `SimPlePlatform`, repository `SimPle.Project`, entity type
   **Environment**, and value `azure-demo`.
5. In `SimPle.Project` -> **Settings** -> **Environments**, create `azure-demo`. Add the following values.

### `azure-demo` variables

| Variable | What to enter |
|---|---|
| `AZURE_RESOURCE_GROUP` | `rg-simple-portfolio` |
| `AZURE_LOCATION` | your chosen Azure region |
| `AZURE_CONTAINERAPP_NAME` | a globally valid short name, e.g. `simple-demo-<random>` |
| `AZURE_MANAGED_ENVIRONMENT_ID` | ID copied from the Container Apps environment |
| `GATEWAY_IMAGE_DIGEST` | published gateway `image@sha256:...` |
| `FRONTEND_IMAGE_DIGEST` | published frontend `image@sha256:...` |
| `BACKEND_IMAGE_DIGEST` | published backend `image@sha256:...` |
| `STORAGE_BUCKET_NAME` | the private B2 bucket name |
| `STORAGE_SERVICE_URL` | B2 S3 endpoint from its console |
| `STORAGE_REGION` | B2 region, e.g. `us-east-005` |
| `RECAPTCHA_SITE_KEY` | public production site key |
| `EMAIL_FROM_NAME` | `SimPle` or your demo sender label |

### `azure-demo` secrets

| Secret | What it is |
|---|---|
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | OIDC identity IDs; no Azure client secret exists |
| `DATABASE_CONNECTION_STRING` | Neon least-privilege application-role TLS connection string |
| `MIGRATION_DATABASE_CONNECTION_STRING` | Neon schema-owner TLS connection string |
| `JWT_SECRET_KEY` | a newly generated 32+ character secret |
| `LOBBY_CREDENTIAL_KEY` | a different newly generated 32+ character secret |
| `RECAPTCHA_SECRET_KEY`, `GOOGLE_CLIENT_ID` | production Google provider values |
| `EMAIL_FROM`, `EMAIL_SMTP_HOST`, `EMAIL_SMTP_USERNAME`, `EMAIL_SMTP_PASSWORD` | dedicated Gmail SMTP configuration |
| `STORAGE_ACCESS_KEY`, `STORAGE_SECRET_KEY` | B2 bucket-scoped application key |
| `APP_ORIGIN` | exact `https://<Container-App-FQDN>` |

The `azure-deploy.yml` workflow validates that every image value contains `@sha256:` and uses GitHub OIDC.
It never needs an Azure client secret or a stored cloud password.

## 4. Bootstrap, then configure the final revision

1. Create Neon first. For the first deployment only, use harmless placeholder Google/SMTP/B2 values that
   satisfy configuration validation and set `APP_ORIGIN` to a temporary HTTPS placeholder. Publish matching
   frontend public placeholder variables. Do not invite people or create real accounts in this bootstrap
   revision.
2. In `SimPle.Project` -> **Actions**, run **Deploy reviewed Azure portfolio revision**. Enter a release
   evidence ID such as `bootstrap-not-a-release`. The Bicep template creates one Container App revision;
   its init containers apply migrations and idempotent seed data before the public containers start.
3. Copy the `publicOrigin` from the successful deployment summary. Confirm the browser sees one HTTPS origin
   and `GET /health/ready` returns `{"status":"healthy"}` through Caddy.
4. Now complete the B2, Google, reCAPTCHA, and Gmail sections above using that exact origin. Update the
   Project environment values/secrets, rebuild and republish the frontend image, update its digest variable,
   then run the deploy workflow again with a genuine reviewed release ID.
5. Test as two accounts: register/verify/reset/login/logout/Google login; profile media upload/read/replace/
   delete; friends; catalog; lobby; reconnect; and expected failure paths. Run Playwright against the public
   origin only after Module 14's release suite exists. Record each result separately.

## 5. Operations, rollback, and public evidence

- **Logs and correlation:** Azure Container Apps logs should be JSON. Copy an `X-Correlation-ID` from a
  failed browser/API response into Log Analytics/Container Apps log search. Do not put request payloads,
  cookies, or secrets in a dashboard or post.
- **Dashboard/alerts:** create a small dashboard for revision health, replica count, failed requests, and
  restart count. Create alerts for readiness failure, repeated restarts, and an unexpected replica count.
  Add the alert links and the human response steps to release evidence. These are operational signals, not
  proof of high availability.
- **Rollback:** Azure portal -> Container App -> **Revisions** -> activate the last known-good revision.
  Verify `/health/ready`, then record the incident, correlation ID, before/after digests, and reason. Do not
  roll a database schema backward casually; prefer a tested forward fix unless the migration runbook says
  otherwise.
- **Stop when idle:** Azure portal -> Container App -> deactivate the active revision or delete the resource
  group when the demonstration period ends. Deleting the resource group is irreversible for those resources;
  export the evidence first and verify the GitHub Pages hub still works.
- **LinkedIn wording:** say `single-instance portfolio demo with OIDC deployment, digest-pinned containers,
  health probes, SBOM/provenance, and documented rollback`. Do not say `production-ready`, `always on`, or
  `highly available`.

## Provider references

- [Azure for Students](https://azure.microsoft.com/en-us/free/students/)
- [Azure budgets and their alert thresholds](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/quick-create-budget-template)
- [Azure Container Apps scaling](https://learn.microsoft.com/en-us/azure/container-apps/scale-app)
- [Neon Free pricing](https://neon.com/pricing)
- [Backblaze B2 private buckets](https://help.backblaze.com/hc/en-us/articles/1260803542610-Creating-a-B2-Bucket-using-the-Web-UI), [application keys](https://www.backblaze.com/docs/en/cloud-storage-application-keys), and [CORS](https://www.backblaze.com/docs/cloud-storage-cross-origin-resource-sharing-rules)
- [Google OAuth origin rules](https://developers.google.com/identity/oauth2/web/guides/error), [reCAPTCHA domain validation](https://developers.google.com/recaptcha/docs/domain_validation), and [Gmail App Passwords](https://support.google.com/mail/answer/185833)

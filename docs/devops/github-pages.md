# GitHub Pages evidence hub

`portfolio/index.html` is a zero-dependency static overview. It contains no telemetry, form, secret,
provider credential, or deployment endpoint. The workflow in `.github/workflows/deploy-pages.yml` only
uploads that folder to GitHub Pages; it does not provision Azure, deploy the app, or change repository
security settings.

## One-time manual enablement

After this branch is merged into `main`:

1. Open `SimPle.Project` on GitHub → **Settings** → **Pages**.
2. Under **Build and deployment**, choose **GitHub Actions** as the source and save.
3. Open **Actions**, run **Deploy portfolio evidence hub** (or push a change under `portfolio/`), and wait for
   the `deploy` job to finish.
4. Open the job's published URL. Verify the page says “Not a deployment status page” and links only to public
   source evidence.
5. Save the successful workflow URL in the portfolio/release evidence. If Pages is disabled, unavailable, or
   fails, keep the repository source as the canonical evidence hub and mark Pages as unavailable—not deployed.

The workflow uses SHA-pinned official GitHub actions and least job permissions. It requires no secret, credit
card, or external account. GitHub Pages availability is controlled by the repository/account settings, so
this repository cannot truthfully assume it has been enabled.

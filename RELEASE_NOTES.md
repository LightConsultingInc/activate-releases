# Release notes

Each release has a section headed by its exact tag. The release workflow refuses to publish a tag
without one. Operators read these before upgrading: new configuration keys, changed defaults,
migrations, and anything they must do are listed first.

## v1.0.5

**Operator actions**
None.

**New configuration keys**
None.

**Migrations**
None.

**Security advisory:** no

**Behaviour changes**
- Company admin > Sign-in: "Who gets which role" now points to where group-to-role mapping actually lives (WorkOS's single sign-on setup, "Groups and role assignments"), says to send group membership in the sign-in, and notes that Microsoft Entra identifies groups by Object ID.

## v1.0.4

Fixes from the admin, champion and sponsor part of the EU production walkthrough.

**Operator actions**
- WorkOS installs: switch on Role assignment (dashboard: Authorization, Role assignment) with Single Sign-On groups as the mapping source, so a company's IT admin can map their groups to activate-admin / activate-sponsor / activate-champion in the setup pages.

**New configuration keys**
None.

**Migrations**
None.

**Security advisory:** yes. Someone marked inactive (by an admin, or by the company's directory when they leave) kept access to the web app, the API and the Claude connector until their sign-in expired. They are now refused at once.

**Behaviour changes**
- Teams & People: admins can switch someone's access off and back on. It shows each person's level and when they were last in Activate.
- The company's usage policy is shown to every learner before they start, as the admin page always said.
- Champion screens (team page, review queue, approval queue, person page) in plain language. The team backlog includes workflows its members mapped before joining the team. Figures with no data behind them are hidden.
- A champion not yet on a team sees a plain message instead of an error.
- Person page: the retired judgement figure is gone, and skills below someone's starting level are no longer flagged as fading.
- Admin pages: no internal agent names or placeholders, and the Analytics key description matches what the screens do.

## v1.0.3

More fixes from the EU production walkthrough.

**Operator actions**
None.

**New configuration keys**
None.

**Migrations**
None.

**Security advisory:** no

**Behaviour changes**
- Sign-out, the sign-in callback and the signed-out redirect build their URLs from `WEB_URL`. Behind a load balancer they sent people to the container's own address (`https://0.0.0.0:3000`), which broke Sign out and the "your company now uses single sign-on" hand-off.
- A company on single sign-on now goes straight to its own identity provider instead of WorkOS's hosted page. Through the hosted page WorkOS quietly reused any earlier session (an admin's password sign-in from before single sign-on), which Activate then refused, so that admin could never get back in.
- Sign out also ends the session at WorkOS, so the next sign-in asks again instead of silently reusing it.
- The single sign-on, domain and directory setup pages (hosted by WorkOS) open in a new tab, so Activate stays open behind them; coming back to the Activate tab refreshes the status.
- Plainer labels in the lead console and admin screens (no raw metric names, spec references or "rung").
- Learner screens in plain language throughout (onboarding, My Ladder, My Workflows, History, the Skill Library); lines with no data yet are hidden instead of showing 0. The interview no longer shows its internal checker notes, and placement explains itself to the learner in their own words.
- Tailored lessons can no longer show leaked raw JSON from the model, and Claude's tables in practice answers render as tables.
- Right after placement, the list of work to practise on waits for the interview's workflows instead of showing "Workflow" placeholders.
- My Ladder fits a phone screen. The approval queue and team page are closed to learners with a plain notice instead of an error.
- A company whose Claude usage reports aren't connected yet (no Analytics key) no longer shows as 0% active: no "Stalled" lead card, the client tile and Mission Control Adoption say what's missing, and Cost & Return stops counting every seat as an inactive-seat cost. `LeadClient.hasUsage` and `CostView.seats.hasUsage` are new payload fields.
- Mission Control: the "Nudge" button, which never sent anything, is removed; the Backlog's hours-at-stake total matches its rows; new workflows say they are scored overnight.
- Readouts treat a person's placement as their starting point rather than progress, say "level" instead of "rung", and no longer mention internal sources or the retired judgement metric.

## v1.0.2

Fixes found by the EU production walkthrough.

**Operator actions**
- WorkOS installs: make sure Email + Password (and optionally Magic Auth) is switched on in the WorkOS environment (dashboard: Authentication, Methods). New environments start with it off, and a company's invited admin has no other way in before single sign-on exists.

**New configuration keys**
None.

**Migrations**
None.

**Security advisory:** no

**Behaviour changes**
- Terraform module: `lead_email_domains` now reaches the API as `LEAD_EMAIL_DOMAINS` (it was always empty, so a cloud cell had no LightCI leads). Self-hosted installs are unaffected: the default is still none.
- Someone on a lead domain who signed in before the domain was configured becomes a lead on their next request.
- The login page names WorkOS errors plainly: a disabled sign-in method no longer reads as a wrong password.

## v1.0.1

Self-serve sign-in setup for WorkOS installs, and stricter sign-in rules.

**Operator actions**
- WorkOS installs: run `WORKOS_API_KEY=… node scripts/workos-roles.mjs` once per WorkOS environment to create the `activate-admin`, `activate-sponsor` and `activate-champion` roles customers assign their groups to.
- WorkOS installs: subscribe the webhook endpoint to `connection.activated`, `connection.deactivated`, `connection.deleted`, `dsync.activated` and `dsync.deleted` as well, so a company's move to single sign-on takes effect at once (otherwise within a minute).
- Nothing to do for OIDC installs.

**New configuration keys**
None.

**Migrations**
None. The move to single sign-on is recorded in the existing `orgs.settings` JSON (`identity.ssoSince`).

**Security advisory:** no

**Behaviour changes**
- Company admin > Sign-in: the company's admin verifies its email domain, connects its identity provider and, optionally, its directory, each through a WorkOS setup page opened at click time. A banner reminds admins until single sign-on is on; an admin whose company is still setting up lands on this page instead of onboarding.
- Lead console: invite a client's admin by email; WorkOS sends the invitation.
- Sign-in phases (WorkOS mode). Until a company's single sign-on is active, only people invited in advance can sign in. Once it is active (recorded, and never undone by switching the connection off), every session must have signed in through single sign-on; password and emailed-code sessions are refused, including Claude connector tokens, which are asked to sign in again. When WorkOS cannot be reached the strictest rule applies. A sign-in through a company's organisation must use an address on the company's email domains. LightCI leads and demo organisations are exempt.
- A refused session is signed out and the login page says why.
- `GET /api/auth/lookup` can return `mode: "setup"`.
- Admins pre-created as admins keep admin on their first WorkOS sign-in.

## v1.0.0

First self-hosted release.

**Operator actions**
- Set `ACTIVATE_EDITION=self-hosted` and `ACTIVATE_LICENSE_FILE` (the license LightCI sent you).
- Choose an identity mode: `AUTH_PROVIDER=oidc` with your own OpenID Connect provider (`AUTH_OIDC_*`), or `workos` with a WorkOS environment you own.
- Configure the marketplace remote: `LIBRARY_PROVIDER=github` with `LIBRARY_REPOSITORY` and `LIBRARY_GIT_TOKEN`, or `LIBRARY_PROVIDER=git` with `LIBRARY_REMOTE_URL`. A local folder is refused in production unless `LIBRARY_ALLOW_LOCAL=true`.
- Set `ACTIVATE_ORG_*` for the first boot (organisation name, slug, email domains, initial admins). Admins pre-created this way keep admin whatever their IdP groups say.
- Run migrations as a step before pods roll: `activate migrate` (the Helm chart and Terraform module do this for you). Boot-time migrations are off in production unless `MIGRATIONS_RUN_ON_BOOT=true`.
- Back up the Secret holding `ACTIVATE_SECRETS_KEY` with the database.

**New configuration keys**
`ACTIVATE_EDITION`, `ACTIVATE_ROLE`, `ACTIVATE_LICENSE_FILE` / `ACTIVATE_LICENSE`, `ACTIVATE_ORG_NAME|SLUG|EMAIL_DOMAINS|INITIAL_ADMINS|SEATS`, `AUTH_PROVIDER`, `AUTH_OIDC_ISSUER|CLIENT_ID|CLIENT_SECRET|SCOPES`, `AUTH_GROUPS_CLAIM`, `AUTH_ROLE_MAP`, `AUTH_WEB_CLIENT_ID`, `DB_SSL_MODE`, `DB_SSL_CA_FILE`, `LIBRARY_PROVIDER|REPOSITORY|GIT_TOKEN|REMOTE_URL|CLONES_DIR|ALLOW_LOCAL`, `ACTIVATE_SECRETS_KEY_PREVIOUS`, `MIGRATIONS_RUN_ON_BOOT`, `WORKER_TIMEZONE`, `JOBS_SCHEMA`, `LOG_LEVEL`, `METRICS_PORT` / `METRICS_ENABLED`, `UPDATE_CHECK_ENABLED` / `UPDATE_INDEX_URL`, `COACH_PLUGIN_DIR`, `DB_SSL_ALLOW_PLAINTEXT` (Compose evaluation only), `WEB_URL` (web app), `SESSION_SECRET` (web app).

**Deprecated (still accepted for two minors)**
`DB_SSL` (use `DB_SSL_MODE`), `GITHUB_REPO` / `GITHUB_TOKEN` (use `LIBRARY_REPOSITORY` / `LIBRARY_GIT_TOKEN`), `NEXT_PUBLIC_API_URL` / `NEXT_PUBLIC_WORKOS_REDIRECT_URI` (the web app reads `API_URL` and `WEB_URL` at runtime).

**Migrations**
Additive: `orgs.emailDomains`, `people.identityIssuer` / `identitySubject`, `instance_keys`, `oauth_clients`, `oauth_codes`, `oauth_refresh_tokens`, `oauth_login_states`, `instance_settings`. The job queue creates its own `pgboss` schema.

**Security advisory:** no

**Behaviour changes**
- Prometheus metrics on port 9464 (`/metrics`) on every api and worker process, never through the ingress: request latency by route, model calls and tokens, queued jobs and last success per queue, marketplace publish failures, licence seats.
- The worker reads LightCI's release index once a day (`UPDATE_CHECK_ENABLED`, default true) and admins see a banner when a newer release exists; nothing is sent. `activate doctor` prints the same.
- The Coach plugin ships in the image; after each upgrade the worker proposes it to every organisation's marketplace as a pull request on `activate/coach-plugin-v<version>`. Nothing is written to a default branch.
- OAuth error responses keep the RFC 6749 shape (`error`, `error_description`).
- Queue installation at start is serialised across processes (api and worker starting together no longer deadlock in Postgres on first boot).
- The web app sends browsers to `PUBLIC_API_URL` to sign in (never the in-cluster `API_URL`); on the connector host only `/mcp` is restricted to Anthropic's ranges, `/oauth` and `/.well-known` are open because people sign in there.
- The web app ships its fonts; the build and the browser never reach Google.
- Production refuses an incomplete or unsafe configuration at start and lists every problem.
- Only LightCI leads may switch organisations with `X-Activate-Org`; invites require champion or admin; the demo seed is lead-only and absent from release images.
- Nightly jobs run once across the cluster through the job queue; `module.prepare` is a singleton job.
- Marketplace writes fetch, commit and push to the remote under a database lock; remotes are the source of truth.
- The web app proxies `/api/*` from its own origin; one web image serves every deployment.
- Images and the chart are published under `ghcr.io/lightconsultinginc/activate/*` and `ghcr.io/lightconsultinginc/charts/activate` (the GitHub organisation that owns the repository; registry paths are lower case).
- `deploy/terraform/aws` takes an optional `workos_webhook_secret_arn` (workos mode) so role sync and deactivation webhooks can be verified.

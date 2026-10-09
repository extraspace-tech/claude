# `../../Extra Space old/extraspace-backend` — the old production system (READ ONLY)

Always loaded. Codigo's code, in use since 2020 (`sgcodigo/extraspace-backend`, 4,300+ commits). It is what runs in production today. **Owner, 2026-10-09: the new monolith does not touch it.** The new system's code never calls it, never reads its databases and never migrates data from it, and nobody changes it. Use it only as a read-only record of how a business rule works today, for example points or autopay.

**Read-only DB access (owner, 2026-10-09):** the MCP `mysql-dev` is the **SG PRODUCTION** database (`extraspace_production`, MySQL 8.0.42) despite its name; `mysql-prod-my` is the **MY PRODUCTION** database (`extraspace_production_mys`, MySQL 5.7.12). The production DB hard rule applies: read only, aggregate counts only (no customer rows copied into chat, docs or briefs), light queries on indexed date columns, only when the owner asks. First use: usage sizing for the AWS estimate. `sitelink_transaction` has no `user_id` filled, so it counts system / job SiteLink calls, not app users. Scanned in full on 2026-10-09:

- `docs/notes/old-backend/01-mobile-api.md`: customer API, 81 routes.
- `docs/notes/old-backend/02-admin-cms.md`: back office, 398 actions, Hangfire jobs.
- `docs/notes/old-backend/03-core-data-infra.md`: ES Express, about 160 MySQL tables, deploy, config, SG/MY.

Read those notes first; open the code only to confirm a detail.

## 🔴 Secrets

Live production secrets are committed in this repo. They include:

- every `appsettings*.json` and `expressSettings*.json`
- `log4net.config`, both `Context.cs` files and `Common/LogHelper.cs`
- the Firebase service-account key files
- `admin_cms/wwwroot/secure/keys`

Never `cat`, `Read`, quote or copy those files into chat, a doc, a brief or a subagent prompt. Find config **key names** with `grep -o '"[A-Za-z:]*"'` or similar, never values. Every brief that sends an agent into this repo repeats this rule. The owner has been told the secrets need rotating (2026-10-09).

## Rules

- A PreToolUse hook blocks every Edit/Write under `Extra Space old/`. Never build, run, `git checkout` or `git switch` it. Use only read commands such as `git show`, `git diff` and `git log`.
- `yes-production` = Singapore and `mys-yes-production` = Malaysia. They are separate forks since 2024-06-26, with separate DB, Redis, S3, Stripe and Noke. Check both branches before saying "the old system does X".
- The old code is a record of behaviour, not a design to copy. The scan found many defects, listed in each note's security section. The worst:
  - an unverified Stripe webhook (`mobile_api/Controllers/WebhookController.cs:47`)
  - a password-reset link returned in the API response (`mobile_api/BL/AuthenticationBL.cs:772`)
  - SiteLink `PaymentSimpleWithSource` called with test card numbers
  - SQL injection in several search and export paths
  - missing permission checks in the CMS
- Facts a rebuild depends on:
  - Customers are SiteLink tenants. Passwords live only in SiteLink.
  - Money is MySQL `decimal`.
  - `datetime` columns have no time zone, and writers mix UtcNow and Now.
  - Admin password hashes and AES-encrypted columns depend on the closed `Lib/Codigo.Crypto.dll`.
  - Points live in a ledger: `point_transaction`, `point_use` and `redeem_reward`.
  - `user_tenantsite` links each member to a SiteLink tenant per site.
- The non-git snapshot `../../Extra Space old/ExtraSpaceAPI|ExtraSpaceCMS` may be newer than the repo for EarnPoints. Which copy is authoritative is OPEN.

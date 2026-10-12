# AWS setup guide — Extra Space platform

Written 2026-10-10 for the owner, who is setting up AWS for the first time. It follows the S0 design spec (`docs/superpowers/specs/2026-10-09-s0-foundation-design.md` §4.4, §5, §6.2, §9) and the cost estimate v4 (`docs/notes/aws-cost/aws-cost-estimate-v4.html`).

**Updated 2026-10-12:** one client-owned AWS account holds staging and production; you sign in with an IAM user (Part A rewritten).

**How to read this guide**

- **Part A** can start the day you get an AWS account. No code is needed.
- **Part B** needs the S0 infrastructure code (`../CMS/infra/ExtraSpace.Infra`, AWS CDK in C#). That code does not exist yet; the S0 implementation plan builds it. Stack names below (`EsNetwork`, `EsData`, …) are **expected names**; the plan fixes the real ones, and this guide is updated then.
- **Part C** is production. **Part D** is day-to-day operation. **Part E** is troubleshooting.
- Do the steps in order. Each step says **who** does it: **you**, **client IT**, or **CDK** (the code creates it; you only run a command).
- Values in `<angle brackets>` are placeholders. The host names use `app.extraspaceasia.com` as an **example only**; the real host name is still OPEN.

🔴 Safety rules that hold for every step:

- Never paste a password, secret or key into chat, a ticket, an email, a git commit or a shell command line. Type it straight into the AWS console or a password prompt.
- `extraspace-tech/cms` is a **public** repository today. Nothing from AWS (account ids are fine; secrets, connection strings and endpoints with credentials are not) goes into it.
- Production data is never copied to your laptop or to staging.

---

## 0. Words you will meet

| Term | Meaning |
|---|---|
| **Account** | One AWS "container" with its own bill, users and resources. We use **one client-owned account** for both staging and production. |
| **Organization** | Groups several accounts under one bill. The first account that creates it is the **management account**. |
| **Region** | A data-centre area. Ours is **Asia Pacific (Singapore), `ap-southeast-1`**. Always check the region picker in the top-right of the console. |
| **Availability Zone (AZ)** | One data centre inside the region. We use 2, so one can fail. |
| **Root user** | The email address that created the account. All-powerful; used almost never. |
| **IAM Identity Center** | Where you create your everyday sign-in (users, groups, which accounts they may enter). Formerly "AWS SSO". |
| **VPC / subnet** | Your private network in AWS. **Public subnets** face the internet (load balancer); **private subnets** do not (app servers, database). |
| **NAT gateway** | Lets servers in private subnets call the internet (SiteLink, Stripe) from a fixed IP address, while nobody can call in. |
| **ALB** | Application Load Balancer: the HTTPS front door that spreads traffic over the app servers. |
| **WAF** | Web Application Firewall in front of the ALB. |
| **ECS / Fargate** | Runs our Docker image as "tasks" without us managing servers. A **service** keeps N tasks running. |
| **ECR** | Docker image registry inside AWS. |
| **RDS** | Managed PostgreSQL. **Multi-AZ** = a live standby copy in a second AZ. **RDS Proxy** = connection pooler in front of it. |
| **Secrets Manager** | Encrypted store for passwords and keys; the app reads them at start. |
| **ACM** | Free HTTPS certificates. |
| **Route 53** | AWS DNS. A **hosted zone** holds the DNS records of one domain or subdomain. |
| **SES** | Email sending. New accounts start in the **sandbox** (can only send to verified addresses). |
| **CloudWatch** | Logs, metrics, alarms, dashboards. **Logs Insights** = search over logs. |
| **CDK** | Infrastructure as code: C# code that describes all the above; `cdk deploy` creates or changes it. |
| **Stack** | One deployable group of resources in CDK / CloudFormation. |
| **OIDC role** | Lets GitHub Actions act in AWS without storing any AWS key in GitHub. |
| **SSM Session Manager** | Opens a secure tunnel to a server without SSH keys or open ports. We use it to reach the private database. |

---

## Part A — Before any code (start as soon as you have an AWS account)

### A1. What we have (decided 2026-10-12)

- **One AWS account, owned by the client**, holds **both staging and production** (PM, 2026-10-12). Staging is not on Vercel.
- You sign in with an **IAM user** the client created. You do **not** have the root user, and you should not need it.
- Known so far: your user is **not** PowerUserAccess; **Billing is access denied**; **Tag Editor** works. Your exact policies are still to be confirmed (A3).
- Staging and production are kept apart inside the account by: separate stacks (`…-staging` / `…-production`), separate networks (VPCs), separate databases, separate secrets (`es/staging/…`, `es/production/…`), and the tag `Environment=staging|production` on every resource. A mistake in a staging command cannot hit production as long as you never type a `-production` stack name by accident; Part C adds the habits that guard this.

### A1b. Account survey (read-only, 2026-10-12)

- Account `110611798568`, no alias. It is the **management account of the client's AWS Organization** (`o-0mp5qfq25w`).
- Owner's IAM user `waiyanmin`: MFA on; **AdministratorAccess** through group `Tech_ES_App` (deploy actions simulated: all allowed; Service Control Policies not checked). Billing console denied: root has probably not switched on "IAM user and role access to Billing information".
- **Shared account.** Already in `ap-southeast-1`: 6 Lambda functions (Node 22: `sugarAPI`, `sitelinkAPI`, `marketingReport-sg/-my/-kr/-hk`), 3 S3 buckets (`marketingreport-1`, `sitelink-1`, `sugar-1`), the default VPC. No EC2, RDS, ECS, ECR, load balancer, Route 53 zone, certificate, secret or CloudFormation stack. Nothing found in `us-east-1`, `ap-southeast-2`, `ap-northeast-2`; `ap-southeast-5` (Malaysia) is not enabled. 🔴 Never change these existing resources.
- Not set up: CloudTrail trail (only the default 90-day history), GuardDuty, account-level S3 Block Public Access (do **not** switch it on ourselves: the existing buckets may rely on public access), budgets.
- SES: **sandbox** (200 emails a day, verified recipients only), no identities.
- Limits fine for our plan: Fargate 30 vCPU, 5 Elastic IPs (we need 3 for NAT), 5 VPCs (we need 2).
- PostgreSQL on `db.m8g.large` Multi-AZ: available up to **18.6**; RDS default is 18.3.
- Recommendation for the client (not blocking): AWS advises against running workloads in the Organization's management account. A free member account for the platform would separate its bill, permissions and risk from the existing Lambdas.

Done 2026-10-12: budget `extraspace-platform-monthly`, US$1,170 a month for the whole account, alerts to the owner and Aung Win Thant at 50 / 80 / 100 % actual and 100 % forecast. It also counts the client's existing Lambdas.

### A2. Protect your own sign-in (you, ~10 min)

1. Sign in with the link the client gave you (`https://<account-id-or-alias>.signin.aws.amazon.com/console`).
2. Region picker (top-right) → **Asia Pacific (Singapore)**.
3. Top-right menu → **Security credentials** → **Assign MFA device** → **Authenticator app** → scan, enter two codes. If this is denied, ask the client's admin to allow you to manage your own MFA (A3).
4. Do **not** create access keys. The command line signs in with your console login instead (A7).

### A3. Ask the client's AWS admin (send them this list)

Your user cannot do these, or should not. Send this list to whoever manages the client's AWS account (it is written for them):

> We are setting up the new ExtraSpace platform (staging and production) in your AWS account, region Singapore (`ap-southeast-1`). Please:
>
> 1. **Permissions for our deployer user `<your IAM user name>`:** attach `AdministratorAccess`, or tell us which permissions you prefer to grant. Our infrastructure tool (AWS CDK) creates networks, load balancers, databases, containers, DNS records, certificates, email identities, secrets and the IAM roles they use, so it needs broad rights. Please also attach `SignInLocalDevelopmentAccess` (lets the AWS command line sign in with the console login instead of long-lived keys; if that policy name does not exist in your console, tell us).
> 2. **Require MFA** on our user, or confirm we may set it up ourselves.
> 3. **Budgets** (we cannot see Billing): create a monthly cost budget of **US$1,170** for the platform, with email alerts to `<your email>` and `<PM email>` at 50 %, 80 % and 100 % actual and 100 % forecast. Once our first resources exist, please **activate the cost allocation tag `Environment`** (Billing → Cost allocation tags) so staging and production show separately, and if possible filter the budget on the tag `Project=extraspace-platform`.
> 4. Confirm **CloudTrail** is on for this account (at least the default 90-day event history), and **S3 Block Public Access** at account level is on.
> 5. Tell us if anything else already runs in this account, and if your organisation has rules for it (Service Control Policies, required tags, allowed regions).
> 6. Optional, recommended: enable **GuardDuty** (threat detection, about US$5–15 a month).

### A4. Check what is already in the account (you)

Tag Editor → Regions **All** → Resource types **All supported** → **Search resources**. Note what exists. If other systems run here, every resource we create must carry our tags, and we never touch theirs. Report the result before Part B.

### A5. Confirm your permissions work (you, after the admin answers A3)

Read-only checks; they change nothing:

```bash
aws sts get-caller-identity --profile extraspace          # shows the account id and your user
aws ec2 describe-vpcs --profile extraspace --query 'Vpcs[].VpcId'
aws iam list-attached-user-policies --user-name <your IAM user name> --profile extraspace
```

`AccessDenied` on any of these means A3 item 1 is not done yet.

### A6. (Not needed in this setup)

Organizations, member accounts and IAM Identity Center are the client's choice; with one client-owned account we do not set them up.

### A7. Your laptop (you, ~30 min)

Install on the Mac (Homebrew):

```bash
brew install --cask session-manager-plugin           # tunnel to the private database
brew install libpq && brew link --force libpq        # psql client only, no local server
brew install --cask orbstack                         # Docker runtime; needed for tests and the local DB
npm install -g aws-cdk                               # CDK command line (Node is already installed)
```

The AWS command line is already installed (`aws-cli/2.36.14`, checked 2026-10-12). Done 2026-10-12: all four tools above are installed; `cdk` is in `~/.local/share/node-v24.18.0/bin`.

🔴 Your `~/.aws` folder has a `default` profile: Codigo's Porsche account `747103386453` (checked 2026-10-12). Never use it for this project; always pass `--profile extraspace --region ap-southeast-1`. Claude sessions in this workspace cannot see it (`.claude/settings.json` sets `AWS_SHARED_CREDENTIALS_FILE=/dev/null`). Your own terminal still can, so type the profile every time.

Sign the command line in with your console login (no access keys):

```bash
aws login --profile extraspace --region ap-southeast-1
```

A browser opens; sign in (with MFA) and approve. The command line refreshes the temporary credentials itself while the session lasts. Check:

```bash
aws sts get-caller-identity --profile extraspace
```

If `aws login` is denied, A3 item 1 (`SignInLocalDevelopmentAccess`) is missing.

Check everything:

```bash
aws --version && cdk --version && psql --version && docker --version
```

### A8. Domain and DNS (you + client IT)

**What we found (checked 2026-10-10):** `extraspaceasia.com` is registered with WebNIC and its DNS is hosted at **ixiz.sg** (`pridns.ixiz.sg`, `secdns.ixiz.sg`, `terdns.ixiz.sg`), not in AWS. Its SPF record already lists Outlook, Mandrill, SendGrid and one IP, and DMARC is `p=none`.

**Recommendation: delegate one subdomain to AWS.** Client IT adds 4 records once; after that, CDK creates every record we need (certificate checks, the ALB address, email DKIM) without asking client IT again, and their main domain and email are never touched.

1. **You**: Console → **Route 53** → **Hosted zones** → **Create hosted zone** → name `<app.extraspaceasia.com>`, type Public. (Costs US$0.50/month.)
2. Open it and copy the 4 values of its **NS** record (they look like `ns-123.awsdns-45.com.`).
3. **Client IT**, at ixiz.sg: add 4 **NS** records for the name `app` (the subdomain) pointing to those 4 values. Nothing else changes in their zone.
4. **You**: check it worked (can take minutes to a few hours):

   ```bash
   dig +short NS app.extraspaceasia.com      # must print the 4 awsdns names
   ```

5. Staging uses names inside the same zone (for example `staging.app.extraspaceasia.com`); with one account there is no separate staging zone.

Resulting names (example): production `https://app.extraspaceasia.com` (`/api`, `/admin`), staging `https://staging.app.extraspaceasia.com`. Email sender (example): `no-reply@app.extraspaceasia.com`.

If the client prefers not to delegate, client IT must instead add every record by hand (certificate validation CNAMEs, the ALB CNAME, 3 DKIM CNAMEs, MAIL FROM records) for each environment, and again whenever one changes. That works, but it is slower and easy to get wrong.

### A9. Email: what to request early (you)

SES itself is created by CDK in Part B, but one step takes a day and needs a human:

- **Leave the sandbox (once for the account).** After B6 has verified the domain: Console → **Amazon SES** → **Account dashboard** → **Request production access**. Mail type: Transactional. Use case text (example): "Sign-in codes and account notifications for ExtraSpace customers in Singapore and Malaysia, about 10,000 emails a month, sent only to users who requested them; bounces and complaints are handled through SES notifications." AWS answers within about 24 hours.
- Done 2026-10-12: `waiyanmin@codigo.co` and `aungwinthant@codigo.co` registered as test inboxes (each must click the AWS confirmation link).
- Until production access is granted, the account can only send to verified addresses. Verify the team's test inboxes: SES → **Identities** → **Create identity** → Email address → click the link in the email. After the sandbox exit, staging can email anyone too; staging therefore only sends to addresses on an allow-list in its config (the S0 plan adds this), so test runs never email real customers.

### A10. Staff sign-in: Microsoft Entra app registration (client IT, guided by you)

The admin back office signs staff in with their Microsoft 365 accounts (spec §6.2). Client IT registers our app once per environment. Send them these steps:

1. https://entra.microsoft.com → **Applications** → **App registrations** → **New registration**.
   - Name: `ExtraSpace Admin (staging)` (second time: `(production)`).
   - Supported account types: **Accounts in this organizational directory only** (single tenant).
   - Redirect URI: platform **Web**, value `https://<staging.app.extraspaceasia.com>/signin-oidc` (production: `https://<app.extraspaceasia.com>/signin-oidc`). `/signin-oidc` is the default path of `Microsoft.Identity.Web`; the S0 plan confirms it.
2. **Certificates & secrets** → **New client secret** → expiry 24 months. Put a calendar reminder 1 month before it expires.
3. **API permissions**: keep the default **Microsoft Graph → User.Read** (delegated). No admin-consent-only permissions are needed.
4. Recommended: **Enterprise applications** → this app → **Properties** → **Assignment required = Yes**, then **Users and groups** → add the staff group that may use the admin. Others are then stopped by Microsoft before they reach us (our app also refuses anyone not added as staff).
5. Hand over: **Directory (tenant) ID**, **Application (client) ID** (not secret, can be emailed) and the **client secret value** — the secret only through a secure channel: ideally client IT types it into AWS Secrets Manager themselves (B4), or uses their password manager's secure share. Never by plain email or chat.

### A11. GitHub (you + org admin)

1. 🔴 Ask the org admin to make `extraspace-tech/cms` **private** before the first real commit (open decision 1).
2. Repository → **Settings** → **Environments** → create `staging` and `production`. On `production`: **Required reviewers** = you (and a second person if available). This is the approval gate before every production deploy.
3. Nothing AWS-related is stored in GitHub secrets: GitHub reaches AWS through the OIDC role created in B2.

---

## Part B — Staging (after the S0 infrastructure code exists)

Order matters: each step needs the one before.

```
B1 bootstrap CDK → B2 CI role → B3 network + data + registry → B4 fill secrets
→ B5 database users → B6 email + certificate → B7 first image + app → B8 migrate → B9 check
```

### B1. Bootstrap CDK (you, once for the account) — ✅ DONE 2026-10-12

Done with `--termination-protection --tags Project=extraspace-platform --tags ManagedBy=cdk`: stack `CDKToolkit` CREATE_COMPLETE (1 S3 bucket + policy, 1 ECR repo, 5 IAM roles, 2 policies, 1 SSM parameter). The command below is kept for reference.

CDK needs a small "toolkit" stack in each account before the first deploy.

```bash
aws login --profile extraspace --region ap-southeast-1
cd "/Users/waiyanmin/Projects/Extra Space/CMS/infra/ExtraSpace.Infra"
cdk bootstrap aws://<ACCOUNT_ID>/ap-southeast-1 --profile extraspace
```

Success ends with `Environment aws://…/ap-southeast-1 bootstrapped.`

### B2. Let GitHub Actions deploy without keys (you, once)

The infra code has a small CI stack (expected name `EsCi`) that creates the GitHub OIDC provider and **two** deploy roles that only `extraspace-tech/cms` may use: the staging role only from `main` and only for `…-staging` stacks; the production role only from the GitHub `production` environment (which needs your approval).

```bash
cdk deploy EsCi --profile extraspace
```

Note the two role ARNs it prints; the GitHub workflow uses them (they are not secrets).

### B3. Network and database (CDK) — ✅ STAGING DONE 2026-10-12

Plan S0-1 creates the network and the database. The image registry (ECR) and the app come with S0-6 (B7).

```bash
cd "/Users/waiyanmin/Projects/Extra Space/CMS/infra/ExtraSpace.Infra"
export PATH="$HOME/.local/share/node-v24.18.0/bin:$PATH" AWS_REGION=ap-southeast-1
cdk diff   EsNetwork-staging EsData-staging --profile extraspace   # read what will be created
cdk deploy EsNetwork-staging EsData-staging --profile extraspace   # answer y to the security prompt after reading it
```

What appeared (starts costing ≈ US$128 a month, ≈ US$4.20 a day):

- VPC `10.10.0.0/16` with public, app and data subnets in 2 AZs, 1 NAT gateway with a fixed IP, an S3 gateway endpoint
- RDS PostgreSQL 18.6 `db.t4g.medium`, single-AZ, encrypted, not public, TLS forced; master password generated by CDK into `es/staging/db-master`
- secrets `es/staging/db-app` and `es/staging/db-readonly`, each holding a generated username and password for the B5 users
- the ops bastion: a `t4g.nano` EC2 instance without SSH or open ports, reachable only through Session Manager; only it may reach the database on 5432

Deploy took 13 minutes (network 2, database 8.5). Stack outputs, staging (not secrets; keep them out of `../CMS`):

| Output | Value |
|---|---|
| `DbEndpoint` | `es-staging-postgres.cxeuq2wg4epf.ap-southeast-1.rds.amazonaws.com` |
| `BastionInstanceId` | `i-02704e4007d4f9f1a` |
| `DbMasterSecretName` | `es/staging/db-master` |
| VPC | `vpc-06927d61e40493979` |

After the deploy the account still had the client's 6 Lambdas and exactly 1 Elastic IP (ours).

### B4. Fill the secrets (you; Entra secret ideally by client IT)

Console → **Secrets Manager** (staging account, Singapore) → open each secret the stack created → **Retrieve secret value** → **Edit** → type the value → **Save**. Expected entries (the plan fixes the exact list):

| Secret | Value | From |
|---|---|---|
| `es/staging/db-app` | already filled by CDK (username `es_app` + generated password); the app builds its connection string from it (S0-2 / S0-6 fix how) | CDK (B3) |
| `es/staging/entra` | tenant id, client id, client secret | client IT (A10) |
| `es/staging/jwt-signing-key` | long random string | generate: `openssl rand -base64 48` and paste the output straight into the console; do not save it anywhere else |
| later (S1) | SiteLink, Stripe test keys | the client's secret store |

The app reads these at start; changing one needs a restart of the tasks (D5).

### B5. Database users (once per environment) — ✅ STAGING DONE 2026-10-12

The app must not use the all-powerful master user. Three users per environment:

| User | Rights | Password in |
|---|---|---|
| `postgres` (master) | everything; runs migrations by hand (B8) | `es/<env>/db-master` |
| `es_app` | read and write tables in `public`; owns schema `hangfire` | `es/<env>/db-app` |
| `es_readonly` | read only (D8, the `postgres-dev` MCP on staging) | `es/<env>/db-readonly` |

CDK already generated all three passwords. The script reads them from Secrets Manager into environment variables and hands them to `psql` with `\getenv`, so no password is typed, shown or saved.

1. Open the tunnel (leave this terminal open until step 4; wait for `Waiting for connections...`):

   ```bash
   aws ssm start-session --profile extraspace --region ap-southeast-1 \
     --target <BastionInstanceId> \
     --document-name AWS-StartPortForwardingSessionToRemoteHost \
     --parameters '{"host":["<DbEndpoint>"],"portNumber":["5432"],"localPortNumber":["15432"]}'
   ```

2. In a second terminal, create the users. `-1` runs it as one transaction, so a failure leaves nothing behind:

   ```bash
   secret() { aws secretsmanager get-secret-value --profile extraspace --region ap-southeast-1 \
     --secret-id "$1" --query SecretString --output text | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["password"])'; }
   ENV=staging
   export PGPASSWORD="$(secret es/$ENV/db-master)"
   export ES_APP_PW="$(secret es/$ENV/db-app)"
   export ES_RO_PW="$(secret es/$ENV/db-readonly)"

   psql "host=localhost port=15432 dbname=extraspace user=postgres sslmode=require" -X -1 -v ON_ERROR_STOP=1 <<'SQL'
   \getenv app_pw ES_APP_PW
   \getenv ro_pw ES_RO_PW
   CREATE ROLE es_app LOGIN PASSWORD :'app_pw';
   CREATE ROLE es_readonly LOGIN PASSWORD :'ro_pw';
   GRANT CONNECT ON DATABASE extraspace TO es_app, es_readonly;
   GRANT USAGE ON SCHEMA public TO es_app, es_readonly;
   ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
     GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO es_app;
   ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
     GRANT USAGE, SELECT ON SEQUENCES TO es_app;
   ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
     GRANT SELECT ON TABLES TO es_readonly;
   GRANT es_app TO postgres WITH SET TRUE, INHERIT FALSE;
   CREATE SCHEMA hangfire AUTHORIZATION es_app;   -- Hangfire creates and upgrades its own tables
   REVOKE es_app FROM postgres;
   SQL
   unset PGPASSWORD ES_APP_PW ES_RO_PW
   ```

   Why the `GRANT es_app TO postgres` / `REVOKE` pair: on RDS the master user is not a real superuser, and PostgreSQL 16+ lets it create a schema owned by `es_app` only while it may switch to `es_app`. RDS gives the master no membership in roles it creates, and `SET createrole_self_grant` does not help (tried 2026-10-12). The pair gives that right for one statement and takes it back.

3. Check (expected: `es_app|t|t`, then a `no pg_hba.conf entry … no encryption` error, which proves TLS is forced):

   ```bash
   export PGPASSWORD="$(secret es/$ENV/db-app)"
   psql "host=localhost port=15432 dbname=extraspace user=es_app sslmode=require" -X -tAc \
     "select current_user, version() like 'PostgreSQL 18.6%', (select ssl from pg_stat_ssl where pid = pg_backend_pid())"
   psql "host=localhost port=15432 dbname=extraspace user=es_app sslmode=disable" -X -c 'select 1' 2>&1 | tail -1
   unset PGPASSWORD
   ```

4. Close the tunnel with Ctrl+C.

Staging result, 2026-10-12: all statements ran; `es_app` logs in over TLS on PostgreSQL 18.6 and can create tables in `hangfire`; a connection without TLS is refused; `es_readonly` cannot create in `public` and has no access to `hangfire`; the master is no longer a member of `es_app`.

🔴 Production: the owner runs this by hand (production DB rule), with `ENV=production` and the production tunnel. The app's `Host=` there is the RDS Proxy endpoint (C2).

### B6. Email domain and HTTPS certificate (CDK)

```bash
cdk deploy EsEdge-staging --profile extraspace
```

CDK creates, inside the delegated zone from A8:

- the ACM certificate for `<staging.app.extraspaceasia.com>`, validated automatically through DNS
- the SES domain identity with DKIM (3 records) and a MAIL FROM subdomain, all records written to Route 53 automatically

Check in the console: **ACM** → status **Issued**; **SES** → **Identities** → status **Verified**, DKIM **Successful**. Both can take up to about 30 minutes.

### B7. First image and the app (CI + CDK)

The app stack needs an image in ECR before it can start tasks.

1. Merge the first S0 code to `main`. GitHub Actions builds the Docker image and pushes it to ECR, tagged with the commit SHA (spec §9.3).
2. Run the database migration first (B8), then deploy the app stack (from then on CI does this on every merge):

   ```bash
   cdk deploy EsApp-staging --profile extraspace -c imageTag=<COMMIT_SHA>
   ```

   This creates the ALB, WAF, the ECS service, the DNS record `<staging.app.extraspaceasia.com>`, log groups, saved log queries and alarms.

### B8. Run a database migration by hand (you, before every deploy that changes the schema)

The rule (spec §5): migrations never run automatically on shared environments.

1. In `../CMS`, generate the script into the context repo:

   ```bash
   cd "/Users/waiyanmin/Projects/Extra Space/CMS"
   dotnet ef migrations script --idempotent \
     --project src/ExtraSpace.Api \
     -o "../Claude/docs/migrations/<YYYY-MM-DD>-<name>.sql"
   ```

2. Read the script. Check that it only adds things, or that the change is safe for the version of the app that is still running (spec §5: every migration stays compatible with the previous app version).
3. Open the tunnel (B5 step 1) and run it as the master user:

   ```bash
   psql "host=localhost port=15432 dbname=extraspace user=postgres sslmode=require" \
     -v ON_ERROR_STOP=1 -f "../Claude/docs/migrations/<YYYY-MM-DD>-<name>.sql"
   ```

   `ON_ERROR_STOP=1` stops at the first error; each migration in an idempotent EF script is in its own transaction, and already-applied ones are skipped.
4. Then deploy the app (B7 / CI).

### B9. Check staging works (you, ~15 min)

```bash
curl -s https://<staging.app.extraspaceasia.com>/health/live     # process up
curl -s https://<staging.app.extraspaceasia.com>/health/ready    # database reachable
curl -sI https://<staging.app.extraspaceasia.com>/health/live | grep -i x-trace-id
```

Then walk the S0 definition of done (spec §11): sign in with a code sent to a verified test inbox, sign in to `/admin` with your Microsoft account (your email must be in `Admin:BootstrapEmails` the first time), open `/admin/jobs`, force an error and find it with the **Trace** query (D3).

In CloudWatch → **Alarms**, every alarm should be **OK** (some show "Insufficient data" for the first hour; that is normal).

---

## Part C — Production

Same steps as Part B with `--profile extraspace` and the `-production` stacks, plus these differences.

### C1. Before the first production deploy

- [ ] Part A done (A3 answered by the client's admin, A8 zone delegated, A9 sandbox exit, A10 production app registration).
- [ ] S0 definition of done passed on staging.
- [ ] PDPA confirmation for Malaysian data hosted in Singapore (open decision 2) received.
- [ ] Production Entra secret, JWT key and (from S1) live SiteLink and Stripe keys under `es/production/…` in Secrets Manager — never the staging ones.

### C2. What is different in production (all done by CDK)

| Item | Staging | Production |
|---|---|---|
| App tasks | 1 × 1 vCPU / 2 GB, role `all` | `api` 2 × 2 vCPU / 4 GB (auto-scales to 4) + `jobs` 1 × 1 vCPU / 2 GB |
| Database | `db.t4g.medium` single-AZ | `db.m8g.large` **Multi-AZ**, 35-day backups, deletion protection, Database Insights advanced |
| RDS Proxy | no | yes — the app connection string points at the **proxy endpoint**; migrations still connect to the database endpoint directly |
| NAT gateways | 1 | 2 (two fixed IPs; give **both** to SiteLink if it allowlists) |
| Cache | — (S1) | Valkey 2 nodes (S1) |
| Log retention | 14 days | 90 days |
| Deploy | automatic on merge to `main` | GitHub `production` environment, needs your approval, same image tag as staging |

### C3. Production deploy, every time

1. Run the migration script on production (B8, with the **production** bastion and database endpoint), if the release has one.
2. GitHub → **Actions** → the run for that commit → **Review deployments** → approve `production`.
3. Watch the ECS service: Console → **ECS** → cluster → service → **Deployments**: the new tasks reach "Running" and the old ones drain. Then check `/health/ready` and the Errors query (D3).

---

## Part D — Day-to-day operation

### D1. Sign in

```bash
aws login --profile extraspace --region ap-southeast-1
```

Console: the sign-in link from the client, with MFA.

### D2. Deploy and roll back

- **Deploy:** merge to `main` → staging is deployed automatically → approve production in GitHub (C3).
- **Roll back the app:** re-run the production deploy job of the **previous** good commit (GitHub → Actions → that run → **Re-run jobs**), or `cdk deploy EsApp-production -c imageTag=<PREVIOUS_SHA> --profile extraspace`. This works because every migration stays compatible with the previous app version (spec §5). A schema change is never "rolled back" by hand; a fix goes forward as a new migration.

### D3. Find what happened (logs)

Console → **CloudWatch** → **Logs Insights** → **Saved queries** (created by CDK, spec §4.4):

| Query | Use it when |
|---|---|
| **Trace** | Someone gives you a `traceId` (from an error screen, the admin toast, or the `X-Trace-Id` header). Paste it; you see the request, the jobs it started and every outside call, in time order. |
| **Errors** | "Is anything broken right now?" Last hour, grouped by route / job. |
| **Slow** | Pages feel slow. Requests over 1 s and slow DB commands. |
| **Outside-call failures** | SiteLink, Stripe or SES problems. |
| **One user** | A customer or staff member reports an issue; search by their id. |

Pick the log groups `/extraspace/<env>/api` and `/extraspace/<env>/jobs` and a time range that covers the event.

### D4. Alarms

Alarms (5xx rate, failed jobs, unhealthy or missing tasks, DB CPU and connections) email the address configured in CDK. When one fires: open **Errors** (D3) for the same time, then the ECS service **Events** tab, then **RDS → Database Insights** if the database alarm fired.

### D5. Restart the app (for example after changing a secret)

ECS → cluster → service → **Update service** → tick **Force new deployment** → **Update**. New tasks start with the new secret values; old ones stop. No downtime with 2 or more tasks.

### D6. Scale

Permanent changes (task size or count, database size) go through the CDK code and a deploy, so the code always matches AWS. A database size change causes a short failover (under about 2 minutes with Multi-AZ); do it outside business hours.

### D7. Restore the database to a point in time

RDS keeps 35 days (production) of point-in-time backups. A restore **creates a new database**; it never overwrites the running one.

1. RDS → Databases → the database → **Actions** → **Restore to point in time** → pick the time just before the problem → new name `extraspace-restore-<date>`.
2. Use the restored copy to read or copy back the lost rows through the tunnel. Switching the app to the copy is a planned change in CDK, not a console click.
3. Delete the copy when done (it costs as much as the original).

### D8. Read-only database access for debugging

Through the tunnel (B5 step 1), as `es_readonly`, created in B5 with its password in `es/<env>/db-readonly`. It sees tables that the master user creates in `public` (default privileges). For tables that existed before B5, run once as the master user: `GRANT SELECT ON ALL TABLES IN SCHEMA public TO es_readonly;`

This is also the user for the planned read-only `postgres-dev` MCP on **staging**. 🔴 Production DB rule: reads only, never writes, never a local app booted against production.

### D9. Recurring chores

| When | What |
|---|---|
| Monthly | Ask the client's admin for the bill split by the `Environment` tag (you have no Billing access), or for read access to Cost Explorer. |
| After 1–2 months of production | Decide the 1-year database reservation (−US$112.78/month, cost v4). |
| 1 month before expiry | Rotate the Entra client secret (A10 step 2 → B4 → D5). |
| Each new PostgreSQL minor version | RDS applies it in the maintenance window; check the RDS **Pending maintenance** list. |
| Quarterly | Review who is in `es-admins` and in the Entra assignment list. |

---

## Part E — Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `ExpiredToken` / credentials expired | Command-line sign-in timed out | `aws login --profile extraspace --region ap-southeast-1` |
| A command acts on the wrong account | The `default` profile was used | Always pass `--profile extraspace`; check with `aws sts get-caller-identity --profile extraspace` |
| `cdk deploy` says "has not been bootstrapped" | B1 skipped | Run B1 |
| Resources missing or "not found" | Console or CLI in the wrong region | Region picker → Singapore; CLI profile has `ap-southeast-1` |
| ACM certificate stuck at "Pending validation" | NS delegation (A8) not working yet | `dig +short NS staging.app.extraspaceasia.com` must show awsdns names |
| Emails not arriving on staging | SES sandbox | Verify the recipient address (A9), or check SES → **Suppression list** |
| ECS tasks start and stop again | App fails at start: usually a missing or wrong secret, or the DB not reachable | ECS → service → **Logs** tab, or the **Errors** query; `/health/ready` |
| `CannotPullContainerError` | Image tag not in ECR, or NAT gateway missing | Check the tag exists in ECR; check the NAT gateway is "Available" |
| Tunnel: `TargetNotConnected` | Bastion stopped | EC2 → start the instance, wait 1 minute |
| psql: `password authentication failed` | Wrong user or old password after a rotation | Re-read the secret; check `user=` |
| Admin sign-in loops or `AADSTS50011` | Redirect URI in Entra does not match the host exactly | Fix the URI in the app registration (A10 step 1) |
| Admin sign-in gives 403 | You are not yet staff | First sign-in needs your email in `Admin:BootstrapEmails` |
| Bill higher than expected | Something left running (a restored DB copy, an extra task) | Cost Explorer → group by **Service** and **Usage type** |

---

## Open points this guide depends on

| Point | Status | Blocks |
|---|---|---|
| AWS account | DECIDED 2026-10-12: one client-owned account for staging and production; IAM user permissions still to confirm (A3) | Part B |
| Host name and subdomain delegation | OPEN (decision 5); proposal in A8 | B6, A10 |
| Entra registration by client IT | OPEN (decision 4) | admin sign-in |
| SES sender address | OPEN (decision 4); proposal `no-reply@<app subdomain>` | sign-in codes |
| Repo private | OPEN (decision 1) | first commit |
| Ops bastion + DB users (`es_app`, `es_readonly`) | **Proposed in this guide**, added to the S0 spec; owner to approve | B5, B8 |
| Stack names, secret names, the Entra callback path | fixed by the S0 implementation plan | this guide's exact commands |
| GuardDuty | not in the v4 estimate; PM to decide | — |

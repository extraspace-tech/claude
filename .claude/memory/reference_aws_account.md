---
name: reference-aws-account
description: The client's AWS account for staging + production (110611798568): how we sign in (profile extraspace), what was set up, what else lives there, and the never-use-the-default-profile rule.
metadata:
  type: reference
---

- **Account `110611798568`**, region `ap-southeast-1`, owned by the client. It is the **management account of their AWS Organization** (`o-0mp5qfq25w`). Staging and production both live here (PM, 2026-10-12).
- **Sign-in:** IAM user `waiyanmin`, MFA on, **AdministratorAccess** through group `Tech_ES_App`. Billing console is denied (root has not enabled IAM billing access).
  - CLI: `aws login --profile extraspace --region ap-southeast-1` (a browser sign-in, no access keys).
  - The profile has **no region** saved, so always pass `--region ap-southeast-1`.
- 🔴 **The `default` profile on the owner's Mac is Codigo's Porsche account `747103386453`** (long-lived keys). It must never be used for Extra Space.
  - The workspace `.claude/settings.json` sets `AWS_SHARED_CREDENTIALS_FILE=/dev/null`, so Claude sessions here cannot use it.
  - Always pass `--profile extraspace`.
  - Incident 2026-10-12: a subagent's `cdk synth` made 3 read-only calls there. Nothing changed. Since then the CDK app does no context lookups (fixed availability zones).
- **Shared with other client systems — never touch:** 6 Lambda functions (`sugarAPI`, `sitelinkAPI`, `marketingReport-sg/-my/-kr/-hk`, Node 22) and 3 S3 buckets (`marketingreport-1`, `sitelink-1`, `sugar-1`). Do not switch on the account-level S3 public-access block either; their buckets may rely on public access.
- **Done by us, 2026-10-12:**
  - `cdk bootstrap`: stack `CDKToolkit`, termination-protected, tagged `Project=extraspace-platform`.
  - Budget `extraspace-platform-monthly`: US$1,170 for the whole account (the client's Lambdas count too). Alerts go to waiyanmin@codigo.co and aungwinthant@codigo.co at 50/80/100 % actual and 100 % forecast.
  - SES test inboxes (sandbox): the same two addresses, both verified.
  - **Staging deployed (S0-1):** `EsNetwork-staging` + `EsData-staging`. DB `es-staging-postgres` (PostgreSQL 18.6, `db.t4g.medium`), bastion `i-02704e4007d4f9f1a` (SSM tunnel to local port 15432), secrets `es/staging/db-{master,app,readonly}`, users `es_app` / `es_readonly`. ≈ US$128/mo. Endpoint and steps: guide B3 / B5.
  - The owner may run `cdk deploy` in their own terminal: Claude Code's safety check blocks `--require-approval never`.
- **Not set up:** CloudTrail trail (only the 90-day event history), GuardDuty, the `Environment` cost tag. These are the client admin's to do.
- **Limits:** Fargate 30 vCPU, 5 Elastic IPs (we use 3 NAT IPs), 5 VPCs. PostgreSQL on `db.m8g.large` / `db.t4g.medium` goes up to 18.6.
- Full walkthrough: `docs/notes/infra/aws-setup-guide.md` (A1b survey, B steps). Related: [[reference-aws-cost-estimate]], [[project-setup-owed]].

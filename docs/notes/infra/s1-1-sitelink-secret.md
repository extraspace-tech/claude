# S1-1: SiteLink secret, settings and alarms — owner runbook

Built in S1-1 Task 8 (`infra/ExtraSpace.Infra/{EnvConfig,Stacks/AppStack,Stacks/Observability}.cs`). Nothing here has been run yet. The owner runs every command in their own terminal; agents never do.

Cost: about +US$2.40/mo for both environments (2 secrets, 4 alarms, 4 filter metrics).

## What the stack adds

- Secret `es/<env>/sitelink`, created with four **empty** JSON keys: `CorpCode`, `CorpUserName`, `CorpPassword`, `ApiKey`.
- ECS secrets `SiteLink__CorpCode`, `SiteLink__CorpUserName`, `SiteLink__CorpPassword`, `SiteLink__ApiKey` on every task definition; the execution role may read the secret.
- Staging: `SiteLink__WriteAllowList__0=LSETUP`. Production: `SiteLink__AllowWritesToAllSites=true` (the app refuses this flag in any other environment).
- Alarms `es-<env>-outbox-failed` (≥ 1 permanently failed outbox message in 5 min) and `es-<env>-sitelink-monthly-calls` (≥ 1 "SiteLink calls this month reached …" line in 60 min; it fires only when `SiteLink:MonthlyCallAlarm` > 0 is set).

## Steps (staging first)

1. `cdk deploy EsApp-staging --profile extraspace --region ap-southeast-1`.
2. Fill the secret from a local file, never through chat, then delete the file:
   `aws secretsmanager put-secret-value --secret-id es/staging/sitelink --secret-string file://<file> --profile extraspace --region ap-southeast-1`
   - 🔴 The file must hold **all four keys**, with `""` for a value you do not have. `CorpUserName` is `user:::licence key`. A missing key stops the task from starting (ResourceInitializationError) and the deployment rolls back.
3. Force a new deployment of the service so the tasks read the new value (the next CI deploy does this too).
4. Production: the same with `EsApp-production` and `es/production/sitelink`.

Until steps 1–3 run, the app has no SiteLink login: every SiteLink call answers 503 and the unit refresh records "SiteLink could not be reached." That is safe.

## Rollback

- Stack: redeploy the previous commit's stack. The staging secret's removal policy is Delete, so it goes into the recovery window. A secret scheduled for deletion blocks creating one with the same name, so before deploying forward again run `aws secretsmanager restore-secret --secret-id es/staging/sitelink --profile extraspace --region ap-southeast-1`.
- Secret value: `put-secret-value` with the previous file, or the all-empty template.

## Not verified before the first staging deploy

- That ECS accepts empty-string JSON values on the first start (only a missing key is documented as an error).
- An offline `cdk synth` (the infra tests synthesize in process; run `cdk diff --profile extraspace` before deploying).

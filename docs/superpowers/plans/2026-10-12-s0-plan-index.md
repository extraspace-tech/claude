# S0 Foundation — plan index

The S0 spec (`docs/superpowers/specs/2026-10-09-s0-foundation-design.md`, approved 2026-10-12) covers six separate subsystems. Each one gets its own plan, and each plan ends with software that builds, passes its tests and can be checked on its own. One plan holding all six would be thousands of lines that no implementer can keep in mind at once.

| Plan | Delivers | Depends on | Can run in parallel with | Status |
|---|---|---|---|---|
| **S0-1** Repo skeleton + AWS network and database | Solution layout, build settings, CDK app with `EsNetwork-<env>` and `EsData-<env>` stacks (VPC, NAT, RDS PostgreSQL 18, bastion, DB secrets, RDS Proxy in production), infra tests. **Staging network + database deployed**, DB users created. | — | — | **done** 2026-10-12 (staging network + DB live): `2026-10-12-s0-1-network-database.md` |
| S0-2 API platform | `ExtraSpace.Api` host, error format, pipeline, logging and tracing (§4.4), app-version check, health, OpenAPI, `ExtraSpace.Engines` (Money), `AppDbContext` + conventions + interceptors, architecture test, `docker-compose.yml` (PostgreSQL + Seq), test harness (WebApplicationFactory + Testcontainers) | S0-1 (skeleton files only) | S0-6 infra part | **done** 2026-10-12, merged to `main` (PR #1): `2026-10-12-s0-2-api-platform.md` (also creates `data_protection_keys`) |
| S0-3 Customer identity + jobs + email | `customer*` tables, code flow, JWT + refresh rotation, `/me`, rate limits, Hangfire with roles and job tracing, SES sender + `login-code` template, `IdentityHousekeeping` | S0-2 | S0-4, S0-5 | after S0-2 |
| S0-4 Admin back end | Entra SSO, cookie (🔴 first: encrypt the Data Protection key ring at rest — KMS/Secrets Manager XML encryptor — or `REVOKE SELECT ON data_protection_keys FROM es_readonly`; S0-2 stores keys in plain XML), CSRF, RBAC, audit filter, staff / roles / audit / permissions endpoints, Hangfire dashboard auth, `xmin` 409 | S0-2 | S0-3, S0-5 | after S0-2 |
| S0-5 Admin UI shell | React 19 + Vite app, layout, Staff / Roles / Audit screens, generated API types | S0-4 contract (OpenAPI) | S0-3 | after S0-4's contract is fixed |
| S0-6 Delivery | Dockerfile, ECR, `EsEdge-<env>` (Route 53, ACM, SES domain), `EsApp-<env>` (ALB, WAF, ECS api/jobs, log groups, saved queries, alarms), `EsCi` (GitHub OIDC roles), GitHub workflows, secret scan; staging deploy and the §11 walk | S0-1; the app parts need S0-2…S0-5 | S0-2…S0-5 for the infra code | after S0-1 |

Rules for every S0 plan (from the workspace rules):

- Code goes to `../CMS`. Implementers are Opus `implementer` subagents; the main session reviews the real diff and gives a verdict per piece.
- **Nobody commits or pushes.** Each task ends with "hand-off": the owner commits. Work happens on a branch per plan (`s0-1-network-database`, …).
- 🔴 `extraspace-tech/cms` is public: no secret, connection string, account id or customer data in any file. Do not push until the repo is private (open item 5), or confirm with the owner.
- AWS changes in the client account `110611798568` run only from the main session, only after the owner's OK, and never touch the client's existing Lambdas and buckets. Production data rules from `.claude/CLAUDE.md` §6 apply.

## Carry-overs from S0-2 (final review, 2026-10-12)

- **S0-3:**
  - Job runs need their own Activity: `ActivitySetup` listens only to `Microsoft.AspNetCore`, so the Hangfire server filter starts `new Activity("job").Start()` (or adds its source to the listener) and calls `Correlation.Begin(...)`. Otherwise job lines have no `traceId`.
  - A 429 or `TOO_MANY_ATTEMPTS` that needs `Retry-After` is written with `ProblemWriter`. `AppException` carries no headers, and the exception handler clears the headers it does not own.
  - Per-IP rate-limit partitions need a fallback key: `RemoteIpAddress` is null under TestServer.
  - Owed test: an outdated app gets 426, not 401, on a signed-in route.
  - Name ids `familyId` and `codeId`, never `refreshTokenId` or `loginCodeId`: those names are masked.
- **S0-4:**
  - 🔴 Encrypt the Data Protection key ring, or revoke `es_readonly`'s read on it, before cookies ship.
  - A fallback auth policy needs `.AllowAnonymous()` on `MapOpenApi()`.
  - The cookie challenge on `/admin/api/*` must return 401, not a redirect.
  - Add `staffId` with `RequestLog.Add`.
  - Add a test that `Access-Control-Allow-Credentials` stays absent.
- **S0-5:**
  - A CSP header for `/admin` in `SecurityHeadersMiddleware`, and static files in slot 7.
  - An OpenAPI document transformer that adds a ProblemDetails / `code` / `traceId` error schema.
  - Browser navigations with `Accept: text/html` get an empty error body today.
  - Decide `NumberHandling`: the web JSON defaults document every int as `["integer","string"]`, so generated TS types read `number | string`. Option: `JsonNumberHandling.Strict` on both JSON option sets, which changes how request bodies are read.
- **S0-6:**
  - Set `App__Version`, `ASPNETCORE_ENVIRONMENT`, non-empty `App__MinVersion__*` values and `Cors__AllowedOrigins__0`.
  - Lock the task security groups to the ALB: forwarded headers are trusted from any caller.
  - The ALB target check is `/health/live`.
  - Error alarms filter on `exception` being present: the 5xx summary line is also at Error.
  - Never alarm on Warning volume: an unreadable `X-App-Version` header logs a Warning on every request.
  - Watch ECS task-stopped events for startup crashes: they come before Serilog starts.
  - Staging serves `/swagger` and `/openapi/v1.json` publicly (decision 9). Confirm with the owner.
  - The slow-query interceptor ignores failed commands (`CommandFailed`).
- **S1:**
  - Make `default(Money)` safe and use the invariant culture in `Money.ToString` once Money reaches EF or a DTO.
  - Use `.HasConversion<string>()` for every enum property.

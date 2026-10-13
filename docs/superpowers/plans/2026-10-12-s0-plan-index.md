# S0 Foundation — plan index

The S0 spec (`docs/superpowers/specs/2026-10-09-s0-foundation-design.md`, approved 2026-10-12) covers six separate subsystems. Each one gets its own plan, and each plan ends with software that builds, passes its tests and can be checked on its own. One plan holding all six would be thousands of lines that no implementer can keep in mind at once.

| Plan | Delivers | Depends on | Can run in parallel with | Status |
|---|---|---|---|---|
| **S0-1** Repo skeleton + AWS network and database | Solution layout, build settings, CDK app with `EsNetwork-<env>` and `EsData-<env>` stacks (VPC, NAT, RDS PostgreSQL 18, bastion, DB secrets, RDS Proxy in production), infra tests. **Staging network + database deployed**, DB users created. | — | — | **done** 2026-10-12 (staging network + DB live): `2026-10-12-s0-1-network-database.md` |
| S0-2 API platform | `ExtraSpace.Api` host, error format, pipeline, logging and tracing (§4.4), app-version check, health, OpenAPI, `ExtraSpace.Engines` (Money), `AppDbContext` + conventions + interceptors, architecture test, `docker-compose.yml` (PostgreSQL + Seq), test harness (WebApplicationFactory + Testcontainers) | S0-1 (skeleton files only) | S0-6 infra part | **done** 2026-10-12, merged to `main` (PR #1): `2026-10-12-s0-2-api-platform.md` (also creates `data_protection_keys`) |
| S0-2b Minimal APIs | Replace MVC controllers with Minimal APIs: `AddValidation()`, one JSON option set, `IEndpointMapper` hook, `TestEndpoints`, endpoint architecture rule (owner, 2026-10-12) | S0-2 | — | **done** 2026-10-12, branch `s0-2b-minimal-apis` (uncommitted until the owner pushes); 134 tests; one implementer + code review + 2 fix rounds. Also: `JsonProblemWriter` (JSON problem for any Accept), `WithEnumGuard()`, enums reject numbers |
| S0-3 Customer identity + jobs + email | `customer*` tables, code flow, JWT + refresh rotation, `/me`, rate limits, Hangfire with roles and job tracing, SES sender + `login-code` template, `IdentityHousekeeping` | S0-2b | S0-4, S0-5 | **done** 2026-10-13, branch `s0-3-customer-identity` (uncommitted until the owner pushes): `2026-10-13-s0-3-customer-identity.md` (16 decisions confirmed by the owner). Subagent-driven: 5 tasks, each one reviewed, plus a whole-branch review and one fix wave |
| S0-4 Admin back end | Entra SSO, cookie (🔴 first: encrypt the Data Protection key ring at rest — KMS/Secrets Manager XML encryptor — or `REVOKE SELECT ON data_protection_keys FROM es_readonly`; S0-2 stores keys in plain XML), CSRF, RBAC, audit filter, staff / roles / audit / permissions endpoints, Hangfire dashboard auth, `xmin` 409 | S0-2 | S0-3, S0-5 | **built** 2026-10-13 on branch `s0-4-admin-backend` (uncommitted until the owner pushes): `2026-10-13-s0-4-admin-backend.md` (17 decisions; key ring → SSM). Subagent-driven: 5 tasks, each reviewed, plus a whole-branch review; local walk 14/14 PASS; Api 278, Engines 18, Infra 32 tests |
| S0-5 Admin UI shell | React 19 + Vite app, layout, Staff / Roles / Audit screens, generated API types | S0-4 contract (OpenAPI) | S0-3 | after S0-4's contract is fixed |
| S0-6 Delivery | Dockerfile, ECR, `EsEdge-<env>` (Route 53, ACM, SES domain), `EsApp-<env>` (ALB, WAF, ECS api/jobs, log groups, saved queries, alarms), `EsCi` (GitHub OIDC roles), GitHub workflows, secret scan; staging deploy and the §11 walk | S0-1; the app parts need S0-2…S0-5 | S0-2…S0-5 for the infra code | after S0-1 |

Rules for every S0 plan (from the workspace rules):

- Code goes to `../CMS`. Implementers are Opus `implementer` subagents; the main session reviews the real diff and gives a verdict per piece.
- **Nobody commits or pushes.** Each task ends with "hand-off": the owner commits. Work happens on a branch per plan (`s0-1-network-database`, …).
- 🔴 `extraspace-tech/cms` is public: no secret, connection string, account id or customer data in any file. Do not push until the repo is private (open item 5), or confirm with the owner.
- AWS changes in the client account `110611798568` run only from the main session, only after the owner's OK, and never touch the client's existing Lambdas and buckets. Production data rules from `.claude/CLAUDE.md` §6 apply.

## Carry-overs from S0-2 (final review, 2026-10-12)

- **S0-3:**
  - (S0-2b) Create the groups in `Program.cs` step 14 as `app.MapGroup("/api/v1").WithEnumGuard()…` (and `/admin/api` in S0-4); `Program.cs` maps groups only, never handlers (the architecture rule cannot see the top-level `Program`). Feature routes in `Features/<X>/<X>Endpoints.cs`. Tell the Flutter team: `errors` is present only for field validation.
  - Job runs need their own Activity: `ActivitySetup` listens only to `Microsoft.AspNetCore`, so the Hangfire server filter starts `new Activity("job").Start()` (or adds its source to the listener) and calls `Correlation.Begin(...)`. Otherwise job lines have no `traceId`.
  - ~~A 429 that needs `Retry-After` is written with `ProblemWriter`~~ Superseded by S0-3 decision 10: `AppException.RetryAfter`, written by `AppExceptionHandler` through `RateLimitSetup.RetryAfterSeconds`.
  - Per-IP rate-limit partitions need a fallback key: `RemoteIpAddress` is null under TestServer.
  - Owed test: an outdated app gets 426, not 401, on a signed-in route.
  - Name ids `familyId` and `codeId`, never `refreshTokenId` or `loginCodeId`: those names are masked.
- **S0-4:**
  - (S0-2b) The audit endpoint filter is its own top-level class (not a lambda or nested type in a class that maps routes), or `EndpointDataAccess` flags its DbContext use. Permissions = `.RequireAuthorization("<perm>")`.
  - 🔴 Encrypt the Data Protection key ring, or revoke `es_readonly`'s read on it, before cookies ship.
  - A fallback auth policy needs `.AllowAnonymous()` on `MapOpenApi()`.
  - The cookie challenge on `/admin/api/*` must return 401, not a redirect.
  - Add `staffId` with `RequestLog.Add`.
  - Add a test that `Access-Control-Allow-Credentials` stays absent.
- **S0-5:**
  - A CSP header for `/admin` in `SecurityHeadersMiddleware`, and static files in slot 7.
  - An OpenAPI document transformer that adds a ProblemDetails / `code` / `traceId` error schema.
  - Since S0-2b every error is a JSON problem, also for `Accept: text/html`; the SPA fallback must serve `/admin/*` navigations before they can 404.
  - Decide `NumberHandling`: the web JSON defaults document every int as `["integer","string"]`, so generated TS types read `number | string`. Option: `JsonNumberHandling.Strict` on the one JSON option set (`ConfigureHttpJsonOptions`), which changes how request bodies are read.
- **S0-6:**
  - Set `App__Version`, `ASPNETCORE_ENVIRONMENT`, non-empty `App__MinVersion__*` values and `Cors__AllowedOrigins__0`.
  - Lock the task security groups to the ALB: forwarded headers are trusted from any caller.
  - The ALB target check is `/health/live`.
  - Error alarms filter on `exception` being present: the 5xx summary line is also at Error.
  - Never alarm on Warning volume: an unreadable `X-App-Version` header logs a Warning on every request.
  - Watch ECS task-stopped events for startup crashes: they come before Serilog starts.
  - Staging serves `/swagger` and `/openapi/v1.json` publicly (decision 9). Confirm with the owner.
  - The slow-query interceptor ignores failed commands (`CommandFailed`).
## Carry-overs from S0-3 (reviews, 2026-10-13)

- **S0-4:**
  - The key-ring item (🔴 above) now also protects the login-code email jobs. `hangfire.job` holds the address and code encrypted with Data Protection, so anyone who can read `data_protection_keys` can read a job payload while it is still valid (10 minutes).
  - Adding the admin cookie scheme removes the automatic default scheme. That is fine for `/api/v1`, because the `Customer` policy names its scheme. The OpenAPI Bearer transformer matches only `Policy == "Customer"`.
  - Every `WithWebHostBuilder` test host sets `App:Role=Api`, so it does not start a second Hangfire server. Hangfire's `GlobalJobFilters` and `JobStorage.Current` are static and shared by every host in the process. A host that leaves the Testing environment also sets `Email:Transport=Ses` and `Email:From`.
  - Request DTOs must be `public`: the .NET 10 validation generator skips `internal` types.
  - Every `[AutomaticRetry]` sets `LogEvents = false`. Every writer of a refresh-token family takes the `refresh-family:<id>` advisory lock first.
- **S0-5:** declare the problem responses (400/401/429) on the `/api/v1/auth/*` routes, or add a group-level convention, so that generated clients get the error types. Today the OpenAPI document lists only 202/200/204.
- **S0-6:**
  - Inject `CustomerAuth:SigningKey` (`es/<env>/…`) and `Email:From` into **both** the `api` and `jobs` services. Both roles validate them at start-up.
  - Use a container image that has tzdata/ICU. `RecurringJobs` resolves `Asia/Singapore` in a static initializer, so a chiseled image without tzdata stops the jobs role at start-up.
  - The ALB keeps `routing.http.xff_header_processing.mode=append`, and the tasks accept traffic only from the ALB. The per-IP limits use the last X-Forwarded-For hop. Pin the XFF mode with a CDK assertion. IPv6 clients are limited per /128.
  - First deploy to an empty `data_protection_keys`: start one task first, or create the key ring once, then scale. Otherwise the `api` tasks and the `jobs` task may each create their own first key, and email jobs fail until the key ring reloads.
  - Walk check: the first `Email` job line in role `jobs` has `correlationId` equal to the request's `traceId`. The tests cover only role `All`.
  - A WAF rate rule for `/api/v1/auth/*`. `/auth/refresh` and `/auth/logout` have no per-IP limit in the app; the token's 256 bits make guessing pointless, so this guards only against floods.
  - The SES identity must be verified before the first deploy. Each SES error logs Error lines, and after 5 attempts `Job Email failed permanently`; the alarm watches that line.
- **Flutter (contract notes):**
  - `POST /auth/code` → 202 with no body, whether or not the email is known.
  - `/auth/code/verify` → 200 `TokenResponse`, or 400 `INVALID_CODE` / `TOO_MANY_ATTEMPTS` / `VALIDATION_FAILED`, or 429.
  - A 429 always has `Retry-After` in seconds. On the per-IP limit it can be the whole hour.
  - Send refresh calls one at a time: a parallel double refresh signs the session out.
  - Logout always returns 204.
  - An access token stays valid for up to 15 minutes after logout.
- **S1:**
  - Add `customerId` to the summary line when binding fails. Today the endpoint filter sets it only once the handler stage is reached. Test it with the first signed-in POST.
  - Outbox for the login-code email (a queuing failure after commit gives a 500 today).
  - Per-IP limits in Valkey, if the per-task count proves too loose.
  - Optionally, move the per-email limit from a fixed window to a rolling one.
  - Make `default(Money)` safe and use the invariant culture in `Money.ToString` once Money reaches EF or a DTO.
  - Use `.HasConversion<string>()` for every enum property.
## Carry-overs from S0-4 (reviews and walk, 2026-10-13)

- **S0-5 (admin UI):**
  - On 401, navigate the whole page to `/admin/api/auth/login` (not a fetch). After sign-in, `GET /admin/api/auth/csrf` and send `X-CSRF-TOKEN` on every write; on 400 `CSRF_FAILED`, fetch a new token and retry once.
  - Send `version` on every PATCH and `?version=` on DELETE; on 409 `CONFLICT`, reload the record. A staff member's own sign-in bumps their `version`.
  - Hide Owner-only actions for non-Owners (granting/changing the Owner role); the server refuses them (403).
  - URL-encode audit `from`/`to` (a raw `+08:00` arrives as a space); both need an offset or `Z`.
  - Local dev: cookies are `es-admin` / `es-csrf` in Development, and `POST /admin/api/auth/dev-login {email}` signs in from loopback (no Entra needed).
  - `/admin/jobs` without a cookie answers 401 JSON; show the menu link only with `jobs.manage`. A future CSP on `/admin` must still allow the Hangfire dashboard's inline scripts on `/admin/jobs`.
  - The Entra callback answers a refused person with a 403 JSON problem; S0-5 may turn it into a page.
  - The SPA fallback `/admin/{*path}` must not catch `/admin/api/*` or `/admin/jobs/*`; until S0-5 ships, `/admin` is 404 after sign-in. `GET /auth/login` shows as a 200 in the OpenAPI document (it is a redirect; the UI navigates to it, never fetches it).
- **S0-6 (delivery):**
  - Env vars on `api` and `jobs`: `DataProtection__SsmPath=/es/<env>/data-protection/`, `Admin__Entra__TenantId`, `Admin__Entra__ClientId`, `Admin__Entra__ClientSecret` (secret `es/<env>/entra-client-secret`), `Admin__BootstrapEmails__0` (remove once the first Owner has signed in). Production refuses to start without SsmPath (every role) and without Entra (roles `api`/`all` only: keep the Entra secret off the `jobs` task). 🔴 Add a CDK assertion that `ASPNETCORE_ENVIRONMENT` is `Staging` or `Production`: with `Development` or `Testing` the key ring would sit in the database and dev-login would be mapped.
  - Task role: `ssm:GetParametersByPath` + `ssm:PutParameter` on `parameter/es/<env>/data-protection*`. The default `aws/ssm` key should need no explicit KMS grant; verify on the first staging deploy, together with the container credentials (the SSM client looks up credentials when it is built).
  - The empty-key-ring race on the first deploy (S0-3 carry-over) now happens in SSM.
  - Client IT registers the Entra app: single tenant, web platform, redirect `https://<host>/admin/api/auth/callback`, a client secret (calendar its expiry), ID token claims `oid`, `preferred_username`, `name`.
  - Staging walk: a real Entra sign-in; an unknown company user → 403; one email job after the key ring moved to SSM; the dashboard behind `jobs.manage`.
  - Migration script `docs/migrations/2026-10-13-admin-tables.sql` runs after `2026-10-13-customer-identity.sql`.
- **Owner questions:** whether Entra B2B guests may sign in, or only company-domain emails (review of Task 3, finding 7). The admin cookie slides with no absolute cap, and logout does not revoke a copied cookie (deactivation does): accepted design, revisit if security asks.

# S0 Foundation — design spec

- **Date:** 2026-10-09
- **Status:** APPROVED by the owner 2026-10-12 (including the 2026-10-10 additions: logging §4.4, cost-v4 sizing, bastion, DB users, subdomain delegation). Implementation plans: `docs/superpowers/plans/2026-10-12-s0-plan-index.md`
- **Sub-project:** S0 of 5 (S0 Foundation → S1 Self-storage → S2 BizPlus booking + credits → S3 Cowork → S4 Extras)
- **Repo:** `../CMS` (`extraspace-tech/cms`)
- **Owner:** the user (the only backend developer); the Flutter app is built by the same team

## 1. Context

ExtraSpace Asia (self-storage, Singapore) gets a **brand-new C# / ASP.NET Core monolith**, written from scratch. It is a functional copy of the PM's demo (`../Backend Demo/backend`): the same features and screens, with our own code. The demo and the old Codigo system are read-only references. We never change them, call them, or copy data from them. Lucy/Iviva is retired, and the Flutter app moves fully onto our API. Self-storage runs on SiteLink CCWs 3.5. The whole BizPlus line (Cowork, facility booking, credits) is built in-house. The first release covers Singapore and Malaysia on one platform (PM, 2026-10-09): currency, time zone and tax live per site, so S0 adds no country logic, and S1 adds the per-country pieces (Stripe account, tax, SiteLink sites).

All program-level decisions and their reasons are in `.claude/rules/cross-repo.md` §4 (decision log). This spec covers only S0.

## 2. Goal of S0

Build the base that every later sub-project stands on, so that S1–S4 only add features:

1. A running monolith on AWS staging, deployed by CI, with production one approval away.
2. Customer sign-in for the Flutter app: email + one-time code, then access and refresh tokens.
3. Staff sign-in for the admin through Microsoft Entra ID, with roles, permissions and an audit log.
4. The admin UI shell (React), with staff, roles and audit screens.
5. The shared platform pieces: error format, validation, logging, jobs, email, money and time helpers, OpenAPI, tests.

### Out of S0 (added by the sub-project that first needs it)

- SiteLink client and the linking of SiteLink tenants at sign-in (S1)
- Stripe (S1)
- S3 file storage (S2)
- the ElastiCache decision (S1)
- any business feature
- push notifications (not in the demo)
- the Flutter app changes (Flutter track)

## 3. Solution layout

```
CMS/
  src/ExtraSpace.Api/              the one deployable
    Platform/                      auth, errors, validation, logging, clock, money, jobs, email
    Features/
      Identity/                    customer sign-in, tokens, /me
      Admin/                       staff, roles, permissions, audit, admin sign-in
      (S1+: Storage/ Payments/ Leads/ Bookings/ Credits/ Cowork/ Content/)
    Integrations/
      Email/                       AWS SES v2
      (S1+: SiteLink/ Stripe/ Files/)
    wwwroot/admin/                 built admin UI (generated, not committed)
  src/ExtraSpace.Engines/          pure business maths: no database, no HTTP (Money lives here)
  admin-ui/                        React + Vite + TypeScript source
  infra/ExtraSpace.Infra/          AWS CDK app (C#)
  tests/ExtraSpace.Engines.Tests/  pure unit tests
  tests/ExtraSpace.Api.Tests/      HTTP + real PostgreSQL (Testcontainers)
  tests/ExtraSpace.Infra.Tests/    CDK assertion tests (added in plan S0-1)
  docker-compose.yml               local PostgreSQL
```

House rules for the layout:

- **One feature = one folder.** It holds the feature's endpoints, services, EF entity configuration and jobs.
- **A feature never touches another feature's tables.** It calls that feature's service. Example: Bookings asks the Credits wallet service to spend credits.
- **Each feature has a public face: `Features/<Feature>/Contracts/`** (its service interfaces and the DTOs they take and return). Another feature may use only that folder. Entities, EF configurations, endpoint classes and service classes stay inside the feature.
- **An architecture test enforces this** (`tests/ExtraSpace.Api.Tests/Architecture/`; built in S0-2 on a recursive Mono.Cecil walk, because NetArchTest missed dependencies inside async lambdas). It fails the build when:
  - code in feature X uses any type of feature Y outside `Y.Contracts` (this also catches `db.Set<YEntity>()`, because it needs Y's entity type)
  - `Platform/` or `Integrations/` depends on `Features/`
  - an endpoint class (name ends with `Endpoints`, or it maps routes) uses the `DbContext` or EF Core (endpoints call a service)
  - `ExtraSpace.Engines` references EF Core, ASP.NET Core or `System.Net.Http`
- **Endpoints are Minimal APIs** (owner, 2026-10-12, S0-2b; replaces MVC controllers). Each feature has `Features/<Feature>/<Feature>Endpoints.cs`: a static class with `Map<Feature>Endpoints(this RouteGroupBuilder group)`. Handlers stay thin, call a service and return `TypedResults`. `Program.cs` creates the route groups once: `/api/v1` (customer JWT) and `/admin/api` (admin cookie, CSRF, audit filter); admin endpoints live in `Features/<Feature>/Admin/`.
- **One `DbContext`.** Each feature registers only its own entity configurations (`IEntityTypeConfiguration<T>` classes in its folder).
- **No repository layer.** Services use the `DbContext` directly.

## 4. Platform

### 4.1 Error format

- Real HTTP status codes; never "200 with an error inside".
- Every error body is RFC 9457 `ProblemDetails` (`application/problem+json`) with two extra fields: `code` (a stable string the app can switch on) and `traceId`.

```json
{ "type": "about:blank", "title": "The code is wrong or has expired", "status": 400,
  "code": "INVALID_CODE", "traceId": "4bf92f3577b34da6a3ce929d0e0e4736" }
```

- Validation errors: status 400, `code = "VALIDATION_FAILED"`, plus `errors: { "<field>": ["message"] }`. These come from .NET 10 Minimal API validation (`AddValidation()`, DataAnnotations), which writes through `IProblemDetailsService`; `ProblemDetailsSetup.Customize` sets the code. A body that is not valid JSON is a `BadHttpRequestException` (`ThrowOnBadRequest = true` in every environment) and also becomes 400 `VALIDATION_FAILED`, without `errors` (clients must treat `errors` as optional). Every error body is this JSON problem whatever the request's `Accept` header.
- Business errors are thrown as one `AppException(status, code, title)` and mapped by one exception handler (`IExceptionHandler`). Unknown exceptions become 500 `INTERNAL_ERROR` without internal details; the details go to the log.
- Statuses without their own code: a bare 400 → `VALIDATION_FAILED`, 401/403/404/409/426/429/5xx → the codes below, anything else → `HTTP_<status>` (S0-2 decision 7). An EF concurrency failure and a PostgreSQL unique violation become `409 CONFLICT`.
- S0 codes: `VALIDATION_FAILED`, `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `RATE_LIMITED`, `APP_UPDATE_REQUIRED`, `INVALID_CODE`, `TOO_MANY_ATTEMPTS`, `INTERNAL_ERROR`. Each later feature adds its own codes in its own spec.

### 4.2 Request pipeline

In order:

1. Forwarded headers (behind the ALB)
2. Trace id: read the W3C `traceparent` if present, set `X-Trace-Id` on the response, push `traceId`, `correlationId`, `albTraceId`, client headers into the log context
3. Serilog request logging (one summary line per request, §4.4)
4. Exception handler
5. Security headers
6. HTTPS redirection, off behind the ALB (TLS ends at the ALB)
7. Static files for `/admin`
8. Routing
9. CORS (allowed origins come from config: only the Flutter web origin; the admin is same-origin)
10. Rate limiter
11. App version check (before sign-in, so an outdated app gets 426, not a 401 refresh loop)
12. Authentication
13. Authorization
14. Feature endpoints (route groups `/api/v1`, `/admin/api`)
15. SPA fallback `/admin/{*path}` → `wwwroot/admin/index.html`

### 4.3 App version check

The Flutter app sends `X-App-Platform: ios|android|web` and `X-App-Version: <semver>`. Config `App:MinVersion:{Platform}` sets the lowest allowed version. If the header is present and below the minimum, the API answers `426` with `code = "APP_UPDATE_REQUIRED"`. Requests without the headers (admin UI, health checks, tools) pass.

### 4.4 Logging and tracing (owner, 2026-10-10: structured and easy to trace)

**Goal:** from one id that a user, the app or the admin UI shows, find every log line of that request, of the jobs it started and of the outside calls it made, in one query.

**Ids that tie lines together**

| Field | What it is | Where it comes from |
|---|---|---|
| `traceId` | W3C trace id of the current request or job run | ASP.NET Core `Activity` (built in). Returned on **every** response as header `X-Trace-Id` and in every error body (§4.1). |
| `correlationId` | The `traceId` of the request that started a chain. A request's own `traceId` = its `correlationId`. | Carried into every Hangfire job it enqueues (§7) and into the outbox rows of S1, so a job run 10 minutes later still points back to the original request. |
| `albTraceId` | The ALB's `X-Amzn-Trace-Id` | Request header, logged so ALB and WAF records can be matched. |
| `jobId`, `jobName` | Hangfire job | Job filter (§7). |

The Flutter app and the admin UI show `traceId` on every error (admin: in the error toast with a copy button; app: on the error screen and in any support report).

**Line format.** Serilog writes one JSON object per line to stdout (Serilog.Expressions template, plain field names because CloudWatch Logs Insights reserves names starting with `@`: `timestamp` UTC, `level`, `messageTemplate`, `message`, `exception`, `traceId`, `spanId`, plus properties; S0-2 decision 2). ECS ships it to CloudWatch Logs. Every line carries:

- always: `traceId`, `spanId`, `correlationId`, `app` (`ExtraSpace`), `env`, `role` (`api` / `jobs` / `all`), `version` (git SHA), `SourceContext`, `feature` (from the namespace, for example `Identity`)
- in a request: `method`, `route` (the route template, not the raw path), `albTraceId`, `clientPlatform`, `clientVersion`, and after sign-in `customerId` or `staffId` (ids only)
- when known: `siteId`, `country`
- in a job: `jobId`, `jobName`, `attempt`

**What gets logged**

- **One summary line per request** (Serilog request logging): method, route, status, `elapsedMs`. Level: Information below 500, except 403 and 429 at Warning (possible abuse); Error for 5xx. `/health/*` is not logged unless it fails.
- **Business events** at Information with a fixed message template and named properties, for example `"Login code sent to customer {customerId}"`, `"Refresh token family {familyId} revoked: reuse detected"`. **All log property names are lowerCamel**, placeholders included (S0-2 decision 3); the ECS task id is in the CloudWatch log stream name, not a property. One line per meaningful state change, not per method call.
- **Every outside call** (SES in S0; SiteLink and Stripe from S1) logs one line: `integration`, `operation` (for SiteLink the WSDL operation name), `elapsedMs`, `outcome` (`ok` / `error` / `timeout` / `circuit-open`), `httpStatus`, `attempt`. Request and response bodies are never logged in production. Whether staging may log redacted SOAP bodies is decided in S1.
- **Slow database commands:** an EF Core `DbCommandInterceptor` logs a Warning for any command over 500 ms (`Logging:SlowQueryMs`), with the command text and `elapsedMs`, never parameter values.
- **Exceptions:** logged once, by the exception handler (§4.1), with the full stack, at Error. Code below it does not log-and-rethrow.
- **Jobs:** start, success (`elapsedMs`) and failure (Error, with `attempt`); a job that exhausts its retries logs `"Job {jobName} failed permanently"` (lowerCamel, as built in S0-3), which an alarm watches.

**Levels in production:** Default Information; `Microsoft.AspNetCore` and `Microsoft.EntityFrameworkCore` Warning; `System.Net.Http` Warning; Debug off. Levels can be changed per namespace through config (`Serilog:MinimumLevel:Override:*`) with a task restart; no code change.

**Code rules**

- Use `ILogger<T>` with message templates and named placeholders; never string interpolation in a log call (analyzer CA2254 set to error).
- Hot or repeated log lines use the `[LoggerMessage]` source generator.
- Never log an entity, a DTO or a request object whole. Log ids.
- 🔴 Never log: tokens, login codes, cookies, `Authorization` headers, passwords, Stripe secrets, connection strings, full request or response bodies, card data. Personal data: ids only; an email address only through `Pii.MaskEmail` (`j***@gmail.com`), and only where a support case needs it (the login flow).
- A Serilog destructuring policy masks any property named like `*token*`, `*secret*`, `*password*`, `loginCode`, `authorization` or `cookie`, as a second line of defence. The login code's wire name stays `code` (§6.1), so the masker does not cover it: its safety rests on never logging request bodies, plus the S0-3 test `A_full_sign_in_flow_logs_no_code_token_or_raw_email`.

**Local development:** console output in a readable text format, and the same JSON sent to a local **Seq** container (`docker-compose.yml`, `http://localhost:5341`, free for one developer) to search by `traceId` or any property. Seq is never used outside Development.

**CloudWatch (§9.2):** log group per environment and role (`/extraspace/<env>/api`, `/extraspace/<env>/jobs`); retention production 90 days, staging 14 days. Saved CloudWatch Logs Insights queries, created by CDK:

1. **Trace**: every line where `traceId` or `correlationId` = X, in time order (request → jobs → outside calls).
2. **Errors** in the last hour, grouped by `route` / `jobName` and exception type.
3. **Slow requests** over 1 s, and slow DB commands.
4. **Outside-call failures** by `integration` and `operation`.
5. **Activity of one customer or staff member** by `customerId` / `staffId`.

Metric filters on Error lines, failed-permanently jobs and outside-call failures feed the alarms in §9.2.

**Not in S0:** OpenTelemetry tracing to AWS X-Ray (a timeline per request across DB and outside calls). The ids above already join every line; add X-Ray later only if log queries prove too slow for a problem. It would add a collector sidecar per task (about US$9 a task a month) plus X-Ray fees.

### 4.5 Health and API docs

- `GET /health/live`: the process is up.
- `GET /health/ready`: the database is reachable.
- The OpenAPI document is at `/openapi/v1.json` (built-in `Microsoft.AspNetCore.OpenApi`), **outside production only** (S0-2 decision 9; S0-5 generates types from a local or CI app).
- An interactive API page (Swagger UI at `/swagger`, pointed at `/openapi/v1.json`) is served **outside production only**.

### 4.6 Money and time (`ExtraSpace.Engines`)

- `Money` is `decimal` with currency. Rounding: half away from zero to 2 places, applied only at the points a feature spec names (for example each line total).
- No `double` or `float` for money anywhere.
- Conversion to Stripe integer cents happens only in the Stripe integration (S1).
- The clock is .NET `TimeProvider`, injected everywhere. `DateTime.Now` and `DateTime.UtcNow` are banned in code, except inside `TimeProvider` registration.
- Business dates use the **site's time zone** (S1 adds `site.time_zone`, an IANA name, default `Asia/Singapore`; Malaysian sites use `Asia/Kuala_Lumpur`). Both are UTC+8 with no daylight saving, but code never assumes that: it converts through the site's zone. Storage is UTC.

## 5. Data

| Topic | Rule |
|---|---|
| Engine | PostgreSQL on RDS, the newest major version RDS supports at implementation time |
| Schema | EF Core code-first migrations in `ExtraSpace.Api` |
| Naming | `snake_case` tables and columns via `EFCore.NamingConventions` |
| Ids | UUID v7 (`Guid.CreateVersion7()`), PostgreSQL `uuid`. Human-readable numbers (invoice, booking) are separate columns, defined by the feature specs |
| Money columns | `numeric(12,2)` |
| Instants | `timestamptz`, C# `DateTime` with Kind `Utc` |
| Business dates / times | `date` / `time`, C# `DateOnly` / `TimeOnly` |
| Status values | `text`, EF string conversion of C# enums |
| Audit stamps | `created_at`, `updated_at` on every table, set by one `SaveChanges` interceptor; `created_by_staff_id` / `updated_by_staff_id` on admin-edited tables |
| Delete | hard delete by default; `archived_at` only where a feature spec asks for history |
| Concurrency | admin edits: optimistic check on PostgreSQL `xmin` (conflict → 409 `CONFLICT`); money and booking writes: row locks (`SELECT … FOR UPDATE`) inside one transaction |
| Shared environments | `dotnet ef migrations script --idempotent` → `docs/migrations/<date>-<name>.sql` in the context repo → run by hand **before** the deploy; every migration stays compatible with the previous app version |
| Seed | reference data in migrations; dev fixtures from a `seed` command; never real customer data (the repo is public) |

### 5.1 S0 tables

| Table | Columns (besides `id`, `created_at`, `updated_at`) | Notes |
|---|---|---|
| `customer` | `email` (unique; stored trimmed and lower-case), `first_name`, `last_name`, `phone` | S1 adds the SiteLink tenant links in its own table |
| `customer_login_code` | `email` (unique), `code_hash`, `expires_at`, `attempts`, `consumed_at`, `request_ip`, `last_sent_at`, `window_started_at`, `sent_in_window` | one row per email; a new request overwrites the code fields. The last three columns (S0-3) make the per-email limits exact |
| `customer_refresh_token` | `customer_id`, `family_id`, `token_hash` (unique), `expires_at`, `replaced_by_id`, `revoked_at`, `user_agent`, `ip` | rotation and theft detection (§6.1) |
| `staff_user` | `email` (unique, lower-case), `display_name`, `entra_object_id` (unique, set at first sign-in), `role_id`, `active`, `last_sign_in_at`, `created_by_staff_id`, `updated_by_staff_id` | staff must exist before they can sign in |
| `role` | `name` (unique), `permissions text[]`, `is_system` | system roles cannot be deleted |
| `audit_log` | `staff_user_id`, `action`, `entity_type`, `entity_id`, `changes jsonb`, `ip`, `occurred_at` | append-only; no update or delete endpoint |
| `data_protection_keys` | (EF Core Data Protection table) | cookie keys shared by all instances; created by S0-2's first migration `InitialPlatform`. 🔴 Stored as plain XML: S0-4 must encrypt the key ring or revoke `es_readonly`'s read before cookies ship |
| schema `hangfire` | (Hangfire tables) | created by Hangfire |

## 6. Identity

### 6.1 Customer sign-in (mobile)

| Step | Endpoint | Behaviour |
|---|---|---|
| Ask for a code | `POST /api/v1/auth/code` `{ email }` | Always `202`, whether or not the email is known (no account probing). Creates a 6-digit code, stores only its hash, valid **10 minutes**. A new request replaces any active code. Limits: one request per email per **60 s** and **5 per hour**; **20 per IP per hour**. Over a limit → `429 RATE_LIMITED`. The email is sent by a Hangfire job queued after commit. |
| Check the code | `POST /api/v1/auth/code/verify` `{ email, code }` | A wrong code adds an attempt; at **5 attempts** the code is dead (`TOO_MANY_ATTEMPTS`). Per IP, at most **30 checks per hour**, so nobody can guess codes across many emails (`429 RATE_LIMITED`). Expired, consumed or unknown → `400 INVALID_CODE` (one message for all, so no hints). On success: mark the code consumed, create the `customer` if new, and return tokens. S1 adds "link SiteLink tenants by this verified email" at this point. |
| Refresh | `POST /api/v1/auth/refresh` `{ refreshToken }` | Valid token → new access token + **new** refresh token; the old one is marked replaced. A replaced or revoked token presented again → **revoke the whole family** (theft detection) → `401`. |
| Sign out | `POST /api/v1/auth/logout` `{ refreshToken }` | Revokes that token's family. Always `204`. |
| Who am I | `GET /api/v1/me` | Needs an access token. Returns `id`, `email`, `firstName`, `lastName`, `phone`. |

- **Access token:** JWT, HS256, 15 minutes. Claims: `sub` (customer id), `email`, `iss`, `aud`. The signing key comes from Secrets Manager.
- **Refresh token:** 32 random bytes (base64url), stored as a SHA-256 hash. It lasts 60 days from issue, and each refresh starts a new 60 days.
- Customer routes use the `Customer` auth scheme (JWT bearer). Public routes (S1 browsing) are `[AllowAnonymous]` and rate-limited per IP. There is **no app API key**, because a key inside an app binary can be extracted.

**As built in S0-3** (plan `docs/superpowers/plans/2026-10-13-s0-3-customer-identity.md`, its 16 decisions confirmed by the owner on 2026-10-13):

- The `/api/v1` group requires the `Customer` policy. `/auth/*` opts out with `.AllowAnonymous()`. Logout is anonymous too: the refresh token in the body is the credential, and an app whose access token has expired must still be able to sign out.
- Email addresses are trimmed and lower-cased before any use. The request check is strict: no display name, no whitespace, a dot in the domain.
- Each code request and each check takes a per-email PostgreSQL advisory lock (`login-code:<email>`), so a double tap runs one call after the other. The per-email limits are exact. "5 per hour" is a fixed window that starts at the first send in the window.
- A per-email 429 carries `Retry-After`: the longer of the 60 s gap and the time left in the hourly window. The per-IP limits (20 code requests, 30 checks per hour) use the in-memory rate limiter. They are counted per API task, and their `Retry-After` is the whole window.
- Wrong attempts 1-4 → `400 INVALID_CODE`. The 5th wrong attempt, and every check after it, → `400 TOO_MANY_ATTEMPTS`. The attempt is committed before the error is returned.
- Code hash: HMAC-SHA256 of `email:code`, keyed with an HKDF sub-key (`login-code`) of `CustomerAuth:SigningKey`. Refresh-token hash: SHA-256, hex.
- The email job is queued after the commit. If queuing fails, the request returns 500 and the code row stays saved. The customer can ask again after 60 s. S1's outbox can remove this gap.
- Token response: `{ accessToken, accessTokenExpiresAt, refreshToken, refreshTokenExpiresAt }`, with times in UTC (`Z`). `accessTokenExpiresAt` equals the JWT `exp`.
- JWT validation: HS256 only, issuer `extraspace`, audience `extraspace-app`, 30 s clock skew, `MapInboundClaims = false`. `CustomerAuth:SigningKey` must be base64 of at least 32 bytes. It is checked at start-up in **every** role, so the `jobs` service needs the secret too.
- Refresh and logout take a per-family advisory lock (`refresh-family:<id>`) before any row lock. A revoke therefore also catches a token that a parallel refresh is inserting. Two parallel refreshes with the same token count as reuse, and both are signed out.
- `/me` for a customer id that no longer exists → `401 UNAUTHENTICATED`.

### 6.2 Staff sign-in (admin)

- Microsoft Entra ID through OpenID Connect with `Microsoft.Identity.Web`, single-tenant: the client's directory only.
- Flow:
  1. The SPA calls `GET /admin/api/me`. A `401` sends the browser to `GET /admin/api/auth/login`.
  2. The server redirects to Entra.
  3. On return, the server finds the `staff_user` by Entra object id, or on first sign-in by email, then records the object id.
  4. It sets the cookie and redirects to `/admin`.
- **The staff member must exist and be `active`**, or they get `403` (a normal M365 user cannot just walk in).
- **Bootstrap:** config `Admin:BootstrapEmails` lists the first staff emails. At first sign-in such a user is created with the system role `Owner`. Once one Owner exists, remove the setting.
- **Cookie:**
  - name `__Host-es-admin`
  - `HttpOnly`, `Secure`, `SameSite=Lax`
  - 8-hour lifetime, sliding
  - Data Protection keys in PostgreSQL
- **Anti-forgery:** the SPA reads a token from `GET /admin/api/auth/csrf` and sends it as the `X-CSRF-TOKEN` header on every write; the server validates it on all admin `POST/PUT/PATCH/DELETE`.
- `POST /admin/api/auth/logout` clears the cookie.

### 6.3 Permissions and audit

- Permissions are string constants in code, owned by each feature (S0: `staff.manage`, `roles.manage`, `audit.read`, `jobs.manage`).
- Roles hold a list of permissions. `Owner` (system role) always has every permission.
- Checked per endpoint: `.RequireAuthorization("staff.manage")`. One policy is generated per permission constant.
- `GET /admin/api/me` returns the staff member and their effective permissions; the UI hides what they lack. The server still checks every call.
- **Audit:** one endpoint filter (`IEndpointFilter` on the `/admin/api` group) writes an `audit_log` row for every successful admin `POST/PUT/PATCH/DELETE`: who, action, entity type and id, and the changed fields (before → after, secrets excluded).
- S0 admin endpoints:
  - `GET/POST/PATCH /admin/api/staff` (`staff.manage`): add a staff member by email, change role, deactivate. Nobody can deactivate themselves or remove the last Owner.
  - `GET/POST/PATCH/DELETE /admin/api/roles` (`roles.manage`): system roles cannot be deleted.
  - `GET /admin/api/audit` (`audit.read`): filter by staff, entity and date; paged.
  - `GET /admin/api/permissions`: the catalogue, for the role editor.

## 7. Background jobs and email

- **Job tracing:** a Hangfire client filter stores the current `correlationId` as a job parameter when a job is enqueued; a server filter starts a new `Activity` for the run and pushes `correlationId`, `jobId`, `jobName` and `attempt` into the log context (§4.4).
- **Hangfire** with `Hangfire.PostgreSql` (schema `hangfire`). Hangfire guarantees one run per job. **Roles (owner, 2026-10-10, cost v4):** the same image runs as `App:Role=api` (no Hangfire server, only enqueues) or `App:Role=jobs` (Hangfire server, no public traffic). Production runs 1 jobs task; staging and local run one process with both roles (`App:Role=all`, the default).
- Recurring jobs are **registered in code at start-up**. Each has an on/off switch `Jobs:<JobName>:Enabled` (default true) and can also be paused in the dashboard.
- The dashboard is at `/admin/jobs`, behind admin SSO + `jobs.manage`.
- Every job must be idempotent; its feature spec names the column or key that proves it.
- S0 job: `IdentityHousekeeping` (daily) deletes expired login codes and refresh tokens older than 30 days past expiry.
- **Email:** AWS SES v2. `IEmailSender` queues a Hangfire job after the DB commit; the job renders an HTML template from `Integrations/Email/Templates/` and sends it. Failures retry. S0 template: `login-code`. The sender address comes from config.

## 8. Admin UI shell

| Need | Choice |
|---|---|
| Base | React 19, Vite, TypeScript (strict), React Router |
| Look | Tailwind CSS + shadcn/ui + lucide icons, matching the demo's screens |
| Server data | TanStack Query |
| Lists | TanStack Table |
| Forms | React Hook Form + Zod (server validation stays the authority) |
| Charts | Recharts (from S1) |
| API types | generated from `/openapi/v1.json` with `openapi-typescript` + `openapi-fetch`; CI fails if the committed types are out of date |

- **No generic CRUD engine.** The demo let one generic endpoint read and write any table, which bypasses feature rules. We build explicit admin endpoints per feature, plus shared components (`<PageShell>`, `<DataTable>`, `<RecordForm>`, `<ConfirmDialog>`) configured per page.
- **No business maths in the browser.** The UI shows server-computed numbers; previews call the server.
- S0 screens:
  - layout (sidebar, header with the signed-in staff member, sign out)
  - an empty dashboard
  - Staff (list, add, edit role, deactivate)
  - Roles (list, edit permissions)
  - Audit log (filter, page)
  - a "Jobs" link to `/admin/jobs`
- Menus and buttons are hidden by permission.
- Build: `npm run build` outputs to `src/ExtraSpace.Api/wwwroot/admin/` (git-ignored; the Docker build produces it).
- Dev: the Vite dev server forwards `/admin/api` and `/admin/jobs` to the local API.

## 9. AWS, CI/CD and environments

### 9.1 Environments

| Env | Where | External systems |
|---|---|---|
| local | `docker compose up` (PostgreSQL), `dotnet run`, `npm run dev` | SES off (codes printed to the log in Development only) |
| staging | AWS, the client's account `110611798568` (shared with production; decided 2026-10-12) | SES sandbox or verified sender; later SiteLink sandbox and Stripe test mode |
| production | AWS, same account | live |

### 9.2 AWS (CDK stacks in `infra/`, one deploy per environment)

- VPC across 2 availability zones; the ALB in public subnets; ECS tasks and RDS in private subnets.
- NAT gateways with Elastic IPs, so outbound calls come from fixed IPs (in case SiteLink or a vendor allowlists IPs; to confirm in S1). Production: 2, one per zone, so an allowlist needs both IPs. Staging: 1.
- Sizing follows the AWS cost estimate v4 (owner, 2026-10-10; `docs/notes/aws-cost/aws-cost-estimate-v4.html`):
  - ECS Fargate ARM. Production: `api` service 2 × 2 vCPU / 4 GB across 2 zones, auto-scaling to 4 on CPU and request count; `jobs` service 1 × 1 vCPU / 2 GB. Staging: 1 × 1 vCPU / 2 GB running both roles.
  - RDS PostgreSQL. Production: `db.m8g.large` Multi-AZ, 50 GB gp3 with storage auto-scaling, 35-day automated backups, point-in-time restore, deletion protection, Database Insights advanced mode, behind **RDS Proxy**. Staging: `db.t4g.medium` single-AZ, no proxy. Check in S0 that Npgsql + EF Core + Hangfire through RDS Proxy do not pin every connection (session state, prepared statements); if they do, connect directly and drop the proxy. Not verified yet.
  - ElastiCache Valkey (production 2 × `cache.t4g.small` with failover, staging 1 × `cache.t4g.micro`) is budgeted; S1 decides what it caches (SiteLink unit and price data, rate limits). S0 does not create it.
  - AWS WAF on the ALB: AWS managed core, known-bad-inputs, IP-reputation and SQL-injection rule groups, plus a rate-based rule.
- ALB with an HTTPS listener (ACM certificate). The host name is OPEN; proposal: client IT delegates one subdomain (example `app.extraspaceasia.com`) to a Route 53 hosted zone in the account (staging uses names inside the same zone), so CDK writes the certificate, ALB and SES DKIM records itself (the client's DNS is at ixiz.sg, checked 2026-10-10).
- **Ops access (approved 2026-10-12):** one small EC2 bastion per environment in a private subnet, SSM Session Manager only (no SSH key, no inbound port), used to tunnel `psql` to RDS for the hand-run migrations (§5) and read-only debugging. Stopped when not in use; a few dollars a month (price not checked).
- **Database users (approved 2026-10-12):** the master user `postgres` (password generated by CDK into Secrets Manager `es/<env>/db-master`) runs migrations only; the app connects as `es_app` (DML on `public`, owner of schema `hangfire`); `es_readonly` for debugging and the staging `postgres-dev` MCP. Created once per environment by hand; steps in `docs/notes/infra/aws-setup-guide.md` B5 / D8.
- ECR, Secrets Manager (app secrets passed into the task as environment variables), SES domain identity, CloudWatch log groups (per environment and role, retention §4.4), the saved Logs Insights queries of §4.4, metric filters, Container Insights and alarms (5xx rate, failed jobs, unhealthy tasks, jobs task down, DB CPU and connections).

### 9.3 CI/CD (GitHub Actions)

1. **Every PR:**
   - `dotnet build` (warnings as errors for nullable issues)
   - all tests, including Testcontainers
   - `npm ci && npm run build` in `admin-ui/`
   - generated API types up to date
   - `cdk synth` / `cdk diff`
2. **Merge to `main`:**
   - one multi-stage Docker image (Node builds the admin UI, then `dotnet publish`, then the ASP.NET runtime image)
   - pushed to ECR with the commit SHA as the tag
   - **deployed to staging automatically**
3. **Production:** a GitHub environment with required approval deploys **the same image tag**. A schema change is applied by hand first (§5).
4. GitHub reaches AWS through **OIDC roles**; no AWS keys are stored in GitHub. CI never receives app secrets.

🔴 The repo is public today, so CI logs are public too. No step may print config or environment.

## 10. Testing

- `ExtraSpace.Engines.Tests`: pure unit tests, xUnit v3 + AwesomeAssertions (changed 2026-10-12: FluentAssertions 8+ needs a commercial licence). Spec acceptance tables we keep become `[Theory]` data.
- `ExtraSpace.Api.Tests`: `WebApplicationFactory` + PostgreSQL in Docker (Testcontainers). Real migrations run against it. External HTTP is faked: SES in S0; SiteLink and Stripe from S1, with recorded responses.
- S0 must-have tests:
  - the code flow: happy path, wrong code ×5, expired, rate limits, no account probing
  - refresh rotation and reuse → family revoked
  - the app-version 426
  - the error shapes
  - permission checks (no permission → 403)
  - an audit row on admin writes
  - the last Owner cannot be removed
  - the `xmin` conflict → 409
  - the architecture test (§3)
  - logging: an error response carries the same `traceId` as its log lines and the `X-Trace-Id` header; a job enqueued by a request logs that request's `correlationId`; a full sign-in flow with captured log output contains no login code, token or unmasked email
- Admin UI: type-check + build in CI. Playwright smoke tests start in S1.
- Before S0 is called done, the `dev-walker` agent walks the staging flows in §11.

## 11. Definition of done for S0

1. CI is green: build with 0 errors, all tests pass, admin UI builds, API types are current.
2. Staging deploys automatically from `main`. Production has a working, approval-gated deploy job; the production stack itself may wait until the AWS account question closes.
3. On staging, a real email address receives a code, signs in, refreshes, and signs out. Replaying an old refresh token cancels the session family.
4. On staging, a bootstrap staff member signs in with Entra and adds a second staff member with a limited role. That person cannot see or call `staff.manage` actions. A company user who was not added gets 403.
5. Every admin change in step 4 appears in the audit log.
6. The Hangfire dashboard opens only for staff with `jobs.manage`. `IdentityHousekeeping` runs once per day with 2 tasks running.
7. No secret is in the repo or in CI logs (checked with a secret scan in CI).
8. On staging, the `traceId` shown on a forced error finds, with the saved **Trace** query, the request line, the exception and the lines of the email job it started.

## 12. Open items (owner or client IT)

| # | Item | Needed by |
|---|---|---|
| 1 | ~~AWS account~~ DECIDED 2026-10-12: one client-owned account for both environments | — |
| 2 | Entra ID app registration by the client's IT; confirm the client is on Microsoft 365 (inferred from MX records) | admin sign-in on staging |
| 3 | SES: sender address, and SPF + DKIM for the domain by the client's IT (SPF today allows only Outlook, Mandrill and SendGrid) | customer codes on staging |
| 4 | Host name(s), for example `app.<domain>` with `/api` and `/admin` on one host | staging HTTPS |
| 5 | Make `extraspace-tech/cms` private (recommended; org admin) | before the first commit |
| 6 | API freeze policy after the first store release: additive-only in `/api/v1`, breaking changes to `/api/v2` (recommended) | before the first store release |
| 7 | **In-app account deletion.** App Store rules require it for apps that create accounts. Design it in S1, once customer data spans features | before the first store release |
| 8 | Swap the `mysql-dev` MCP for a read-only `postgres-dev` pointed at staging | once staging exists |

## 13. Notes for later sub-projects

- **S1 outside-call rules (owner, 2026-10-09):**
  - Every outside call (SiteLink, Stripe, SES) has a timeout, a limited retry with backoff for safe reads only, and a circuit breaker, so a slow SiteLink cannot hold the request threads of the whole app. HTTP clients use `Microsoft.Extensions.Http.Resilience`; the SiteLink SOAP client gets the same limits on its binding.
  - Every side effect after a payment (for example: Stripe paid → record the payment in SiteLink with `PaymentSimpleCashWithSource`, issue credits, send the receipt) runs as an idempotent job, and the record that triggers it is saved in the same transaction as the payment. How: an outbox row in our own table that a Hangfire job picks up, or Hangfire enlisted in that transaction; S1 picks one after checking what `Hangfire.PostgreSql` supports (not verified yet). A failure retries; it is never lost, and a repeat changes nothing. The S1 spec names the idempotency key per step and what staff see when the retries run out.
- S1 adds: SiteLink tenant linking inside "check the code" (only for the verified email, matched case-insensitively), `site.time_zone` and currency per site, the SiteLink cache decision (in-memory vs ElastiCache), Stripe, S3 if needed.
- Every later spec lists which demo spec rules it keeps and which it changes, and checks the demo for new commits first (`docs/notes/demo-backend/sync-log.md`).
- Every later spec also reads the client's artifact notes (`docs/notes/client-artifacts/`). Where they disagree with the demo, it lists the conflict for the PM instead of choosing.
- S0 is not affected by the artifacts: the ES App prototype has no real sign-in, so our email + one-time code decision stands.

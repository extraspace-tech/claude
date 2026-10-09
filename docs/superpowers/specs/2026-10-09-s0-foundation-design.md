# S0 Foundation — design spec

- **Date:** 2026-10-09
- **Status:** design approved section by section in the brainstorm of 2026-10-09; this written spec is waiting for owner review
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
  docker-compose.yml               local PostgreSQL
```

House rules for the layout:

- **One feature = one folder.** It holds the feature's controllers, services, EF entity configuration and jobs.
- **A feature never touches another feature's tables.** It calls that feature's service. Example: Bookings asks the Credits wallet service to spend credits.
- **Each feature has a public face: `Features/<Feature>/Contracts/`** (its service interfaces and the DTOs they take and return). Another feature may use only that folder. Entities, EF configurations, controllers and service classes stay inside the feature.
- **An architecture test enforces this** (`tests/ExtraSpace.Api.Tests/Architecture/`; library picked in the plan, ArchUnitNET or NetArchTest). It fails the build when:
  - code in feature X uses any type of feature Y outside `Y.Contracts` (this also catches `db.Set<YEntity>()`, because it needs Y's entity type)
  - `Platform/` or `Integrations/` depends on `Features/`
  - a controller injects the `DbContext` (controllers call a service)
  - `ExtraSpace.Engines` references EF Core, ASP.NET Core or `System.Net.Http`
- **Endpoints are MVC `[ApiController]` controllers.** Controllers stay thin and call a service. Mobile controllers route under `api/v1/...`; admin controllers live in `Features/<Feature>/Admin/` and route under `admin/api/...`.
- **One `DbContext`.** Each feature registers only its own entity configurations (`IEntityTypeConfiguration<T>` classes in its folder).
- **No repository layer.** Services use the `DbContext` directly.

## 4. Platform

### 4.1 Error format

- Real HTTP status codes; never "200 with an error inside".
- Every error body is RFC 9457 `ProblemDetails` (`application/problem+json`) with two extra fields: `code` (a stable string the app can switch on) and `traceId`.

```json
{ "type": "about:blank", "title": "The code is wrong or has expired", "status": 400,
  "code": "INVALID_CODE", "traceId": "00-4bf9...-01" }
```

- Validation errors: status 400, `code = "VALIDATION_FAILED"`, plus `errors: { "<field>": ["message"] }`. These come from `[ApiController]` model validation, mapped to our shape by one `InvalidModelStateResponseFactory`.
- Business errors are thrown as one `AppException(status, code, title)` and mapped by one exception handler (`IExceptionHandler`). Unknown exceptions become 500 `INTERNAL_ERROR` without internal details; the details go to the log.
- S0 codes: `VALIDATION_FAILED`, `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `RATE_LIMITED`, `APP_UPDATE_REQUIRED`, `INVALID_CODE`, `TOO_MANY_ATTEMPTS`, `INTERNAL_ERROR`. Each later feature adds its own codes in its own spec.

### 4.2 Request pipeline

In order:

1. Forwarded headers (behind the ALB)
2. Request id / trace id
3. Serilog request logging
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
14. Controllers
15. SPA fallback `/admin/{*path}` → `wwwroot/admin/index.html`

### 4.3 App version check

The Flutter app sends `X-App-Platform: ios|android|web` and `X-App-Version: <semver>`. Config `App:MinVersion:{Platform}` sets the lowest allowed version. If the header is present and below the minimum, the API answers `426` with `code = "APP_UPDATE_REQUIRED"`. Requests without the headers (admin UI, health checks, tools) pass.

### 4.4 Logging

- Serilog writes JSON to stdout; ECS ships it to CloudWatch Logs.
- Every line carries the trace id.
- Never log tokens, codes, cookies, `Authorization` headers, full request or response bodies, or personal data beyond ids.

### 4.5 Health and API docs

- `GET /health/live`: the process is up.
- `GET /health/ready`: the database is reachable.
- The OpenAPI document is at `/openapi/v1.json` (built-in `Microsoft.AspNetCore.OpenApi`).
- An interactive API page (Swagger UI pointed at `/openapi/v1.json`) is served **outside production only**.

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
| `customer_login_code` | `email`, `code_hash`, `expires_at`, `attempts`, `consumed_at`, `request_ip` | one active code per email; a new request replaces the old one |
| `customer_refresh_token` | `customer_id`, `family_id`, `token_hash` (unique), `expires_at`, `replaced_by_id`, `revoked_at`, `user_agent`, `ip` | rotation and theft detection (§6.1) |
| `staff_user` | `email` (unique, lower-case), `display_name`, `entra_object_id` (unique, set at first sign-in), `role_id`, `active`, `last_sign_in_at`, `created_by_staff_id`, `updated_by_staff_id` | staff must exist before they can sign in |
| `role` | `name` (unique), `permissions text[]`, `is_system` | system roles cannot be deleted |
| `audit_log` | `staff_user_id`, `action`, `entity_type`, `entity_id`, `changes jsonb`, `ip`, `occurred_at` | append-only; no update or delete endpoint |
| `data_protection_keys` | (EF Core Data Protection table) | cookie keys shared by all instances |
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
- Checked per action: `[Authorize(Policy = "staff.manage")]`. One policy is generated per permission constant.
- `GET /admin/api/me` returns the staff member and their effective permissions; the UI hides what they lack. The server still checks every call.
- **Audit:** one MVC action filter writes an `audit_log` row for every successful admin `POST/PUT/PATCH/DELETE`: who, action, entity type and id, and the changed fields (before → after, secrets excluded).
- S0 admin endpoints:
  - `GET/POST/PATCH /admin/api/staff` (`staff.manage`): add a staff member by email, change role, deactivate. Nobody can deactivate themselves or remove the last Owner.
  - `GET/POST/PATCH/DELETE /admin/api/roles` (`roles.manage`): system roles cannot be deleted.
  - `GET /admin/api/audit` (`audit.read`): filter by staff, entity and date; paged.
  - `GET /admin/api/permissions`: the catalogue, for the role editor.

## 7. Background jobs and email

- **Hangfire** with `Hangfire.PostgreSql` (schema `hangfire`). Every app instance runs the Hangfire server; Hangfire guarantees one run per job.
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
| staging | AWS (account OPEN) | SES sandbox or verified sender; later SiteLink sandbox and Stripe test mode |
| production | AWS (separate account recommended) | live |

### 9.2 AWS (CDK stacks in `infra/`, one deploy per environment)

- VPC across 2 availability zones; the ALB in public subnets; ECS tasks and RDS in private subnets.
- NAT gateway with an Elastic IP, so outbound calls come from a fixed IP (in case SiteLink or a vendor allowlists IPs; to confirm in S1).
- ECS Fargate service: staging 1 task; production 2 tasks across 2 zones, auto-scaling on CPU and request count.
- RDS PostgreSQL: staging single-AZ, small; production Multi-AZ, 14-day automated backups, point-in-time restore, deletion protection.
- ALB with an HTTPS listener (ACM certificate). The host name is OPEN.
- ECR, Secrets Manager (app secrets passed into the task as environment variables), SES domain identity, CloudWatch log groups and alarms (5xx rate, failed jobs, unhealthy tasks).

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

- `ExtraSpace.Engines.Tests`: pure unit tests, xUnit + FluentAssertions. Spec acceptance tables we keep become `[Theory]` data.
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

## 12. Open items (owner or client IT)

| # | Item | Needed by |
|---|---|---|
| 1 | AWS account(s): which, and who owns them (separate staging and production recommended) | infra work in S0 |
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

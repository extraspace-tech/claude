# `../CMS` — the new C# monolith

Always loaded. Applies to every file under `../CMS/`. Rewritten 2026-10-09 after the owner decided on a brand-new system (`.claude/rules/cross-repo.md` §4). The S0 design spec (`docs/superpowers/specs/2026-10-09-s0-foundation-design.md`) fixes the layout and conventions below; fill in the remaining **TBD** at phase 1, and keep this file as the house-rules sheet for the repo.

## Facts

- Remote `extraspace-tech/cms`, branch `main`. 🔴 PUBLIC repository: no secrets, no connection strings, no real customer data, not even in a test fixture. The whole monolith lives here (owner, 2026-10-09): mobile API, admin API, React admin UI, jobs. `../API` is not used. Making this repo private is recommended and OPEN (org admin).
- Architecture: **one monolith** (owner, 2026-10-09): mobile API, admin back office and background jobs in one deployable, hosted on AWS.
- Written **from scratch**. The demo (`../Backend Demo/backend`) and the old Codigo system are read-only references, never integrated (`.claude/rules/backend-demo.md`, `.claude/rules/old-backend.md`).
- Database: **PostgreSQL on AWS RDS, our own schema**, EF Core migrations owned by this repo.
- Stack (recommended, confirm in the design spec): .NET 10 (installed locally: `dotnet 10.0.400`), EF Core + Npgsql (+ EFCore.NamingConventions snake_case), Minimal APIs (owner, 2026-10-12; MVC controllers until S0-2b), Hangfire on PostgreSQL, Stripe.net, AWS SES v2, Serilog, .NET `TimeProvider`, xUnit v3 + AwesomeAssertions (not FluentAssertions 8+, commercial licence) + Testcontainers. No Redis in S0; ElastiCache Valkey is budgeted (cost v4) and S1 decides what it caches; no NodaTime. One image, three roles: `App:Role=api|jobs|all` (S0 spec §7). Admin UI: React + Vite + TypeScript (owner, 2026-10-09), built to static files in the API's `wwwroot` and served same-origin; Node is needed only on dev machines and CI, never in production. Layout (S0 spec §3): `src/ExtraSpace.Api` (`Platform/`, `Features/<Feature>/` with `Admin/` sub-folder, `Integrations/`), `src/ExtraSpace.Engines` (pure maths), `admin-ui/`, `infra/ExtraSpace.Infra` (CDK), `tests/ExtraSpace.Engines.Tests`, `tests/ExtraSpace.Api.Tests`, `tests/ExtraSpace.Infra.Tests` (CDK assertions). UI libs: React 19, Tailwind + shadcn/ui, TanStack Query/Table, React Hook Form + Zod, Recharts, `openapi-typescript` + `openapi-fetch`. Paths: OpenAPI `/openapi/v1.json` (Swagger UI outside production), health `/health/live` + `/health/ready`, Hangfire `/admin/jobs`. Local port: API `http://localhost:5080`, PostgreSQL `localhost:5433`, Seq `http://localhost:5341`.

## House rules (design defaults; only the owner changes them)

1. Money is exact: `numeric` in PostgreSQL, `decimal` in C#. Never `double` or `float` for money. One rounding helper; the rule is set in the design spec.
2. Business dates use the site's time zone (`site.time_zone`, default `Asia/Singapore`; MY sites `Asia/Kuala_Lumpur`); storage is UTC. Never `DateTime.Now`.
3. Never handle card data. Stripe only via hosted Checkout + one signature-verified webhook. A new payment flow needs explicit business approval.
4. Never call a SiteLink card-carrying operation; record payments with `PaymentSimpleCashWithSource`. SiteLink request field names exactly as in the WSDL (`docs/notes/sitelink/`).
5. Every BizPlus credit change goes through the wallet service (single writer).
6. Mobile routes live under `/api/v1/*`. They change freely until the first store release of our app. After that, changes are additive only (freeze policy OPEN, `.claude/rules/cross-repo.md` §4).
7. Every endpoint that reads or changes a customer's data checks ownership. Never trust a client-reported amount; the server prices everything.
8. Configuration values come from the environment or a secret store, never from a committed file.
9. Write tests with the code (xUnit). Where a spec feature doc has an acceptance table we keep, port it as `[Theory]` data.
10. A feature uses another feature only through its `Features/<Feature>/Contracts/` folder (service interfaces + DTOs), never its entities or tables. The architecture test in `tests/ExtraSpace.Api.Tests/Architecture/` enforces it; never weaken that test to make a build pass.
11. Outside calls (SiteLink, Stripe, SES) have a timeout, a circuit breaker and retries for safe reads only. Side effects after a payment run as idempotent jobs whose trigger is saved in the payment's own transaction (outbox row or enlisted Hangfire job; S1 decides).

## Conventions to decide in the design spec (write the answer here)

- Error envelope: ProblemDetails + `code` + `traceId`, real status codes; validation 400 `VALIDATION_FAILED` + `errors` (S0 spec §4.1).
- Delete: hard by default; `archived_at` only where a feature spec asks (S0 spec §5).
- Audit stamps: `created_at` / `updated_at` (UTC) by one `SaveChanges` interceptor; `created_by_staff_id` / `updated_by_staff_id` on admin-edited tables; admin writes also go to `audit_log` via one action filter.
- Logging (S0 spec §4.4): Serilog compact JSON to stdout; every line has `traceId` + `correlationId` (carried into Hangfire jobs), `role`, `version`; `X-Trace-Id` on every response; one summary line per request, one line per outside call, slow-query Warning > 500 ms; `ILogger<T>` message templates only (CA2254 = error); ids not entities; emails only via `Pii.MaskEmail`; never tokens, codes, cookies, secrets or bodies. Local: Seq at `http://localhost:5341`. CloudWatch saved query **Trace** finds a whole chain by id.
- Plain `DbContext` in services, no repository layer (decided).
- Jobs: Hangfire on PostgreSQL (schema `hangfire`), registered in code at start-up, `Jobs:<Name>:Enabled` switch, idempotent (decided).

## Built so far (S0-1, merged to `main` 2026-10-12)

- Root: `ExtraSpace.slnx`, `global.json` (SDK 10.0.400, `"test": {"runner": "Microsoft.Testing.Platform"}` — required for xunit.v3 on the .NET 10 SDK), `Directory.Build.props` (net10.0, nullable as errors), `Directory.Packages.props` (central versions), `.editorconfig` (CA2254 = error, LF).
- Tests: `dotnet test tests/ExtraSpace.Infra.Tests`. Filter with the Microsoft Testing Platform form: `dotnet test tests/ExtraSpace.Infra.Tests -- --filter-class "*DataStackTests"`, not the VSTest `--filter "FullyQualifiedName~…"` form. Serial tests: `[assembly: Xunit.v3.Parallelization(Mode = Xunit.Sdk.ParallelMode.None)]` (`CollectionBehavior.DisableTestParallelization` is a compile error in xunit.v3 4.x).
- CDK (`infra/ExtraSpace.Infra`): `EnvConfig` (sizes per environment) → `InfraComposer.Compose(app, account)` → stacks `EsNetwork-<env>`, `EsData-<env>`. The availability zones are fixed and overridden on the stack, so there are no context lookups and no `cdk.context.json`; keep it that way, the test `Compose_needs_no_context_lookup` guards it.
- CDK CLI: `~/.local/share/node-v24.18.0/bin/cdk` (put it on PATH). Always `--profile extraspace` (the account comes from it). Never `--all`; always name the stacks. `cdk synth` offline: unset `AWS_PROFILE` and set `AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null CDK_DEFAULT_ACCOUNT=123456789012`.

## Built so far (S0-2, merged to `main` via PR #1, 2026-10-12)

- `src/ExtraSpace.Api/Platform/`: `Data` (AppDbContext, TimestampsInterceptor, SlowQueryInterceptor, migrations), `Errors` (AppException, ErrorCodes, AppExceptionHandler, ProblemDetailsSetup, ProblemWriter), `Health`, `Hosting` (AppOptions, PlatformServices), `Http` (AppVersion, security headers, rate-limit 429), `Logging` (LoggingSetup, Pii, RequestLog, enrichers, request summary), `Tracing` (RequestTrace, Correlation, ActivitySetup). Pipeline order = spec §4.2, in `Program.cs`.
- Endpoints (S0-2b, Minimal APIs; guide `docs/notes/cms/minimal-apis-vs-mvc.md`): `Features/<X>/<X>Endpoints.cs`, a static class with `Map<X>Endpoints(this RouteGroupBuilder group)`, called from `Program.cs` step 14 on the `/api/v1` or `/admin/api` group. Routes start with a slash (`MapGroup("/api/v1")`, `MapGet("/me")`): the logged `route` is the template text. Handlers take services as parameters, call a service (never the `DbContext`; the architecture rule `EndpointDataAccess` checks every `*Endpoints` class and every class that maps routes) and return `TypedResults`. Validation = DataAnnotations + `AddValidation()`; errors keys are camelCased in `ProblemDetailsSetup.Customize`; messages use the C# name unless `[Display(Name=…)]`. Bad JSON bodies throw (`ThrowOnBadRequest = true`) → 400 `VALIDATION_FAILED`.
- Feature code registers from `Program.cs` or its own folder, never from `PlatformServices`; it reads its tables with `db.Set<T>()` (no feature `DbSet` on `AppDbContext`).
- Errors: throw `AppException(status, code, title)`; never `return BadRequest(obj)` (the body must stay a problem). Middleware writes errors with `ProblemWriter.WriteAsync`.
- Logging: `RequestLog.Add(HttpContext, "customerId", id)` (void) puts a property on every later line of the request and its summary line. `Correlation.Begin(id)` for job runs (S0-3). Never name an id property with `token`, `secret`, `password`, `logincode`, `authorization`, `cookie` or `connectionstring` in it (it is masked to `***`): use `familyId`, `codeId`. Only `{@object}` values are inspected by the masker; never log objects with `{obj}` / `{$obj}`. EF's own failure events are logged at Debug; our exception handler logs every 5xx once.
- Enum wire values are PascalCase names (`"Active"`), the same text EF stores; store enums with `.HasConversion<string>()` per property (no global convention).
- JSON settings live in ONE option set, `ConfigureHttpJsonOptions` (responses and the OpenAPI document both read it; since S0-2b). Never add `AddControllers`. An OpenAPI schema transformer gives enum schemas `type: string` and drops `null` from the shared enum component (nullable uses wrap it in `oneOf`); `ApiDocsTests` guards every enum in the document.
- `ExecuteUpdate`/`ExecuteDelete` skip `TimestampsInterceptor`: set `updated_at` yourself.
- Every error body is the JSON problem whatever the `Accept` header (`JsonProblemWriter`, S0-2b; the framework writer refused non-JSON Accept values and skipped `Customize`). Its default `type`/`title` come from `_ = TypedResults.Problem(problem)` (undocumented framework behaviour, guarded by the 404 `Accept: text/html` test).
- `errors` is present for field validation only. Binding failures (bad JSON, `"count":"abc"`, `?page=abc`, empty body) are 400 `VALIDATION_FAILED` without `errors`.
- Enums: JSON rejects numbers (`allowIntegerValues: false`); route/query enums need `.WithEnumGuard()` on the group (`Platform/Http/EnumArgumentsFilter.cs`; it does not cover `[Flags]` combinations, `[FromQuery(Name=…)]` key names or `[AsParameters]`).
- Request DTOs never use `[JsonPropertyName]`: validation error keys are the camelCased C# names, so a renamed JSON field would get the wrong key.
- After `dotnet ef migrations add`, strip the BOM EF writes (all three files) so diffs stay clean (`.editorconfig` charset utf-8).
- Architecture test (`tests/ExtraSpace.Api.Tests/Architecture/`) uses a recursive Mono.Cecil walk (NetArchTest missed async lambdas); its known blind spots are listed in `ArchitectureRules.cs`.
- Tests: `dotnet test tests/ExtraSpace.Api.Tests` needs Docker (OrbStack); one PostgreSQL 18.6 Testcontainer per run (`ApiFactory`, xUnit assembly fixture); test-only endpoints live in `TestSupport/TestEndpoints.cs` under `/test/*` (added through `IEndpointMapper`; the test host also calls `AddValidation()` because the validation generator only sees types in its own project).

## Built so far (S0-3, branch `s0-3-customer-identity`, 2026-10-13)

- **`Platform/Jobs`** (Hangfire on PostgreSQL, schema `hangfire`):
  - Enqueue with `IBackgroundJobClient`. Every role can enqueue; only roles `Jobs` and `All` run the server and register recurring jobs.
  - A recurring job is a class that implements `IRecurringJob`, declared with `services.AddRecurringJob<TJob>(name, cron)`. It runs in time zone `Asia/Singapore` and has a `Jobs:<name>:Enabled` switch.
  - Job classes can be `internal sealed`. Only the method must be public.
  - `JobTracingFilter` gives every run its own Activity and the log properties `jobId`, `jobName` (the class name without its `Job` suffix; "unknown" when Hangfire cannot load the type), `attempt` and `correlationId` (the traceId of the request that enqueued the job). It logs `Job {jobName} started / succeeded / failed / failed permanently`.
  - **Every `[AutomaticRetry]` sets `LogEvents = false`.** Our filter already logs each attempt.
- **`Integrations/Email`:**
  - `IEmailSender.Enqueue(new EmailMessage(template, to, values, validFor))`. Call it **after** the DB commit. It renders the template at once, so a missing value fails the request.
  - The address and the values are encrypted with a time-limited Data Protection protector. The job argument `expiresAt` is in clear: an expired email logs a Warning and is not retried, while an unreadable payload fails and raises the alarm.
  - `EmailJob`: 5 attempts with delays 10/20/40/80/160 s. At-least-once delivery.
  - Transports (`Email:Transport`):
    - `Ses` (default; needs `Email:From`; no SDK retries, 10 s timeout; an SES error is rethrown with only its code and status, because sandbox messages name the recipient);
    - `Log` (Development only; prints the whole email, code included);
    - `None` (Testing only; the test host supplies `FakeEmailTransport`).
  - Templates are embedded under `Integrations/Email/Templates/`. Today there is one: `login-code` (`code`, `minutes`).
- **`Features/Identity`:**
  - Tables `customer`, `customer_login_code` (one row per email) and `customer_refresh_token`.
  - Services: `LoginCodeService` (per-email advisory lock `login-code:<email>`), `TokenService` (per-family advisory lock `refresh-family:<id>`; every writer of a family takes it first), `AccessTokens` and `CustomerService`.
  - Recurring job `IdentityHousekeeping`: daily at 03:00 SGT.
  - All types are internal **except request DTOs, which must be `public`**, because the .NET 10 validation generator skips internal types.
- **The `/api/v1` group** (`Program.cs` step 14): `app.MapGroup("/api/v1").RequireCustomer().WithEnumGuard()`.
  - `RequireCustomer()` = `RequireAuthorization("Customer")`, plus an endpoint filter that adds `customerId` to the request log.
  - Public routes opt out with `.AllowAnonymous()`: the whole `/auth` sub-group, logout included.
  - JWT scheme `Customer`: HS256 only, `MapInboundClaims = false`, 30 s skew. `CustomerAuth:SigningKey` must be base64 of at least 32 bytes. It is checked at start-up in every role.
  - `AppException { RetryAfter = … }` → the `Retry-After` header, through `RateLimitSetup.RetryAfterSeconds`.
  - Per-IP policies `auth-code` (20 per hour) and `auth-verify` (30 per hour) are in memory, counted per task.
- **Tests:**
  - `api.ClientWithIp()` gives each test its own X-Forwarded-For address, so one test's per-IP limits never hit another.
  - `AuthFlow` (`RequestCodeAsync`, `VerifyAsync`, `api.SignInAsync(client, email)`).
  - `api.Emails` (`FakeEmailTransport`: `SentTo`, `WaitForAsync`, `CodeForAsync`).
  - `LogCapture.All()` / `WaitForAsync`.
  - `IdentityTestData` (test-only signing key, `NewEmail`, `CreateCustomerAsync`, `AccessTokenFor`, `ForgedToken`).
  - 🔴 Every `WithWebHostBuilder` host sets `App:Role=Api`: Hangfire's filters and storage are static and shared by every host in the process.
  - Log checks match a unique property. `Pii.MaskEmail` maps every `x-…@example.test` address to the same value.

## Running locally

From `../CMS`:

```bash
docker compose up -d     # PostgreSQL 18.6 on 127.0.0.1:5433 (no password, loopback only), Seq on http://localhost:5341
dotnet user-secrets set "ConnectionStrings:Default" "Host=localhost;Port=5433;Database=extraspace;Username=postgres" --project src/ExtraSpace.Api
dotnet user-secrets set "CustomerAuth:SigningKey" "$(openssl rand -base64 48)" --project src/ExtraSpace.Api   # S0-3: the app refuses to start without it
dotnet tool restore
dotnet ef database update --project src/ExtraSpace.Api --connection "Host=localhost;Port=5433;Database=extraspace;Username=postgres"   # migrate BEFORE the first run
dotnet run --project src/ExtraSpace.Api      # http://localhost:5080
```

Development sends email through the `Log` transport: the sign-in code is printed in the console (`Development email`). Health `/health/live`, `/health/ready`; OpenAPI `/openapi/v1.json`; Swagger UI `/swagger` (both outside production). In Seq, find a request with `@TraceId = '<id>'` (Seq keeps the trace id as its built-in field, not as `traceId`). Shared environments: migration scripts go to `docs/migrations/` via `dotnet ef migrations script --idempotent`; strip the BOM before running them with `psql`. Kill the app after testing (port 5080 is in `.claude/dev-ports`).

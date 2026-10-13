# CMS: what is built so far

Moved here from `.claude/rules/cms.md` on 2026-10-13 so it no longer loads on every call. It holds the conventions and helpers each S0 piece added. Read it before you design, build, review or walk CMS code; every implementer and reviewer brief names it. Add each new piece's section here, not to `cms.md`.

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
  - Tables `customer`, `login_code` (S0-4b: one row per purpose + email; was `customer_login_code`) and `customer_refresh_token`.
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

## Built so far (S0-4, branch `s0-4-admin-backend`, 2026-10-13)

- **Key ring:** outside Development/Testing it lives in SSM Parameter Store (`DataProtection:SsmPath`, `/es/<env>/data-protection/`, SecureString, `Amazon.AspNetCore.DataProtection.SSM`); the app refuses to start without the path. Development/Testing keep the `data_protection_keys` table. A test host in any other environment calls `.UseTestKeyRing()` (fake SSM client on 127.0.0.1:9 + in-memory repository), and a Production test host also `.UseTestEntra()`.
- **Serilog:** `AddSerilog(..., preserveStaticLogger: true)`. Nothing uses the static `Log`; test hosts in one process no longer silence each other.
- **`Features/Admin`:** tables `staff_user`, `role` (system role Owner, fixed id `Role.OwnerId`), `audit_log` (append-only, `occurred_at`, no `created_at`/`updated_at`).
- **The `/admin/api` group** (`Program.cs` step 14): `app.MapGroup("/admin/api").RequireStaff().WithEnumGuard()`.
  - `RequireStaff()` = policy `Staff` (cookie scheme `Staff`) + `AdminRequestFilter`: CSRF check on every POST/PUT/PATCH/DELETE (400 `CSRF_FAILED`), audit context. Anonymous routes (`.AllowAnonymous()`) skip the filter entirely; a non-anonymous route without a staff id fails closed (401).
  - Permissions: a feature registers `services.AddPermissions(new Permission(name, description))` (`Features/Admin/Contracts`) and guards routes with `.RequireAuthorization("<name>")`. One policy per name; Owner holds every name; stored names that left the catalogue are ignored.
  - The cookie holds only the staff id. `StaffAccess` reloads staff + role on every request (deactivation or role change applies at the next request). Read the loaded session with `HttpContext.StaffSession()`. `StaffAccess` also adds `staffId` to the request log, so every line of a staff request has it (403s and `/admin/jobs` included).
  - Cookies: `__Host-es-admin` / `__Host-es-csrf` (Secure always); in **Development** `es-admin` / `es-csrf` with SameAsRequest, so plain http works locally.
  - Sign-in (S0-4b, replaces Entra and dev-login): `POST /admin/api/auth/code {email}` (always 202; mail only to an active staff member or an eligible bootstrap address) and `POST /admin/api/auth/code/verify {email, code}` (204 + cookie). `StaffSignIn` wraps Identity's `ILoginCodes` with `LoginCodePurpose.Staff`. `Admin:AllowedEmailDomains` limits staff addresses. Locally the code is printed in the console.
- **Audit:** mark an entity `IAudited` (needs a `Guid Id`) and, if admin-edited, `IHasStaffStamps`; `[NotAudited]` keeps a property out. `AuditInterceptor` writes one `audit_log` row per changed entity in the same SaveChanges (`changes = { camelName: { from, to } }`, enums as names). 🔴 Admin writes go through tracked entities: `ExecuteUpdate`/`ExecuteDelete` skip the audit.
- **Concurrency:** admin-edited entities have `uint Version` with `.IsRowVersion()` (`xmin`); responses carry `version`; PATCH bodies and `DELETE ?version=` must send it; stale → 409. PostgreSQL unique AND foreign-key violations → 409 `CONFLICT`, logged once at Warning with the constraint name.
- **Owner rules:** every write that can change who is an active Owner takes `pg_advisory_xact_lock(hashtextextended('staff-owners', 0))` and re-checks the actor under it. Only an active Owner grants or changes the Owner role; at least one active Owner always remains.
- **Minimal API gotchas:** a group's `""` route keeps a trailing slash in its template (use `MapGroup("")` + full paths); a handler with only `HttpContext` returning `Task<T>` binds the `RequestDelegate` overload and its result is discarded (cast to `(Delegate)`, ASP0016); EF cannot order after projecting into a positional record (order first).
- **Hangfire dashboard:** `/admin/jobs` via `MapHangfireDashboardWithAuthorizationPolicy("jobs.manage", …)`; 401/403 JSON, POSTs need the antiforgery token (Hangfire reads our `IAntiforgery`). Each successful dashboard write logs `Jobs dashboard action {path} by staff {staffId}`; dashboard actions are not audited. The framework's own OpenIdConnect log category is set to `Fatal` (our redacted Warning records sign-in failures).
- **Tests:** `api.AdminClient()` (https base address: `__Host-` cookies are Secure), `SignedInAdminAsync`, `StaffClientAsync(perms)`, `client.AddCsrfAsync()`, test route `POST /test/admin/sign-in/{staffId}`. 🔴 Only `[Collection("Owners")]` tests create or change Owners, and they call `ClearOwnersAsync()` first.

## Built so far (S0-4b, branch `s0-4b-staff-email-code`, 2026-10-13)

- **One code engine with a purpose:** `Features/Identity/Contracts/ILoginCodes` (`SendAsync`, `VerifyAsync<T>(…, onVerified, …)`) and `LoginCodePurpose { Customer, Staff }`. Another feature that needs emailed codes injects `ILoginCodes`; it never reads `login_code`.
- `VerifyAsync` opens the transaction: a wrong code is counted and committed before the error; on a match the code is consumed and `onVerified` runs in the same transaction (join `db.Database.CurrentTransaction`, never commit it). If `onVerified` throws, the code stays usable.
- The purpose is in the unique key `(purpose, email)`, the advisory lock `login-code:<purpose>:<email>` and the hash input. Send limits are per purpose.
- 🔴 EF scaffolds a **drop + create** for a renamed table: write the rename by hand (`StaffEmailCode` migration) and never `migrations remove` a hand-written one.
- No Entra, no OpenIdConnect package, no dev-login. Production needs no sign-in settings.

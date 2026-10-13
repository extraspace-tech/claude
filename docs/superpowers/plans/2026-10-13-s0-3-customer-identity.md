# S0-3 Customer identity, jobs and email — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this workspace the implementer is the Opus `implementer` agent and the reviewer the Opus `code-reviewer` agent; Task 6 is run by the main session only. Agents never commit (memory `feedback-sdd-without-commits`).

**Goal:** Customers of the Flutter app sign in with email + a 6-digit code, get a 15-minute JWT and a rotated 60-day refresh token, read `GET /api/v1/me` and sign out. Background jobs (Hangfire on PostgreSQL) carry the request's `correlationId`, send the login-code email through SES, and run the daily `IdentityHousekeeping`.

**Architecture:** Three new areas in `src/ExtraSpace.Api`:
- `Platform/Jobs` sets up Hangfire: roles, the tracing filter and recurring-job registration.
- `Integrations/Email` holds `IEmailSender`, which queues an `EmailJob`. The job renders an embedded template and sends it through an `IEmailTransport`: SES, a log transport for Development, or a fake in tests.
- `Features/Identity` holds the customer tables, `LoginCodeService`, `TokenService`, `AccessTokens` and `IdentityEndpoints`. `Program.cs` creates the `/api/v1` route group once: it requires the `Customer` policy, adds `customerId` to the request log and guards enum arguments. The auth routes opt out with `.AllowAnonymous()`.

**Tech Stack:**
- .NET 10 (SDK 10.0.400, runtime 10.0.11), ASP.NET Core Minimal APIs (since S0-2b), EF Core 10 + Npgsql 10.0.3.
- **New:** Hangfire.Core / Hangfire.AspNetCore 1.8.25, Hangfire.PostgreSql 1.21.1, Microsoft.AspNetCore.Authentication.JwtBearer 10.0.11, AWSSDK.SimpleEmailV2 4.0.106.2, AWSSDK.Extensions.NETCore.Setup 4.0.102.2.
- Tests: xUnit v3 + AwesomeAssertions + Testcontainers (PostgreSQL 18.6).

**Spec:** `docs/superpowers/specs/2026-10-09-s0-foundation-design.md`: §4.4 logging (jobs, outside calls, never-log list), §5 / §5.1 data, §6.1 customer sign-in, §7 jobs and email, §9.1 environments, §10 must-have tests. Also read `docs/superpowers/plans/2026-10-12-s0-plan-index.md` ("Carry-overs from S0-2" → S0-3), `.claude/rules/cms.md` and the guide `docs/notes/cms/minimal-apis-vs-mvc.md`.

**Clients affected:**
- **Flutter.** New `/api/v1/auth/code`, `/auth/code/verify`, `/auth/refresh`, `/auth/logout` and `/api/v1/me`, with the token response shape below.
  - The app must send refresh calls one at a time: two parallel refreshes with the same token count as reuse, and the whole session family is signed out (spec §6.1).
  - Treat `errors` as optional on a 400 (S0-2b).
  - Show `traceId` on errors.
- **Admin UI:** none (S0-4).
- **Cron:** `IdentityHousekeeping` (new).
- **Stripe:** none.

## Global Constraints

- **Repo and branch.** Repo `../CMS` (`extraspace-tech/cms`, 🔴 PUBLIC). Work on branch `s0-3-customer-identity`, cut from `main` at `441cc27`. **Never `git commit`, `push`, `stash` or `reset`.** The owner commits.
- **No secrets in the repo.** No secret, signing key, connection string, AWS account id or real email address in any committed file. Test-only keys are allowed in test code and must say "test" in their text. Real keys come from user-secrets (local) or Secrets Manager (AWS).
- **Agent limits.** Subagents never run `dotnet user-secrets`, `docker compose` or any AWS command, and never dispatch subagents.
- **Files.** No new `.md` file inside `../CMS`. LF line endings. Match `.editorconfig` and the surrounding idiom: low comment density, one-line "why" comments, file-scoped namespaces, primary constructors, `internal sealed` unless a test or another layer needs the type.
- **Package versions** live only in `Directory.Packages.props`. ASP.NET Core packages are pinned to **10.0.11**.
- **Namespaces:** `ExtraSpace.Api.Platform.Jobs`, `ExtraSpace.Api.Integrations.Email`, `ExtraSpace.Api.Features.Identity` (`.Contracts` for what other features may use).
- **Banned in `src/`** (RS0030): `DateTime.Now/UtcNow/Today`, `DateTimeOffset.Now/UtcNow`, `Guid.NewGuid`. Use the injected `TimeProvider` and `Guid.CreateVersion7()`.
- **Endpoints are Minimal APIs.** Routes start with a slash. Handlers take services as parameters, call a service (never `AppDbContext`) and return `TypedResults`. Errors are thrown as `AppException(status, code, title)`. Request DTOs are classes with `{ get; init; }` properties and DataAnnotations, with no `[JsonPropertyName]`.
- **Log property names are lowerCamel**, placeholders included, and hot lines use `[LoggerMessage]`. 🔴 Never log a login code, token, refresh token, `Authorization` header, signing key or unmasked email. An email in a log line goes only through `Pii.MaskEmail`.
- **Masked property names.** Properties named with `token`, `secret`, `password`, `logincode`, `authorization`, `cookie` or `connectionstring` are masked, so ids are named `codeId` and `familyId`.
- **Data rules.**
  - Tables are `snake_case` and singular (`customer`), with UUID v7 ids set in code.
  - Instants are `timestamptz` with C# `DateTime` Kind Utc.
  - `created_at` / `updated_at` are set by `TimestampsInterceptor`. `ExecuteUpdate` / `ExecuteDelete` skip it, so set `updated_at` yourself there.
- **Transactions.** Every `BeginTransactionAsync` has a `CommitAsync` on every path that must keep its writes, including the "wrong code" path, which counts an attempt and then throws (engineering checklist §2).
- **Migrations.** After `dotnet ef migrations add`, strip the BOM from the 3 generated files.
- **Tests.** Test environment `Testing`. `ExtraSpace.Api.Tests` needs Docker. Filter form: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*LoginCodeTests"`.
- **Spec values (§6.1, verbatim):**
  - code: 6 digits, valid **10 minutes**, a new request replaces the active code; one request per email per **60 s** and **5 per hour**; **20 per IP per hour**; **5 attempts**; **30 checks per IP per hour**
  - access token: JWT HS256, **15 minutes**, claims `sub`, `email`, `iss`, `aud`
  - refresh token: **32 random bytes** base64url, stored as SHA-256, **60 days** from each issue
  - housekeeping deletes refresh tokens **30 days past expiry**

## Review Focus

1. **Double tap / parallel requests for one email.** The app retries `POST /auth/code` or `/auth/code/verify`. Expected: no 500 and no 409; exactly one code goes out, and the rest get 429. Pinned by Task 4 `Parallel_code_requests_for_one_email_send_one_code` (a per-email advisory lock serialises them).
2. **A failed verify attempt is lost** because the error is thrown inside the transaction and rolls the attempt counter back. Expected: the 5th wrong code locks the code even across requests. Pinned by Task 4 `Five_wrong_codes_lock_the_code`.
3. **The same person types the email differently** (`" Jane@Example.COM "` vs `jane@example.com`). Expected: one code row, one customer. Pinned by Task 4 `Email_case_and_spaces_do_not_matter`.
4. **A login code or address reaches storage or logs:**
   - the Hangfire job arguments (`hangfire.job.arguments`)
   - a log line in the whole flow (request, email job, verify, refresh, me, logout)

   Expected: neither contains the code, any token or the raw address. Pinned by Task 2 `Job_arguments_hold_no_address_or_values` and Task 5 `A_full_sign_in_flow_logs_no_code_token_or_raw_email`.
5. **A replayed refresh token** (stolen, or the app's double refresh). Expected: 401, the whole family revoked (the newest token also stops working), one Warning line `reuse detected`, no 500. Pinned by Task 5 `Replaying_a_used_refresh_token_revokes_the_family`.

## Decisions this plan makes (owner to confirm with the plan)

1. **Feature folder `Features/Identity`** for customer sign-in and `/me`. S0-4 puts staff in its own feature.
2. **One `customer_login_code` row per email.** Unique `email`; a new request overwrites the code fields. The spec's columns gain `last_sent_at`, `window_started_at` and `sent_in_window`, so the per-email limits (60 s, 5 per hour) are exact across all API tasks. Each code request and verify takes `pg_advisory_xact_lock(hashtextextended(email, 0))` first, so parallel calls for one email run one after another.
3. **Per-IP limits (20 code requests, 30 checks per hour) use ASP.NET Core's in-memory rate limiter.** Its count is per task, so with N API tasks the real limit is up to N× (production runs 2–4). The per-code 5-attempt lock is exact. S1 may move these limits to Valkey.
4. **`TOO_MANY_ATTEMPTS` is a 400.** Wrong attempts 1–4 → 400 `INVALID_CODE`. The 5th wrong attempt, and every check after it (even the right code), → 400 `TOO_MANY_ATTEMPTS`.
5. **Hashes.**
   - Code hash = HMAC-SHA256 of `email:code`, keyed with a sub-key derived (HKDF-SHA256, info `login-code`) from `CustomerAuth:SigningKey`. A 6-digit code hashed with plain SHA-256 could be reversed from a database leak in milliseconds.
   - Refresh-token hash = plain SHA-256, lower-case hex: the token has 256 bits of entropy.
6. **Email job payload is encrypted.** The address and all template values are protected with a time-limited Data Protection protector (login code: 10 minutes), so `hangfire.job` never holds the code or the address in clear. If the payload has expired by the time the job runs, the job logs a Warning and ends without retrying.
7. **Email transports** (`Email:Transport`):
   - `Ses` is the default.
   - `Log` is for Development only, and startup refuses it elsewhere. It prints the whole email, code included (spec §9.1).
   - `None` registers no transport; the test host supplies a fake.
   - SES needs `Email:From` (open item 3: the client's sender + SPF/DKIM).
8. **Hangfire.**
   - `WorkerCount` 5, `QueuePollInterval` 5 s (config `Jobs:*`).
   - Retries: Hangfire's default `AutomaticRetry` is replaced by one with `LogEvents = false`, because our filter logs each attempt once. Every `[AutomaticRetry]` we write also sets `LogEvents = false`.
   - The dashboard (`/admin/jobs`) waits for S0-4's admin sign-in.
9. **Recurring jobs** are declared with `services.AddRecurringJob<TJob>(name, cron)` and registered at start-up, only in roles `Jobs` / `All`. They use the time zone `Asia/Singapore`, with the switch `Jobs:<name>:Enabled`. `IdentityHousekeeping` runs daily at 03:00 SGT and deletes:
   - login-code rows that expired more than 1 day ago;
   - refresh tokens that expired more than 30 days ago.
10. **`AppException` gains `RetryAfter`**: the exception handler writes it as the `Retry-After` header (whole seconds, rounded up). Used by the per-email 429s.
11. **Token response:** `{ accessToken, accessTokenExpiresAt, refreshToken, refreshTokenExpiresAt }`, times in UTC (`Z`).
12. **JWT validation.** `MapInboundClaims = false`, so `sub` stays `sub`; HS256 only; clock skew 30 s. The key is `CustomerAuth:SigningKey`: base64, at least 32 bytes, checked at start-up.
13. **`/api/v1` requires a customer by default.** Every route needs the `Customer` policy unless it says `.AllowAnonymous()`. A filter on the group adds `customerId` to the request log after sign-in.
14. **OpenAPI** declares a `Bearer` (JWT) security scheme, so Swagger UI's "Authorize" button works.
15. **`/me` for a customer id that no longer exists** → 401 `UNAUTHENTICATED`.
16. **SES call.** No SDK retries (`MaxErrorRetry = 0`) and a 10 s timeout; the Hangfire job retries (5 attempts). No circuit breaker in S0: S1 adds `Microsoft.Extensions.Http.Resilience` for the outside calls.

---

### Task 1: Background jobs platform (Hangfire, roles, job tracing, recurring jobs)

**Files:**
- Modify: `Directory.Packages.props`, `src/ExtraSpace.Api/ExtraSpace.Api.csproj`, `src/ExtraSpace.Api/appsettings.json`, `src/ExtraSpace.Api/Platform/Hosting/PlatformServices.cs`
- Create: `src/ExtraSpace.Api/Platform/Jobs/JobsOptions.cs`, `JobsSetup.cs`, `JobTracingFilter.cs`, `RecurringJobs.cs`
- Modify (tests): `tests/ExtraSpace.Api.Tests/ApiFactory.cs`, `TestSupport/LogCapture.cs`, `TestSupport/TestEndpoints.cs`
- Create (tests): `tests/ExtraSpace.Api.Tests/TestSupport/TestJobs.cs`, `tests/ExtraSpace.Api.Tests/Platform/JobsTests.cs`

**Interfaces:**
- Consumes: `Correlation.Begin/CurrentId`, `AppOptions.Role` / `AppRole`, `ConnectionStrings:Default`.
- Produces:
  - `JobsSetup.AddPlatformJobs(this IServiceCollection, IConfiguration)`, called by `AddPlatform`;
  - `public interface IRecurringJob { Task RunAsync(CancellationToken cancellationToken); }`;
  - `RecurringJobs.AddRecurringJob<TJob>(this IServiceCollection, string name, string cron) where TJob : class, IRecurringJob`;
  - log lines with `jobId`, `jobName` (class name without a trailing `Job`), `attempt` (1-based) and `correlationId`;
  - Hangfire's `IBackgroundJobClient` in DI;
  - `LogCapture.All()` and `LogCapture.WaitForAsync(...)` for later tasks.

- [ ] **Step 1: Branch**

```bash
cd "/Users/waiyanmin/Projects/Extra Space/CMS"
git status --short          # must print nothing; stop and report if not
git log --oneline -1        # 441cc27 switch to minimal API architecture
git switch -c s0-3-customer-identity
```

- [ ] **Step 2: Packages.** In `Directory.Packages.props`, add to the `Api` group, keeping alphabetical order:

```xml
    <PackageVersion Include="AWSSDK.Extensions.NETCore.Setup" Version="4.0.102.2" />
    <PackageVersion Include="AWSSDK.SimpleEmailV2" Version="4.0.106.2" />
    <PackageVersion Include="Hangfire.AspNetCore" Version="1.8.25" />
    <PackageVersion Include="Hangfire.Core" Version="1.8.25" />
    <PackageVersion Include="Hangfire.PostgreSql" Version="1.21.1" />
    <PackageVersion Include="Microsoft.AspNetCore.Authentication.JwtBearer" Version="10.0.11" />
```

In `ExtraSpace.Api.csproj`, add `PackageReference`s for `Hangfire.AspNetCore`, `Hangfire.Core` and `Hangfire.PostgreSql`. The AWS and JwtBearer references come in Tasks 2 and 3. `Hangfire.PostgreSql` brings `Dapper.AOT`: if the build shows warnings from it, report them; do not suppress them globally.

- [ ] **Step 3: Write the failing tests.** `tests/ExtraSpace.Api.Tests/TestSupport/TestJobs.cs`:

```csharp
using Hangfire;
using Microsoft.Extensions.Logging;

namespace ExtraSpace.Api.Tests.TestSupport;

/// <summary>Test-only Hangfire jobs, enqueued through <c>POST /test/jobs/{kind}</c>.</summary>
public sealed class TestJobs(ILogger<TestJobs> logger)
{
    public void Ok(string marker) => logger.LogInformation("Test job ran {marker}", marker);

    [AutomaticRetry(Attempts = 0, LogEvents = false)]
    public void Fail(string marker) => throw new InvalidOperationException("job-boom " + marker);
}
```

In `TestEndpoints.Map`, add inside the `/test` group:

```csharp
        test.MapPost("/jobs/{kind}", (string kind, IBackgroundJobClient jobs) =>
        {
            var marker = Guid.NewGuid().ToString("N");
            var jobId = kind == "fail" ? jobs.Enqueue<TestJobs>(j => j.Fail(marker)) : jobs.Enqueue<TestJobs>(j => j.Ok(marker));
            return TypedResults.Ok(new { jobId, marker });
        });
```

In `LogCapture`, add:

```csharp
    public IReadOnlyList<JsonElement> All() => _lines.Select(line => JsonDocument.Parse(line).RootElement).ToList();

    /// <summary>Waits until <paramref name="count"/> lines match (jobs log on a worker thread, after the request returned).</summary>
    public async Task<IReadOnlyList<JsonElement>> WaitForAsync(Func<JsonElement, bool> match, int count = 1, int timeoutSeconds = 20)
    {
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (true)
        {
            var found = All().Where(match).ToList();
            if (found.Count >= count) return found;
            if (DateTime.UtcNow > deadline) throw new TimeoutException($"Expected {count} matching log lines, found {found.Count}.");
            await Task.Delay(100);
        }
    }
```

In `ApiFactory.ConfigureWebHost`, add `builder.UseSetting("Jobs:QueuePollInterval", "00:00:00.200");` and, in `ConfigureTestServices`, `services.AddTransient<TestJobs>();`.

`tests/ExtraSpace.Api.Tests/Platform/JobsTests.cs`:

```csharp
using System.Net.Http.Json;
using System.Text.Json;
using ExtraSpace.Api.Platform.Jobs;
using ExtraSpace.Api.Tests.TestSupport;
using Hangfire;
using Hangfire.Common;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class JobsTests(ApiFactory api)
{
    private readonly HttpClient _client = api.CreateClient();
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private static string? Str(JsonElement line, string name) =>
        line.TryGetProperty(name, out var value) ? value.ToString() : null;

    private async Task<(string TraceId, string JobId, string Marker)> EnqueueAsync(string kind)
    {
        var response = await _client.PostAsync($"/test/jobs/{kind}", null, Ct);
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Ct);
        return (Problem.TraceIdOf(response), body.GetProperty("jobId").GetString()!, body.GetProperty("marker").GetString()!);
    }

    [Fact]
    public async Task A_job_enqueued_by_a_request_carries_its_correlation_id()
    {
        var (traceId, jobId, marker) = await EnqueueAsync("ok");

        var line = (await api.Logs.WaitForAsync(l => Str(l, "marker") == marker)).Single();
        Str(line, "correlationId").Should().Be(traceId);
        Str(line, "traceId").Should().MatchRegex("^[0-9a-f]{32}$").And.NotBe(traceId, "a job run is its own trace");
        Str(line, "jobId").Should().Be(jobId);
        Str(line, "jobName").Should().Be("TestJobs");
        Str(line, "attempt").Should().Be("1");

        var done = await api.Logs.WaitForAsync(l => Str(l, "jobId") == jobId && Str(l, "messageTemplate") == "Job {jobName} succeeded in {elapsedMs} ms");
        Str(done.Single(), "correlationId").Should().Be(traceId);
        api.Logs.All().Where(l => Str(l, "jobId") == jobId && Str(l, "messageTemplate") == "Job {jobName} started").Should().ContainSingle();
    }

    [Fact]
    public async Task A_failed_job_logs_its_exception_once_and_fails_permanently()
    {
        var (traceId, jobId, marker) = await EnqueueAsync("fail");

        var permanent = await api.Logs.WaitForAsync(l => Str(l, "jobId") == jobId && Str(l, "messageTemplate") == "Job {jobName} failed permanently");
        Str(permanent.Single(), "level").Should().Be("Error");
        Str(permanent.Single(), "correlationId").Should().Be(traceId);

        var withException = api.Logs.All().Where(l => Str(l, "jobId") == jobId && l.TryGetProperty("exception", out _)).ToList();
        withException.Should().ContainSingle("each failed attempt is logged once, by our filter only");
        Str(withException[0], "exception").Should().Contain("job-boom " + marker);
    }

    [Theory]
    [InlineData("Api", 0)]
    [InlineData("Jobs", 2)]
    [InlineData("All", 2)]
    public void Only_the_jobs_roles_run_a_job_server(string role, int hostedServices)
    {
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["App:Role"] = role,
            ["ConnectionStrings:Default"] = "Host=unused",
        }).Build();
        var services = new ServiceCollection();
        services.AddPlatformJobs(config);
        services.Count(d => d.ServiceType == typeof(IHostedService)).Should().Be(hostedServices);
    }

    [Fact]
    public async Task Recurring_jobs_follow_their_enabled_switch()
    {
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Jobs:Second:Enabled"] = "false",
        }).Build();
        var manager = new FakeRecurringJobManager();
        var registrar = new RecurringJobsRegistrar(
            [
                new RecurringJobDefinition("First", Cron.Daily(3), (m, id, cron, o) => m.AddOrUpdate<TestRecurring>(id, j => j.RunAsync(CancellationToken.None), cron, o)),
                new RecurringJobDefinition("Second", Cron.Daily(4), (m, id, cron, o) => m.AddOrUpdate<TestRecurring>(id, j => j.RunAsync(CancellationToken.None), cron, o)),
            ],
            manager, config, NullLogger<RecurringJobsRegistrar>.Instance);

        await registrar.StartAsync(Ct);

        manager.Added.Should().Equal("First");
        manager.Removed.Should().Equal("Second");
        manager.TimeZones.Should().AllSatisfy(z => z.Id.Should().Be("Asia/Singapore"));
    }

    private sealed class TestRecurring : IRecurringJob
    {
        public Task RunAsync(CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed class FakeRecurringJobManager : IRecurringJobManager
    {
        public List<string> Added { get; } = [];
        public List<string> Removed { get; } = [];
        public List<TimeZoneInfo> TimeZones { get; } = [];

        public void AddOrUpdate(string recurringJobId, Job job, string cronExpression, RecurringJobOptions options)
        {
            Added.Add(recurringJobId);
            TimeZones.Add(options.TimeZone);
        }

        public void Trigger(string recurringJobId) { }

        public void RemoveIfExists(string recurringJobId) => Removed.Add(recurringJobId);
    }
}
```

Note for the implementer: check `IRecurringJobManager`'s exact members in Hangfire 1.8.25, and adjust the fake, not the test's intent. The hosted-service count for `Jobs`/`All` is Hangfire's server plus our registrar. If Hangfire 1.8.25 registers a different number, assert `> 0` and that `RecurringJobsRegistrar` is among the descriptors. Report what you found.

- [ ] **Step 4: Run them to see them fail** (they do not compile yet): `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*JobsTests"`.

- [ ] **Step 5: Implement.** `Platform/Jobs/JobsOptions.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Jobs;

public sealed class JobsOptions
{
    public const string Section = "Jobs";

    public int WorkerCount { get; set; } = 5;

    /// <summary>How often an idle worker checks the queue. Tests use 200 ms.</summary>
    public TimeSpan QueuePollInterval { get; set; } = TimeSpan.FromSeconds(5);
}
```

`Platform/Jobs/RecurringJobs.cs`:

```csharp
using Hangfire;

namespace ExtraSpace.Api.Platform.Jobs;

/// <summary>A job that runs on a schedule (S0 spec §7). Implementations must be idempotent.</summary>
public interface IRecurringJob
{
    Task RunAsync(CancellationToken cancellationToken);
}

public sealed record RecurringJobDefinition(
    string Name, string Cron, Action<IRecurringJobManager, string, string, RecurringJobOptions> AddOrUpdate);

public static class RecurringJobs
{
    /// <summary>Declares a recurring job; <c>Jobs:&lt;name&gt;:Enabled=false</c> removes it at the next start-up.</summary>
    public static IServiceCollection AddRecurringJob<TJob>(this IServiceCollection services, string name, string cron)
        where TJob : class, IRecurringJob
    {
        services.AddScoped<TJob>();
        services.AddSingleton(new RecurringJobDefinition(name, cron,
            (manager, id, schedule, options) => manager.AddOrUpdate<TJob>(id, job => job.RunAsync(CancellationToken.None), schedule, options)));
        return services;
    }
}

/// <summary>Writes the declared schedules to Hangfire at start-up (roles Jobs and All only).</summary>
internal sealed partial class RecurringJobsRegistrar(
    IEnumerable<RecurringJobDefinition> jobs, IRecurringJobManager manager, IConfiguration configuration,
    ILogger<RecurringJobsRegistrar> logger) : IHostedService
{
    // Business schedules use Singapore time (S0 spec §4.6); both SG and MY are UTC+8.
    private static readonly TimeZoneInfo Schedule = TimeZoneInfo.FindSystemTimeZoneById("Asia/Singapore");

    public Task StartAsync(CancellationToken cancellationToken)
    {
        foreach (var job in jobs)
        {
            if (configuration.GetValue($"{JobsOptions.Section}:{job.Name}:Enabled", true))
            {
                job.AddOrUpdate(manager, job.Name, job.Cron, new RecurringJobOptions { TimeZone = Schedule });
            }
            else
            {
                manager.RemoveIfExists(job.Name);
                LogDisabled(logger, job.Name);
            }
        }
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    [LoggerMessage(Level = LogLevel.Information, Message = "Recurring job {jobName} is disabled by configuration")]
    private static partial void LogDisabled(ILogger logger, string jobName);
}
```

`Platform/Jobs/JobTracingFilter.cs`:

```csharp
using System.Diagnostics;
using ExtraSpace.Api.Platform.Tracing;
using Hangfire.Client;
using Hangfire.Common;
using Hangfire.Server;
using Hangfire.States;
using Hangfire.Storage;
using Serilog.Context;

namespace ExtraSpace.Api.Platform.Jobs;

/// <summary>
/// Job tracing (S0 spec §7, §4.4): stores the enqueuing request's correlationId on the job, gives each run its own trace,
/// and logs start, success and each failed attempt once (Hangfire's own retry logging is off).
/// </summary>
internal sealed partial class JobTracingFilter(ILogger<JobTracingFilter> logger) : IClientFilter, IServerFilter, IApplyStateFilter
{
    internal const string CorrelationParameter = "correlationId";
    private const string ScopeItem = "es.jobScope";

    public void OnCreating(CreatingContext context) =>
        context.SetJobParameter(CorrelationParameter, Correlation.CurrentId ?? Activity.Current?.TraceId.ToHexString());

    public void OnCreated(CreatedContext context) { }

    public void OnPerforming(PerformingContext context)
    {
        var activity = new Activity("job").Start();
        var correlationId = context.GetJobParameter<string>(CorrelationParameter) ?? activity.TraceId.ToHexString();
        var jobName = JobName(context.BackgroundJob.Job);
        context.Items[ScopeItem] = new RunScope(
            activity,
            Correlation.Begin(correlationId),
            LogContext.PushProperty("jobId", context.BackgroundJob.Id),
            LogContext.PushProperty("jobName", jobName),
            LogContext.PushProperty("attempt", context.GetJobParameter<int>("RetryCount") + 1),
            Stopwatch.GetTimestamp());
        LogStarted(logger, jobName);
    }

    public void OnPerformed(PerformedContext context)
    {
        if (context.Items.TryGetValue(ScopeItem, out var item) is false || item is not RunScope scope) return;
        var jobName = JobName(context.BackgroundJob.Job);
        var elapsedMs = (long)Stopwatch.GetElapsedTime(scope.Started).TotalMilliseconds;
        if (context.Exception is null) LogSucceeded(logger, jobName, elapsedMs);
        else LogFailed(logger, context.Exception, jobName, elapsedMs);
        scope.Dispose();
    }

    // AutomaticRetry schedules a retry until the attempts run out; only then is Failed applied.
    public void OnStateApplied(ApplyStateContext context, IWriteOnlyTransaction transaction)
    {
        if (context.NewState is not FailedState) return;
        var jobId = context.BackgroundJob.Id;
        var correlationId = SerializationHelper.Deserialize<string>(context.Connection.GetJobParameter(jobId, CorrelationParameter));
        var jobName = JobName(context.BackgroundJob.Job);
        using (LogContext.PushProperty("jobId", jobId))
        using (LogContext.PushProperty("jobName", jobName))
        using (LogContext.PushProperty("correlationId", correlationId))
        {
            LogFailedPermanently(logger, jobName);
        }
    }

    public void OnStateUnapplied(ApplyStateContext context, IWriteOnlyTransaction transaction) { }

    internal static string JobName(Job job) =>
        job.Type.Name.EndsWith("Job", StringComparison.Ordinal) ? job.Type.Name[..^3] : job.Type.Name;

    private sealed record RunScope(Activity Activity, IDisposable Correlation, IDisposable JobId, IDisposable JobName, IDisposable Attempt, long Started)
        : IDisposable
    {
        public void Dispose()
        {
            Attempt.Dispose();
            JobName.Dispose();
            JobId.Dispose();
            Correlation.Dispose();
            Activity.Stop();
        }
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "Job {jobName} started")]
    private static partial void LogStarted(ILogger logger, string jobName);

    [LoggerMessage(Level = LogLevel.Information, Message = "Job {jobName} succeeded in {elapsedMs} ms")]
    private static partial void LogSucceeded(ILogger logger, string jobName, long elapsedMs);

    [LoggerMessage(Level = LogLevel.Error, Message = "Job {jobName} failed in {elapsedMs} ms")]
    private static partial void LogFailed(ILogger logger, Exception exception, string jobName, long elapsedMs);

    [LoggerMessage(Level = LogLevel.Error, Message = "Job {jobName} failed permanently")]
    private static partial void LogFailedPermanently(ILogger logger, string jobName);
}
```

Notes for the implementer (verify, don't guess):
- `PerformContext.Items`, `PerformingContext.GetJobParameter<T>`, `CreatingContext.SetJobParameter`, `IStorageConnection.GetJobParameter` and `SerializationHelper` are Hangfire 1.8 APIs. If a signature differs, adapt the call and keep the behaviour.
- `context.Exception` on `PerformedContext` must be the job's own exception. The failure test checks that its message reaches the log.
- The AsyncLocal values pushed in `OnPerforming` must be visible inside the job method. The correlation test proves it.

`Platform/Jobs/JobsSetup.cs`:

```csharp
using ExtraSpace.Api.Platform.Hosting;
using Hangfire;
using Hangfire.PostgreSql;

namespace ExtraSpace.Api.Platform.Jobs;

public static class JobsSetup
{
    /// <summary>Hangfire on PostgreSQL, schema <c>hangfire</c> (S0 spec §7). Every role enqueues; only Jobs and All run the server.</summary>
    public static IServiceCollection AddPlatformJobs(this IServiceCollection services, IConfiguration configuration)
    {
        var options = configuration.GetSection(JobsOptions.Section).Get<JobsOptions>() ?? new JobsOptions();
        var role = configuration.GetSection(AppOptions.Section).Get<AppOptions>()?.Role ?? AppRole.All;

        services.AddSingleton<JobTracingFilter>();
        services.AddHangfire((sp, config) =>
        {
            // Our filter logs each attempt once; Hangfire's default retry filter would log the same failure again.
            GlobalJobFilters.Filters.Remove(typeof(AutomaticRetryAttribute));
            config.SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
                .UseSimpleAssemblyNameTypeSerializer()
                .UseRecommendedSerializerSettings()
                .UseFilter(new AutomaticRetryAttribute { LogEvents = false })
                .UseFilter(sp.GetRequiredService<JobTracingFilter>())
                .UsePostgreSqlStorage(
                    c => c.UseNpgsqlConnection(sp.GetRequiredService<IConfiguration>().GetConnectionString("Default")
                        ?? throw new InvalidOperationException("ConnectionStrings:Default is not set.")),
                    new PostgreSqlStorageOptions
                    {
                        SchemaName = "hangfire",
                        PrepareSchemaIfNecessary = true,
                        QueuePollInterval = options.QueuePollInterval,
                    });
        });

        if (role is AppRole.Jobs or AppRole.All)
        {
            services.AddHangfireServer(o => o.WorkerCount = options.WorkerCount);
            services.AddHostedService<RecurringJobsRegistrar>();
        }
        return services;
    }
}
```

In `PlatformServices.AddPlatform`, after the data section, add `services.AddPlatformJobs(configuration);` with the comment line `// Jobs (S0 spec §7)`.

`appsettings.json`: add `"Jobs": { "WorkerCount": 5, "QueuePollInterval": "00:00:05" }`. Under `Serilog:MinimumLevel:Override`, add `"Hangfire": "Warning"`.

- [ ] **Step 6: Run the tests.**
  - `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*JobsTests"` passes.
  - Then run the full `dotnet test tests/ExtraSpace.Api.Tests`: all 84 earlier tests still pass. No test may log a Hangfire start-up error: grep the test output for `Hangfire` at Error.

- [ ] **Step 7: Hand-off.** Write the report (files, decisions, the exact build and test lines) and stop. Do not commit.

---

### Task 2: Email integration (`IEmailSender`, `EmailJob`, templates, SES and Log transports)

**Files:**
- Modify: `src/ExtraSpace.Api/ExtraSpace.Api.csproj` (AWS packages, embedded templates), `src/ExtraSpace.Api/Program.cs`, `src/ExtraSpace.Api/appsettings.json`, `src/ExtraSpace.Api/appsettings.Development.json`
- Create: `src/ExtraSpace.Api/Integrations/Email/` (`IEmailSender.cs`, `IEmailTransport.cs`, `EmailOptions.cs`, `EmailSetup.cs`, `EmailTemplates.cs`, `EmailJob.cs`, `HangfireEmailSender.cs`, `SesEmailTransport.cs`, `LogEmailTransport.cs`, `Templates/login-code.html`, `Templates/login-code.txt`)
- Modify (tests): `ApiFactory.cs`, `TestSupport/TestEndpoints.cs`
- Create (tests): `tests/ExtraSpace.Api.Tests/TestSupport/FakeEmailTransport.cs`, `tests/ExtraSpace.Api.Tests/Integrations/EmailTests.cs`

**Interfaces:**
- Consumes: Task 1's Hangfire `IBackgroundJobClient`, the `JobTracingFilter` log properties, and `Pii.MaskEmail`.
- Produces (used by Task 4):

```csharp
namespace ExtraSpace.Api.Integrations.Email;
public sealed record EmailMessage(string Template, string To, IReadOnlyDictionary<string, string> Values, TimeSpan ValidFor);
public interface IEmailSender { string Enqueue(EmailMessage message); }   // returns the Hangfire job id; call it AFTER the DB commit
public sealed record RenderedEmail(string To, string Subject, string Html, string Text);
public interface IEmailTransport { Task SendAsync(RenderedEmail email, CancellationToken cancellationToken); }
public static IServiceCollection AddEmail(this IServiceCollection services, IConfiguration configuration, IHostEnvironment environment);
```

  The template `login-code` takes the values `code` and `minutes`.

- [ ] **Step 1: Write the failing tests.** `TestSupport/FakeEmailTransport.cs`:

```csharp
using System.Collections.Concurrent;
using System.Text.RegularExpressions;
using ExtraSpace.Api.Integrations.Email;

namespace ExtraSpace.Api.Tests.TestSupport;

/// <summary>Stands in for SES in tests: keeps every email the jobs send.</summary>
public sealed partial class FakeEmailTransport : IEmailTransport
{
    private readonly ConcurrentQueue<RenderedEmail> _sent = new();

    public IReadOnlyList<RenderedEmail> SentTo(string to) => _sent.Where(e => e.To == to).ToList();

    public Task SendAsync(RenderedEmail email, CancellationToken cancellationToken)
    {
        _sent.Enqueue(email);
        return Task.CompletedTask;
    }

    public async Task<RenderedEmail> WaitForAsync(string to, int count = 1, int timeoutSeconds = 20)
    {
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (SentTo(to).Count < count)
        {
            if (DateTime.UtcNow > deadline) throw new TimeoutException($"Expected {count} emails to {to}, got {SentTo(to).Count}.");
            await Task.Delay(100);
        }
        return SentTo(to)[count - 1];
    }

    /// <summary>The 6-digit code in the n-th login-code email to this address.</summary>
    public async Task<string> CodeForAsync(string to, int count = 1) =>
        SixDigits().Match((await WaitForAsync(to, count)).Text).Value;

    [GeneratedRegex(@"\b\d{6}\b")]
    private static partial Regex SixDigits();
}
```

Changes to `ApiFactory`:
- Add `builder.UseSetting("Email:Transport", "None");`.
- Add a property `public FakeEmailTransport Emails { get; } = new();`.
- In `ConfigureTestServices`, add `services.AddSingleton<IEmailTransport>(Emails);`.

`TestEndpoints`, inside `/test`:

```csharp
        test.MapPost("/email", (string to, string code, int? validForMs, IEmailSender email) =>
        {
            var jobId = email.Enqueue(new EmailMessage("login-code", to,
                new Dictionary<string, string> { ["code"] = code, ["minutes"] = "10" },
                TimeSpan.FromMilliseconds(validForMs ?? 600_000)));
            return TypedResults.Ok(new { jobId });
        });
```

`tests/ExtraSpace.Api.Tests/Integrations/EmailTests.cs`:

```csharp
using System.Net.Http.Json;
using System.Text.Json;
using ExtraSpace.Api.Integrations.Email;
using Npgsql;

namespace ExtraSpace.Api.Tests.Integrations;

public sealed class EmailTests(ApiFactory api)
{
    private readonly HttpClient _client = api.CreateClient();
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private static string NewAddress() => $"email-{Guid.NewGuid():N}@example.test";

    private static string? Str(JsonElement line, string name) =>
        line.TryGetProperty(name, out var value) ? value.ToString() : null;

    private async Task<string> SendAsync(string to, string code, int? validForMs = null)
    {
        var url = $"/test/email?to={Uri.EscapeDataString(to)}&code={Uri.EscapeDataString(code)}"
            + (validForMs is { } ms ? $"&validForMs={ms}" : "");
        var response = await _client.PostAsync(url, null, Ct);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<JsonElement>(Ct)).GetProperty("jobId").GetString()!;
    }

    [Fact]
    public async Task The_job_renders_the_template_and_sends_it()
    {
        var to = NewAddress();
        await SendAsync(to, "12<34>56");

        var email = await api.Emails.WaitForAsync(to);
        email.Subject.Should().Be("Your ExtraSpace sign-in code");
        email.Html.Should().Contain("12&lt;34&gt;56").And.NotContain("12<34>56");
        email.Text.Should().Contain("12<34>56").And.Contain("10 minutes");

        var sent = await api.Logs.WaitForAsync(l => Str(l, "messageTemplate") == "Email {template} sent to {email}"
            && Str(l, "email") == ExtraSpace.Api.Platform.Logging.Pii.MaskEmail(to));
        Str(sent.Single(), "template").Should().Be("login-code");
    }

    [Fact]
    public async Task Job_arguments_hold_no_address_or_values()
    {
        var to = NewAddress();
        var jobId = await SendAsync(to, "918273");

        await using var connection = new NpgsqlConnection(api.ConnectionString);
        await connection.OpenAsync(Ct);
        await using var command = new NpgsqlCommand("SELECT invocationdata::text || ' ' || arguments::text FROM hangfire.job WHERE id = @id", connection);
        command.Parameters.AddWithValue("id", long.Parse(jobId));
        var stored = (string)(await command.ExecuteScalarAsync(Ct))!;
        stored.Should().NotContain(to).And.NotContain("918273");
    }

    [Fact]
    public async Task An_expired_payload_is_dropped_with_a_warning()
    {
        var to = NewAddress();
        var jobId = await SendAsync(to, "555666", validForMs: 1);

        var warning = await api.Logs.WaitForAsync(l => Str(l, "jobId") == jobId
            && Str(l, "messageTemplate") == "Email {template} expired before it was sent");
        Str(warning.Single(), "level").Should().Be("Warning");
        api.Emails.SentTo(to).Should().BeEmpty();
    }

    [Fact]
    public void Rendering_fails_loudly_on_a_missing_value_or_unknown_template()
    {
        var render = () => EmailTemplates.Render("login-code", "a@example.test", new Dictionary<string, string> { ["code"] = "1" });
        render.Should().Throw<InvalidOperationException>().WithMessage("*minutes*");
        var unknown = () => EmailTemplates.EnsureKnown("no-such-template");
        unknown.Should().Throw<InvalidOperationException>();
    }

    [Fact]
    public void The_ses_request_carries_html_text_and_sender()
    {
        var request = SesEmailTransport.ToRequest(new RenderedEmail("to@example.test", "Subject", "<p>h</p>", "t"), "ExtraSpace <no-reply@example.test>");
        request.FromEmailAddress.Should().Be("ExtraSpace <no-reply@example.test>");
        request.Destination.ToAddresses.Should().Equal("to@example.test");
        request.Content.Simple.Subject.Data.Should().Be("Subject");
        request.Content.Simple.Body.Html.Data.Should().Be("<p>h</p>");
        request.Content.Simple.Body.Text.Data.Should().Be("t");
    }
}
```

The `hangfire.job` column names come from Hangfire.PostgreSql's schema. If they differ in 1.21.1, read the real table and adapt the query; the test's intent (no address, no code anywhere in the stored job) stays.

- [ ] **Step 2: Run them to see them fail** (they do not compile yet).

- [ ] **Step 3: Implement.** In `ExtraSpace.Api.csproj`, add `PackageReference`s for `AWSSDK.Extensions.NETCore.Setup` and `AWSSDK.SimpleEmailV2`, and:

```xml
  <ItemGroup>
    <EmbeddedResource Include="Integrations/Email/Templates/*" LogicalName="email/%(Filename)%(Extension)" />
  </ItemGroup>
```

`Integrations/Email/IEmailSender.cs`:

```csharp
namespace ExtraSpace.Api.Integrations.Email;

/// <summary>
/// An email to send. <paramref name="ValidFor"/> bounds how long the queued job may still send it (a login code is useless
/// after 10 minutes); the address and values are encrypted inside the job, so the job tables never hold them in clear.
/// </summary>
public sealed record EmailMessage(string Template, string To, IReadOnlyDictionary<string, string> Values, TimeSpan ValidFor);

public interface IEmailSender
{
    /// <summary>Queues the email as a Hangfire job and returns its id. Call it after the database commit (S0 spec §7).</summary>
    string Enqueue(EmailMessage message);
}
```

`Integrations/Email/IEmailTransport.cs`:

```csharp
namespace ExtraSpace.Api.Integrations.Email;

public sealed record RenderedEmail(string To, string Subject, string Html, string Text);

/// <summary>Delivers one rendered email: SES, the Development log, or a test fake.</summary>
public interface IEmailTransport
{
    Task SendAsync(RenderedEmail email, CancellationToken cancellationToken);
}
```

`Integrations/Email/EmailOptions.cs`:

```csharp
namespace ExtraSpace.Api.Integrations.Email;

public enum EmailTransport { Ses, Log, None }

public sealed class EmailOptions
{
    public const string Section = "Email";

    /// <summary><c>Ses</c> (default); <c>Log</c> prints emails, Development only; <c>None</c> leaves the transport to the host (tests).</summary>
    public EmailTransport Transport { get; set; } = EmailTransport.Ses;

    /// <summary>Sender, for example <c>ExtraSpace &lt;no-reply@…&gt;</c>; must be verified in SES (open item 3).</summary>
    public string From { get; set; } = "";
}
```

`Integrations/Email/EmailTemplates.cs`:

```csharp
using System.Text.Encodings.Web;
using System.Text.RegularExpressions;

namespace ExtraSpace.Api.Integrations.Email;

/// <summary>Templates are embedded files <c>Templates/&lt;name&gt;.html</c> and <c>.txt</c> with <c>{{value}}</c> placeholders.</summary>
public static partial class EmailTemplates
{
    private static readonly Dictionary<string, string> Subjects = new(StringComparer.Ordinal)
    {
        ["login-code"] = "Your ExtraSpace sign-in code",
    };

    public static void EnsureKnown(string template)
    {
        if (!Subjects.ContainsKey(template)) throw new InvalidOperationException($"Unknown email template '{template}'.");
    }

    public static RenderedEmail Render(string template, string to, IReadOnlyDictionary<string, string> values)
    {
        EnsureKnown(template);
        return new RenderedEmail(to, Subjects[template],
            Fill(Load(template + ".html"), values, HtmlEncoder.Default.Encode),
            Fill(Load(template + ".txt"), values, v => v));
    }

    private static string Load(string file)
    {
        using var stream = typeof(EmailTemplates).Assembly.GetManifestResourceStream("email/" + file)
            ?? throw new InvalidOperationException($"Email template file '{file}' is not embedded.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    private static string Fill(string text, IReadOnlyDictionary<string, string> values, Func<string, string> encode) =>
        Placeholder().Replace(text, m => values.TryGetValue(m.Groups[1].Value, out var value)
            ? encode(value)
            : throw new InvalidOperationException($"Email value '{m.Groups[1].Value}' is missing."));

    [GeneratedRegex(@"\{\{(\w+)\}\}")]
    private static partial Regex Placeholder();
}
```

`Integrations/Email/Templates/login-code.txt`:

```text
Your ExtraSpace sign-in code is {{code}}

It expires in {{minutes}} minutes. If you did not ask for it, you can ignore this email.
```

`Integrations/Email/Templates/login-code.html`:

```html
<!doctype html>
<html lang="en">
<body style="margin:0;padding:24px;background:#f5f5f5;font-family:Arial,Helvetica,sans-serif;color:#222">
  <table role="presentation" width="100%" style="max-width:480px;margin:0 auto;background:#fff;border-radius:8px;padding:24px">
    <tr><td>
      <p style="margin:0 0 16px">Your ExtraSpace sign-in code is</p>
      <p style="margin:0 0 16px;font-size:32px;font-weight:bold;letter-spacing:6px">{{code}}</p>
      <p style="margin:0;color:#666">It expires in {{minutes}} minutes. If you did not ask for it, you can ignore this email.</p>
    </td></tr>
  </table>
</body>
</html>
```

`Integrations/Email/HangfireEmailSender.cs`:

```csharp
using System.Text.Json;
using Hangfire;
using Microsoft.AspNetCore.DataProtection;

namespace ExtraSpace.Api.Integrations.Email;

internal sealed record EmailPayload(string To, Dictionary<string, string> Values);

internal sealed class HangfireEmailSender(IBackgroundJobClient jobs, IDataProtectionProvider protection) : IEmailSender
{
    internal const string Purpose = "ExtraSpace.Integrations.Email.v1";

    public string Enqueue(EmailMessage message)
    {
        EmailTemplates.EnsureKnown(message.Template);
        var payload = JsonSerializer.Serialize(new EmailPayload(message.To, new Dictionary<string, string>(message.Values)));
        var sealedPayload = protection.CreateProtector(Purpose).ToTimeLimitedDataProtector().Protect(payload, message.ValidFor);
        return jobs.Enqueue<EmailJob>(job => job.SendAsync(message.Template, sealedPayload, CancellationToken.None));
    }
}
```

`Integrations/Email/EmailJob.cs`:

```csharp
using System.Security.Cryptography;
using System.Text.Json;
using ExtraSpace.Api.Platform.Logging;
using Hangfire;
using Microsoft.AspNetCore.DataProtection;

namespace ExtraSpace.Api.Integrations.Email;

public sealed partial class EmailJob(IDataProtectionProvider protection, IEmailTransport transport, ILogger<EmailJob> logger)
{
    [AutomaticRetry(Attempts = 5, LogEvents = false)]
    public async Task SendAsync(string template, string payload, CancellationToken cancellationToken)
    {
        EmailPayload message;
        try
        {
            var json = protection.CreateProtector(HangfireEmailSender.Purpose).ToTimeLimitedDataProtector().Unprotect(payload);
            message = JsonSerializer.Deserialize<EmailPayload>(json)!;
        }
        catch (CryptographicException)
        {
            // Past its ValidFor (or the key ring lost the key): sending a stale login code helps nobody, so no retry.
            LogExpired(logger, template);
            return;
        }

        await transport.SendAsync(EmailTemplates.Render(template, message.To, message.Values), cancellationToken);
        LogSent(logger, template, Pii.MaskEmail(message.To));
    }

    [LoggerMessage(Level = LogLevel.Warning, Message = "Email {template} expired before it was sent")]
    private static partial void LogExpired(ILogger logger, string template);

    [LoggerMessage(Level = LogLevel.Information, Message = "Email {template} sent to {email}")]
    private static partial void LogSent(ILogger logger, string template, string email);
}
```

`Integrations/Email/SesEmailTransport.cs`:

```csharp
using System.Diagnostics;
using Amazon.Runtime;
using Amazon.SimpleEmailV2;
using Amazon.SimpleEmailV2.Model;
using Microsoft.Extensions.Options;

namespace ExtraSpace.Api.Integrations.Email;

/// <summary>AWS SES v2. One log line per call (S0 spec §4.4); the job logs the exception and Hangfire retries.</summary>
internal sealed partial class SesEmailTransport(
    IAmazonSimpleEmailServiceV2 ses, IOptions<EmailOptions> options, ILogger<SesEmailTransport> logger) : IEmailTransport
{
    public async Task SendAsync(RenderedEmail email, CancellationToken cancellationToken)
    {
        var started = Stopwatch.GetTimestamp();
        try
        {
            var response = await ses.SendEmailAsync(ToRequest(email, options.Value.From), cancellationToken);
            LogCall(logger, "ses", "SendEmail", "ok", (int)response.HttpStatusCode, Elapsed(started));
        }
        catch (AmazonServiceException e)
        {
            LogCallFailed(logger, "ses", "SendEmail", "error", (int)e.StatusCode, Elapsed(started));
            throw;
        }
        catch (Exception e) when (e is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            LogCallFailed(logger, "ses", "SendEmail", e is OperationCanceledException ? "timeout" : "error", 0, Elapsed(started));
            throw;
        }
    }

    internal static SendEmailRequest ToRequest(RenderedEmail email, string from) => new()
    {
        FromEmailAddress = from,
        Destination = new Destination { ToAddresses = [email.To] },
        Content = new EmailContent
        {
            Simple = new Message
            {
                Subject = new Content { Data = email.Subject, Charset = "UTF-8" },
                Body = new Body
                {
                    Html = new Content { Data = email.Html, Charset = "UTF-8" },
                    Text = new Content { Data = email.Text, Charset = "UTF-8" },
                },
            },
        },
    };

    private static long Elapsed(long started) => (long)Stopwatch.GetElapsedTime(started).TotalMilliseconds;

    [LoggerMessage(Level = LogLevel.Information, Message = "Outside call {integration} {operation}: {outcome} in {elapsedMs} ms")]
    private static partial void LogCall(ILogger logger, string integration, string operation, string outcome, int httpStatus, long elapsedMs);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Outside call {integration} {operation}: {outcome} in {elapsedMs} ms")]
    private static partial void LogCallFailed(ILogger logger, string integration, string operation, string outcome, int httpStatus, long elapsedMs);
}
```

Note: a `[LoggerMessage]` parameter that is not in the template (`httpStatus`) is still logged as a property, which is what we want (spec §4.4 `httpStatus`). If the generator warns about it, keep it as a property by adding `{httpStatus}` to the end of the message: `... in {elapsedMs} ms (HTTP {httpStatus})`.

`Integrations/Email/LogEmailTransport.cs`:

```csharp
namespace ExtraSpace.Api.Integrations.Email;

/// <summary>Development only (S0 spec §9.1): prints the whole email, login code included, so sign-in works without SES.</summary>
internal sealed partial class LogEmailTransport(ILogger<LogEmailTransport> logger) : IEmailTransport
{
    public Task SendAsync(RenderedEmail email, CancellationToken cancellationToken)
    {
        LogEmail(logger, email.To, email.Subject, email.Text);
        return Task.CompletedTask;
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "Development email to {to}: {subject}\n{text}")]
    private static partial void LogEmail(ILogger logger, string to, string subject, string text);
}
```

`Integrations/Email/EmailSetup.cs`:

```csharp
using Amazon.SimpleEmailV2;

namespace ExtraSpace.Api.Integrations.Email;

public static class EmailSetup
{
    public static IServiceCollection AddEmail(this IServiceCollection services, IConfiguration configuration, IHostEnvironment environment)
    {
        services.AddOptions<EmailOptions>().Bind(configuration.GetSection(EmailOptions.Section))
            .Validate(o => o.Transport != EmailTransport.Ses || o.From.Length > 0, "Email:From must be set when Email:Transport is Ses")
            .ValidateOnStart();
        services.AddSingleton<IEmailSender, HangfireEmailSender>();
        services.AddScoped<EmailJob>();

        var transport = configuration.GetSection(EmailOptions.Section).Get<EmailOptions>()?.Transport ?? EmailTransport.Ses;
        switch (transport)
        {
            case EmailTransport.Ses:
                var aws = configuration.GetAWSOptions();
                aws.DefaultClientConfig.MaxErrorRetry = 0;          // the Hangfire job retries instead (5 attempts)
                aws.DefaultClientConfig.Timeout = TimeSpan.FromSeconds(10);
                services.AddDefaultAWSOptions(aws);
                services.AddAWSService<IAmazonSimpleEmailServiceV2>();
                services.AddSingleton<IEmailTransport, SesEmailTransport>();
                break;
            case EmailTransport.Log when environment.IsDevelopment():
                services.AddSingleton<IEmailTransport, LogEmailTransport>();
                break;
            case EmailTransport.Log:
                throw new InvalidOperationException("Email:Transport=Log prints login codes and is allowed in Development only.");
        }
        return services;
    }
}
```

In `Program.cs`, after `builder.Services.AddPlatform(builder.Configuration);`, add `builder.Services.AddEmail(builder.Configuration, builder.Environment);`.

Configuration changes:
- `appsettings.json`: add `"Email": { "Transport": "Ses", "From": "" }` and `"AWS": { "Region": "ap-southeast-1" }`.
- `appsettings.Development.json`: add `"Email": { "Transport": "Log" }`.
- 🔴 Never add `AWS:Profile` anywhere. On AWS the task role gives the credentials, and local runs use `Log`.

- [ ] **Step 4: Run the tests.** Run `--filter-class "*EmailTests"`, then the full API suite: everything passes.

- [ ] **Step 5: Hand-off.** Write the report and stop.

---

### Task 3: Identity data, JWT sign-in scheme, the `/api/v1` group and `GET /api/v1/me`

**Files:**
- Modify: `src/ExtraSpace.Api/ExtraSpace.Api.csproj` (JwtBearer), `src/ExtraSpace.Api/Program.cs`, `src/ExtraSpace.Api/appsettings.json`
- Create: `src/ExtraSpace.Api/Features/Identity/` (`Customer.cs`, `CustomerLoginCode.cs`, `CustomerRefreshToken.cs`, `IdentityEntityConfigurations.cs`, `CustomerAuthOptions.cs`, `CustomerAuth.cs`, `AccessTokens.cs`, `CustomerService.cs`, `IdentityDtos.cs`, `IdentityEndpoints.cs`, `Contracts/CustomerPrincipal.cs`)
- Create: migration `AddCustomerIdentity` in `src/ExtraSpace.Api/Platform/Data/Migrations/` (3 files, BOM stripped)
- Modify (tests): `ApiFactory.cs`, `Platform/ApiDocsTests.cs` (one new test)
- Create (tests): `tests/ExtraSpace.Api.Tests/TestSupport/IdentityTestData.cs`, `tests/ExtraSpace.Api.Tests/Features/Identity/MeTests.cs`, `IdentityDataTests.cs`

**Interfaces:**
- Consumes: `AppDbContext` (applies every `IEntityTypeConfiguration` in the assembly), `IHasTimestamps`, `RequestLog.Add`, `AppException`, `ErrorCodes`, `EnumArgumentsFilter.WithEnumGuard`.
- Produces (Tasks 4–5 rely on these exact names):
  - entities `Customer`, `CustomerLoginCode` and `CustomerRefreshToken` (properties below);
  - `CustomerAuth.Scheme = "Customer"`, `CustomerAuth.Policy = "Customer"`, `CustomerAuth.AddIdentityFeature(this IServiceCollection, IConfiguration)`;
  - `AccessTokens.Issue(Guid customerId, string email) → (string Token, DateTime ExpiresAt)`;
  - `CustomerPrincipal.CustomerId(this ClaimsPrincipal) → Guid?`;
  - `IdentityEndpoints.RequireCustomer(this RouteGroupBuilder)` and `IdentityEndpoints.MapIdentityEndpoints(this RouteGroupBuilder)`;
  - `IdentityErrors.Unauthenticated()`;
  - DTO `MeResponse(Guid Id, string Email, string? FirstName, string? LastName, string? Phone)`.

- [ ] **Step 1: Write the failing tests.** `TestSupport/IdentityTestData.cs`:

```csharp
using ExtraSpace.Api.Features.Identity;
using ExtraSpace.Api.Platform.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace ExtraSpace.Api.Tests.TestSupport;

public static class IdentityTestData
{
    /// <summary>Base64 of 48 bytes; a public, test-only signing key.</summary>
    public const string SigningKey = "dGVzdC1vbmx5LXNpZ25pbmcta2V5LW5vdC1hLXNlY3JldC0wMTIzNDU2Nzg5YWJjZA==";

    public static string NewEmail(string prefix = "c") => $"{prefix}-{Guid.NewGuid():N}@example.test";

    public static async Task WithDbAsync(this ApiFactory api, Func<AppDbContext, Task> action)
    {
        await using var scope = api.Services.CreateAsyncScope();
        await action(scope.ServiceProvider.GetRequiredService<AppDbContext>());
    }

    public static async Task<Customer> CreateCustomerAsync(this ApiFactory api, string? email = null)
    {
        var customer = new Customer { Email = email ?? NewEmail(), FirstName = "Jane", LastName = "Tan", Phone = "+6590000000" };
        await api.WithDbAsync(async db =>
        {
            db.Add(customer);
            await db.SaveChangesAsync();
        });
        return customer;
    }

    public static string AccessTokenFor(this ApiFactory api, Customer customer) =>
        api.Services.GetRequiredService<AccessTokens>().Issue(customer.Id, customer.Email).Token;

    /// <summary>A token our app did not issue in this shape: another key, or a lifetime already over.</summary>
    public static string ForgedToken(Guid customerId, string key = SigningKey, int expiresInMinutes = 15) =>
        new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = "extraspace",
            Audience = "extraspace-app",
            Claims = new Dictionary<string, object> { ["sub"] = customerId.ToString() },
            IssuedAt = DateTime.UtcNow.AddMinutes(-30),
            NotBefore = DateTime.UtcNow.AddMinutes(-30),
            Expires = DateTime.UtcNow.AddMinutes(expiresInMinutes),
            SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(Convert.FromBase64String(key)), SecurityAlgorithms.HmacSha256),
        });
}
```

In `ApiFactory.ConfigureWebHost`, add `builder.UseSetting("CustomerAuth:SigningKey", IdentityTestData.SigningKey);`.

`tests/ExtraSpace.Api.Tests/Features/Identity/MeTests.cs`:

```csharp
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using ExtraSpace.Api.Tests.TestSupport;

namespace ExtraSpace.Api.Tests.Features.Identity;

public sealed class MeTests(ApiFactory api)
{
    private readonly HttpClient _client = api.CreateClient();
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private Task<HttpResponseMessage> GetMeAsync(string? token, params (string Name, string Value)[] headers)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, "/api/v1/me");
        if (token is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        foreach (var (name, value) in headers) request.Headers.Add(name, value);
        return _client.SendAsync(request, Ct);
    }

    [Fact]
    public async Task A_signed_in_customer_gets_their_profile()
    {
        var customer = await api.CreateCustomerAsync();
        var response = await GetMeAsync(api.AccessTokenFor(customer));

        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(Ct);
        body.GetProperty("id").GetGuid().Should().Be(customer.Id);
        body.GetProperty("email").GetString().Should().Be(customer.Email);
        body.GetProperty("firstName").GetString().Should().Be("Jane");
        body.GetProperty("lastName").GetString().Should().Be("Tan");
        body.GetProperty("phone").GetString().Should().Be("+6590000000");
    }

    [Fact]
    public async Task No_token_is_401() =>
        await Problem.ReadAsync(await GetMeAsync(null), 401, "UNAUTHENTICATED");

    [Fact]
    public async Task A_token_signed_with_another_key_is_401() =>
        await Problem.ReadAsync(await GetMeAsync(IdentityTestData.ForgedToken(Guid.CreateVersion7(),
            key: Convert.ToBase64String(new byte[48]))), 401, "UNAUTHENTICATED");

    [Fact]
    public async Task An_expired_token_is_401()
    {
        var customer = await api.CreateCustomerAsync();
        await Problem.ReadAsync(await GetMeAsync(IdentityTestData.ForgedToken(customer.Id, expiresInMinutes: -5)), 401, "UNAUTHENTICATED");
    }

    [Fact]
    public async Task A_token_for_a_deleted_customer_is_401() =>
        await Problem.ReadAsync(await GetMeAsync(IdentityTestData.ForgedToken(Guid.CreateVersion7())), 401, "UNAUTHENTICATED");

    [Fact]
    public async Task An_outdated_app_gets_426_before_sign_in_is_checked() =>
        await Problem.ReadAsync(await GetMeAsync(null, ("X-App-Platform", "ios"), ("X-App-Version", "1.0.0")), 426, "APP_UPDATE_REQUIRED");

    [Fact]
    public async Task Signed_in_requests_log_the_customer_id()
    {
        var customer = await api.CreateCustomerAsync();
        var response = await GetMeAsync(api.AccessTokenFor(customer));
        var summary = api.Logs.LinesFor(Problem.TraceIdOf(response)).Single(l => l.GetProperty("messageTemplate").GetString() == "HTTP {method} {route} responded {status} in {elapsedMs} ms");
        summary.GetProperty("customerId").GetString().Should().Be(customer.Id.ToString());
    }

    [Fact]
    public async Task The_access_token_has_the_spec_claims_and_lifetime()
    {
        var customer = await api.CreateCustomerAsync();
        var token = new Microsoft.IdentityModel.JsonWebTokens.JsonWebToken(api.AccessTokenFor(customer));
        token.Subject.Should().Be(customer.Id.ToString());
        token.GetClaim("email").Value.Should().Be(customer.Email);
        token.Issuer.Should().Be("extraspace");
        token.Audiences.Should().Equal("extraspace-app");
        token.Alg.Should().Be("HS256");
        (token.ValidTo - token.IssuedAt).Should().Be(TimeSpan.FromMinutes(15));
    }
}
```

`tests/ExtraSpace.Api.Tests/Features/Identity/IdentityDataTests.cs`:

```csharp
using ExtraSpace.Api.Features.Identity;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Tests.Features.Identity;

public sealed class IdentityDataTests(ApiFactory api)
{
    [Fact]
    public async Task Customer_email_is_unique()
    {
        var email = IdentityTestData.NewEmail();
        await api.CreateCustomerAsync(email);
        var duplicate = () => api.CreateCustomerAsync(email);
        await duplicate.Should().ThrowAsync<DbUpdateException>();
    }

    [Fact]
    public async Task Refresh_tokens_and_login_codes_round_trip_with_utc_times()
    {
        var customer = await api.CreateCustomerAsync();
        var expires = new DateTime(2030, 1, 2, 3, 4, 5, DateTimeKind.Utc);
        await api.WithDbAsync(async db =>
        {
            db.Add(new CustomerRefreshToken { CustomerId = customer.Id, FamilyId = Guid.CreateVersion7(), TokenHash = new string('a', 64), ExpiresAt = expires });
            db.Add(new CustomerLoginCode { Email = IdentityTestData.NewEmail(), CodeHash = new string('b', 64), ExpiresAt = expires, LastSentAt = expires, WindowStartedAt = expires });
            await db.SaveChangesAsync();
        });
        await api.WithDbAsync(async db =>
        {
            var token = await db.Set<CustomerRefreshToken>().SingleAsync(t => t.CustomerId == customer.Id);
            token.ExpiresAt.Should().Be(expires);
            token.ExpiresAt.Kind.Should().Be(DateTimeKind.Utc);
        });
    }
}
```

In `ApiDocsTests`, add a test asserting that the document has `components.securitySchemes.Bearer` with `type = "http"`, `scheme = "bearer"` and `bearerFormat = "JWT"`. Follow the file's existing pattern for reading `/openapi/v1.json`.

- [ ] **Step 2: Run them to see them fail** (they do not compile).

- [ ] **Step 3: Entities and configurations.** `Features/Identity/Customer.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;

namespace ExtraSpace.Api.Features.Identity;

/// <summary>An app customer (S0 spec §5.1). Created at the first verified sign-in; email stored trimmed and lower-case.</summary>
public sealed class Customer : IHasTimestamps
{
    public Guid Id { get; init; } = Guid.CreateVersion7();
    public required string Email { get; set; }
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public string? Phone { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
```

`Features/Identity/CustomerLoginCode.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;

namespace ExtraSpace.Api.Features.Identity;

/// <summary>
/// One row per email (plan decision 2): the active code plus the per-email send limits. A new request overwrites the code.
/// </summary>
public sealed class CustomerLoginCode : IHasTimestamps
{
    public Guid Id { get; init; } = Guid.CreateVersion7();
    public required string Email { get; init; }
    public string CodeHash { get; set; } = "";
    public DateTime ExpiresAt { get; set; }
    public int Attempts { get; set; }
    public DateTime? ConsumedAt { get; set; }
    public string? RequestIp { get; set; }
    public DateTime LastSentAt { get; set; }
    public DateTime WindowStartedAt { get; set; }
    public int SentInWindow { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
```

`Features/Identity/CustomerRefreshToken.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;

namespace ExtraSpace.Api.Features.Identity;

/// <summary>A rotated refresh token (S0 spec §6.1). Only its SHA-256 hash is stored; a family is one sign-in session.</summary>
public sealed class CustomerRefreshToken : IHasTimestamps
{
    public Guid Id { get; init; } = Guid.CreateVersion7();
    public Guid CustomerId { get; init; }
    public Guid FamilyId { get; init; }
    public required string TokenHash { get; init; }
    public DateTime ExpiresAt { get; init; }
    public Guid? ReplacedById { get; set; }
    public DateTime? RevokedAt { get; set; }
    public string? UserAgent { get; init; }
    public string? Ip { get; init; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
```

`Features/Identity/IdentityEntityConfigurations.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace ExtraSpace.Api.Features.Identity;

internal sealed class CustomerConfiguration : IEntityTypeConfiguration<Customer>
{
    public void Configure(EntityTypeBuilder<Customer> builder)
    {
        builder.ToTable("customer");
        builder.Property(c => c.Id).ValueGeneratedNever();
        builder.Property(c => c.Email).HasMaxLength(254);
        builder.HasIndex(c => c.Email).IsUnique();
        builder.Property(c => c.FirstName).HasMaxLength(100);
        builder.Property(c => c.LastName).HasMaxLength(100);
        builder.Property(c => c.Phone).HasMaxLength(32);
    }
}

internal sealed class CustomerLoginCodeConfiguration : IEntityTypeConfiguration<CustomerLoginCode>
{
    public void Configure(EntityTypeBuilder<CustomerLoginCode> builder)
    {
        builder.ToTable("customer_login_code");
        builder.Property(c => c.Id).ValueGeneratedNever();
        builder.Property(c => c.Email).HasMaxLength(254);
        builder.HasIndex(c => c.Email).IsUnique();
        builder.Property(c => c.CodeHash).HasMaxLength(64);
        builder.Property(c => c.RequestIp).HasMaxLength(45);
        builder.HasIndex(c => c.ExpiresAt);
    }
}

internal sealed class CustomerRefreshTokenConfiguration : IEntityTypeConfiguration<CustomerRefreshToken>
{
    public void Configure(EntityTypeBuilder<CustomerRefreshToken> builder)
    {
        builder.ToTable("customer_refresh_token");
        builder.Property(t => t.Id).ValueGeneratedNever();
        builder.Property(t => t.TokenHash).HasMaxLength(64);
        builder.HasIndex(t => t.TokenHash).IsUnique();
        builder.HasIndex(t => t.FamilyId);
        builder.HasIndex(t => t.ExpiresAt);
        builder.Property(t => t.UserAgent).HasMaxLength(256);
        builder.Property(t => t.Ip).HasMaxLength(45);
        builder.HasOne<Customer>().WithMany().HasForeignKey(t => t.CustomerId).OnDelete(DeleteBehavior.Cascade);
    }
}
```

- [ ] **Step 4: Options, tokens, service, endpoints.** `Features/Identity/CustomerAuthOptions.cs`:

```csharp
namespace ExtraSpace.Api.Features.Identity;

public sealed class CustomerAuthOptions
{
    public const string Section = "CustomerAuth";

    public string Issuer { get; set; } = "extraspace";
    public string Audience { get; set; } = "extraspace-app";

    /// <summary>Base64 of at least 32 random bytes. From Secrets Manager on AWS and user-secrets locally; never a committed file.</summary>
    public string SigningKey { get; set; } = "";

    internal byte[] SigningKeyBytes() => Convert.FromBase64String(SigningKey);

    internal static bool IsValidKey(string key)
    {
        try
        {
            return Convert.FromBase64String(key).Length >= 32;
        }
        catch (FormatException)
        {
            return false;
        }
    }
}
```

`Features/Identity/AccessTokens.cs`:

```csharp
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace ExtraSpace.Api.Features.Identity;

/// <summary>Issues the 15-minute customer JWT (S0 spec §6.1): HS256, claims sub, email, iss, aud.</summary>
public sealed class AccessTokens(IOptions<CustomerAuthOptions> options, TimeProvider time)
{
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(15);
    private readonly JsonWebTokenHandler _handler = new();

    public (string Token, DateTime ExpiresAt) Issue(Guid customerId, string email)
    {
        var auth = options.Value;
        var now = time.GetUtcNow().UtcDateTime;
        var expires = now + Lifetime;
        var token = _handler.CreateToken(new SecurityTokenDescriptor
        {
            Issuer = auth.Issuer,
            Audience = auth.Audience,
            Claims = new Dictionary<string, object>
            {
                [JwtRegisteredClaimNames.Sub] = customerId.ToString(),
                [JwtRegisteredClaimNames.Email] = email,
            },
            IssuedAt = now,
            NotBefore = now,
            Expires = expires,
            SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(auth.SigningKeyBytes()), SecurityAlgorithms.HmacSha256),
        });
        return (token, expires);
    }
}
```

`Features/Identity/Contracts/CustomerPrincipal.cs`:

```csharp
using System.Security.Claims;

namespace ExtraSpace.Api.Features.Identity.Contracts;

public static class CustomerPrincipal
{
    /// <summary>The signed-in customer's id (JWT <c>sub</c>), or null when the request is anonymous.</summary>
    public static Guid? CustomerId(this ClaimsPrincipal user) =>
        Guid.TryParse(user.FindFirstValue("sub"), out var id) ? id : null;
}
```

`Features/Identity/IdentityDtos.cs`:

```csharp
namespace ExtraSpace.Api.Features.Identity;

public sealed record MeResponse(Guid Id, string Email, string? FirstName, string? LastName, string? Phone);
```

`Features/Identity/CustomerService.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Identity;

public sealed class CustomerService(AppDbContext db)
{
    public Task<MeResponse?> GetMeAsync(Guid customerId, CancellationToken cancellationToken) =>
        db.Set<Customer>().AsNoTracking()
            .Where(c => c.Id == customerId)
            .Select(c => new MeResponse(c.Id, c.Email, c.FirstName, c.LastName, c.Phone))
            .SingleOrDefaultAsync(cancellationToken);
}
```

`Features/Identity/IdentityEndpoints.cs`:

```csharp
using System.Security.Claims;
using ExtraSpace.Api.Features.Identity.Contracts;
using ExtraSpace.Api.Platform.Errors;
using ExtraSpace.Api.Platform.Logging;
using Microsoft.AspNetCore.Http.HttpResults;

namespace ExtraSpace.Api.Features.Identity;

public static class IdentityEndpoints
{
    /// <summary>Every route of the group needs a signed-in customer unless it says <c>.AllowAnonymous()</c>.</summary>
    public static RouteGroupBuilder RequireCustomer(this RouteGroupBuilder group)
    {
        group.RequireAuthorization(CustomerAuth.Policy);
        group.AddEndpointFilter(static (context, next) =>
        {
            if (context.HttpContext.User.CustomerId() is { } customerId) RequestLog.Add(context.HttpContext, "customerId", customerId);
            return next(context);
        });
        return group;
    }

    public static RouteGroupBuilder MapIdentityEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/me", GetMe).WithTags("Me");
        return api;
    }

    private static async Task<Ok<MeResponse>> GetMe(ClaimsPrincipal user, CustomerService customers, CancellationToken cancellationToken) =>
        TypedResults.Ok(await customers.GetMeAsync(user.CustomerId() ?? throw IdentityErrors.Unauthenticated(), cancellationToken)
            ?? throw IdentityErrors.Unauthenticated());
}

internal static class IdentityErrors
{
    public static AppException Unauthenticated() => new(401, ErrorCodes.Unauthenticated, "Sign in again.");
}
```

`Features/Identity/CustomerAuth.cs`:

```csharp
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi;

namespace ExtraSpace.Api.Features.Identity;

public static class CustomerAuth
{
    public const string Scheme = "Customer";
    public const string Policy = "Customer";

    public static IServiceCollection AddIdentityFeature(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<CustomerAuthOptions>().Bind(configuration.GetSection(CustomerAuthOptions.Section))
            .Validate(o => CustomerAuthOptions.IsValidKey(o.SigningKey), "CustomerAuth:SigningKey must be base64 of at least 32 bytes")
            .ValidateOnStart();

        services.AddAuthentication().AddJwtBearer(Scheme);
        services.AddOptions<JwtBearerOptions>(Scheme).Configure<IOptions<CustomerAuthOptions>>((jwt, auth) =>
        {
            jwt.MapInboundClaims = false;   // keep `sub` as `sub`
            jwt.TokenValidationParameters = new TokenValidationParameters
            {
                ValidIssuer = auth.Value.Issuer,
                ValidAudience = auth.Value.Audience,
                IssuerSigningKey = new SymmetricSecurityKey(auth.Value.SigningKeyBytes()),
                ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
                ClockSkew = TimeSpan.FromSeconds(30),
                NameClaimType = JwtRegisteredClaimNames.Sub,
            };
        });
        services.AddAuthorizationBuilder()
            .AddPolicy(Policy, p => p.AddAuthenticationSchemes(Scheme).RequireAuthenticatedUser());

        services.AddSingleton<AccessTokens>();
        services.AddScoped<CustomerService>();

        // Swagger UI's "Authorize" button: paste the accessToken from /api/v1/auth/code/verify.
        services.Configure<OpenApiOptions>("v1", o => o.AddDocumentTransformer((document, _, _) =>
        {
            document.Components ??= new OpenApiComponents();
            document.Components.SecuritySchemes ??= new Dictionary<string, IOpenApiSecurityScheme>();
            document.Components.SecuritySchemes["Bearer"] = new OpenApiSecurityScheme
            {
                Type = SecuritySchemeType.Http,
                Scheme = "bearer",
                BearerFormat = "JWT",
                Description = "Customer access token from POST /api/v1/auth/code/verify",
            };
            document.Security = [new OpenApiSecurityRequirement { [new OpenApiSecuritySchemeReference("Bearer", document)] = [] }];
            return Task.CompletedTask;
        }));
        return services;
    }
}
```

Note: the `Microsoft.OpenApi` 2.x type names above (`IOpenApiSecurityScheme`, `OpenApiSecuritySchemeReference`, `document.Security`) are written from memory. Check them against the package the project already restores and adapt the code; the `ApiDocsTests` assertion is the contract. If the JWT bearer handler writes a body on its 401 challenge (it should not), the `No_token_is_401` problem-shape test will show it.

In `ExtraSpace.Api.csproj`, add the `Microsoft.AspNetCore.Authentication.JwtBearer` `PackageReference`. In `appsettings.json`, add `"CustomerAuth": { "Issuer": "extraspace", "Audience": "extraspace-app" }`; the `SigningKey` never goes in a committed file.

`Program.cs`: after `AddEmail`, add `builder.Services.AddIdentityFeature(builder.Configuration);`. Then replace the step-14 lines with:

```csharp
                                                    // 14: feature endpoints, each Features/<X>/<X>Endpoints.cs; groups only, never handlers here
var api = app.MapGroup("/api/v1").RequireCustomer().WithEnumGuard();   // customer API; public routes opt out with .AllowAnonymous()
api.MapIdentityEndpoints();
foreach (var mapper in app.Services.GetServices<IEndpointMapper>()) mapper.Map(app);
```

- [ ] **Step 5: Migration.**

```bash
cd "/Users/waiyanmin/Projects/Extra Space/CMS"
dotnet tool restore
dotnet ef migrations add AddCustomerIdentity --project src/ExtraSpace.Api --output-dir Platform/Data/Migrations
```

Strip the BOM from the three changed or new migration files (`sed -i '' '1s/^\xEF\xBB\xBF//' <file>`). Read the generated `Up`: three tables, unique `email` on `customer` and `customer_login_code`, unique `token_hash`, indexes on `family_id`, `expires_at` and `customer_id`, and the cascade FK. Report anything else in it.

- [ ] **Step 6: Run the tests.** Run `--filter-class "*MeTests"`, `*IdentityDataTests` and `*ApiDocsTests`, then the full suite, and the architecture test in particular: `IdentityEndpoints` must not touch the `DbContext`.

- [ ] **Step 7: Hand-off.** Write the report and stop.

---

### Task 4: The code flow (`POST /api/v1/auth/code`, `/auth/code/verify`) with its limits

**Files:**
- Modify: `src/ExtraSpace.Api/Platform/Errors/AppException.cs`, `AppExceptionHandler.cs` (Retry-After)
- Create: `src/ExtraSpace.Api/Features/Identity/` (`LoginCodeHasher.cs`, `LoginCodeService.cs`, `TokenService.cs`, `EmailAddresses.cs`)
- Modify: `Features/Identity/IdentityDtos.cs`, `IdentityEndpoints.cs`, `CustomerAuth.cs`
- Modify (tests): `ApiFactory.cs` (`ClientWithIp`)
- Create (tests): `tests/ExtraSpace.Api.Tests/TestSupport/AuthFlow.cs`, `tests/ExtraSpace.Api.Tests/Features/Identity/LoginCodeTests.cs`

**Interfaces:**
- Consumes:
  - from Task 3: the entities, `AccessTokens`, `IdentityErrors`, `CustomerAuth`;
  - from Task 2: `IEmailSender`, `EmailMessage` (template `login-code`, values `code`, `minutes`).
- Produces (Task 5 relies on these):
  - `TokenService` (`internal SignIn StartSession(Customer, string? ip, string? userAgent)`, `internal static string Hash(string token)`);
  - `public sealed record TokenResponse(string AccessToken, DateTime AccessTokenExpiresAt, string RefreshToken, DateTime RefreshTokenExpiresAt)`;
  - `public sealed record SignIn(Guid CustomerId, TokenResponse Tokens)`;
  - `AppException.RetryAfter`;
  - the test helpers `ApiFactory.ClientWithIp()` and `AuthFlow.SignInAsync(...)`.

- [ ] **Step 1: Write the failing tests.** In `ApiFactory`, add:

```csharp
    private static int _ip;

    /// <summary>A client with its own X-Forwarded-For address, so per-IP limits of one test never hit another.</summary>
    public HttpClient ClientWithIp()
    {
        var n = Interlocked.Increment(ref _ip);
        var client = CreateClient();
        client.DefaultRequestHeaders.Add("X-Forwarded-For", $"10.{(n >> 16) & 255}.{(n >> 8) & 255}.{n & 255}");
        return client;
    }
```

`TestSupport/AuthFlow.cs`:

```csharp
using System.Net.Http.Json;
using System.Text.Json;

namespace ExtraSpace.Api.Tests.TestSupport;

public static class AuthFlow
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    public static Task<HttpResponseMessage> RequestCodeAsync(this HttpClient client, string email) =>
        client.PostAsJsonAsync("/api/v1/auth/code", new { email }, Ct);

    public static Task<HttpResponseMessage> VerifyAsync(this HttpClient client, string email, string code) =>
        client.PostAsJsonAsync("/api/v1/auth/code/verify", new { email, code }, Ct);

    /// <summary>Request a code, read it from the fake email, verify it; returns the token response body.</summary>
    public static async Task<JsonElement> SignInAsync(this ApiFactory api, HttpClient client, string email)
    {
        var sentBefore = api.Emails.SentTo(email.Trim().ToLowerInvariant()).Count;
        (await client.RequestCodeAsync(email)).StatusCode.Should().Be(System.Net.HttpStatusCode.Accepted);
        var code = await api.Emails.CodeForAsync(email.Trim().ToLowerInvariant(), sentBefore + 1);
        var response = await client.VerifyAsync(email, code);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<JsonElement>(Ct);
    }
}
```

`tests/ExtraSpace.Api.Tests/Features/Identity/LoginCodeTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using ExtraSpace.Api.Features.Identity;
using ExtraSpace.Api.Platform.Logging;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Tests.Features.Identity;

public sealed class LoginCodeTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private static string? Str(JsonElement line, string name) =>
        line.TryGetProperty(name, out var value) ? value.ToString() : null;

    private Task SetCodeRowAsync(string email, Action<CustomerLoginCode> change) =>
        api.WithDbAsync(async db =>
        {
            var row = await db.Set<CustomerLoginCode>().SingleAsync(c => c.Email == email, Ct);
            change(row);
            await db.SaveChangesAsync(Ct);
        });

    [Fact]
    public async Task A_code_signs_the_customer_in_and_the_token_works()
    {
        var client = api.ClientWithIp();
        var email = IdentityTestData.NewEmail();

        var request = await client.RequestCodeAsync(email);
        request.StatusCode.Should().Be(HttpStatusCode.Accepted);
        (await request.Content.ReadAsStringAsync(Ct)).Should().BeEmpty();

        var code = await api.Emails.CodeForAsync(email);
        var verify = await client.VerifyAsync(email, code);
        verify.EnsureSuccessStatusCode();
        var tokens = JsonDocument.Parse(await verify.Content.ReadAsStringAsync(Ct)).RootElement;
        tokens.GetProperty("refreshToken").GetString().Should().MatchRegex("^[A-Za-z0-9_-]{43}$");
        tokens.GetProperty("accessTokenExpiresAt").GetString().Should().EndWith("Z");

        using var me = new HttpRequestMessage(HttpMethod.Get, "/api/v1/me");
        me.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokens.GetProperty("accessToken").GetString());
        var profile = await client.SendAsync(me, Ct);
        profile.EnsureSuccessStatusCode();

        await api.WithDbAsync(async db => (await db.Set<Customer>().CountAsync(c => c.Email == email, Ct)).Should().Be(1));
    }

    [Fact]
    public async Task A_second_sign_in_reuses_the_customer()
    {
        var email = IdentityTestData.NewEmail();
        await api.SignInAsync(api.ClientWithIp(), email);
        await SetCodeRowAsync(email, r => r.LastSentAt = r.LastSentAt.AddMinutes(-2));
        await api.SignInAsync(api.ClientWithIp(), email);
        await api.WithDbAsync(async db => (await db.Set<Customer>().CountAsync(c => c.Email == email, Ct)).Should().Be(1));
    }

    [Fact]
    public async Task Email_case_and_spaces_do_not_matter()
    {
        var email = IdentityTestData.NewEmail();
        var client = api.ClientWithIp();
        (await client.RequestCodeAsync("  " + email.ToUpperInvariant() + " ")).StatusCode.Should().Be(HttpStatusCode.Accepted);
        var code = await api.Emails.CodeForAsync(email);
        (await client.VerifyAsync(email, code)).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task Known_and_unknown_emails_get_the_same_answer()
    {
        var known = (await api.CreateCustomerAsync()).Email;
        var unknown = IdentityTestData.NewEmail();
        var client = api.ClientWithIp();
        var a = await client.RequestCodeAsync(known);
        var b = await client.RequestCodeAsync(unknown);
        a.StatusCode.Should().Be(HttpStatusCode.Accepted);
        b.StatusCode.Should().Be(HttpStatusCode.Accepted);
        (await a.Content.ReadAsStringAsync(Ct)).Should().Be(await b.Content.ReadAsStringAsync(Ct));
        await api.Emails.WaitForAsync(known);
        await api.Emails.WaitForAsync(unknown);
    }

    [Fact]
    public async Task Five_wrong_codes_lock_the_code()
    {
        var email = IdentityTestData.NewEmail();
        var client = api.ClientWithIp();
        await client.RequestCodeAsync(email);
        var code = await api.Emails.CodeForAsync(email);
        var wrong = code == "000000" ? "111111" : "000000";

        for (var i = 1; i <= 4; i++) await Problem.ReadAsync(await client.VerifyAsync(email, wrong), 400, "INVALID_CODE");
        await Problem.ReadAsync(await client.VerifyAsync(email, wrong), 400, "TOO_MANY_ATTEMPTS");
        await Problem.ReadAsync(await client.VerifyAsync(email, code), 400, "TOO_MANY_ATTEMPTS");
    }

    [Fact]
    public async Task An_expired_code_is_invalid()
    {
        var email = IdentityTestData.NewEmail();
        var client = api.ClientWithIp();
        await client.RequestCodeAsync(email);
        var code = await api.Emails.CodeForAsync(email);
        await SetCodeRowAsync(email, r => r.ExpiresAt = DateTime.UtcNow.AddSeconds(-1));
        await Problem.ReadAsync(await client.VerifyAsync(email, code), 400, "INVALID_CODE");
    }

    [Fact]
    public async Task A_code_works_once()
    {
        var email = IdentityTestData.NewEmail();
        var client = api.ClientWithIp();
        await client.RequestCodeAsync(email);
        var code = await api.Emails.CodeForAsync(email);
        (await client.VerifyAsync(email, code)).EnsureSuccessStatusCode();
        await Problem.ReadAsync(await client.VerifyAsync(email, code), 400, "INVALID_CODE");
    }

    [Fact]
    public async Task An_unknown_email_is_invalid_not_404() =>
        await Problem.ReadAsync(await api.ClientWithIp().VerifyAsync(IdentityTestData.NewEmail(), "123456"), 400, "INVALID_CODE");

    [Fact]
    public async Task A_new_request_replaces_the_old_code()
    {
        var email = IdentityTestData.NewEmail();
        var client = api.ClientWithIp();
        await client.RequestCodeAsync(email);
        var first = await api.Emails.CodeForAsync(email);
        await SetCodeRowAsync(email, r => r.LastSentAt = r.LastSentAt.AddSeconds(-61));
        (await client.RequestCodeAsync(email)).StatusCode.Should().Be(HttpStatusCode.Accepted);
        var second = await api.Emails.CodeForAsync(email, 2);
        if (first != second) await Problem.ReadAsync(await client.VerifyAsync(email, first), 400, "INVALID_CODE");
        (await client.VerifyAsync(email, second)).EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task A_second_request_within_60_seconds_is_429_with_retry_after()
    {
        var email = IdentityTestData.NewEmail();
        var client = api.ClientWithIp();
        await client.RequestCodeAsync(email);
        var response = await client.RequestCodeAsync(email);
        await Problem.ReadAsync(response, 429, "RATE_LIMITED");
        response.Headers.RetryAfter!.Delta!.Value.TotalSeconds.Should().BeInRange(1, 60);
    }

    [Fact]
    public async Task The_sixth_request_in_an_hour_is_429()
    {
        var email = IdentityTestData.NewEmail();
        var client = api.ClientWithIp();
        await client.RequestCodeAsync(email);
        await SetCodeRowAsync(email, r =>
        {
            r.SentInWindow = 5;
            r.WindowStartedAt = DateTime.UtcNow.AddMinutes(-10);
            r.LastSentAt = DateTime.UtcNow.AddMinutes(-2);
        });
        var response = await client.RequestCodeAsync(email);
        await Problem.ReadAsync(response, 429, "RATE_LIMITED");
        response.Headers.RetryAfter!.Delta!.Value.TotalMinutes.Should().BeInRange(49, 51);
    }

    [Fact]
    public async Task The_hourly_window_resets()
    {
        var email = IdentityTestData.NewEmail();
        var client = api.ClientWithIp();
        await client.RequestCodeAsync(email);
        await SetCodeRowAsync(email, r =>
        {
            r.SentInWindow = 5;
            r.WindowStartedAt = DateTime.UtcNow.AddMinutes(-61);
            r.LastSentAt = DateTime.UtcNow.AddMinutes(-2);
        });
        (await client.RequestCodeAsync(email)).StatusCode.Should().Be(HttpStatusCode.Accepted);
    }

    [Fact]
    public async Task One_ip_may_request_20_codes_an_hour()
    {
        var client = api.ClientWithIp();
        for (var i = 0; i < 20; i++)
            (await client.RequestCodeAsync(IdentityTestData.NewEmail("ip"))).StatusCode.Should().Be(HttpStatusCode.Accepted);
        await Problem.ReadAsync(await client.RequestCodeAsync(IdentityTestData.NewEmail("ip")), 429, "RATE_LIMITED");
    }

    [Fact]
    public async Task One_ip_may_check_30_codes_an_hour()
    {
        var client = api.ClientWithIp();
        for (var i = 0; i < 30; i++)
            await Problem.ReadAsync(await client.VerifyAsync(IdentityTestData.NewEmail("guess"), "123456"), 400, "INVALID_CODE");
        await Problem.ReadAsync(await client.VerifyAsync(IdentityTestData.NewEmail("guess"), "123456"), 429, "RATE_LIMITED");
    }

    [Fact]
    public async Task Parallel_code_requests_for_one_email_send_one_code()
    {
        var email = IdentityTestData.NewEmail();
        var client = api.ClientWithIp();
        var responses = await Task.WhenAll(Enumerable.Range(0, 5).Select(_ => client.RequestCodeAsync(email)));
        responses.Count(r => r.StatusCode == HttpStatusCode.Accepted).Should().Be(1);
        responses.Count(r => r.StatusCode == HttpStatusCode.TooManyRequests).Should().Be(4);
        await api.Emails.WaitForAsync(email);
        await Task.Delay(1000, Ct);
        api.Emails.SentTo(email).Should().HaveCount(1);
    }

    [Theory]
    [InlineData("not-an-email", "123456", "email")]
    [InlineData("a@example.test", "12ab56", "code")]
    [InlineData("a@example.test", "1234567", "code")]
    public async Task Bad_input_is_a_validation_error(string email, string code, string field)
    {
        var body = await Problem.ReadAsync(await api.ClientWithIp().VerifyAsync(email, code), 400, "VALIDATION_FAILED");
        body.GetProperty("errors").TryGetProperty(field, out _).Should().BeTrue();
    }

    [Fact]
    public async Task The_request_logs_a_masked_email_and_never_the_code()
    {
        var email = IdentityTestData.NewEmail();
        var response = await api.ClientWithIp().RequestCodeAsync(email);
        var traceId = Problem.TraceIdOf(response);
        var code = await api.Emails.CodeForAsync(email);

        var requested = api.Logs.LinesFor(traceId).Single(l => Str(l, "messageTemplate") == "Login code {codeId} requested for {email}");
        Str(requested, "email").Should().Be(Pii.MaskEmail(email));
        api.Logs.RawLinesFor(traceId).Should().NotContain(l => l.Contains(code) || l.Contains(email));
    }
}
```

Note: `Problem.ReadAsync` checks the body `traceId` against the header, so the 429s here also prove the rate-limit answers keep the error contract.

- [ ] **Step 2: Run them to see them fail.**

- [ ] **Step 3: `Retry-After` on `AppException`.** In `AppException`, add:

```csharp
    /// <summary>Written as the Retry-After header (whole seconds, rounded up); for 429 answers.</summary>
    public TimeSpan? RetryAfter { get; init; }
```

In `AppExceptionHandler.TryHandleAsync`, right after `http.Response.StatusCode = status;`, add:

```csharp
        if (exception is AppException { RetryAfter: { } retryAfter })
            http.Response.Headers.RetryAfter = ((int)Math.Ceiling(retryAfter.TotalSeconds)).ToString(CultureInfo.InvariantCulture);
```

with `using System.Globalization;`.

- [ ] **Step 4: Hashing, email normalisation, tokens.** `Features/Identity/EmailAddresses.cs`:

```csharp
namespace ExtraSpace.Api.Features.Identity;

internal static class EmailAddresses
{
    /// <summary>One spelling per address (S0 spec §5.1): trimmed, lower-case.</summary>
    public static string Normalize(string email) => email.Trim().ToLowerInvariant();
}
```

`Features/Identity/LoginCodeHasher.cs`:

```csharp
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;

namespace ExtraSpace.Api.Features.Identity;

/// <summary>
/// HMAC-SHA256 of <c>email:code</c> with a key derived from the signing key (plan decision 5): a 6-digit code hashed
/// without a secret could be recovered from a database copy in milliseconds.
/// </summary>
public sealed class LoginCodeHasher(IOptions<CustomerAuthOptions> options)
{
    private readonly byte[] _key = HKDF.DeriveKey(HashAlgorithmName.SHA256, options.Value.SigningKeyBytes(), 32,
        info: Encoding.UTF8.GetBytes("login-code"));

    public static string NewCode() => RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6", System.Globalization.CultureInfo.InvariantCulture);

    public string Hash(string email, string code) =>
        Convert.ToHexStringLower(HMACSHA256.HashData(_key, Encoding.UTF8.GetBytes(email + ":" + code)));

    public bool Matches(string storedHash, string email, string code) =>
        CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(storedHash), Encoding.ASCII.GetBytes(Hash(email, code)));
}
```

Add to `IdentityDtos.cs`:

```csharp
using System.ComponentModel.DataAnnotations;

public sealed record TokenResponse(string AccessToken, DateTime AccessTokenExpiresAt, string RefreshToken, DateTime RefreshTokenExpiresAt);

/// <summary>The outcome of a sign-in or refresh: the tokens for the app, the id for the request log.</summary>
public sealed record SignIn(Guid CustomerId, TokenResponse Tokens);

public sealed class RequestCodeBody
{
    [Required, EmailAddress, MaxLength(254)]
    public string? Email { get; init; }
}

public sealed class VerifyCodeBody
{
    [Required, EmailAddress, MaxLength(254)]
    public string? Email { get; init; }

    [Required, RegularExpression("^[0-9]{6}$")]
    public string? Code { get; init; }
}
```

`Features/Identity/TokenService.cs` (Task 5 adds refresh and logout to this class):

```csharp
using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using ExtraSpace.Api.Platform.Data;

namespace ExtraSpace.Api.Features.Identity;

/// <summary>Refresh-token sessions (S0 spec §6.1): a family per sign-in, rotated on every refresh, revoked as a whole.</summary>
public sealed partial class TokenService(AppDbContext db, AccessTokens access, TimeProvider time)
{
    public static readonly TimeSpan RefreshLifetime = TimeSpan.FromDays(60);

    /// <summary>Adds the first refresh token of a new family; the caller saves and commits.</summary>
    internal SignIn StartSession(Customer customer, string? ip, string? userAgent) =>
        Issue(customer, Guid.CreateVersion7(), ip, userAgent).SignIn;

    private (SignIn SignIn, CustomerRefreshToken Row) Issue(Customer customer, Guid familyId, string? ip, string? userAgent)
    {
        var refreshToken = Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(32));
        var row = new CustomerRefreshToken
        {
            CustomerId = customer.Id,
            FamilyId = familyId,
            TokenHash = Hash(refreshToken),
            ExpiresAt = time.GetUtcNow().UtcDateTime + RefreshLifetime,
            Ip = Clip(ip, 45),
            UserAgent = Clip(userAgent, 256),
        };
        db.Add(row);
        var (accessToken, accessExpiresAt) = access.Issue(customer.Id, customer.Email);
        return (new SignIn(customer.Id, new TokenResponse(accessToken, accessExpiresAt, refreshToken, row.ExpiresAt)), row);
    }

    internal static string Hash(string token) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    private static string? Clip(string? value, int max) => value is null || value.Length <= max ? value : value[..max];
}
```

(No logger yet: an unread primary-constructor parameter is a warning. Task 5 adds `ILogger<TokenService> logger` when it adds the log lines.)

- [ ] **Step 5: `LoginCodeService`.** `Features/Identity/LoginCodeService.cs`:

```csharp
using ExtraSpace.Api.Integrations.Email;
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Errors;
using ExtraSpace.Api.Platform.Logging;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Identity;

/// <summary>Email + one-time code sign-in (S0 spec §6.1).</summary>
public sealed partial class LoginCodeService(
    AppDbContext db, LoginCodeHasher hasher, TokenService tokens, IEmailSender email, TimeProvider time,
    ILogger<LoginCodeService> logger)
{
    public static readonly TimeSpan CodeLifetime = TimeSpan.FromMinutes(10);
    private static readonly TimeSpan ResendGap = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan Window = TimeSpan.FromHours(1);
    private const int MaxPerWindow = 5;
    internal const int MaxAttempts = 5;

    public async Task RequestAsync(string rawEmail, string? ip, CancellationToken cancellationToken)
    {
        var address = EmailAddresses.Normalize(rawEmail);
        var now = time.GetUtcNow().UtcDateTime;
        var code = LoginCodeHasher.NewCode();
        Guid codeId;

        await using (var transaction = await db.Database.BeginTransactionAsync(cancellationToken))
        {
            await LockAsync(address, cancellationToken);
            var row = await db.Set<CustomerLoginCode>().SingleOrDefaultAsync(c => c.Email == address, cancellationToken);
            if (row is null)
            {
                row = new CustomerLoginCode { Email = address, WindowStartedAt = now };
                db.Add(row);
            }
            else
            {
                if (now - row.LastSentAt < ResendGap) throw RateLimited(row.LastSentAt + ResendGap - now);
                if (now - row.WindowStartedAt >= Window)
                {
                    row.WindowStartedAt = now;
                    row.SentInWindow = 0;
                }
                if (row.SentInWindow >= MaxPerWindow) throw RateLimited(row.WindowStartedAt + Window - now);
            }

            row.CodeHash = hasher.Hash(address, code);
            row.ExpiresAt = now + CodeLifetime;
            row.Attempts = 0;
            row.ConsumedAt = null;
            row.RequestIp = ip;
            row.LastSentAt = now;
            row.SentInWindow++;
            await db.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            codeId = row.Id;
        }

        email.Enqueue(new EmailMessage("login-code", address,
            new Dictionary<string, string> { ["code"] = code, ["minutes"] = ((int)CodeLifetime.TotalMinutes).ToString(System.Globalization.CultureInfo.InvariantCulture) },
            CodeLifetime));
        LogRequested(logger, codeId, Pii.MaskEmail(address));
    }

    public async Task<SignIn> VerifyAsync(string rawEmail, string code, string? ip, string? userAgent, CancellationToken cancellationToken)
    {
        var address = EmailAddresses.Normalize(rawEmail);
        var now = time.GetUtcNow().UtcDateTime;

        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        await LockAsync(address, cancellationToken);
        var row = await db.Set<CustomerLoginCode>().SingleOrDefaultAsync(c => c.Email == address, cancellationToken);
        if (row is null || row.ConsumedAt is not null || row.ExpiresAt <= now || row.CodeHash.Length == 0) throw InvalidCode();
        if (row.Attempts >= MaxAttempts) throw TooManyAttempts();

        if (!hasher.Matches(row.CodeHash, address, code))
        {
            row.Attempts++;
            await db.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);   // the failed attempt must count although we answer with an error
            if (row.Attempts < MaxAttempts) throw InvalidCode();
            LogLocked(logger, row.Id);
            throw TooManyAttempts();
        }

        row.ConsumedAt = now;
        var customer = await db.Set<Customer>().SingleOrDefaultAsync(c => c.Email == address, cancellationToken);
        var isNew = customer is null;
        if (customer is null)
        {
            customer = new Customer { Email = address };
            db.Add(customer);
        }
        var signIn = tokens.StartSession(customer, ip, userAgent);
        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        if (isNew) LogCreated(logger, customer.Id);
        LogSignedIn(logger, customer.Id);
        return signIn;
    }

    // Parallel calls for one address (a double tap) run one after another; the lock ends with the transaction.
    private Task LockAsync(string address, CancellationToken cancellationToken) =>
        db.Database.ExecuteSqlAsync($"SELECT pg_advisory_xact_lock(hashtextextended({address}, 0))", cancellationToken);

    private static AppException RateLimited(TimeSpan wait) =>
        new(429, ErrorCodes.RateLimited, "Too many requests. Try again later.") { RetryAfter = wait };

    private static AppException InvalidCode() => new(400, ErrorCodes.InvalidCode, "The code is wrong or has expired.");

    private static AppException TooManyAttempts() => new(400, ErrorCodes.TooManyAttempts, "Too many wrong codes. Ask for a new code.");

    [LoggerMessage(Level = LogLevel.Information, Message = "Login code {codeId} requested for {email}")]
    private static partial void LogRequested(ILogger logger, Guid codeId, string email);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Login code {codeId} locked after too many wrong attempts")]
    private static partial void LogLocked(ILogger logger, Guid codeId);

    [LoggerMessage(Level = LogLevel.Information, Message = "Customer {customerId} created")]
    private static partial void LogCreated(ILogger logger, Guid customerId);

    [LoggerMessage(Level = LogLevel.Information, Message = "Customer {customerId} signed in")]
    private static partial void LogSignedIn(ILogger logger, Guid customerId);
}
```

- [ ] **Step 6: Endpoints and registration.** In `CustomerAuth`, add the constants and registrations:

```csharp
    public const string CodeRateLimit = "auth-code";
    public const string VerifyRateLimit = "auth-verify";
```

```csharp
        services.AddSingleton<LoginCodeHasher>();
        services.AddScoped<TokenService>();
        services.AddScoped<LoginCodeService>();
        // Per IP, in memory, so per API task (plan decision 3); the per-email limits live in the database.
        services.Configure<RateLimiterOptions>(o =>
        {
            o.AddPolicy(CodeRateLimit, http => PerIpPerHour(http, 20));
            o.AddPolicy(VerifyRateLimit, http => PerIpPerHour(http, 30));
        });
```

```csharp
    private static RateLimitPartition<string> PerIpPerHour(HttpContext http, int permits) =>
        RateLimitPartition.GetFixedWindowLimiter(http.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = permits, Window = TimeSpan.FromHours(1), QueueLimit = 0 });
```

(`using System.Threading.RateLimiting; using Microsoft.AspNetCore.RateLimiting;`. The `"unknown"` fallback key is the S0-2 carry-over: TestServer has no remote address.)

In `IdentityEndpoints.MapIdentityEndpoints`, before `/me`:

```csharp
        var auth = api.MapGroup("/auth").AllowAnonymous().WithTags("Auth");
        auth.MapPost("/code", RequestCode).RequireRateLimiting(CustomerAuth.CodeRateLimit);
        auth.MapPost("/code/verify", VerifyCode).RequireRateLimiting(CustomerAuth.VerifyRateLimit);
```

and the handlers:

```csharp
    private static async Task<Accepted> RequestCode(RequestCodeBody body, HttpContext http, LoginCodeService codes, CancellationToken cancellationToken)
    {
        await codes.RequestAsync(body.Email!, Ip(http), cancellationToken);
        return TypedResults.Accepted((string?)null);
    }

    private static async Task<Ok<TokenResponse>> VerifyCode(VerifyCodeBody body, HttpContext http, LoginCodeService codes, CancellationToken cancellationToken)
    {
        var signIn = await codes.VerifyAsync(body.Email!, body.Code!, Ip(http), UserAgent(http), cancellationToken);
        RequestLog.Add(http, "customerId", signIn.CustomerId);
        return TypedResults.Ok(signIn.Tokens);
    }

    private static string? Ip(HttpContext http) => http.Connection.RemoteIpAddress?.ToString();

    private static string? UserAgent(HttpContext http) => http.Request.Headers.UserAgent.ToString() is { Length: > 0 } ua ? ua : null;
```

If `TypedResults.Accepted((string?)null)` writes a `Location` header or a body, use the overload that writes neither. The test asserts an empty body.

- [ ] **Step 7: Run the tests.** Run `--filter-class "*LoginCodeTests"`, then the full suite. The rate-limit tests take a few seconds because of the email jobs; that is fine.

- [ ] **Step 8: Hand-off.** Write the report and stop.

---

### Task 5: Refresh rotation, sign-out, `IdentityHousekeeping`, and the full-flow log check

**Files:**
- Modify: `Features/Identity/TokenService.cs`, `IdentityDtos.cs`, `IdentityEndpoints.cs`, `CustomerAuth.cs`
- Create: `Features/Identity/IdentityHousekeepingJob.cs`
- Create (tests): `tests/ExtraSpace.Api.Tests/Features/Identity/RefreshTokenTests.cs`, `IdentityHousekeepingTests.cs`, `SignInLoggingTests.cs`

**Interfaces:**
- Consumes:
  - from Task 4: `TokenService.Issue` (private), `Hash`, `SignIn`, `TokenResponse`, `AuthFlow.SignInAsync`, `ClientWithIp`;
  - from Task 1: `IRecurringJob`, `AddRecurringJob<TJob>`.
- Produces: `POST /api/v1/auth/refresh` (`{ refreshToken }` → 200 `TokenResponse`, or 401 `UNAUTHENTICATED`), `POST /api/v1/auth/logout` (`{ refreshToken }` → 204 always), and the recurring job `IdentityHousekeeping` (daily 03:00 SGT).

- [ ] **Step 1: Write the failing tests.** `RefreshTokenTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ExtraSpace.Api.Features.Identity;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Tests.Features.Identity;

public sealed class RefreshTokenTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private static string? Str(JsonElement line, string name) =>
        line.TryGetProperty(name, out var value) ? value.ToString() : null;

    private static Task<HttpResponseMessage> RefreshAsync(HttpClient client, string refreshToken) =>
        client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken }, Ct);

    private static Task<HttpResponseMessage> LogoutAsync(HttpClient client, string refreshToken) =>
        client.PostAsJsonAsync("/api/v1/auth/logout", new { refreshToken }, Ct);

    private static string Refresh(JsonElement tokens) => tokens.GetProperty("refreshToken").GetString()!;

    [Fact]
    public async Task A_refresh_rotates_both_tokens()
    {
        var client = api.ClientWithIp();
        var first = await api.SignInAsync(client, IdentityTestData.NewEmail());
        var response = await RefreshAsync(client, Refresh(first));
        response.EnsureSuccessStatusCode();
        var second = await response.Content.ReadFromJsonAsync<JsonElement>(Ct);

        Refresh(second).Should().NotBe(Refresh(first));
        await api.WithDbAsync(async db =>
        {
            var old = await db.Set<CustomerRefreshToken>().SingleAsync(t => t.TokenHash == TokenService.Hash(Refresh(first)), Ct);
            var next = await db.Set<CustomerRefreshToken>().SingleAsync(t => t.TokenHash == TokenService.Hash(Refresh(second)), Ct);
            old.ReplacedById.Should().Be(next.Id);
            next.FamilyId.Should().Be(old.FamilyId);
            next.ExpiresAt.Should().BeCloseTo(DateTime.UtcNow.AddDays(60), TimeSpan.FromMinutes(1));
        });
    }

    [Fact]
    public async Task Replaying_a_used_refresh_token_revokes_the_family()
    {
        var client = api.ClientWithIp();
        var first = await api.SignInAsync(client, IdentityTestData.NewEmail());
        var second = await (await RefreshAsync(client, Refresh(first))).Content.ReadFromJsonAsync<JsonElement>(Ct);

        var replay = await RefreshAsync(client, Refresh(first));
        await Problem.ReadAsync(replay, 401, "UNAUTHENTICATED");
        await Problem.ReadAsync(await RefreshAsync(client, Refresh(second)), 401, "UNAUTHENTICATED");

        var warning = api.Logs.LinesFor(Problem.TraceIdOf(replay))
            .Where(l => Str(l, "messageTemplate") == "Refresh token family {familyId} revoked: reuse detected").ToList();
        warning.Should().ContainSingle();
        Str(warning[0], "level").Should().Be("Warning");
    }

    [Fact]
    public async Task An_expired_refresh_token_is_401()
    {
        var client = api.ClientWithIp();
        var tokens = await api.SignInAsync(client, IdentityTestData.NewEmail());
        var hash = TokenService.Hash(Refresh(tokens));
        await api.WithDbAsync(db => db.Set<CustomerRefreshToken>().Where(t => t.TokenHash == hash)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.ExpiresAt, DateTime.UtcNow.AddSeconds(-1)), Ct));
        await Problem.ReadAsync(await RefreshAsync(client, Refresh(tokens)), 401, "UNAUTHENTICATED");
    }

    [Fact]
    public async Task An_unknown_refresh_token_is_401() =>
        await Problem.ReadAsync(await RefreshAsync(api.ClientWithIp(), "not-a-real-token"), 401, "UNAUTHENTICATED");

    [Fact]
    public async Task Logout_revokes_the_session_and_always_answers_204()
    {
        var client = api.ClientWithIp();
        var first = await api.SignInAsync(client, IdentityTestData.NewEmail());
        var second = await (await RefreshAsync(client, Refresh(first))).Content.ReadFromJsonAsync<JsonElement>(Ct);

        (await LogoutAsync(client, Refresh(second))).StatusCode.Should().Be(HttpStatusCode.NoContent);
        await Problem.ReadAsync(await RefreshAsync(client, Refresh(second)), 401, "UNAUTHENTICATED");
        (await LogoutAsync(client, "not-a-real-token")).StatusCode.Should().Be(HttpStatusCode.NoContent);
    }
}
```

`IdentityHousekeepingTests.cs`:

```csharp
using ExtraSpace.Api.Features.Identity;
using ExtraSpace.Api.Tests.TestSupport;
using Hangfire;
using Hangfire.Storage;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace ExtraSpace.Api.Tests.Features.Identity;

public sealed class IdentityHousekeepingTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task It_deletes_only_old_rows_and_can_run_twice()
    {
        var customer = await api.CreateCustomerAsync();
        var now = DateTime.UtcNow;
        var oldCode = IdentityTestData.NewEmail("old");
        var freshCode = IdentityTestData.NewEmail("fresh");
        await api.WithDbAsync(async db =>
        {
            db.AddRange(
                new CustomerLoginCode { Email = oldCode, CodeHash = "x", ExpiresAt = now.AddDays(-2), LastSentAt = now.AddDays(-2), WindowStartedAt = now.AddDays(-2) },
                new CustomerLoginCode { Email = freshCode, CodeHash = "x", ExpiresAt = now.AddHours(-1), LastSentAt = now.AddHours(-1), WindowStartedAt = now.AddHours(-1) },
                new CustomerRefreshToken { CustomerId = customer.Id, FamilyId = Guid.CreateVersion7(), TokenHash = "old-" + Guid.NewGuid().ToString("N"), ExpiresAt = now.AddDays(-31) },
                new CustomerRefreshToken { CustomerId = customer.Id, FamilyId = Guid.CreateVersion7(), TokenHash = "recent-" + Guid.NewGuid().ToString("N"), ExpiresAt = now.AddDays(-29) });
            await db.SaveChangesAsync(Ct);
        });

        for (var run = 0; run < 2; run++)
        {
            await using var scope = api.Services.CreateAsyncScope();
            await scope.ServiceProvider.GetRequiredService<IdentityHousekeepingJob>().RunAsync(Ct);
        }

        await api.WithDbAsync(async db =>
        {
            (await db.Set<CustomerLoginCode>().AnyAsync(c => c.Email == oldCode, Ct)).Should().BeFalse();
            (await db.Set<CustomerLoginCode>().AnyAsync(c => c.Email == freshCode, Ct)).Should().BeTrue();
            var tokens = await db.Set<CustomerRefreshToken>().Where(t => t.CustomerId == customer.Id).Select(t => t.TokenHash).ToListAsync(Ct);
            tokens.Should().ContainSingle().Which.Should().StartWith("recent-");
        });
    }

    [Fact]
    public void It_is_scheduled_daily_at_3am_singapore_time()
    {
        using var connection = api.Services.GetRequiredService<JobStorage>().GetConnection();
        var job = connection.GetRecurringJobs().Single(j => j.Id == "IdentityHousekeeping");
        job.Cron.Should().Be("0 3 * * *");
        job.TimeZoneId.Should().Be("Asia/Singapore");
    }
}
```

`SignInLoggingTests.cs`:

```csharp
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using ExtraSpace.Api.Platform.Logging;
using ExtraSpace.Api.Tests.TestSupport;

namespace ExtraSpace.Api.Tests.Features.Identity;

public sealed class SignInLoggingTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    // Spec §10: "a full sign-in flow with captured log output contains no login code, token or unmasked email".
    [Fact]
    public async Task A_full_sign_in_flow_logs_no_code_token_or_raw_email()
    {
        var client = api.ClientWithIp();
        var email = IdentityTestData.NewEmail("flow");
        var traceIds = new List<string>();

        var request = await client.RequestCodeAsync(email);
        traceIds.Add(Problem.TraceIdOf(request));
        var code = await api.Emails.CodeForAsync(email);
        await api.Logs.WaitForAsync(l => l.TryGetProperty("correlationId", out var c) && c.GetString() == traceIds[0]
            && l.GetProperty("messageTemplate").GetString() == "Email {template} sent to {email}");

        var verify = await client.VerifyAsync(email, code);
        traceIds.Add(Problem.TraceIdOf(verify));
        var tokens = await verify.Content.ReadFromJsonAsync<JsonElement>(Ct);

        using var me = new HttpRequestMessage(HttpMethod.Get, "/api/v1/me");
        me.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokens.GetProperty("accessToken").GetString());
        traceIds.Add(Problem.TraceIdOf(await client.SendAsync(me, Ct)));

        var refresh = await client.PostAsJsonAsync("/api/v1/auth/refresh", new { refreshToken = tokens.GetProperty("refreshToken").GetString() }, Ct);
        traceIds.Add(Problem.TraceIdOf(refresh));
        var rotated = await refresh.Content.ReadFromJsonAsync<JsonElement>(Ct);

        var logout = await client.PostAsJsonAsync("/api/v1/auth/logout", new { refreshToken = rotated.GetProperty("refreshToken").GetString() }, Ct);
        traceIds.Add(Problem.TraceIdOf(logout));

        var lines = traceIds.SelectMany(api.Logs.RawLinesFor).ToList();   // includes the email job: its correlationId is the request's traceId
        lines.Should().HaveCountGreaterThan(8);
        string[] secrets =
        [
            code, email,
            tokens.GetProperty("accessToken").GetString()!, tokens.GetProperty("refreshToken").GetString()!,
            rotated.GetProperty("accessToken").GetString()!, rotated.GetProperty("refreshToken").GetString()!,
        ];
        foreach (var secret in secrets) lines.Should().NotContain(l => l.Contains(secret));
        lines.Should().Contain(l => l.Contains(Pii.MaskEmail(email)));
    }
}
```

- [ ] **Step 2: Run them to see them fail.**

- [ ] **Step 3: Implement refresh and logout.** Add to `IdentityDtos.cs`:

```csharp
public sealed class RefreshBody
{
    [Required, MaxLength(128)]
    public string? RefreshToken { get; init; }
}
```

Add `ILogger<TokenService> logger` as the last primary-constructor parameter of `TokenService`, then add (`using Microsoft.EntityFrameworkCore;`):

```csharp
    public async Task<SignIn> RefreshAsync(string refreshToken, string? ip, string? userAgent, CancellationToken cancellationToken)
    {
        var now = time.GetUtcNow().UtcDateTime;
        var hash = Hash(refreshToken);
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        var row = await db.Set<CustomerRefreshToken>()
            .FromSql($"SELECT * FROM customer_refresh_token WHERE token_hash = {hash} FOR UPDATE")
            .SingleOrDefaultAsync(cancellationToken);
        if (row is null) throw IdentityErrors.Unauthenticated();

        if (row.ReplacedById is not null || row.RevokedAt is not null)
        {
            // A token that was already used is back: someone else holds a copy (spec §6.1 theft detection).
            await RevokeFamilyAsync(row.FamilyId, now, cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            if (row.ReplacedById is not null) LogReuse(logger, row.FamilyId, row.CustomerId);
            throw IdentityErrors.Unauthenticated();
        }
        if (row.ExpiresAt <= now) throw IdentityErrors.Unauthenticated();

        var customer = await db.Set<Customer>().SingleOrDefaultAsync(c => c.Id == row.CustomerId, cancellationToken)
            ?? throw IdentityErrors.Unauthenticated();
        var (signIn, next) = Issue(customer, row.FamilyId, ip, userAgent);
        row.ReplacedById = next.Id;
        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return signIn;
    }

    public async Task LogoutAsync(string refreshToken, CancellationToken cancellationToken)
    {
        var hash = Hash(refreshToken);
        var familyId = await db.Set<CustomerRefreshToken>().Where(t => t.TokenHash == hash)
            .Select(t => (Guid?)t.FamilyId).SingleOrDefaultAsync(cancellationToken);
        if (familyId is null) return;
        await RevokeFamilyAsync(familyId.Value, time.GetUtcNow().UtcDateTime, cancellationToken);
        LogSignedOut(logger, familyId.Value);
    }

    // ExecuteUpdate skips TimestampsInterceptor, so updated_at is set here.
    private Task<int> RevokeFamilyAsync(Guid familyId, DateTime now, CancellationToken cancellationToken) =>
        db.Set<CustomerRefreshToken>().Where(t => t.FamilyId == familyId && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now).SetProperty(t => t.UpdatedAt, now), cancellationToken);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Refresh token family {familyId} revoked: reuse detected")]
    private static partial void LogReuse(ILogger logger, Guid familyId, Guid customerId);

    [LoggerMessage(Level = LogLevel.Information, Message = "Refresh token family {familyId} signed out")]
    private static partial void LogSignedOut(ILogger logger, Guid familyId);
```

(`customerId` is not in `LogReuse`'s template; `[LoggerMessage]` still logs it as a property. If the generator refuses this, add `for customer {customerId}` to the message.)

`IdentityEndpoints`, in the `auth` group:

```csharp
        auth.MapPost("/refresh", Refresh);
        auth.MapPost("/logout", Logout);
```

```csharp
    private static async Task<Ok<TokenResponse>> Refresh(RefreshBody body, HttpContext http, TokenService tokens, CancellationToken cancellationToken)
    {
        var signIn = await tokens.RefreshAsync(body.RefreshToken!, Ip(http), UserAgent(http), cancellationToken);
        RequestLog.Add(http, "customerId", signIn.CustomerId);
        return TypedResults.Ok(signIn.Tokens);
    }

    private static async Task<NoContent> Logout(RefreshBody body, TokenService tokens, CancellationToken cancellationToken)
    {
        await tokens.LogoutAsync(body.RefreshToken!, cancellationToken);
        return TypedResults.NoContent();
    }
```

- [ ] **Step 4: `IdentityHousekeepingJob`.** `Features/Identity/IdentityHousekeepingJob.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Jobs;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Identity;

/// <summary>Daily clean-up (S0 spec §7). Idempotent: it only deletes rows past a cut-off, so a second run deletes nothing.</summary>
public sealed partial class IdentityHousekeepingJob(AppDbContext db, TimeProvider time, ILogger<IdentityHousekeepingJob> logger) : IRecurringJob
{
    private static readonly TimeSpan CodeRetention = TimeSpan.FromDays(1);
    private static readonly TimeSpan TokenRetention = TimeSpan.FromDays(30);

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        var now = time.GetUtcNow().UtcDateTime;
        var codeCutoff = now - CodeRetention;
        var tokenCutoff = now - TokenRetention;
        var codes = await db.Set<CustomerLoginCode>().Where(c => c.ExpiresAt < codeCutoff).ExecuteDeleteAsync(cancellationToken);
        var tokens = await db.Set<CustomerRefreshToken>().Where(t => t.ExpiresAt < tokenCutoff).ExecuteDeleteAsync(cancellationToken);
        LogDone(logger, codes, tokens);
    }

    // Not {tokens}: a property named like *token* is masked to *** (S0 spec §4.4).
    [LoggerMessage(Level = LogLevel.Information, Message = "Identity housekeeping deleted {codeRows} login codes and {refreshRows} refresh tokens")]
    private static partial void LogDone(ILogger logger, int codeRows, int refreshRows);
}
```

In `CustomerAuth.AddIdentityFeature`, add: `services.AddRecurringJob<IdentityHousekeepingJob>("IdentityHousekeeping", Cron.Daily(3));` (`using Hangfire; using ExtraSpace.Api.Platform.Jobs;`).

- [ ] **Step 5: Run the tests.** Run the three new classes, then the whole solution: `dotnet build ExtraSpace.slnx` gives 0 warnings and 0 errors, and all three test projects pass. Report the counts. They were 84 / 18 / 32 before this plan.

- [ ] **Step 6: Hand-off.** Write the report and stop.

---

### Task 6: Review, local run, migration script and docs (main session)

**Files:** nothing in `../CMS` is written by the main session. It creates `docs/migrations/<date>-customer-identity.sql` and updates docs in the context repo.

- [ ] **Step 1: Read the real diff.**
  - Run `git -C ../CMS status --short` and `git -C ../CMS diff --stat`, and read every file under `src/`.
  - Build, and run the three test projects yourself.
  - Check every Global Constraint.
  - Check that `git -C ../CMS grep -nE 'SigningKey"\s*:\s*"[A-Za-z0-9+/=]{20,}|Password=|110611798568' -- src` returns nothing. The test key lives only under `tests/`.
  - Check that each Review Focus line has its test and that the test passes.

- [ ] **Step 2: Whole-branch review.** Dispatch one `code-reviewer` (Opus) on the branch against this plan and the spec §6.1 / §7, focusing on the token and code security, the transactions and the log hygiene. One fix dispatch, one scoped re-review.

- [ ] **Step 3: Local run.** From `../CMS`:

```bash
docker compose up -d
# owner, once: dotnet user-secrets set "CustomerAuth:SigningKey" "$(openssl rand -base64 48)" --project src/ExtraSpace.Api
dotnet ef database update --project src/ExtraSpace.Api --connection "Host=localhost;Port=5433;Database=extraspace;Username=postgres"
dotnet run --project src/ExtraSpace.Api &        # http://localhost:5080, Development: Email:Transport=Log
```

Then, in Swagger (`/swagger`):
1. Run `POST /api/v1/auth/code`.
2. Read the code from the "Development email" console line.
3. Run `POST /api/v1/auth/code/verify`.
4. Click "Authorize" with the access token and call `GET /api/v1/me`.

In Seq, the request's `traceId` finds the request, the email job (by `correlationId`) and the sign-in line. Kill the app afterwards.

- [ ] **Step 4: Migration script for staging** (not run now; S0-6 runs it as the master user through the bastion):

```bash
dotnet ef migrations script --idempotent --project src/ExtraSpace.Api \
  --output "/Users/waiyanmin/Projects/Extra Space/Claude/docs/migrations/<YYYY-MM-DD>-customer-identity.sql"
```

Strip the BOM. Note in the file header that it also contains `InitialPlatform` (idempotent). Hangfire creates its own tables in schema `hangfire` at start-up, as `es_app`, which owns that schema.

- [ ] **Step 5: Docs** (context repo):
  - **`cms.md`:** a "Built so far (S0-3)" section covering:
    - `Platform/Jobs`: `AddRecurringJob`, `IRecurringJob`, the `LogEvents = false` rule, `jobName` without the trailing `Job`;
    - `Integrations/Email`: `IEmailSender.Enqueue` after commit, the transports, templates;
    - `Features/Identity` and the `/api/v1` group (`RequireCustomer`, `AllowAnonymous`);
    - `ClientWithIp`, `AuthFlow`, `FakeEmailTransport`;
    - "Running locally": the signing-key secret.
  - **The guide `minimal-apis-vs-mvc.md`:**
    - the real `/api/v1` group with `RequireAuthorization` + `AllowAnonymous` compared with `[Authorize]` / `[AllowAnonymous]`;
    - the `customerId` endpoint filter compared with an action filter;
    - `RequireRateLimiting` compared with `[EnableRateLimiting]`;
    - `TypedResults.Accepted` / `NoContent`;
    - the JWT bearer scheme plus policy compared with MVC's `[Authorize(AuthenticationSchemes = …)]`.
  - **Spec §5.1:** the three new `customer_login_code` columns. **§6.1:** the plan decisions the owner confirmed.
  - **Plan index:** S0-3 done, plus carry-overs.
  - **Memory:** the resume block.

- [ ] **Step 6: Verdict and hand-off.** Report ACCEPT / FIX NEEDED / BLOCKED per task, with evidence. Give the owner the GitHub message: the commit message plus the PR title and body, in bullets, with no `Co-Authored-By` line (memory `feedback-user-commits-and-tests`).

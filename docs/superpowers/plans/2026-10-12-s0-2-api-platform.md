# S0-2 API platform — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this workspace the implementer is the Opus `implementer` agent; Task 7 is run by the main session only.

**Goal:** Create the `ExtraSpace.Api` host and `ExtraSpace.Engines` with every shared platform piece that S0-3…S0-6 and S1+ build on: error format, request pipeline, structured logging and tracing, app-version check, health, OpenAPI, the `AppDbContext` with its conventions and interceptors, `Money`, the architecture test, `docker-compose.yml` (PostgreSQL + Seq) and the integration-test harness.

**Architecture:** One ASP.NET Core 10 MVC host. Shared code lives in `src/ExtraSpace.Api/Platform/<Area>/`; there are no features yet. `Program.cs` holds the pipeline in the exact order of spec §4.2, and `PlatformServices.AddPlatform` registers the services. Integration tests run the real app through `WebApplicationFactory` against PostgreSQL 18.6 in Docker (Testcontainers), with test-only controllers added from the test assembly, and a Serilog sink that captures the same JSON lines production writes.

**Tech Stack:** .NET 10 (SDK 10.0.400, runtime 10.0.11), ASP.NET Core MVC, EF Core 10 + Npgsql 10.0.3 + EFCore.NamingConventions 10.0.1, Serilog.AspNetCore 10.0.0 + Serilog.Expressions 5.0.0 + Serilog.Sinks.Seq 9.1.0, Microsoft.AspNetCore.OpenApi 10.0.11 + Swashbuckle.AspNetCore.SwaggerUI 10.3.0, xUnit v3 4.0.2 + AwesomeAssertions 9.6.0 + Testcontainers.PostgreSql 4.16.0 + Mono.Cecil 0.11.3 (architecture test; NetArchTest.Rules 1.3.2 was dropped in Task 6 fix round 1), Docker (OrbStack 29.8 on the owner's Mac).

**Spec:** `docs/superpowers/specs/2026-10-09-s0-foundation-design.md` (§3 layout, §4.1–4.6 platform, §5 data, §10 testing), plus `docs/superpowers/plans/2026-10-12-s0-plan-index.md` and `.claude/rules/cms.md`.

## Global Constraints

- Repo `../CMS` (`extraspace-tech/cms`, 🔴 PUBLIC). No secret, password, connection string, endpoint or AWS account id in any committed file. Local configuration goes through `dotnet user-secrets`.
- Work on branch `s0-2-api-platform`, cut from `main` at `84b8475`. **Never `git commit` or `git push`**: each task ends with a hand-off, and the owner commits.
- No new `.md` file inside `../CMS` (a hook blocks it). LF line endings. Match `.editorconfig`.
- Package versions live only in `Directory.Packages.props`. ASP.NET Core / EF Core packages are pinned to **10.0.11** (the installed runtime).
- Namespaces: `ExtraSpace.Api.Platform.<Area>` (`Data`, `Errors`, `Health`, `Hosting`, `Http`, `Logging`, `Tracing`), `ExtraSpace.Api.Features.<Feature>` (from S0-3), `ExtraSpace.Api.Integrations.<Name>` (from S0-3), `ExtraSpace.Engines`.
- Banned in `src/` (analyzer RS0030 = error): `DateTime.Now`, `DateTime.UtcNow`, `DateTime.Today`, `DateTimeOffset.Now`, `DateTimeOffset.UtcNow`, `Guid.NewGuid`. Use the injected `TimeProvider` and `Guid.CreateVersion7()`.
- **Log property names are lowerCamel everywhere**, including message-template placeholders: `"Login code sent to customer {customerId}"`, never `{CustomerId}`. CA2254 stays an error. Hot lines use `[LoggerMessage]`.
- A log property whose name contains `token`, `secret`, `password`, `logincode`, `authorization`, `cookie` or `connectionstring` (any case) is masked to `***`. Never give a non-secret property such a name.
- Headers: `X-Trace-Id` (response, every request), `traceparent` (W3C, honoured on input), `X-App-Platform`, `X-App-Version`, `X-Amzn-Trace-Id` (read from the ALB).
- `traceId` everywhere = the 32-character lower-case hex W3C trace id (`Activity.TraceId.ToHexString()`): header, error body and log lines.
- Error codes (spec §4.1): `VALIDATION_FAILED`, `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `RATE_LIMITED`, `APP_UPDATE_REQUIRED`, `INVALID_CODE`, `TOO_MANY_ATTEMPTS`, `INTERNAL_ERROR`; other statuses fall back to `HTTP_<status>`.
- Test environment name: `Testing`. `ExtraSpace.Api.Tests` needs Docker running (`docker info` must succeed).
- Test filter form (Microsoft Testing Platform): `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*ErrorTests"`.
- Local ports: API `http://localhost:5080`, PostgreSQL `localhost:5433`, Seq `http://localhost:5341`.

## Review Focus

1. **One error path returns a `traceId` that differs from the `X-Trace-Id` header or from the log lines** (unmatched 404, 405, 426, 429, 500). Expected: every path goes through one customizer and shows the same 32-hex id. Pinned by `Problem.ReadAsync` (asserts body `traceId` == header) in the Task 3 `ErrorTests` (404, 405, 409, 418, 500), the Task 5 `AppVersionTests` (426) and `HttpPipelineTests.Rate_limited_request_gets_429_problem` (429), and by Task 4 `LoggingTests.Error_response_trace_id_matches_its_log_lines`.
2. **A secret reaches the logs** through a secret-named property, a destructured object or the rendered message, or an exception message reaches a 500 body. Expected: `***` in every case, and no exception text in responses. Pinned by Task 4 `LoggingTests.Secret_named_properties_are_masked_everywhere` and Task 3 `ErrorTests.Unknown_exception_is_500_without_details`.
3. **A client spoofs `X-Forwarded-For`** to dodge the per-IP limits that S0-3 adds. Expected: only the last hop, the one the ALB appended, becomes `RemoteIpAddress`. Pinned by Task 5 `HttpPipelineTests.Forwarded_headers_take_only_the_last_hop`.
4. **Odd app-version headers**: a build suffix `1.9.9+99`, `iOS` casing, only one header sent, a garbage value, a platform with no minimum. Expected: below the minimum → 426; a value that can't be parsed or a missing header → pass, so a bad header never locks users out. Pinned by Task 5 `AppVersionTests`.
5. **An exception logged twice** (once by the framework, once by us), which would double every error alarm in S0-6. Expected: exactly one Error line with the exception per failed request. Pinned by Task 4 `LoggingTests.Error_response_trace_id_matches_its_log_lines` (asserts a single exception line).

## Decisions this plan makes (owner to confirm with the plan)

These fill gaps in the spec or change small details of it. Task 7 writes the confirmed ones into the spec.

1. **`traceId` is the 32-hex W3C trace id** (`4bf92f3577b34da6a3ce929d0e0e4736`), not the full `traceparent` string that the §4.1 example shows. It is shorter to copy, and it is the value CloudWatch, Seq and X-Ray all key on.
2. **JSON log fields have plain names** (`timestamp`, `level`, `message`, `messageTemplate`, `exception`, `traceId`, `spanId`), not `CompactJsonFormatter`'s `@t`/`@l`/`@mt`. CloudWatch Logs Insights reserves names that start with `@`. The line is still one JSON object per line, written with Serilog.Expressions.
3. **All log property names are lowerCamel**, including placeholders. The §4.4 example `{CustomerId}` becomes `{customerId}`, so a single query on `customerId` finds both enriched and template properties.
4. **Our own request-summary middleware** instead of `UseSerilogRequestLogging`, so the summary line carries exactly the spec's fields (`method`, `route`, `status`, `elapsedMs`) and its level rules.
5. **`taskId` is not added by the app.** The CloudWatch log stream name already contains the ECS task id (S0-6 sets `awslogs-stream-prefix`).
6. **An `AppException` below 500 is not logged by the exception handler.** It is an expected outcome (wrong code, conflict). The summary line records the status, and features log business events. Only 5xx and unknown exceptions are logged, at Error with the stack.
7. **Codes for other statuses:** a bare 400 → `VALIDATION_FAILED`; 401/403/404/409/426/429 → the spec codes; ≥500 → `INTERNAL_ERROR`; anything else → `HTTP_<status>` (for example `HTTP_405`).
8. **Generic 409s:** an EF concurrency failure and a PostgreSQL unique violation (`23505`) both become `409 CONFLICT`, so a race never surfaces as a 500.
9. **The OpenAPI document is served outside production only**, like Swagger UI (`/swagger`). S0-5's type generation runs against a local or CI app, never production.
10. **An app-version header that can't be parsed passes**, with a Warning log line. Build and pre-release suffixes are ignored (`1.4.0+12` and `1.4.0-beta` both count as `1.4.0`).
11. **`data_protection_keys` is created here**, as the first real migration (`InitialPlatform`), instead of in S0-4. S0-4's cookie only uses it.
12. **Local setup:** PostgreSQL on `127.0.0.1:5433` without a password (trust auth, bound to loopback only), Seq on `127.0.0.1:5341` without sign-in, API on port 5080.
13. **`Guid.NewGuid` is banned in `src/`** next to the clock APIs, so every id is UUID v7.
14. **A request the client aborted** gets status 499 and is not logged as an error.
15. **Masking is a Serilog enricher**, not a destructuring policy. An enricher covers top-level properties and destructured objects alike; a destructuring policy only sees `{@object}` values.

---

### Task 1: Build plumbing and `ExtraSpace.Engines` (Money)

**Files:**
- Modify: `../CMS/Directory.Packages.props`, `../CMS/.editorconfig`, `../CMS/ExtraSpace.slnx`
- Create: `../CMS/src/Directory.Build.props`, `../CMS/src/BannedSymbols.txt`
- Create: `../CMS/src/ExtraSpace.Engines/ExtraSpace.Engines.csproj`, `../CMS/src/ExtraSpace.Engines/Money.cs`
- Create: `../CMS/tests/ExtraSpace.Engines.Tests/ExtraSpace.Engines.Tests.csproj`, `../CMS/tests/ExtraSpace.Engines.Tests/MoneyTests.cs`

**Interfaces:**
- Consumes: the S0-1 root files (`global.json`, `Directory.Build.props`).
- Produces: central versions for every package of this plan; the banned-API analyzer for every project under `src/`; `ExtraSpace.Engines.Money` with `Money(decimal amount, string currency)`, `Amount`, `Currency`, `static Money Zero(string currency)`, `static decimal Round(decimal amount)` (the only money rounding rule), `Money Round()`, operators `+`, `-` (binary and unary) and `* decimal`.

- [ ] **Step 1: Create the branch**

```bash
cd "/Users/waiyanmin/Projects/Extra Space/CMS"
git status --short          # must print nothing; stop and report if not
git log --oneline -1        # 84b8475 feat(infra): solution skeleton, CDK network and database stacks
git switch -c s0-2-api-platform
```

- [ ] **Step 2: Central package versions** — replace `Directory.Packages.props` with:

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup Label="Infra">
    <PackageVersion Include="Amazon.CDK.Lib" Version="2.273.0" />
    <PackageVersion Include="Constructs" Version="10.8.1" />
  </ItemGroup>
  <ItemGroup Label="Api">
    <PackageVersion Include="EFCore.NamingConventions" Version="10.0.1" />
    <PackageVersion Include="Microsoft.AspNetCore.DataProtection.EntityFrameworkCore" Version="10.0.11" />
    <PackageVersion Include="Microsoft.AspNetCore.OpenApi" Version="10.0.11" />
    <PackageVersion Include="Microsoft.CodeAnalysis.BannedApiAnalyzers" Version="5.6.0" />
    <PackageVersion Include="Microsoft.EntityFrameworkCore.Design" Version="10.0.11" />
    <PackageVersion Include="Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore" Version="10.0.11" />
    <PackageVersion Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="10.0.3" />
    <PackageVersion Include="Serilog.AspNetCore" Version="10.0.0" />
    <PackageVersion Include="Serilog.Expressions" Version="5.0.0" />
    <PackageVersion Include="Serilog.Sinks.Seq" Version="9.1.0" />
    <PackageVersion Include="Swashbuckle.AspNetCore.SwaggerUI" Version="10.3.0" />
  </ItemGroup>
  <ItemGroup Label="Tests">
    <PackageVersion Include="AwesomeAssertions" Version="9.6.0" />
    <PackageVersion Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.11" />
    <PackageVersion Include="Microsoft.Extensions.Diagnostics.Testing" Version="10.10.0" />
    <PackageVersion Include="Microsoft.Extensions.TimeProvider.Testing" Version="10.10.0" />
    <PackageVersion Include="Microsoft.NET.Test.Sdk" Version="18.10.1" />
    <PackageVersion Include="NetArchTest.Rules" Version="1.3.2" />
    <PackageVersion Include="Testcontainers.PostgreSql" Version="4.16.0" />
    <PackageVersion Include="xunit.runner.visualstudio" Version="4.0.1" />
    <PackageVersion Include="xunit.v3" Version="4.0.2" />
  </ItemGroup>
</Project>
```

- [ ] **Step 3: Banned APIs for `src/`**

`src/Directory.Build.props`:

```xml
<Project>
  <Import Project="$([MSBuild]::GetPathOfFileAbove('Directory.Build.props', '$(MSBuildThisFileDirectory)../'))" />
  <ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.BannedApiAnalyzers" PrivateAssets="all" />
    <AdditionalFiles Include="$(MSBuildThisFileDirectory)BannedSymbols.txt" />
  </ItemGroup>
</Project>
```

`src/BannedSymbols.txt`:

```
P:System.DateTime.Now;Use the injected TimeProvider (S0 spec §4.6)
P:System.DateTime.UtcNow;Use the injected TimeProvider (S0 spec §4.6)
P:System.DateTime.Today;Use the injected TimeProvider and the site's time zone (S0 spec §4.6)
P:System.DateTimeOffset.Now;Use the injected TimeProvider (S0 spec §4.6)
P:System.DateTimeOffset.UtcNow;Use the injected TimeProvider (S0 spec §4.6)
M:System.Guid.NewGuid;Use Guid.CreateVersion7() for ids and RandomNumberGenerator for secrets
```

Append to the `[*.cs]` section of `.editorconfig`:

```ini
dotnet_diagnostic.RS0030.severity = error
# log property names are lowerCamel (S0-2 plan, Global Constraints)
dotnet_diagnostic.CA1727.severity = none
```

- [ ] **Step 4: Create the projects**

```bash
cd "/Users/waiyanmin/Projects/Extra Space/CMS"
mkdir -p src/ExtraSpace.Engines tests/ExtraSpace.Engines.Tests
```

`src/ExtraSpace.Engines/ExtraSpace.Engines.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>ExtraSpace.Engines</RootNamespace>
  </PropertyGroup>
</Project>
```

`tests/ExtraSpace.Engines.Tests/ExtraSpace.Engines.Tests.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="AwesomeAssertions" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit.runner.visualstudio" />
    <PackageReference Include="xunit.v3" />
  </ItemGroup>
  <ItemGroup>
    <Using Include="AwesomeAssertions" />
    <Using Include="Xunit" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../../src/ExtraSpace.Engines/ExtraSpace.Engines.csproj" />
  </ItemGroup>
</Project>
```

```bash
dotnet sln ExtraSpace.slnx add --solution-folder src src/ExtraSpace.Engines/ExtraSpace.Engines.csproj
dotnet sln ExtraSpace.slnx add --solution-folder tests tests/ExtraSpace.Engines.Tests/ExtraSpace.Engines.Tests.csproj
```

- [ ] **Step 5: Write the failing tests** — `tests/ExtraSpace.Engines.Tests/MoneyTests.cs`:

```csharp
using System.Globalization;
using ExtraSpace.Engines;

namespace ExtraSpace.Engines.Tests;

public sealed class MoneyTests
{
    private static decimal D(string value) => decimal.Parse(value, CultureInfo.InvariantCulture);

    [Theory]
    [InlineData("0.005", "0.01")]
    [InlineData("-0.005", "-0.01")]
    [InlineData("2.675", "2.68")]
    [InlineData("1.004", "1.00")]
    [InlineData("1.015", "1.02")]
    [InlineData("-1.015", "-1.02")]
    [InlineData("10.999", "11.00")]
    [InlineData("0", "0.00")]
    public void Round_is_half_away_from_zero_to_two_places(string input, string expected) =>
        Money.Round(D(input)).Should().Be(D(expected));

    [Fact]
    public void Instance_round_keeps_the_currency() =>
        new Money(D("100.005"), "SGD").Round().Should().Be(new Money(D("100.01"), "SGD"));

    [Fact]
    public void Multiplying_does_not_round_until_asked()
    {
        var line = new Money(D("33.335"), "MYR") * 3m;
        line.Amount.Should().Be(D("100.005"));
        line.Round().Amount.Should().Be(D("100.01"));
    }

    [Fact]
    public void Adding_and_subtracting_need_the_same_currency()
    {
        (new Money(1.10m, "SGD") + new Money(2.20m, "SGD")).Should().Be(new Money(3.30m, "SGD"));
        (new Money(1.10m, "SGD") - new Money(2.20m, "SGD")).Should().Be(new Money(-1.10m, "SGD"));
        var mixed = () => new Money(1m, "SGD") + new Money(1m, "MYR");
        mixed.Should().Throw<InvalidOperationException>().WithMessage("*SGD*MYR*");
    }

    [Fact]
    public void Negation_and_zero() =>
        (-new Money(5m, "SGD")).Should().Be(new Money(-5m, "SGD") + Money.Zero("SGD"));

    [Theory]
    [InlineData("sgd")]
    [InlineData("SG")]
    [InlineData("SGDX")]
    [InlineData("S1D")]
    [InlineData("")]
    [InlineData(null)]
    public void Currency_must_be_a_three_letter_upper_case_code(string? currency)
    {
        var create = () => new Money(1m, currency!);
        create.Should().Throw<ArgumentException>();
    }
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `dotnet test tests/ExtraSpace.Engines.Tests`
Expected: build error `CS0246: The type or namespace name 'Money' could not be found`.

- [ ] **Step 7: Implement** — `src/ExtraSpace.Engines/Money.cs`:

```csharp
namespace ExtraSpace.Engines;

/// <summary>An exact amount in one currency. Rounding happens only where a feature spec says so, through <see cref="Round()"/>.</summary>
public readonly record struct Money
{
    public decimal Amount { get; }
    public string Currency { get; }

    public Money(decimal amount, string currency)
    {
        if (currency is not { Length: 3 } || !currency.All(char.IsAsciiLetterUpper))
            throw new ArgumentException($"Currency must be a 3-letter upper-case ISO 4217 code, got '{currency}'.", nameof(currency));
        Amount = amount;
        Currency = currency;
    }

    public static Money Zero(string currency) => new(0m, currency);

    /// <summary>Half away from zero to 2 places (S0 spec §4.6). The only money rounding rule in the codebase.</summary>
    public static decimal Round(decimal amount) => decimal.Round(amount, 2, MidpointRounding.AwayFromZero);

    public Money Round() => new(Round(Amount), Currency);

    public static Money operator +(Money a, Money b) => new(a.Amount + b.Amount, SameCurrency(a, b));
    public static Money operator -(Money a, Money b) => new(a.Amount - b.Amount, SameCurrency(a, b));
    public static Money operator -(Money a) => new(-a.Amount, a.Currency);
    public static Money operator *(Money a, decimal factor) => new(a.Amount * factor, a.Currency);

    private static string SameCurrency(Money a, Money b) =>
        a.Currency == b.Currency ? a.Currency : throw new InvalidOperationException($"Cannot combine {a.Currency} and {b.Currency}.");

    public override string ToString() => $"{Amount:0.00##} {Currency}";
}
```

- [ ] **Step 8: Run tests**

Run: `dotnet test tests/ExtraSpace.Engines.Tests`
Expected: 18 tests pass, 0 fail (theory rows count one each: 8 + 1 + 1 + 1 + 1 + 6).

- [ ] **Step 9: Prove the banned-API rule works, then undo**

Add the line `private static readonly DateTime Probe = DateTime.UtcNow;` inside `Money`, run `dotnet build src/ExtraSpace.Engines`. Expected: `error RS0030: The symbol 'DateTime.UtcNow' is banned in this project: Use the injected TimeProvider (S0 spec §4.6)`. Remove the line and build again: 0 errors, 0 warnings.

- [ ] **Step 10: Hand-off** — report the build and test output. Do not commit.

---

### Task 2: API host, database, data protection, health and the test harness

**Files:**
- Create: `../CMS/src/ExtraSpace.Api/ExtraSpace.Api.csproj`, `Program.cs`, `appsettings.json`, `appsettings.Development.json`, `Properties/launchSettings.json`
- Create: `../CMS/src/ExtraSpace.Api/Platform/Hosting/AppOptions.cs`, `Platform/Hosting/PlatformServices.cs`
- Create: `../CMS/src/ExtraSpace.Api/Platform/Data/AppDbContext.cs`, `IHasTimestamps.cs`, `TimestampsInterceptor.cs`, `DesignTimeDbContextFactory.cs`, `Migrations/*` (generated)
- Create: `../CMS/src/ExtraSpace.Api/Platform/Health/HealthEndpoints.cs`
- Create: `../CMS/docker-compose.yml`, `../CMS/.config/dotnet-tools.json` (generated)
- Create: `../CMS/tests/ExtraSpace.Api.Tests/ExtraSpace.Api.Tests.csproj`, `AssemblyInfo.cs`, `ApiFactory.cs`, `TestSupport/TestController.cs`, `TestSupport/StampedDbContext.cs`, `Platform/HealthTests.cs`, `Platform/DataTests.cs`
- Modify: `../CMS/ExtraSpace.slnx`

**Interfaces:**
- Consumes: Task 1 (`ExtraSpace.Engines`, central versions, banned APIs).
- Produces:
  - `AppOptions` (`Section = "App"`; `AppRole Role` = `All|Api|Jobs`, default `All`; `string Version`, default `"dev"`; `Dictionary<string,string> MinVersion`) and `enum AppRole`.
  - `PlatformServices.AddPlatform(this IServiceCollection, IConfiguration)`.
  - `AppDbContext` (`DbSet<DataProtectionKey> DataProtectionKeys`; applies every `IEntityTypeConfiguration<>` in the Api assembly; `decimal` → `numeric(12,2)`; snake_case).
  - `IHasTimestamps` (`DateTime CreatedAt`, `DateTime UpdatedAt`), and `TimestampsInterceptor(TimeProvider)`, which stamps them in UTC.
  - `HealthEndpoints.MapHealthEndpoints(this IEndpointRouteBuilder)`.
  - Test side: `ApiFactory` (assembly fixture; `ConnectionString`; `Task<string> CreateDatabaseAsync(string prefix)`), `TestController` at route `test/*` (test assembly only), `StampedDbContext` / `StampedThing`.

- [ ] **Step 1: Check Docker** — `docker info --format '{{.ServerVersion}}'` must print a version (29.8.x). If it fails, stop and report: OrbStack is not running.

- [ ] **Step 2: Create the API project**

`src/ExtraSpace.Api/ExtraSpace.Api.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <RootNamespace>ExtraSpace.Api</RootNamespace>
    <UserSecretsId>extraspace-api</UserSecretsId>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="EFCore.NamingConventions" />
    <PackageReference Include="Microsoft.AspNetCore.DataProtection.EntityFrameworkCore" />
    <PackageReference Include="Microsoft.AspNetCore.OpenApi" />
    <PackageReference Include="Microsoft.EntityFrameworkCore.Design" PrivateAssets="all" IncludeAssets="runtime; build; native; contentfiles; analyzers; buildtransitive" />
    <PackageReference Include="Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore" />
    <PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" />
    <PackageReference Include="Serilog.AspNetCore" />
    <PackageReference Include="Serilog.Expressions" />
    <PackageReference Include="Serilog.Sinks.Seq" />
    <PackageReference Include="Swashbuckle.AspNetCore.SwaggerUI" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../ExtraSpace.Engines/ExtraSpace.Engines.csproj" />
  </ItemGroup>
  <ItemGroup>
    <InternalsVisibleTo Include="ExtraSpace.Api.Tests" />
  </ItemGroup>
</Project>
```

`src/ExtraSpace.Api/Properties/launchSettings.json`:

```json
{
  "profiles": {
    "ExtraSpace.Api": {
      "commandName": "Project",
      "applicationUrl": "http://localhost:5080",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      }
    }
  }
}
```

`src/ExtraSpace.Api/appsettings.json` (the keys later tasks read are already here):

```json
{
  "App": {
    "Role": "All",
    "Version": "dev",
    "MinVersion": {}
  },
  "Cors": {
    "AllowedOrigins": []
  },
  "Logging": {
    "SlowQueryMs": 500
  },
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft.AspNetCore": "Warning",
        "Microsoft.EntityFrameworkCore": "Warning",
        "System.Net.Http": "Warning"
      }
    }
  },
  "AllowedHosts": "*"
}
```

`src/ExtraSpace.Api/appsettings.Development.json`:

```json
{
  "Seq": {
    "Url": "http://localhost:5341"
  }
}
```

`docker-compose.yml` (repo root):

```yaml
name: extraspace
services:
  postgres:
    image: postgres:18.6
    environment:
      POSTGRES_DB: extraspace
      # Local only: no password, and the port is bound to 127.0.0.1.
      POSTGRES_HOST_AUTH_METHOD: trust
    ports:
      - "127.0.0.1:5433:5432"
    volumes:
      - pgdata:/var/lib/postgresql
  seq:
    image: datalust/seq:2026.1
    environment:
      ACCEPT_EULA: "Y"
      SEQ_FIRSTRUN_NOAUTHENTICATION: "true"
    ports:
      - "127.0.0.1:5341:80"
    volumes:
      - seqdata:/data
volumes:
  pgdata:
  seqdata:
```

- [ ] **Step 3: Write the platform code**

`src/ExtraSpace.Api/Platform/Hosting/AppOptions.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Hosting;

/// <summary>Which parts this process runs (S0 spec §7): <c>Api</c> serves HTTP, <c>Jobs</c> runs the Hangfire server, <c>All</c> does both.</summary>
public enum AppRole { All, Api, Jobs }

public sealed class AppOptions
{
    public const string Section = "App";

    public AppRole Role { get; set; } = AppRole.All;

    /// <summary>Git SHA of the running build; set by the Docker image (S0-6).</summary>
    public string Version { get; set; } = "dev";

    /// <summary>Lowest allowed Flutter app version per platform (<c>ios</c>, <c>android</c>, <c>web</c>).</summary>
    public Dictionary<string, string> MinVersion { get; set; } = new();
}
```

`src/ExtraSpace.Api/Platform/Data/IHasTimestamps.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Data;

/// <summary>Every table has <c>created_at</c> / <c>updated_at</c> (S0 spec §5); <see cref="TimestampsInterceptor"/> sets them.</summary>
public interface IHasTimestamps
{
    DateTime CreatedAt { get; set; }
    DateTime UpdatedAt { get; set; }
}
```

`src/ExtraSpace.Api/Platform/Data/TimestampsInterceptor.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace ExtraSpace.Api.Platform.Data;

public sealed class TimestampsInterceptor(TimeProvider time) : SaveChangesInterceptor
{
    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        Stamp(eventData.Context);
        return result;
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        Stamp(eventData.Context);
        return ValueTask.FromResult(result);
    }

    private void Stamp(DbContext? context)
    {
        if (context is null) return;
        var now = time.GetUtcNow().UtcDateTime;
        foreach (var entry in context.ChangeTracker.Entries<IHasTimestamps>())
        {
            if (entry.State == EntityState.Added)
            {
                entry.Entity.CreatedAt = now;
                entry.Entity.UpdatedAt = now;
            }
            else if (entry.State == EntityState.Modified)
            {
                entry.Entity.UpdatedAt = now;
                entry.Property(nameof(IHasTimestamps.CreatedAt)).IsModified = false;
            }
        }
    }
}
```

`src/ExtraSpace.Api/Platform/Data/AppDbContext.cs`:

```csharp
using Microsoft.AspNetCore.DataProtection.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Platform.Data;

/// <summary>The one DbContext (S0 spec §3). Each feature adds its own IEntityTypeConfiguration classes in its folder.</summary>
public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options), IDataProtectionKeyContext
{
    public DbSet<DataProtectionKey> DataProtectionKeys { get; set; } = null!;

    protected override void OnModelCreating(ModelBuilder modelBuilder) =>
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);

    protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder) =>
        configurationBuilder.Properties<decimal>().HavePrecision(12, 2);
}
```

`src/ExtraSpace.Api/Platform/Data/DesignTimeDbContextFactory.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace ExtraSpace.Api.Platform.Data;

/// <summary>Used only by <c>dotnet ef</c> to build migrations and scripts; it never connects. Pass <c>--connection</c> to update a database.</summary>
public sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql("Host=localhost")
            .UseSnakeCaseNamingConvention()
            .Options);
}
```

`src/ExtraSpace.Api/Platform/Health/HealthEndpoints.cs`:

```csharp
using Microsoft.AspNetCore.Diagnostics.HealthChecks;

namespace ExtraSpace.Api.Platform.Health;

public static class HealthEndpoints
{
    /// <summary><c>/health/live</c>: the process is up (ALB target check). <c>/health/ready</c>: the database answers (S0 spec §4.5).</summary>
    public static void MapHealthEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false }).AllowAnonymous();
        app.MapHealthChecks("/health/ready", new HealthCheckOptions { Predicate = check => check.Tags.Contains("ready") }).AllowAnonymous();
    }
}
```

`src/ExtraSpace.Api/Platform/Hosting/PlatformServices.cs`:

```csharp
using System.Text.Json.Serialization;
using ExtraSpace.Api.Platform.Data;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Platform.Hosting;

public static class PlatformServices
{
    public static IServiceCollection AddPlatform(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<AppOptions>().Bind(configuration.GetSection(AppOptions.Section)).ValidateOnStart();
        services.AddSingleton(TimeProvider.System);

        services.AddSingleton<TimestampsInterceptor>();
        services.AddDbContext<AppDbContext>((sp, options) => options
            .UseNpgsql(sp.GetRequiredService<IConfiguration>().GetConnectionString("Default")
                ?? throw new InvalidOperationException("ConnectionStrings:Default is not set."))
            .UseSnakeCaseNamingConvention()
            .AddInterceptors(sp.GetRequiredService<TimestampsInterceptor>()));
        services.AddDataProtection().SetApplicationName("ExtraSpace").PersistKeysToDbContext<AppDbContext>();
        services.AddHealthChecks().AddDbContextCheck<AppDbContext>("database", tags: ["ready"]);

        services.AddControllers()
            .AddJsonOptions(o => o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter()));
        return services;
    }
}
```

`src/ExtraSpace.Api/Program.cs`:

```csharp
using ExtraSpace.Api.Platform.Health;
using ExtraSpace.Api.Platform.Hosting;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddPlatform(builder.Configuration);

var app = builder.Build();
app.UseRouting();
app.MapControllers();
app.MapHealthEndpoints();
app.Run();

public partial class Program;
```

(If the compiler reports that `Program` is already public, for example analyzer ASP0027, remove the last line.)

- [ ] **Step 4: Build and create the first migration**

```bash
cd "/Users/waiyanmin/Projects/Extra Space/CMS"
dotnet sln ExtraSpace.slnx add --solution-folder src src/ExtraSpace.Api/ExtraSpace.Api.csproj
dotnet build src/ExtraSpace.Api        # 0 errors, 0 warnings
dotnet new tool-manifest
dotnet tool install dotnet-ef --version 10.0.11
dotnet ef migrations add InitialPlatform --project src/ExtraSpace.Api --output-dir Platform/Data/Migrations
```

Expected: three files under `Platform/Data/Migrations/` (`<stamp>_InitialPlatform.cs`, its `.Designer.cs` and `AppDbContextModelSnapshot.cs`), creating table `data_protection_keys` with columns `id` (integer, identity), `friendly_name` (text, null) and `xml` (text, null). Open the migration and check the snake_case names. If the table is `DataProtectionKeys`, the naming convention is not applied: stop and report.

- [ ] **Step 5: Create the test project and harness**

`tests/ExtraSpace.Api.Tests/ExtraSpace.Api.Tests.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>
  <ItemGroup>
    <FrameworkReference Include="Microsoft.AspNetCore.App" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="AwesomeAssertions" />
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" />
    <PackageReference Include="Microsoft.Extensions.Diagnostics.Testing" />
    <PackageReference Include="Microsoft.Extensions.TimeProvider.Testing" />
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="NetArchTest.Rules" />
    <PackageReference Include="Testcontainers.PostgreSql" />
    <PackageReference Include="xunit.runner.visualstudio" />
    <PackageReference Include="xunit.v3" />
  </ItemGroup>
  <ItemGroup>
    <Using Include="AwesomeAssertions" />
    <Using Include="Xunit" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../../src/ExtraSpace.Api/ExtraSpace.Api.csproj" />
  </ItemGroup>
</Project>
```

`tests/ExtraSpace.Api.Tests/AssemblyInfo.cs`:

```csharp
[assembly: AssemblyFixture(typeof(ExtraSpace.Api.Tests.ApiFactory))]
```

`tests/ExtraSpace.Api.Tests/ApiFactory.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Testcontainers.PostgreSql;

namespace ExtraSpace.Api.Tests;

/// <summary>One PostgreSQL 18.6 container and one app host for the whole test run (xUnit assembly fixture).</summary>
public sealed class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder("postgres:18.6").Build();

    public string ConnectionString => _postgres.GetConnectionString();

    public async ValueTask InitializeAsync()
    {
        await _postgres.StartAsync();
        await using var scope = Services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("ConnectionStrings:Default", ConnectionString);
        builder.ConfigureTestServices(services =>
            services.AddControllers().AddApplicationPart(typeof(TestController).Assembly));
    }

    /// <summary>A fresh empty database in the same container, for tests that need their own tables.</summary>
    public async Task<string> CreateDatabaseAsync(string prefix)
    {
        var name = $"{prefix}_{Guid.NewGuid():N}";
        await using var connection = new NpgsqlConnection(ConnectionString);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand($"CREATE DATABASE \"{name}\"", connection);
        await command.ExecuteNonQueryAsync();
        return new NpgsqlConnectionStringBuilder(ConnectionString) { Database = name }.ConnectionString;
    }

    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        await _postgres.DisposeAsync();
    }
}
```

(If `new PostgreSqlBuilder("postgres:18.6")` does not compile in Testcontainers 4.16, use `new PostgreSqlBuilder().WithImage("postgres:18.6")`.)

`tests/ExtraSpace.Api.Tests/TestSupport/TestController.cs`:

```csharp
using Microsoft.AspNetCore.Mvc;

namespace ExtraSpace.Api.Tests.TestSupport;

/// <summary>Test-only endpoints, added to the app by <see cref="ApiFactory"/>. Never part of the shipped API.</summary>
[ApiController]
[Route("test")]
public sealed class TestController : ControllerBase
{
    [HttpGet("ok")]
    public IActionResult Ok200() => Ok(new { ok = true });
}
```

`tests/ExtraSpace.Api.Tests/TestSupport/StampedDbContext.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Tests.TestSupport;

public sealed class StampedThing : IHasTimestamps
{
    public Guid Id { get; init; } = Guid.CreateVersion7();
    public string Name { get; set; } = "";
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}

/// <summary>A tiny context in its own database, so interceptor tests never touch the app's migrated schema.</summary>
public sealed class StampedDbContext(DbContextOptions<StampedDbContext> options) : DbContext(options)
{
    public DbSet<StampedThing> Things => Set<StampedThing>();
}
```

```bash
dotnet sln ExtraSpace.slnx add --solution-folder tests tests/ExtraSpace.Api.Tests/ExtraSpace.Api.Tests.csproj
```

- [ ] **Step 6: Write the tests**

`tests/ExtraSpace.Api.Tests/Platform/HealthTests.cs`:

```csharp
using System.Net;
using Microsoft.AspNetCore.Hosting;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class HealthTests(ApiFactory api)
{
    [Fact]
    public async Task Live_and_ready_are_200_when_the_database_answers()
    {
        var client = api.CreateClient();
        (await client.GetAsync("/health/live", TestContext.Current.CancellationToken)).StatusCode.Should().Be(HttpStatusCode.OK);
        var ready = await client.GetAsync("/health/ready", TestContext.Current.CancellationToken);
        ready.StatusCode.Should().Be(HttpStatusCode.OK);
        (await ready.Content.ReadAsStringAsync(TestContext.Current.CancellationToken)).Should().Be("Healthy");
    }

    [Fact]
    public async Task Ready_is_503_and_live_stays_200_when_the_database_is_down()
    {
        await using var broken = api.WithWebHostBuilder(b =>
            b.UseSetting("ConnectionStrings:Default", "Host=127.0.0.1;Port=1;Database=x;Username=x;Timeout=2"));
        var client = broken.CreateClient();
        (await client.GetAsync("/health/live", TestContext.Current.CancellationToken)).StatusCode.Should().Be(HttpStatusCode.OK);
        (await client.GetAsync("/health/ready", TestContext.Current.CancellationToken)).StatusCode.Should().Be(HttpStatusCode.ServiceUnavailable);
    }
}
```

`tests/ExtraSpace.Api.Tests/Platform/DataTests.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Time.Testing;
using Npgsql;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class DataTests(ApiFactory api)
{
    [Fact]
    public async Task Migrations_create_data_protection_keys_in_snake_case()
    {
        var ct = TestContext.Current.CancellationToken;
        await using var connection = new NpgsqlConnection(api.ConnectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            "select column_name from information_schema.columns where table_name = 'data_protection_keys' order by column_name", connection);
        var columns = new List<string>();
        await using (var reader = await command.ExecuteReaderAsync(ct))
            while (await reader.ReadAsync(ct)) columns.Add(reader.GetString(0));
        columns.Should().Equal("friendly_name", "id", "xml");
    }

    [Fact]
    public async Task Data_protection_keys_are_stored_in_postgres()
    {
        var protector = api.Services.GetRequiredService<IDataProtectionProvider>().CreateProtector("test");
        protector.Unprotect(protector.Protect("hello")).Should().Be("hello");

        await using var scope = api.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        (await db.DataProtectionKeys.CountAsync(TestContext.Current.CancellationToken)).Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task Timestamps_are_utc_and_created_at_never_changes()
    {
        var ct = TestContext.Current.CancellationToken;
        var time = new FakeTimeProvider(new DateTimeOffset(2026, 10, 12, 1, 2, 3, TimeSpan.Zero));
        var connection = await api.CreateDatabaseAsync("stamps");
        StampedDbContext Open() => new(new DbContextOptionsBuilder<StampedDbContext>()
            .UseNpgsql(connection).UseSnakeCaseNamingConvention()
            .AddInterceptors(new TimestampsInterceptor(time)).Options);

        var thing = new StampedThing { Name = "first" };
        await using (var db = Open())
        {
            await db.Database.EnsureCreatedAsync(ct);
            db.Things.Add(thing);
            await db.SaveChangesAsync(ct);
        }

        time.Advance(TimeSpan.FromMinutes(5));
        await using (var db = Open())
        {
            var loaded = await db.Things.SingleAsync(x => x.Id == thing.Id, ct);
            loaded.Name = "renamed";
            loaded.CreatedAt = DateTime.UnixEpoch;
            await db.SaveChangesAsync(ct);
        }

        await using (var db = Open())
        {
            var saved = await db.Things.AsNoTracking().SingleAsync(x => x.Id == thing.Id, ct);
            saved.CreatedAt.Should().Be(new DateTime(2026, 10, 12, 1, 2, 3, DateTimeKind.Utc));
            saved.CreatedAt.Kind.Should().Be(DateTimeKind.Utc);
            saved.UpdatedAt.Should().Be(new DateTime(2026, 10, 12, 1, 7, 3, DateTimeKind.Utc));
        }
    }
}
```

- [ ] **Step 7: Run**

Run: `dotnet test tests/ExtraSpace.Api.Tests`
Expected: 5 tests pass. The first run pulls `postgres:18.6`, which takes about a minute.

- [ ] **Step 8: Hand-off** — report: build 0/0, the migration file names and their `CreateTable` call, the test output. Do not commit.

---

### Task 3: Error format and trace id

**Files:**
- Create: `../CMS/src/ExtraSpace.Api/Platform/Errors/ErrorCodes.cs`, `AppException.cs`, `AppExceptionHandler.cs`, `ProblemDetailsSetup.cs`, `ProblemWriter.cs`
- Create: `../CMS/src/ExtraSpace.Api/Platform/Tracing/ActivitySetup.cs`, `Correlation.cs`, `RequestTrace.cs`, `RequestTraceMiddleware.cs`
- Modify: `../CMS/src/ExtraSpace.Api/Platform/Hosting/PlatformServices.cs`, `../CMS/src/ExtraSpace.Api/Program.cs`
- Create: `../CMS/tests/ExtraSpace.Api.Tests/TestSupport/Problem.cs`, `Platform/ErrorTests.cs`, `Platform/TraceTests.cs`
- Modify: `../CMS/tests/ExtraSpace.Api.Tests/TestSupport/TestController.cs`

**Interfaces:**
- Consumes: Task 2 (`AppDbContext`, `PlatformServices`, `ApiFactory`, `TestController`).
- Produces:
  - `AppException(int status, string code, string title)`, with `Status`, `Code`, `Title`.
  - `ErrorCodes` constants plus `ErrorCodes.ForStatus(int)`.
  - `ProblemWriter.WriteAsync(HttpContext, int status, string code, string title)` for middleware that answers before MVC.
  - `RequestTrace.HeaderName` (`"X-Trace-Id"`) and `RequestTrace.TraceId(HttpContext)`.
  - `Correlation.CurrentId` and `Correlation.Begin(string correlationId)`. **S0-3's Hangfire filters use these.**
  - `ActivitySetup.EnsureRequestActivities()`.
  - Test side: `Problem.ReadAsync(HttpResponseMessage, int status, string code)` and `Problem.TraceIdOf(HttpResponseMessage)`.

- [ ] **Step 1: Add the test endpoints** — replace `TestController.cs` with:

```csharp
using System.ComponentModel.DataAnnotations;
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Errors;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Tests.TestSupport;

/// <summary>Test-only endpoints, added to the app by <see cref="ApiFactory"/>. Never part of the shipped API.</summary>
[ApiController]
[Route("test")]
public sealed class TestController(AppDbContext db) : ControllerBase
{
    [HttpGet("ok")]
    public IActionResult Ok200() => Ok(new { ok = true });

    [HttpGet("app-error")]
    public IActionResult AppError() => throw new AppException(400, ErrorCodes.InvalidCode, "The code is wrong or has expired");

    [HttpGet("boom")]
    public IActionResult Boom() => throw new InvalidOperationException("secret-detail-12345");

    [HttpGet("concurrency")]
    public IActionResult Concurrency() => throw new DbUpdateConcurrencyException("row changed");

    [HttpGet("unique")]
    public async Task<IActionResult> Unique()
    {
        await db.Database.ExecuteSqlRawAsync(
            "create temp table if not exists t_unique (x int unique); truncate t_unique; insert into t_unique values (1), (1);");
        return Ok();
    }

    [HttpPost("validate")]
    public IActionResult Validate(TestBody body) => Ok(body);

    [HttpGet("status/{status:int}")]
    public IActionResult Status(int status) => StatusCode(status);
}

public sealed class TestBody
{
    [Required, EmailAddress]
    public string? Email { get; set; }

    [Range(1, 10)]
    public int Count { get; set; }
}
```

- [ ] **Step 2: Write the failing tests**

`tests/ExtraSpace.Api.Tests/TestSupport/Problem.cs`:

```csharp
using System.Net.Http.Json;
using System.Text.Json;

namespace ExtraSpace.Api.Tests.TestSupport;

public static class Problem
{
    /// <summary>Asserts the S0 error shape (spec §4.1) and that the body traceId equals the X-Trace-Id header.</summary>
    public static async Task<JsonElement> ReadAsync(HttpResponseMessage response, int status, string code)
    {
        ((int)response.StatusCode).Should().Be(status);
        response.Content.Headers.ContentType?.MediaType.Should().Be("application/problem+json");
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        body.GetProperty("status").GetInt32().Should().Be(status);
        body.GetProperty("code").GetString().Should().Be(code);
        body.GetProperty("traceId").GetString().Should().Be(TraceIdOf(response)).And.MatchRegex("^[0-9a-f]{32}$");
        return body;
    }

    public static string TraceIdOf(HttpResponseMessage response) => response.Headers.GetValues("X-Trace-Id").Single();
}
```

`tests/ExtraSpace.Api.Tests/Platform/ErrorTests.cs`:

```csharp
using System.Net.Http.Json;
using System.Text;
using ExtraSpace.Api.Tests.TestSupport;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class ErrorTests(ApiFactory api)
{
    private readonly HttpClient _client = api.CreateClient();
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task App_exception_keeps_its_status_code_and_title()
    {
        var body = await Problem.ReadAsync(await _client.GetAsync("/test/app-error", Ct), 400, "INVALID_CODE");
        body.GetProperty("title").GetString().Should().Be("The code is wrong or has expired");
    }

    [Fact]
    public async Task Unknown_exception_is_500_without_details()
    {
        var response = await _client.GetAsync("/test/boom", Ct);
        await Problem.ReadAsync(response, 500, "INTERNAL_ERROR");
        var raw = await response.Content.ReadAsStringAsync(Ct);
        raw.Should().NotContain("secret-detail-12345").And.NotContain("InvalidOperationException").And.NotContain("at ExtraSpace");
    }

    [Fact]
    public async Task Validation_errors_are_400_with_camel_case_fields()
    {
        var response = await _client.PostAsJsonAsync("/test/validate", new { email = "not-an-email", count = 99 }, Ct);
        var body = await Problem.ReadAsync(response, 400, "VALIDATION_FAILED");
        var errors = body.GetProperty("errors");
        errors.TryGetProperty("email", out _).Should().BeTrue();
        errors.TryGetProperty("count", out _).Should().BeTrue();
    }

    [Fact]
    public async Task Malformed_json_is_a_validation_error()
    {
        using var content = new StringContent("{ \"email\": ", Encoding.UTF8, "application/json");
        await Problem.ReadAsync(await _client.PostAsync("/test/validate", content, Ct), 400, "VALIDATION_FAILED");
    }

    [Fact]
    public async Task Unknown_route_is_404_problem() =>
        await Problem.ReadAsync(await _client.GetAsync("/no/such/route", Ct), 404, "NOT_FOUND");

    [Fact]
    public async Task Wrong_method_is_405_with_a_fallback_code() =>
        await Problem.ReadAsync(await _client.DeleteAsync("/test/ok", Ct), 405, "HTTP_405");

    [Theory]
    [InlineData(401, "UNAUTHENTICATED")]
    [InlineData(403, "FORBIDDEN")]
    [InlineData(418, "HTTP_418")]
    public async Task Empty_error_responses_become_problems(int status, string code) =>
        await Problem.ReadAsync(await _client.GetAsync($"/test/status/{status}", Ct), status, code);

    [Fact]
    public async Task Concurrency_failure_is_409_conflict() =>
        await Problem.ReadAsync(await _client.GetAsync("/test/concurrency", Ct), 409, "CONFLICT");

    [Fact]
    public async Task Unique_violation_is_409_conflict() =>
        await Problem.ReadAsync(await _client.GetAsync("/test/unique", Ct), 409, "CONFLICT");
}
```

`tests/ExtraSpace.Api.Tests/Platform/TraceTests.cs`:

```csharp
using ExtraSpace.Api.Tests.TestSupport;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class TraceTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Every_response_has_a_new_32_hex_trace_id()
    {
        var client = api.CreateClient();
        var first = Problem.TraceIdOf(await client.GetAsync("/test/ok", Ct));
        var second = Problem.TraceIdOf(await client.GetAsync("/health/live", Ct));
        first.Should().MatchRegex("^[0-9a-f]{32}$");
        second.Should().MatchRegex("^[0-9a-f]{32}$").And.NotBe(first);
    }

    [Fact]
    public async Task Incoming_w3c_traceparent_is_honoured()
    {
        var client = api.CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, "/test/ok");
        request.Headers.Add("traceparent", "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01");
        Problem.TraceIdOf(await client.SendAsync(request, Ct)).Should().Be("0af7651916cd43dd8448eb211c80319c");
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*ErrorTests" --filter-class "*TraceTests"`
Expected: build error `CS0246` for `AppException` / `ErrorCodes`.

- [ ] **Step 4: Implement**

`src/ExtraSpace.Api/Platform/Errors/ErrorCodes.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Errors;

/// <summary>Stable codes the app and admin UI switch on (S0 spec §4.1). Each feature adds its own in its own spec.</summary>
public static class ErrorCodes
{
    public const string ValidationFailed = "VALIDATION_FAILED";
    public const string Unauthenticated = "UNAUTHENTICATED";
    public const string Forbidden = "FORBIDDEN";
    public const string NotFound = "NOT_FOUND";
    public const string Conflict = "CONFLICT";
    public const string RateLimited = "RATE_LIMITED";
    public const string AppUpdateRequired = "APP_UPDATE_REQUIRED";
    public const string InvalidCode = "INVALID_CODE";
    public const string TooManyAttempts = "TOO_MANY_ATTEMPTS";
    public const string InternalError = "INTERNAL_ERROR";

    /// <summary>The code for a response that carries none of its own.</summary>
    public static string ForStatus(int status) => status switch
    {
        400 => ValidationFailed,
        401 => Unauthenticated,
        403 => Forbidden,
        404 => NotFound,
        409 => Conflict,
        426 => AppUpdateRequired,
        429 => RateLimited,
        >= 500 => InternalError,
        _ => $"HTTP_{status}",
    };
}
```

`src/ExtraSpace.Api/Platform/Errors/AppException.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Errors;

/// <summary>A business error with its HTTP status and stable code; the exception handler turns it into ProblemDetails.</summary>
public sealed class AppException(int status, string code, string title) : Exception(title)
{
    public int Status { get; } = status;
    public string Code { get; } = code;
    public string Title { get; } = title;
}
```

`src/ExtraSpace.Api/Platform/Tracing/RequestTrace.cs`:

```csharp
using System.Diagnostics;

namespace ExtraSpace.Api.Platform.Tracing;

public static class RequestTrace
{
    public const string HeaderName = "X-Trace-Id";
    private const string ItemKey = "es.traceId";

    /// <summary>The 32-hex W3C trace id of this request: the same value in the header, the error body and every log line.</summary>
    public static string TraceId(HttpContext http) =>
        http.Items[ItemKey] as string ?? Activity.Current?.TraceId.ToHexString() ?? http.TraceIdentifier;

    internal static void Set(HttpContext http, string traceId) => http.Items[ItemKey] = traceId;
}
```

`src/ExtraSpace.Api/Platform/Tracing/Correlation.cs`:

```csharp
using Serilog.Context;

namespace ExtraSpace.Api.Platform.Tracing;

/// <summary>
/// The traceId of the request that started a chain (S0 spec §4.4). A request's own traceId is its correlationId;
/// S0-3's Hangfire filters carry it into every job the request enqueues.
/// </summary>
public static class Correlation
{
    private static readonly AsyncLocal<string?> Current = new();

    public static string? CurrentId => Current.Value;

    public static IDisposable Begin(string correlationId)
    {
        var previous = Current.Value;
        Current.Value = correlationId;
        return new Scope(previous, LogContext.PushProperty("correlationId", correlationId));
    }

    private sealed class Scope(string? previous, IDisposable logScope) : IDisposable
    {
        public void Dispose()
        {
            logScope.Dispose();
            Current.Value = previous;
        }
    }
}
```

`src/ExtraSpace.Api/Platform/Tracing/ActivitySetup.cs`:

```csharp
using System.Diagnostics;

namespace ExtraSpace.Api.Platform.Tracing;

public static class ActivitySetup
{
    private static int _registered;

    /// <summary>ASP.NET Core only creates a request Activity when something listens; this guarantees one, so every request has a W3C trace id.</summary>
    public static void EnsureRequestActivities()
    {
        if (Interlocked.Exchange(ref _registered, 1) == 1) return;
        ActivitySource.AddActivityListener(new ActivityListener
        {
            ShouldListenTo = source => source.Name == "Microsoft.AspNetCore",
            Sample = static (ref ActivityCreationOptions<ActivityContext> _) => ActivitySamplingResult.AllData,
        });
    }
}
```

`src/ExtraSpace.Api/Platform/Tracing/RequestTraceMiddleware.cs`:

```csharp
using System.Diagnostics;
using Microsoft.Extensions.Primitives;
using Serilog.Context;
using Serilog.Core;
using Serilog.Core.Enrichers;

namespace ExtraSpace.Api.Platform.Tracing;

/// <summary>Step 2 of the pipeline (S0 spec §4.2): sets X-Trace-Id and the request's log context.</summary>
public sealed class RequestTraceMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext http)
    {
        var traceId = Activity.Current?.TraceId.ToHexString() ?? ActivityTraceId.CreateRandom().ToHexString();
        RequestTrace.Set(http, traceId);
        http.Response.OnStarting(() =>
        {
            http.Response.Headers[RequestTrace.HeaderName] = traceId;
            return Task.CompletedTask;
        });

        var properties = new List<ILogEventEnricher> { new PropertyEnricher("method", http.Request.Method) };
        AddHeader(properties, "albTraceId", http.Request.Headers["X-Amzn-Trace-Id"], 128);
        AddHeader(properties, "clientPlatform", http.Request.Headers["X-App-Platform"], 16);
        AddHeader(properties, "clientVersion", http.Request.Headers["X-App-Version"], 32);

        using (Correlation.Begin(traceId))
        using (LogContext.Push([.. properties]))
        {
            await next(http);
        }
    }

    // Client-supplied values: clipped so a header cannot bloat every log line.
    private static void AddHeader(List<ILogEventEnricher> properties, string name, StringValues value, int maxLength)
    {
        var text = value.ToString();
        if (text.Length > 0) properties.Add(new PropertyEnricher(name, text.Length <= maxLength ? text : text[..maxLength]));
    }
}
```

`src/ExtraSpace.Api/Platform/Errors/ProblemDetailsSetup.cs`:

```csharp
using ExtraSpace.Api.Platform.Tracing;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Infrastructure;

namespace ExtraSpace.Api.Platform.Errors;

public static class ProblemDetailsSetup
{
    /// <summary>Runs for every ProblemDetails the app writes: exception handler, status-code pages, MVC, validation, ProblemWriter.</summary>
    public static void Customize(ProblemDetailsContext context)
    {
        var problem = context.ProblemDetails;
        problem.Status ??= context.HttpContext.Response.StatusCode;
        problem.Extensions.TryAdd("code", ErrorCodes.ForStatus(problem.Status.Value));
        // Overwrites the framework's default traceId (the full traceparent form) with our 32-hex id.
        problem.Extensions["traceId"] = RequestTrace.TraceId(context.HttpContext);
    }

    public static IActionResult ValidationResponse(ActionContext context)
    {
        var factory = context.HttpContext.RequestServices.GetRequiredService<ProblemDetailsFactory>();
        var problem = factory.CreateValidationProblemDetails(
            context.HttpContext, context.ModelState, StatusCodes.Status400BadRequest, "One or more fields are invalid.");
        problem.Extensions["code"] = ErrorCodes.ValidationFailed;
        return new BadRequestObjectResult(problem) { ContentTypes = { "application/problem+json" } };
    }
}
```

`src/ExtraSpace.Api/Platform/Errors/ProblemWriter.cs`:

```csharp
using Microsoft.AspNetCore.Mvc;

namespace ExtraSpace.Api.Platform.Errors;

/// <summary>Writes an error response from middleware that runs before MVC (version check, rate limiter).</summary>
public static class ProblemWriter
{
    public static async Task WriteAsync(HttpContext http, int status, string code, string title)
    {
        http.Response.StatusCode = status;
        var problem = new ProblemDetails { Status = status, Title = title };
        problem.Extensions["code"] = code;
        var service = http.RequestServices.GetRequiredService<IProblemDetailsService>();
        await service.TryWriteAsync(new ProblemDetailsContext { HttpContext = http, ProblemDetails = problem });
    }
}
```

`src/ExtraSpace.Api/Platform/Errors/AppExceptionHandler.cs`:

```csharp
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace ExtraSpace.Api.Platform.Errors;

/// <summary>The one place exceptions become responses (S0 spec §4.1) and the one place they are logged (§4.4).</summary>
internal sealed partial class AppExceptionHandler(IProblemDetailsService problems, ILogger<AppExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext http, Exception exception, CancellationToken cancellationToken)
    {
        if (exception is OperationCanceledException && http.RequestAborted.IsCancellationRequested)
        {
            http.Response.StatusCode = 499; // client closed the request; nobody is listening
            return true;
        }

        var (status, code, title) = Classify(exception);
        if (status >= 500) LogUnhandled(logger, exception);

        http.Response.StatusCode = status;
        var problem = new ProblemDetails { Status = status, Title = title };
        problem.Extensions["code"] = code;
        await problems.TryWriteAsync(new ProblemDetailsContext { HttpContext = http, ProblemDetails = problem });
        return true;
    }

    internal static (int Status, string Code, string Title) Classify(Exception exception) => exception switch
    {
        AppException app => (app.Status, app.Code, app.Title),
        DbUpdateConcurrencyException => (409, ErrorCodes.Conflict, "The record was changed by someone else. Reload and try again."),
        _ when IsUniqueViolation(exception) => (409, ErrorCodes.Conflict, "A record with the same value already exists."),
        BadHttpRequestException bad => (bad.StatusCode, ErrorCodes.ForStatus(bad.StatusCode), "The request is invalid."),
        _ => (500, ErrorCodes.InternalError, "An unexpected error occurred."),
    };

    private static bool IsUniqueViolation(Exception exception)
    {
        for (var current = exception; current is not null; current = current.InnerException)
            if (current is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation }) return true;
        return false;
    }

    [LoggerMessage(Level = LogLevel.Error, Message = "Unhandled exception")]
    private static partial void LogUnhandled(ILogger logger, Exception exception);
}
```

Replace `src/ExtraSpace.Api/Platform/Hosting/PlatformServices.cs` with:

```csharp
using System.Text.Json.Serialization;
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Errors;
using ExtraSpace.Api.Platform.Tracing;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc.ModelBinding.Metadata;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Platform.Hosting;

public static class PlatformServices
{
    public static IServiceCollection AddPlatform(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<AppOptions>().Bind(configuration.GetSection(AppOptions.Section)).ValidateOnStart();
        services.AddSingleton(TimeProvider.System);

        services.AddSingleton<TimestampsInterceptor>();
        services.AddDbContext<AppDbContext>((sp, options) => options
            .UseNpgsql(sp.GetRequiredService<IConfiguration>().GetConnectionString("Default")
                ?? throw new InvalidOperationException("ConnectionStrings:Default is not set."))
            .UseSnakeCaseNamingConvention()
            .AddInterceptors(sp.GetRequiredService<TimestampsInterceptor>()));
        services.AddDataProtection().SetApplicationName("ExtraSpace").PersistKeysToDbContext<AppDbContext>();
        services.AddHealthChecks().AddDbContextCheck<AppDbContext>("database", tags: ["ready"]);

        ActivitySetup.EnsureRequestActivities();
        services.AddExceptionHandler<AppExceptionHandler>();
        services.AddProblemDetails(o => o.CustomizeProblemDetails = ProblemDetailsSetup.Customize);
        services.AddControllers(o => o.ModelMetadataDetailsProviders.Add(new SystemTextJsonValidationMetadataProvider()))
            .AddJsonOptions(o => o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter()))
            .ConfigureApiBehaviorOptions(o => o.InvalidModelStateResponseFactory = ProblemDetailsSetup.ValidationResponse);
        return services;
    }
}
```

Replace `src/ExtraSpace.Api/Program.cs` with:

```csharp
using ExtraSpace.Api.Platform.Health;
using ExtraSpace.Api.Platform.Hosting;
using ExtraSpace.Api.Platform.Tracing;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddPlatform(builder.Configuration);

var app = builder.Build();

app.UseMiddleware<RequestTraceMiddleware>();
app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseRouting();
app.MapControllers();
app.MapHealthEndpoints();
app.Run();

public partial class Program;
```

- [ ] **Step 5: Run**

Run: `dotnet test tests/ExtraSpace.Api.Tests`
Expected: all pass (5 from Task 2 + 13 here = 18). If `Unknown_exception_is_500_without_details` shows `traceId` in the full `00-…-01` form, the customizer ran before the framework default: check that `Customize` overwrites (`Extensions["traceId"] =`), not `TryAdd`.

- [ ] **Step 6: Hand-off** — report the build and test output. Do not commit.

---

### Task 4: Structured logging and tracing

**Files:**
- Create: `../CMS/src/ExtraSpace.Api/Platform/Logging/LoggingSetup.cs`, `LoggingOptions.cs`, `FeatureEnricher.cs`, `SensitiveDataMasker.cs`, `Pii.cs`, `RequestLog.cs`, `RequestSummaryMiddleware.cs`, `RouteLogContextMiddleware.cs`
- Create: `../CMS/src/ExtraSpace.Api/Platform/Data/SlowQueryInterceptor.cs`
- Modify: `../CMS/src/ExtraSpace.Api/Platform/Hosting/PlatformServices.cs`, `../CMS/src/ExtraSpace.Api/Program.cs`
- Create: `../CMS/tests/ExtraSpace.Api.Tests/TestSupport/LogCapture.cs`, `Platform/LoggingTests.cs`, `Platform/PiiTests.cs`, `Platform/SlowQueryTests.cs`
- Modify: `../CMS/tests/ExtraSpace.Api.Tests/ApiFactory.cs`, `TestSupport/TestController.cs`

**Interfaces:**
- Consumes: Task 3 (`RequestTraceMiddleware`, `Correlation`, `AppExceptionHandler`).
- Produces:
  - `LoggingSetup.AddPlatformLogging(this WebApplicationBuilder)` and `LoggingSetup.CreateJsonFormatter()`.
  - `Pii.MaskEmail(string?)`.
  - `RequestLog.Add(HttpContext, string name, object value)`. **S0-3 calls it with `customerId` and S0-4 with `staffId`**, after sign-in. **Changed in fix round 1: it returns `void`** (properties live in `HttpContext.Items`, added to every line by `RequestContextEnricher`); the code blocks below show the first version.
  - `LoggingOptions` (`Section = "Logging"`, `SlowQueryMs = 500`) and `SlowQueryInterceptor`.
  - Log fields: `timestamp`, `level`, `message`, `messageTemplate`, `exception`, `traceId`, `spanId`, `correlationId`, `app`, `env`, `role`, `version`, `SourceContext`, `feature`, `method`, `route`, `albTraceId`, `clientPlatform`, `clientVersion`.
  - Test side: `ApiFactory.Logs` (`LogCapture`, with `LinesFor(string traceId)` returning parsed JSON lines).

- [ ] **Step 1: Capture logs in tests**

`tests/ExtraSpace.Api.Tests/TestSupport/LogCapture.cs`:

```csharp
using System.Collections.Concurrent;
using System.Text.Json;
using ExtraSpace.Api.Platform.Logging;
using Serilog.Core;
using Serilog.Events;
using Serilog.Formatting;

namespace ExtraSpace.Api.Tests.TestSupport;

/// <summary>Receives every log event and renders it with the production JSON formatter, so tests see the real lines.</summary>
public sealed class LogCapture : ILogEventSink
{
    private readonly ConcurrentQueue<string> _lines = new();
    private readonly ITextFormatter _formatter = LoggingSetup.CreateJsonFormatter();

    public void Emit(LogEvent logEvent)
    {
        using var writer = new StringWriter();
        _formatter.Format(logEvent, writer);
        _lines.Enqueue(writer.ToString());
    }

    public IReadOnlyList<string> RawLinesFor(string traceId) =>
        _lines.Where(line => line.Contains(traceId, StringComparison.Ordinal)).ToList();

    public IReadOnlyList<JsonElement> LinesFor(string traceId) =>
        RawLinesFor(traceId)
            .Select(line => JsonDocument.Parse(line).RootElement)
            .Where(e => e.TryGetProperty("traceId", out var t) && t.GetString() == traceId)
            .ToList();
}
```

Replace `ApiFactory.ConfigureWebHost` and add the `Logs` property (the rest of the file stays):

```csharp
    public LogCapture Logs { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("ConnectionStrings:Default", ConnectionString);
        builder.ConfigureTestServices(services =>
        {
            services.AddControllers().AddApplicationPart(typeof(TestController).Assembly);
            services.AddSingleton<Serilog.Core.ILogEventSink>(Logs);
        });
    }
```

In `TestController`, change the constructor to `TestController(AppDbContext db, ILogger<TestController> logger)`, add `using ExtraSpace.Api.Platform.Logging;` and `using Microsoft.Extensions.Logging;`, and add:

```csharp
    [HttpGet("log-secrets")]
    public IActionResult LogSecrets()
    {
        logger.LogInformation(
            "Sign-in check {password} {refreshToken} {loginCode} {authorization} {email} {safe} {@session}",
            "pw-SENTINEL", "rt-SENTINEL", "654321", "Bearer ah-SENTINEL", Pii.MaskEmail("jane@example.com"), "visible-value",
            new { SessionToken = "st-SENTINEL", Device = "pixel" });
        return Ok();
    }

    [HttpGet("customer-line")]
    public IActionResult CustomerLine()
    {
        RequestLog.Add(HttpContext, "customerId", "c-123");
        logger.LogInformation("Customer did a thing");
        return Ok();
    }
```

- [ ] **Step 2: Write the failing tests**

`tests/ExtraSpace.Api.Tests/Platform/LoggingTests.cs`:

```csharp
using System.Text.Json;
using ExtraSpace.Api.Platform.Logging;
using ExtraSpace.Api.Tests.TestSupport;
using Serilog.Events;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class LoggingTests(ApiFactory api)
{
    private readonly HttpClient _client = api.CreateClient();
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private static string? Str(JsonElement line, string name) =>
        line.TryGetProperty(name, out var value) ? value.ToString() : null;

    [Fact]
    public async Task Error_response_trace_id_matches_its_log_lines()
    {
        var response = await _client.GetAsync("/test/boom", Ct);
        var traceId = (await Problem.ReadAsync(response, 500, "INTERNAL_ERROR")).GetProperty("traceId").GetString()!;

        var lines = api.Logs.LinesFor(traceId);
        lines.Should().NotBeEmpty();
        lines.Should().AllSatisfy(line =>
        {
            Str(line, "correlationId").Should().Be(traceId);
            Str(line, "app").Should().Be("ExtraSpace");
            Str(line, "env").Should().Be("Testing");
            Str(line, "role").Should().Be("all");
            Str(line, "version").Should().Be("dev");
            Str(line, "method").Should().Be("GET");
            line.TryGetProperty("spanId", out _).Should().BeTrue();
        });

        var withException = lines.Where(l => l.TryGetProperty("exception", out _)).ToList();
        withException.Should().ContainSingle("an exception is logged exactly once");
        Str(withException[0], "level").Should().Be("Error");
        Str(withException[0], "exception").Should().Contain("secret-detail-12345");

        var summary = lines.Single(l => Str(l, "messageTemplate")!.StartsWith("HTTP "));
        Str(summary, "level").Should().Be("Error");
        Str(summary, "route").Should().Be("test/boom");
        Str(summary, "status").Should().Be("500");
        summary.TryGetProperty("elapsedMs", out _).Should().BeTrue();
    }

    [Fact]
    public async Task Lines_are_json_with_plain_field_names()
    {
        var traceId = Problem.TraceIdOf(await _client.GetAsync("/test/ok", Ct));
        var raw = api.Logs.RawLinesFor(traceId).Should().ContainSingle().Subject;
        raw.Should().EndWith("\n");
        var line = JsonDocument.Parse(raw).RootElement;
        foreach (var field in new[] { "timestamp", "level", "message", "messageTemplate", "traceId", "spanId" })
            line.TryGetProperty(field, out _).Should().BeTrue(field);
        line.EnumerateObject().Should().NotContain(p => p.Name.StartsWith('@'));
        Str(line, "messageTemplate").Should().Be("HTTP {method} {route} responded {status} in {elapsedMs} ms");
        Str(line, "message").Should().Contain("test/ok").And.Contain("200");
    }

    [Theory]
    [InlineData("/test/ok", "Information")]
    [InlineData("/test/status/403", "Warning")]
    [InlineData("/test/status/429", "Warning")]
    [InlineData("/test/status/404", "Information")]
    [InlineData("/test/boom", "Error")]
    public async Task Summary_level_follows_the_status(string path, string level)
    {
        var traceId = Problem.TraceIdOf(await _client.GetAsync(path, Ct));
        var summary = api.Logs.LinesFor(traceId).Single(l => Str(l, "messageTemplate")!.StartsWith("HTTP "));
        Str(summary, "level").Should().Be(level);
    }

    [Fact]
    public async Task Health_checks_are_not_logged_when_healthy()
    {
        var traceId = Problem.TraceIdOf(await _client.GetAsync("/health/live", Ct));
        api.Logs.LinesFor(traceId).Should().BeEmpty();
    }

    [Fact]
    public async Task Secret_named_properties_are_masked_everywhere()
    {
        var traceId = Problem.TraceIdOf(await _client.GetAsync("/test/log-secrets", Ct));
        var raw = api.Logs.RawLinesFor(traceId).Single(l => l.Contains("Sign-in check", StringComparison.Ordinal));
        raw.Should().NotContain("SENTINEL").And.NotContain("654321").And.NotContain("jane@");
        raw.Should().Contain("visible-value").And.Contain("pixel").And.Contain("j***@example.com");
        var line = JsonDocument.Parse(raw).RootElement;
        foreach (var name in new[] { "password", "refreshToken", "loginCode", "authorization" })
            Str(line, name).Should().Be("***", name);
        line.GetProperty("session").GetProperty("SessionToken").GetString().Should().Be("***");
    }

    [Fact]
    public async Task Request_properties_reach_later_lines_and_the_summary()
    {
        var traceId = Problem.TraceIdOf(await _client.GetAsync("/test/customer-line", Ct));
        var lines = api.Logs.LinesFor(traceId);
        Str(lines.Single(l => Str(l, "messageTemplate") == "Customer did a thing"), "customerId").Should().Be("c-123");
        Str(lines.Single(l => Str(l, "messageTemplate")!.StartsWith("HTTP ")), "customerId").Should().Be("c-123");
        Str(lines.Single(l => Str(l, "messageTemplate") == "Customer did a thing"), "route").Should().Be("test/customer-line");
    }

    [Fact]
    public void Feature_comes_from_the_namespace()
    {
        static LogEvent Event(string source) => new(DateTimeOffset.UnixEpoch, LogEventLevel.Information, null,
            Serilog.Events.MessageTemplate.Empty, [new LogEventProperty("SourceContext", new ScalarValue(source))]);

        var feature = Event("ExtraSpace.Api.Features.Identity.LoginService");
        new FeatureEnricher().Enrich(feature, null!);
        feature.Properties["feature"].ToString().Should().Be("\"Identity\"");

        var platform = Event("ExtraSpace.Api.Platform.Errors.AppExceptionHandler");
        new FeatureEnricher().Enrich(platform, null!);
        platform.Properties.Should().NotContainKey("feature");
    }
}
```

`tests/ExtraSpace.Api.Tests/Platform/PiiTests.cs`:

```csharp
using ExtraSpace.Api.Platform.Logging;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class PiiTests
{
    [Theory]
    [InlineData("jane@gmail.com", "j***@gmail.com")]
    [InlineData("j@x.io", "j***@x.io")]
    [InlineData("  Jane@Gmail.com ", "J***@Gmail.com")]
    [InlineData("a@b@c.com", "a***@c.com")]
    [InlineData("no-at-sign", "***")]
    [InlineData("@x.com", "***")]
    [InlineData("x@", "***")]
    [InlineData("", "***")]
    [InlineData(null, "***")]
    public void Mask_email(string? input, string expected) => Pii.MaskEmail(input).Should().Be(expected);
}
```

`tests/ExtraSpace.Api.Tests/Platform/SlowQueryTests.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Logging;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Testing;
using Microsoft.Extensions.Options;
using Npgsql;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class SlowQueryTests(ApiFactory api)
{
    [Fact]
    public async Task Slow_commands_log_a_warning_with_the_sql_but_never_parameter_values()
    {
        var ct = TestContext.Current.CancellationToken;
        var logger = new FakeLogger<SlowQueryInterceptor>();
        var interceptor = new SlowQueryInterceptor(Options.Create(new LoggingOptions { SlowQueryMs = 100 }), logger);
        var connection = await api.CreateDatabaseAsync("slow");
        await using var db = new StampedDbContext(new DbContextOptionsBuilder<StampedDbContext>()
            .UseNpgsql(connection).AddInterceptors(interceptor).Options);

        await db.Database.ExecuteSqlRawAsync("select 1", ct);
        logger.Collector.Count.Should().Be(0);

        await db.Database.ExecuteSqlRawAsync("select pg_sleep(0.3) where @p is not null", [new NpgsqlParameter("p", "SENTINEL-VALUE")], ct);
        var record = logger.Collector.GetSnapshot().Should().ContainSingle().Subject;
        record.Level.Should().Be(Microsoft.Extensions.Logging.LogLevel.Warning);
        record.Message.Should().Contain("pg_sleep").And.NotContain("SENTINEL-VALUE");
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*LoggingTests" --filter-class "*PiiTests" --filter-class "*SlowQueryTests"`
Expected: build error `CS0246` for `LoggingSetup` / `Pii` / `SlowQueryInterceptor`.

- [ ] **Step 4: Implement**

`src/ExtraSpace.Api/Platform/Logging/LoggingOptions.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Logging;

public sealed class LoggingOptions
{
    public const string Section = "Logging";

    /// <summary>Database commands slower than this log a Warning (S0 spec §4.4).</summary>
    public int SlowQueryMs { get; set; } = 500;
}
```

`src/ExtraSpace.Api/Platform/Logging/Pii.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Logging;

public static class Pii
{
    /// <summary><c>jane@gmail.com</c> → <c>j***@gmail.com</c>. The only way an email may appear in a log (S0 spec §4.4).</summary>
    public static string MaskEmail(string? email)
    {
        if (string.IsNullOrWhiteSpace(email)) return "***";
        var trimmed = email.Trim();
        var at = trimmed.LastIndexOf('@');
        if (at <= 0 || at == trimmed.Length - 1) return "***";
        return string.Concat(trimmed.AsSpan(0, 1), "***", trimmed.AsSpan(at));
    }
}
```

`src/ExtraSpace.Api/Platform/Logging/FeatureEnricher.cs`:

```csharp
using Serilog.Core;
using Serilog.Events;

namespace ExtraSpace.Api.Platform.Logging;

/// <summary>Adds <c>feature</c> (for example <c>Identity</c>) from a logger in <c>ExtraSpace.Api.Features.&lt;Feature&gt;</c>.</summary>
internal sealed class FeatureEnricher : ILogEventEnricher
{
    private const string Prefix = "ExtraSpace.Api.Features.";

    public void Enrich(LogEvent logEvent, ILogEventPropertyFactory propertyFactory)
    {
        if (!logEvent.Properties.TryGetValue("SourceContext", out var value) || value is not ScalarValue { Value: string source }
            || !source.StartsWith(Prefix, StringComparison.Ordinal)) return;
        var rest = source.AsSpan(Prefix.Length);
        var dot = rest.IndexOf('.');
        logEvent.AddPropertyIfAbsent(new LogEventProperty("feature", new ScalarValue((dot < 0 ? rest : rest[..dot]).ToString())));
    }
}
```

`src/ExtraSpace.Api/Platform/Logging/SensitiveDataMasker.cs`:

```csharp
using Serilog.Core;
using Serilog.Events;

namespace ExtraSpace.Api.Platform.Logging;

/// <summary>
/// Second line of defence (S0 spec §4.4): any property, or property of a logged object, whose name looks secret is replaced by ***.
/// Registered last, so it also sees properties added by the other enrichers and by log scopes.
/// </summary>
internal sealed class SensitiveDataMasker : ILogEventEnricher
{
    internal const string Mask = "***";
    private static readonly string[] Fragments = ["token", "secret", "password", "logincode", "authorization", "cookie", "connectionstring"];

    internal static bool IsSensitive(string name)
    {
        foreach (var fragment in Fragments)
            if (name.Contains(fragment, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    public void Enrich(LogEvent logEvent, ILogEventPropertyFactory propertyFactory)
    {
        foreach (var (name, value) in logEvent.Properties.ToArray())
        {
            var masked = IsSensitive(name) ? new ScalarValue(Mask) : MaskNested(value);
            if (!ReferenceEquals(masked, value)) logEvent.AddOrUpdateProperty(new LogEventProperty(name, masked));
        }
    }

    private static LogEventPropertyValue MaskNested(LogEventPropertyValue value)
    {
        switch (value)
        {
            case StructureValue structure:
            {
                var changed = false;
                var properties = new List<LogEventProperty>(structure.Properties.Count);
                foreach (var property in structure.Properties)
                {
                    var masked = IsSensitive(property.Name) ? new ScalarValue(Mask) : MaskNested(property.Value);
                    changed |= !ReferenceEquals(masked, property.Value);
                    properties.Add(new LogEventProperty(property.Name, masked));
                }
                return changed ? new StructureValue(properties, structure.TypeTag) : structure;
            }
            case SequenceValue sequence:
            {
                var elements = sequence.Elements.Select(MaskNested).ToList();
                return elements.Where((e, i) => !ReferenceEquals(e, sequence.Elements[i])).Any() ? new SequenceValue(elements) : sequence;
            }
            default:
                return value;
        }
    }
}
```

`src/ExtraSpace.Api/Platform/Logging/RequestLog.cs`:

```csharp
using Serilog.Context;

namespace ExtraSpace.Api.Platform.Logging;

public static class RequestLog
{
    private const string ItemKey = "es.requestLog";

    /// <summary>Adds a property to every later log line of this request and to its summary line (for example <c>customerId</c> after sign-in).</summary>
    public static IDisposable Add(HttpContext http, string name, object value)
    {
        Properties(http)[name] = value;
        return LogContext.PushProperty(name, value);
    }

    internal static Dictionary<string, object> Properties(HttpContext http)
    {
        if (http.Items[ItemKey] is not Dictionary<string, object> properties)
            http.Items[ItemKey] = properties = new();
        return properties;
    }
}
```

`src/ExtraSpace.Api/Platform/Logging/RequestSummaryMiddleware.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Logging;

/// <summary>One summary line per request (S0 spec §4.4). Health checks are logged only when they fail.</summary>
internal sealed partial class RequestSummaryMiddleware(RequestDelegate next, ILogger<RequestSummaryMiddleware> logger, TimeProvider time)
{
    public async Task InvokeAsync(HttpContext http)
    {
        var start = time.GetTimestamp();
        try
        {
            await next(http);
        }
        finally
        {
            var status = http.Response.StatusCode;
            if (status >= 500 || !http.Request.Path.StartsWithSegments("/health"))
            {
                // The exception handler clears the endpoint before it writes a 500, so the route saved after routing comes first.
                var route = http.Items[RouteLogContextMiddleware.RouteItemKey] as string
                    ?? (http.GetEndpoint() as RouteEndpoint)?.RoutePattern.RawText
                    ?? "(unmatched)";
                var elapsedMs = (long)time.GetElapsedTime(start).TotalMilliseconds;
                var properties = RequestLog.Properties(http);
                using (properties.Count > 0 ? logger.BeginScope(properties) : null)
                {
                    Summary(logger, LevelFor(status), http.Request.Method, route, status, elapsedMs);
                }
            }
        }
    }

    internal static LogLevel LevelFor(int status) => status switch
    {
        >= 500 => LogLevel.Error,
        403 or 429 => LogLevel.Warning,
        _ => LogLevel.Information,
    };

    [LoggerMessage(Message = "HTTP {method} {route} responded {status} in {elapsedMs} ms")]
    private static partial void Summary(ILogger logger, LogLevel level, string method, string route, int status, long elapsedMs);
}
```

`src/ExtraSpace.Api/Platform/Logging/RouteLogContextMiddleware.cs`:

```csharp
using Serilog.Context;

namespace ExtraSpace.Api.Platform.Logging;

/// <summary>Runs after routing: adds the route template (never the raw path) to every log line of the request.</summary>
internal sealed class RouteLogContextMiddleware(RequestDelegate next)
{
    internal const string RouteItemKey = "es.route";

    public async Task InvokeAsync(HttpContext http)
    {
        if ((http.GetEndpoint() as RouteEndpoint)?.RoutePattern.RawText is not { } route)
        {
            await next(http);
            return;
        }
        http.Items[RouteItemKey] = route;
        using (LogContext.PushProperty("route", route))
        {
            await next(http);
        }
    }
}
```

`src/ExtraSpace.Api/Platform/Logging/LoggingSetup.cs`:

```csharp
using System.Globalization;
using ExtraSpace.Api.Platform.Hosting;
using Microsoft.Extensions.Options;
using Serilog;
using Serilog.Formatting;
using Serilog.Templates;

namespace ExtraSpace.Api.Platform.Logging;

public static class LoggingSetup
{
    // One JSON object per line (S0 spec §4.4). Plain field names: CloudWatch Logs Insights reserves names that start with '@'.
    private const string JsonTemplate =
        "{ {timestamp: UtcDateTime(@t), level: @l, message: @m, messageTemplate: @mt, exception: @x, traceId: @tr, spanId: @sp, ..@p} }\n";

    public static ITextFormatter CreateJsonFormatter() => new ExpressionTemplate(JsonTemplate, CultureInfo.InvariantCulture);

    public static WebApplicationBuilder AddPlatformLogging(this WebApplicationBuilder builder)
    {
        var environment = builder.Environment;
        var configuration = builder.Configuration;
        builder.Services.AddSerilog((services, logger) =>
        {
            var app = services.GetRequiredService<IOptions<AppOptions>>().Value;
            logger.ReadFrom.Configuration(configuration)
                .ReadFrom.Services(services)
                .Enrich.FromLogContext()
                .Enrich.WithProperty("app", "ExtraSpace")
                .Enrich.WithProperty("env", environment.EnvironmentName)
                .Enrich.WithProperty("role", app.Role.ToString().ToLowerInvariant())
                .Enrich.WithProperty("version", app.Version)
                .Enrich.With<FeatureEnricher>()
                .Enrich.With<SensitiveDataMasker>();

            if (environment.IsDevelopment())
            {
                logger.WriteTo.Console(
                    outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj} trace={TraceId}{NewLine}{Exception}",
                    formatProvider: CultureInfo.InvariantCulture);
                if (configuration["Seq:Url"] is { Length: > 0 } seqUrl) logger.WriteTo.Seq(seqUrl);
            }
            else
            {
                logger.WriteTo.Console(CreateJsonFormatter());
            }
        });
        return builder;
    }
}
```

`src/ExtraSpace.Api/Platform/Data/SlowQueryInterceptor.cs`:

```csharp
using System.Data.Common;
using ExtraSpace.Api.Platform.Logging;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Options;

namespace ExtraSpace.Api.Platform.Data;

/// <summary>Warns about slow database commands with the SQL text and time; parameter values are never logged (S0 spec §4.4).</summary>
public sealed partial class SlowQueryInterceptor(IOptions<LoggingOptions> options, ILogger<SlowQueryInterceptor> logger) : DbCommandInterceptor
{
    public override DbDataReader ReaderExecuted(DbCommand command, CommandExecutedEventData eventData, DbDataReader result)
    {
        Check(command, eventData);
        return result;
    }

    public override ValueTask<DbDataReader> ReaderExecutedAsync(
        DbCommand command, CommandExecutedEventData eventData, DbDataReader result, CancellationToken cancellationToken = default)
    {
        Check(command, eventData);
        return ValueTask.FromResult(result);
    }

    public override int NonQueryExecuted(DbCommand command, CommandExecutedEventData eventData, int result)
    {
        Check(command, eventData);
        return result;
    }

    public override ValueTask<int> NonQueryExecutedAsync(
        DbCommand command, CommandExecutedEventData eventData, int result, CancellationToken cancellationToken = default)
    {
        Check(command, eventData);
        return ValueTask.FromResult(result);
    }

    public override object? ScalarExecuted(DbCommand command, CommandExecutedEventData eventData, object? result)
    {
        Check(command, eventData);
        return result;
    }

    public override ValueTask<object?> ScalarExecutedAsync(
        DbCommand command, CommandExecutedEventData eventData, object? result, CancellationToken cancellationToken = default)
    {
        Check(command, eventData);
        return ValueTask.FromResult(result);
    }

    private void Check(DbCommand command, CommandExecutedEventData eventData)
    {
        var elapsedMs = (long)eventData.Duration.TotalMilliseconds;
        if (elapsedMs > options.Value.SlowQueryMs) SlowCommand(logger, elapsedMs, command.CommandText);
    }

    [LoggerMessage(Level = LogLevel.Warning, Message = "Slow database command took {elapsedMs} ms: {commandText}")]
    private static partial void SlowCommand(ILogger logger, long elapsedMs, string commandText);
}
```

In `PlatformServices.AddPlatform`, add after the `AppOptions` line:

```csharp
        services.Configure<LoggingOptions>(configuration.GetSection(LoggingOptions.Section));
```

register the interceptor next to `TimestampsInterceptor`, and add it to the DbContext:

```csharp
        services.AddSingleton<TimestampsInterceptor>();
        services.AddSingleton<SlowQueryInterceptor>();
        services.AddDbContext<AppDbContext>((sp, options) => options
            .UseNpgsql(sp.GetRequiredService<IConfiguration>().GetConnectionString("Default")
                ?? throw new InvalidOperationException("ConnectionStrings:Default is not set."))
            .UseSnakeCaseNamingConvention()
            .AddInterceptors(sp.GetRequiredService<TimestampsInterceptor>(), sp.GetRequiredService<SlowQueryInterceptor>()));
```

(and `using ExtraSpace.Api.Platform.Logging;`).

Replace `src/ExtraSpace.Api/Program.cs` with:

```csharp
using ExtraSpace.Api.Platform.Health;
using ExtraSpace.Api.Platform.Hosting;
using ExtraSpace.Api.Platform.Logging;
using ExtraSpace.Api.Platform.Tracing;

var builder = WebApplication.CreateBuilder(args);
builder.AddPlatformLogging();
builder.Services.AddPlatform(builder.Configuration);

var app = builder.Build();

app.UseMiddleware<RequestTraceMiddleware>();
app.UseMiddleware<RequestSummaryMiddleware>();
app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseRouting();
app.UseMiddleware<RouteLogContextMiddleware>();
app.MapControllers();
app.MapHealthEndpoints();
app.Run();

public partial class Program;
```

- [ ] **Step 5: Run**

Run: `dotnet test tests/ExtraSpace.Api.Tests`
Expected: 39 pass (18 earlier + 11 logging + 9 Pii + 1 slow query).

If `Error_response_trace_id_matches_its_log_lines` finds **two** exception lines, the framework's `ExceptionHandlerMiddleware` also logged. Fix it in `Program.cs`, never in the test: `app.UseExceptionHandler(new ExceptionHandlerOptions { SuppressDiagnosticsCallback = _ => true });`. If that option does not exist in 10.0.11, add `"Microsoft.AspNetCore.Diagnostics.ExceptionHandlerMiddleware": "Fatal"` under `Serilog:MinimumLevel:Override` in `appsettings.json`.

- [ ] **Step 6: Hand-off** — report the build and test output. Do not commit.

---

### Task 5: The rest of the pipeline — forwarded headers, security headers, CORS, rate limiter, app-version check, OpenAPI

**Files:**
- Create: `../CMS/src/ExtraSpace.Api/Platform/Http/SecurityHeadersMiddleware.cs`, `AppVersion.cs`, `AppVersionMiddleware.cs`, `RateLimitSetup.cs`
- Modify: `../CMS/src/ExtraSpace.Api/Platform/Hosting/PlatformServices.cs`, `../CMS/src/ExtraSpace.Api/Program.cs`
- Create: `../CMS/tests/ExtraSpace.Api.Tests/Platform/HttpPipelineTests.cs`, `Platform/AppVersionTests.cs`, `Platform/ApiDocsTests.cs`
- Modify: `../CMS/tests/ExtraSpace.Api.Tests/ApiFactory.cs`, `TestSupport/TestController.cs`

**Interfaces:**
- Consumes: Tasks 3–4 (`ProblemWriter`, `ErrorCodes`, `RequestTrace`, `AppOptions.MinVersion`).
- Produces:
  - `AppVersion.Parse(string?) : Version?`.
  - `RateLimitSetup.Configure(RateLimiterOptions)`. S0-3 adds its policies with `services.AddRateLimiter(o => o.AddPolicy(...))` and partitions per IP on `HttpContext.Connection.RemoteIpAddress`, which the forwarded headers have already set.
  - The final pipeline order of spec §4.2. S0-3/S0-4 only register authentication schemes and policies (`AddAuthentication`/`AddAuthorization` are already called). S0-5 fills slots 7 and 15 (`/admin` static files and SPA fallback).
  - Owed by S0-3, because S0-2 has no signed-in route: a test that an outdated app gets 426 on an authenticated route, not 401.

- [ ] **Step 1: Configure the test host** — in `ApiFactory.ConfigureWebHost` add these lines after the connection string, and the rate-limit policy inside `ConfigureTestServices` (add `using Microsoft.AspNetCore.RateLimiting;`):

```csharp
        builder.UseSetting("App:MinVersion:ios", "2.0.0");
        builder.UseSetting("App:MinVersion:android", "2.0.0");
        builder.UseSetting("Cors:AllowedOrigins:0", "https://app.example.test");
```

```csharp
            services.Configure<RateLimiterOptions>(o => o.AddFixedWindowLimiter("test-tight", w =>
            {
                w.PermitLimit = 1;
                w.Window = TimeSpan.FromMinutes(1);
            }));
```

Add to `TestController` (also add `using Microsoft.AspNetCore.RateLimiting;`):

```csharp
    [HttpGet("ip")]
    public IActionResult Ip() => Ok(new { ip = HttpContext.Connection.RemoteIpAddress?.ToString(), https = Request.IsHttps });

    [HttpGet("limited")]
    [EnableRateLimiting("test-tight")]
    public IActionResult Limited() => Ok();
```

- [ ] **Step 2: Write the failing tests**

`tests/ExtraSpace.Api.Tests/Platform/HttpPipelineTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ExtraSpace.Api.Tests.TestSupport;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class HttpPipelineTests(ApiFactory api)
{
    private readonly HttpClient _client = api.CreateClient();
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Forwarded_headers_take_only_the_last_hop()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/test/ip");
        request.Headers.Add("X-Forwarded-For", "198.51.100.7, 203.0.113.9");
        request.Headers.Add("X-Forwarded-Proto", "https");
        var body = await (await _client.SendAsync(request, Ct)).Content.ReadFromJsonAsync<JsonElement>(Ct);
        body.GetProperty("ip").GetString().Should().Be("203.0.113.9");
        body.GetProperty("https").GetBoolean().Should().BeTrue();
    }

    [Theory]
    [InlineData("/test/ok")]
    [InlineData("/test/boom")]
    public async Task Security_headers_are_on_success_and_error_responses(string path)
    {
        var response = await _client.GetAsync(path, Ct);
        response.Headers.GetValues("X-Content-Type-Options").Should().Equal("nosniff");
        response.Headers.GetValues("X-Frame-Options").Should().Equal("DENY");
        response.Headers.GetValues("Referrer-Policy").Should().Equal("no-referrer");
        response.Headers.GetValues("Strict-Transport-Security").Should().Equal("max-age=31536000");
    }

    [Fact]
    public async Task Allowed_origin_gets_cors_headers_and_can_read_the_trace_id()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/test/ok");
        request.Headers.Add("Origin", "https://app.example.test");
        var response = await _client.SendAsync(request, Ct);
        response.Headers.GetValues("Access-Control-Allow-Origin").Should().Equal("https://app.example.test");
        response.Headers.GetValues("Access-Control-Expose-Headers").Single().Should().Contain("X-Trace-Id");
    }

    [Fact]
    public async Task Other_origins_get_no_cors_headers()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/test/ok");
        request.Headers.Add("Origin", "https://evil.example.test");
        var response = await _client.SendAsync(request, Ct);
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Headers.Contains("Access-Control-Allow-Origin").Should().BeFalse();
    }

    [Fact]
    public async Task Rate_limited_request_gets_429_problem()
    {
        (await _client.GetAsync("/test/limited", Ct)).StatusCode.Should().Be(HttpStatusCode.OK);
        var response = await _client.GetAsync("/test/limited", Ct);
        await Problem.ReadAsync(response, 429, "RATE_LIMITED");
        response.Headers.Contains("Retry-After").Should().BeTrue();
    }
}
```

`tests/ExtraSpace.Api.Tests/Platform/AppVersionTests.cs`:

```csharp
using System.Net;
using ExtraSpace.Api.Platform.Http;
using ExtraSpace.Api.Tests.TestSupport;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class AppVersionTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Theory]
    [InlineData("1.4.0", "1.4.0")]
    [InlineData("1.4", "1.4.0")]
    [InlineData("1.4.0+12", "1.4.0")]
    [InlineData("1.4.0-beta.2", "1.4.0")]
    [InlineData(" 2.10.3 ", "2.10.3")]
    public void Parse_reads_semver_like_values(string raw, string expected) =>
        AppVersion.Parse(raw).Should().Be(Version.Parse(expected));

    [Theory]
    [InlineData("garbage")]
    [InlineData("1")]
    [InlineData("")]
    [InlineData(null)]
    public void Parse_returns_null_when_it_cannot(string? raw) => AppVersion.Parse(raw).Should().BeNull();

    private async Task<HttpResponseMessage> Send(string? platform, string? version)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/test/ok");
        if (platform is not null) request.Headers.Add("X-App-Platform", platform);
        if (version is not null) request.Headers.Add("X-App-Version", version);
        return await api.CreateClient().SendAsync(request, Ct);
    }

    [Theory]
    [InlineData("ios", "1.9.9")]
    [InlineData("iOS", "1.0.0")]
    [InlineData("android", "1.9.9+99")]
    public async Task Below_the_minimum_is_426(string platform, string version) =>
        await Problem.ReadAsync(await Send(platform, version), 426, "APP_UPDATE_REQUIRED");

    [Theory]
    [InlineData("ios", "2.0.0")]
    [InlineData("ios", "2.0.0+15")]
    [InlineData("android", "3.1.0")]
    [InlineData("web", "0.0.1")]
    [InlineData("ios", "garbage")]
    [InlineData("ios", null)]
    [InlineData(null, "0.0.1")]
    [InlineData(null, null)]
    public async Task Everything_else_passes(string? platform, string? version) =>
        (await Send(platform, version)).StatusCode.Should().Be(HttpStatusCode.OK);
}
```

`tests/ExtraSpace.Api.Tests/Platform/ApiDocsTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class ApiDocsTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task OpenApi_and_swagger_ui_are_served_outside_production()
    {
        var client = api.CreateClient();
        var document = await client.GetFromJsonAsync<JsonElement>("/openapi/v1.json", Ct);
        document.GetProperty("openapi").GetString().Should().StartWith("3.");
        (await client.GetAsync("/swagger/index.html", Ct)).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Production_serves_neither()
    {
        await using var production = api.WithWebHostBuilder(b => b.UseEnvironment("Production"));
        var client = production.CreateClient();
        (await client.GetAsync("/openapi/v1.json", Ct)).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await client.GetAsync("/swagger/index.html", Ct)).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*HttpPipelineTests" --filter-class "*AppVersionTests" --filter-class "*ApiDocsTests"`
Expected: build error `CS0246` for `AppVersion`.

- [ ] **Step 4: Implement**

`src/ExtraSpace.Api/Platform/Http/AppVersion.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Http;

public static class AppVersion
{
    /// <summary>
    /// Reads "1.4.0", "1.4", "1.4.0+12" or "1.4.0-beta.2" as 1.4.0; build and pre-release parts are ignored.
    /// Returns null when the value cannot be read.
    /// </summary>
    public static Version? Parse(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var core = value.Trim();
        var cut = core.IndexOfAny(['-', '+']);
        if (cut >= 0) core = core[..cut];
        if (!Version.TryParse(core, out var version)) return null;
        return new Version(version.Major, version.Minor, Math.Max(version.Build, 0));
    }
}
```

`src/ExtraSpace.Api/Platform/Http/AppVersionMiddleware.cs`:

```csharp
using ExtraSpace.Api.Platform.Errors;
using ExtraSpace.Api.Platform.Hosting;
using Microsoft.Extensions.Options;

namespace ExtraSpace.Api.Platform.Http;

/// <summary>
/// Step 11 (S0 spec §4.3): an app below the platform's minimum version gets 426 before sign-in runs.
/// Requests without both headers (admin UI, health checks, tools) pass, and so does a version that cannot be read.
/// </summary>
internal sealed partial class AppVersionMiddleware(RequestDelegate next, IOptionsMonitor<AppOptions> options, ILogger<AppVersionMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext http)
    {
        var platform = http.Request.Headers["X-App-Platform"].ToString();
        var raw = http.Request.Headers["X-App-Version"].ToString();
        if (platform.Length > 0 && raw.Length > 0 && MinimumFor(platform) is { } minimum)
        {
            var version = AppVersion.Parse(raw);
            if (version is null)
            {
                UnreadableVersion(logger);
            }
            else if (version < minimum)
            {
                await ProblemWriter.WriteAsync(http, StatusCodes.Status426UpgradeRequired, ErrorCodes.AppUpdateRequired,
                    "Please update the app to continue.");
                return;
            }
        }
        await next(http);
    }

    private Version? MinimumFor(string platform)
    {
        foreach (var (name, value) in options.CurrentValue.MinVersion)
            if (string.Equals(name, platform, StringComparison.OrdinalIgnoreCase)) return AppVersion.Parse(value);
        return null;
    }

    // clientPlatform and clientVersion are already on the line (log context, clipped).
    [LoggerMessage(Level = LogLevel.Warning, Message = "Unreadable X-App-Version header; request let through")]
    private static partial void UnreadableVersion(ILogger logger);
}
```

`src/ExtraSpace.Api/Platform/Http/SecurityHeadersMiddleware.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Http;

/// <summary>Step 5. Set in OnStarting, because the exception handler clears headers before it writes an error.</summary>
internal sealed class SecurityHeadersMiddleware(RequestDelegate next, IHostEnvironment environment)
{
    public Task InvokeAsync(HttpContext http)
    {
        http.Response.OnStarting(() =>
        {
            var headers = http.Response.Headers;
            headers.XContentTypeOptions = "nosniff";
            headers.XFrameOptions = "DENY";
            headers["Referrer-Policy"] = "no-referrer";
            if (!environment.IsDevelopment()) headers.StrictTransportSecurity = "max-age=31536000";
            return Task.CompletedTask;
        });
        return next(http);
    }
}
```

`src/ExtraSpace.Api/Platform/Http/RateLimitSetup.cs`:

```csharp
using System.Globalization;
using System.Threading.RateLimiting;
using ExtraSpace.Api.Platform.Errors;
using Microsoft.AspNetCore.RateLimiting;

namespace ExtraSpace.Api.Platform.Http;

/// <summary>The shared 429 answer. Features add their own policies (S0-3: code requests and checks).</summary>
public static class RateLimitSetup
{
    public static void Configure(RateLimiterOptions options)
    {
        options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
        options.OnRejected = async (context, _) =>
        {
            if (context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
                context.HttpContext.Response.Headers.RetryAfter =
                    ((int)Math.Ceiling(retryAfter.TotalSeconds)).ToString(CultureInfo.InvariantCulture);
            await ProblemWriter.WriteAsync(context.HttpContext, StatusCodes.Status429TooManyRequests, ErrorCodes.RateLimited,
                "Too many requests. Try again later.");
        };
    }
}
```

Replace `src/ExtraSpace.Api/Platform/Hosting/PlatformServices.cs` with the final version:

```csharp
using System.Text.Json.Serialization;
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Errors;
using ExtraSpace.Api.Platform.Http;
using ExtraSpace.Api.Platform.Logging;
using ExtraSpace.Api.Platform.Tracing;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Mvc.ModelBinding.Metadata;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Platform.Hosting;

public static class PlatformServices
{
    public static IServiceCollection AddPlatform(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddOptions<AppOptions>().Bind(configuration.GetSection(AppOptions.Section)).ValidateOnStart();
        services.Configure<LoggingOptions>(configuration.GetSection(LoggingOptions.Section));
        services.AddSingleton(TimeProvider.System);

        // Data (S0 spec §5)
        services.AddSingleton<TimestampsInterceptor>();
        services.AddSingleton<SlowQueryInterceptor>();
        services.AddDbContext<AppDbContext>((sp, options) => options
            .UseNpgsql(sp.GetRequiredService<IConfiguration>().GetConnectionString("Default")
                ?? throw new InvalidOperationException("ConnectionStrings:Default is not set."))
            .UseSnakeCaseNamingConvention()
            .AddInterceptors(sp.GetRequiredService<TimestampsInterceptor>(), sp.GetRequiredService<SlowQueryInterceptor>()));
        services.AddDataProtection().SetApplicationName("ExtraSpace").PersistKeysToDbContext<AppDbContext>();
        services.AddHealthChecks().AddDbContextCheck<AppDbContext>("database", tags: ["ready"]);

        // Errors and MVC (S0 spec §4.1)
        ActivitySetup.EnsureRequestActivities();
        services.AddExceptionHandler<AppExceptionHandler>();
        services.AddProblemDetails(o => o.CustomizeProblemDetails = ProblemDetailsSetup.Customize);
        services.AddControllers(o => o.ModelMetadataDetailsProviders.Add(new SystemTextJsonValidationMetadataProvider()))
            .AddJsonOptions(o => o.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter()))
            .ConfigureApiBehaviorOptions(o => o.InvalidModelStateResponseFactory = ProblemDetailsSetup.ValidationResponse);

        // Pipeline (S0 spec §4.2)
        services.Configure<ForwardedHeadersOptions>(o =>
        {
            o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            o.ForwardLimit = 1;          // the ALB appends the real client IP last; earlier entries are client-supplied
            o.KnownIPNetworks.Clear();   // only the ALB can reach the tasks (security groups), and its IPs change
            o.KnownProxies.Clear();
        });
        var corsOrigins = configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
        services.AddCors(o => o.AddDefaultPolicy(p => p
            .WithOrigins(corsOrigins).AllowAnyHeader().AllowAnyMethod().WithExposedHeaders(RequestTrace.HeaderName)));
        services.AddRateLimiter(RateLimitSetup.Configure);
        services.AddAuthentication();
        services.AddAuthorization();
        services.AddOpenApi();
        return services;
    }
}
```

(If `KnownIPNetworks` does not exist in 10.0.11, use `KnownNetworks`.)

Replace `src/ExtraSpace.Api/Program.cs` with the final version:

```csharp
using ExtraSpace.Api.Platform.Health;
using ExtraSpace.Api.Platform.Hosting;
using ExtraSpace.Api.Platform.Http;
using ExtraSpace.Api.Platform.Logging;
using ExtraSpace.Api.Platform.Tracing;

var builder = WebApplication.CreateBuilder(args);
builder.AddPlatformLogging();
builder.Services.AddPlatform(builder.Configuration);

var app = builder.Build();

// Order = S0 spec §4.2.
app.UseForwardedHeaders();                          // 1
app.UseMiddleware<RequestTraceMiddleware>();        // 2
app.UseMiddleware<RequestSummaryMiddleware>();      // 3
app.UseExceptionHandler();                          // 4
app.UseStatusCodePages();                           //   empty error responses become ProblemDetails
app.UseMiddleware<SecurityHeadersMiddleware>();     // 5
                                                    // 6: no HTTPS redirection, TLS ends at the ALB
if (!app.Environment.IsProduction())                // 7: static files (Swagger UI now, /admin in S0-5)
    app.UseSwaggerUI(o =>
    {
        o.SwaggerEndpoint("/openapi/v1.json", "ExtraSpace API v1");
        o.RoutePrefix = "swagger";
    });
app.UseRouting();                                   // 8
app.UseMiddleware<RouteLogContextMiddleware>();
app.UseCors();                                      // 9
app.UseRateLimiter();                               // 10
app.UseMiddleware<AppVersionMiddleware>();          // 11
app.UseAuthentication();                            // 12
app.UseAuthorization();                             // 13
app.MapControllers();                               // 14
app.MapHealthEndpoints();
if (!app.Environment.IsProduction()) app.MapOpenApi();
                                                    // 15: SPA fallback /admin/{*path} in S0-5
app.Run();

public partial class Program;
```

(If Task 4 had to add `SuppressDiagnosticsCallback`, keep it on `UseExceptionHandler`.)

- [ ] **Step 5: Run everything**

Run: `dotnet build ExtraSpace.slnx && dotnet test ExtraSpace.slnx`
Expected: build 0 errors, 0 warnings; Infra 32, Engines 18 and Api 67 tests pass (39 earlier + 6 pipeline + 20 app version + 2 API docs).

- [ ] **Step 6: Hand-off** — report the build and test output. Do not commit.

---

### Task 6: Architecture test

**Files:**
- Create: `../CMS/tests/ExtraSpace.Api.Tests/Architecture/ArchitectureRules.cs`, `Architecture/ArchitectureTests.cs`, `Architecture/Fixtures.cs`

**Interfaces:**
- Consumes: the Api and Engines assemblies.
- Produces: `ArchitectureRules.CrossFeatureViolations(Assembly, string root)`, `LayerViolations(Assembly, string root)`, `ControllerDataAccess(Assembly, string root)` and `ForbiddenEngineReferences(Assembly)`. Each returns the offending type or assembly names; an empty list means the rule holds. 🔴 Never weaken these rules or the fixtures to make a build pass (`.claude/rules/cms.md` rule 10).

- [ ] **Step 1: Write the fixtures** — deliberate violations that prove each rule bites. `tests/ExtraSpace.Api.Tests/Architecture/Fixtures.cs`:

```csharp
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

// Deliberate violations for the architecture tests. "Alphabet" exists to catch a prefix bug: it must not count as part of "Alpha".
namespace ExtraSpace.Api.Tests.ArchFixtures.Features.Beta.Contracts
{
    public interface IBetaService
    {
        int Count();
    }
}

namespace ExtraSpace.Api.Tests.ArchFixtures.Features.Beta
{
    internal sealed class BetaEntity
    {
        public int Id { get; set; }
    }

    internal sealed class BetaService : Contracts.IBetaService
    {
        public int Count() => 0;
    }

    internal sealed class BetaController(ArchFixtures.Platform.FixtureDbContext db) : ControllerBase
    {
        internal int Rows() => db.ChangeTracker.Entries().Count();
    }
}

namespace ExtraSpace.Api.Tests.ArchFixtures.Features.Alpha
{
    internal sealed class AlphaInternal
    {
        public int Value { get; set; }
    }

    internal sealed class AlphaGood(Beta.Contracts.IBetaService beta)
    {
        public int Use() => beta.Count();
    }

    internal sealed class AlphaBad
    {
        public object Peek() => new Beta.BetaEntity();
    }
}

namespace ExtraSpace.Api.Tests.ArchFixtures.Features.Alphabet
{
    internal sealed class AlphabetBad
    {
        public object Peek() => new Alpha.AlphaInternal();
    }
}

namespace ExtraSpace.Api.Tests.ArchFixtures.Platform
{
    internal sealed class FixtureDbContext : DbContext;

    internal sealed class PlatformBad
    {
        public object Peek() => new Features.Beta.BetaEntity();
    }
}
```

- [ ] **Step 2: Write the tests** — `tests/ExtraSpace.Api.Tests/Architecture/ArchitectureTests.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Engines;

namespace ExtraSpace.Api.Tests.Architecture;

public sealed class ArchitectureTests
{
    private const string ApiRoot = "ExtraSpace.Api";
    private const string FixtureRoot = "ExtraSpace.Api.Tests.ArchFixtures";
    private const string Fixtures = FixtureRoot + ".Features.";
    private static readonly System.Reflection.Assembly Api = typeof(AppDbContext).Assembly;
    private static readonly System.Reflection.Assembly Tests = typeof(ArchitectureTests).Assembly;

    [Fact]
    public void The_api_follows_every_rule()
    {
        ArchitectureRules.CrossFeatureViolations(Api, ApiRoot).Should().BeEmpty();
        ArchitectureRules.LayerViolations(Api, ApiRoot).Should().BeEmpty();
        ArchitectureRules.ControllerDataAccess(Api, ApiRoot).Should().BeEmpty();
    }

    [Fact]
    public void Engines_reference_no_ef_aspnet_or_http() =>
        ArchitectureRules.ForbiddenEngineReferences(typeof(Money).Assembly).Should().BeEmpty();

    [Fact]
    public void Cross_feature_rule_catches_use_outside_contracts() =>
        ArchitectureRules.CrossFeatureViolations(Tests, FixtureRoot).Should()
            .BeEquivalentTo(Fixtures + "Alpha.AlphaBad", Fixtures + "Alphabet.AlphabetBad");

    [Fact]
    public void Layer_rule_catches_platform_using_a_feature() =>
        ArchitectureRules.LayerViolations(Tests, FixtureRoot).Should().BeEquivalentTo(FixtureRoot + ".Platform.PlatformBad");

    [Fact]
    public void Controller_rule_catches_a_db_context() =>
        ArchitectureRules.ControllerDataAccess(Tests, FixtureRoot).Should().BeEquivalentTo(Fixtures + "Beta.BetaController");

    [Fact]
    public void Engine_rule_catches_a_forbidden_reference() =>
        ArchitectureRules.ForbiddenEngineReferences(Api).Should().NotBeEmpty();
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*ArchitectureTests"`
Expected: build error `CS0103: The name 'ArchitectureRules' does not exist`.

- [ ] **Step 4: Implement** — `tests/ExtraSpace.Api.Tests/Architecture/ArchitectureRules.cs`:

```csharp
using System.Reflection;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NetArchTest.Rules;

namespace ExtraSpace.Api.Tests.Architecture;

/// <summary>The layout rules of S0 spec §3. Each method returns the offending names; empty means the rule holds.</summary>
public static class ArchitectureRules
{
    /// <summary>Feature X may use feature Y only through <c>Y.Contracts</c> (this also catches <c>db.Set&lt;YEntity&gt;()</c>).</summary>
    public static IReadOnlyList<string> CrossFeatureViolations(Assembly assembly, string root)
    {
        var featuresPrefix = root + ".Features.";
        var featureTypes = assembly.GetTypes()
            .Where(t => t.Namespace?.StartsWith(featuresPrefix, StringComparison.Ordinal) == true)
            .ToList();
        var features = featureTypes.Select(t => FeatureOf(t.Namespace!, featuresPrefix)).Distinct().ToList();

        var violations = new List<string>();
        foreach (var x in features)
        foreach (var y in features.Where(y => y != x))
        {
            var internals = featureTypes
                .Where(t => FeatureOf(t.Namespace!, featuresPrefix) == y && !IsContracts(t.Namespace!, featuresPrefix + y))
                .Select(t => t.FullName!)
                .ToArray();
            if (internals.Length == 0) continue;
            var result = Types.InAssembly(assembly)
                .That().ResideInNamespaceMatching(Under(featuresPrefix + x))
                .ShouldNot().HaveDependencyOnAny(internals)
                .GetResult();
            violations.AddRange(Failures(result));
        }
        return violations.Distinct().ToList();
    }

    /// <summary><c>Platform/</c> and <c>Integrations/</c> never depend on <c>Features/</c>.</summary>
    public static IReadOnlyList<string> LayerViolations(Assembly assembly, string root) =>
        Failures(Types.InAssembly(assembly)
            .That().ResideInNamespaceMatching($"^{Regex.Escape(root)}\\.(Platform|Integrations)(\\.|$)")
            .ShouldNot().HaveDependencyOn(root + ".Features.")
            .GetResult());

    /// <summary>Controllers call a service; they never touch a DbContext or EF Core.</summary>
    public static IReadOnlyList<string> ControllerDataAccess(Assembly assembly, string root)
    {
        var dbContexts = assembly.GetTypes().Where(t => typeof(DbContext).IsAssignableFrom(t)).Select(t => t.FullName!);
        return Failures(Types.InAssembly(assembly)
            .That().ResideInNamespaceMatching(Under(root)).And().Inherit(typeof(ControllerBase))
            .ShouldNot().HaveDependencyOnAny([.. dbContexts, "Microsoft.EntityFrameworkCore"])
            .GetResult());
    }

    /// <summary><c>ExtraSpace.Engines</c> is pure maths: no EF Core, ASP.NET Core or System.Net.Http.</summary>
    public static IReadOnlyList<string> ForbiddenEngineReferences(Assembly engines) =>
        engines.GetReferencedAssemblies()
            .Select(r => r.Name!)
            .Where(n => n.StartsWith("Microsoft.EntityFrameworkCore", StringComparison.Ordinal)
                || n.StartsWith("Microsoft.AspNetCore", StringComparison.Ordinal)
                || n == "System.Net.Http")
            .ToList();

    private static string Under(string ns) => $"^{Regex.Escape(ns)}(\\.|$)";

    private static string FeatureOf(string ns, string featuresPrefix)
    {
        var rest = ns[featuresPrefix.Length..];
        var dot = rest.IndexOf('.');
        return dot < 0 ? rest : rest[..dot];
    }

    private static bool IsContracts(string ns, string featureNs) =>
        ns == featureNs + ".Contracts" || ns.StartsWith(featureNs + ".Contracts.", StringComparison.Ordinal);

    private static IEnumerable<string> Failures(TestResult result) =>
        result.IsSuccessful ? [] : result.FailingTypeNames ?? [];
}
```

- [ ] **Step 5: Run**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*ArchitectureTests"`
Expected: 6 pass (Api total 73). If a fixture test lists extra compiler-generated names (`+<>c`), filter names that contain `<` inside `Failures`. Never remove a fixture.

- [ ] **Step 6: Run the whole solution** — `dotnet build ExtraSpace.slnx && dotnet test ExtraSpace.slnx`: 0 errors, 0 warnings, all tests pass.

- [ ] **Step 7: Hand-off** — report the build and test output. Do not commit.

---

### Task 7: Review, local run, migration script and docs (main session)

**Files:** none in `../CMS` written by the main session. Creates `docs/migrations/<date>-initial-platform.sql` and updates docs in the context repo.

- [ ] **Step 1: Read the real diff** — `git -C ../CMS status --short` and `git -C ../CMS diff --stat`. Read every file under `src/`. Run `dotnet build ExtraSpace.slnx` and `dotnet test ExtraSpace.slnx` yourself. Check:
  - every Global Constraint
  - no connection string, password or account id anywhere: `git -C ../CMS grep -nE 'Password=|110611798568|rds\.amazonaws' -- . ':!*.Designer.cs'` returns nothing
  - each Review Focus line has its test, and the test passes

- [ ] **Step 2: Local run** (from `../CMS`):

```bash
docker compose up -d
dotnet user-secrets set "ConnectionStrings:Default" "Host=localhost;Port=5433;Database=extraspace;Username=postgres" --project src/ExtraSpace.Api
dotnet ef database update --project src/ExtraSpace.Api --connection "Host=localhost;Port=5433;Database=extraspace;Username=postgres"
dotnet run --project src/ExtraSpace.Api &      # http://localhost:5080
curl -si http://localhost:5080/health/ready | head -5          # 200, X-Trace-Id header
curl -s  http://localhost:5080/no/such/route                    # 404 problem with code NOT_FOUND and traceId
curl -s  http://localhost:5080/openapi/v1.json | head -c 200    # OpenAPI 3.x
```

In Seq (`http://localhost:5341`), search `traceId = '<id from the 404>'`: the summary line is there. Then stop the app (kill the `dotnet run` process) and leave the containers running for the owner, or `docker compose stop`.

- [ ] **Step 3: Migration script for staging** (not run now; S0-6 runs it before the first deploy, as the master user through the bastion, guide B8):

```bash
dotnet ef migrations script --idempotent --project src/ExtraSpace.Api \
  --output "/Users/waiyanmin/Projects/Extra Space/Claude/docs/migrations/<YYYY-MM-DD>-initial-platform.sql"
```

- [ ] **Step 4: Docs** (context repo):
  - `.claude/rules/cms.md`: fill "Running locally" with Step 2's commands and the ports. Add "Built so far (S0-2)" lines: the `Platform/` areas, `RequestLog.Add`, `Correlation`, `ProblemWriter`, `ApiFactory`, the log-field rules.
  - `.claude/dev-ports`: add `5080`.
  - Spec §4.1 / §4.4 / §4.5 / §5.1: write in the decisions the owner confirmed (32-hex traceId, plain JSON field names, lowerCamel properties, OpenAPI outside production, `data_protection_keys` in S0-2, `HTTP_<status>` fallback).
  - The plan index: S0-2 done. Memory `project_setup_owed.md`: RESUME → S0-3 plan next.

- [ ] **Step 5: Verdict and hand-off** — report each task as ACCEPT, FIX NEEDED or BLOCKED, with the evidence. Give the owner this commit message for `../CMS`:

```
feat(api): API platform — errors, logging and tracing, pipeline, data, tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

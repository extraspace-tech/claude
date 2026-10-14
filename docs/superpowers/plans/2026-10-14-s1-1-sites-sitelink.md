# S1-1 Sites & SiteLink — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this workspace the implementer is the Opus `implementer` agent, infra (Task 8) is the `devops` agent, the reviewer is the Opus `code-reviewer` agent, and Task 12 is run by the main session. Agents never commit (memory `feedback-sdd-without-commits`): every "Commit" step below is replaced by "stop and report the diff".

**Goal:** Staff can manage sites, storage types and unit sizes in the admin. Every night, and when staff ask, the system copies each site's units from SiteLink into our database through a resilient, rate-limited, call-counted SOAP client that cannot write to a real site outside production. Side effects use a transactional outbox, and the login-code email moves onto it.

**Architecture:** There are five pieces.
1. Two pure helpers in `ExtraSpace.Engines`: `Currencies` and `SiteClock`.
2. `Platform/Outbox`: an `outbox_message` table written in the caller's EF transaction, and a Hangfire dispatcher. The dispatcher runs every minute and is also nudged right after each commit.
3. `Integrations/SiteLink`: a typed `HttpClient` that posts SOAP 1.1 envelopes and parses DataSet replies. It uses a `Microsoft.Extensions.Http.Resilience` pipeline (retries for reads only), a token-bucket limiter for reads, a monthly call counter table, and a write allow-list.
4. `Features/Sites`: the tables, the unit refresh (service + jobs), and the admin API.
5. The admin UI: the sidebar becomes grouped, two shared page templates (list and record) are added, and four Platform pages are built.

**Tech Stack:**
- .NET 10 (SDK 10.0.400), ASP.NET Core Minimal APIs, EF Core 10 + Npgsql 10.0.3, Hangfire 1.8.25 + Hangfire.PostgreSql 1.21.1.
- **New:** `Microsoft.Extensions.Http.Resilience` 10.10.0. This is the same dotnet/extensions release train as the pinned `Microsoft.Extensions.Diagnostics.Testing` 10.10.0. If restore cannot find it, use the newest 10.x and say so in the report.
- Tests: xUnit v3, AwesomeAssertions, Testcontainers (PostgreSQL 18.6).
- Admin UI: React 19.3, React Router 8, TanStack Query 5 + Table 9, React Hook Form + Zod 4, Vitest + MSW 3.

**Spec:** `docs/superpowers/specs/2026-10-14-s1-self-storage-design.md`.
- **Implemented here:** §4 (layout), §5.1 (sites tables), §5.6 (outbox), §6.1–6.7 (SiteLink client and unit refresh; on-demand parts excluded, see decision 14), §9.10 (outbox), §11.1–11.3 (the look, Platform pages, `sites.manage`), §13 (jobs `OutboxDispatcher` and `UnitRefresh`), and §14 (the matching tests).
- **Read with it:**
  - `docs/notes/cms/built-so-far.md` (🔴 always)
  - `docs/notes/s1-research/s1-checks.md` §B7 (WSDL order of the unit operations)
  - `docs/notes/sitelink/sitelink-api-pdf-notes.md` (return codes, null date, `iCurrencyDecimals`). It is vendor-confidential: paraphrase it and never copy it into `../CMS`.
  - `docs/notes/s1-research/s1-research-crosscutting.md` §1–2 (how the demo admin pages look)
  - demo spec `features/03-units-sites-quotes.md` §4.1 and §9.5–9.6

**Clients affected:**
- **Admin UI:**
  - New pages: Sites, Storage Types, Unit Sizes, Units.
  - The sidebar becomes grouped: Platform and Access Control.
  - S0 pages are renamed to the demo's labels: Staff becomes "Admin Users", Audit log becomes "Audit Log".
  - New OpenAPI types.
- **Jobs:** new `OutboxDispatcher` (every minute) and `UnitRefresh` (hourly; each site at 03:00 in its own zone).
- **SiteLink:** reads only (`UnitsInformation_v3`, `UnitTypePriceList_v2`). There are no writes in S1-1, but the write guard is built and tested.
- **AWS (Task 8):**
  - Secret `es/<env>/sitelink`.
  - Environment variables `SiteLink__*`.
  - Two new alarms: SiteLink monthly calls, and an outbox message that failed permanently.
- **Flutter:** none. Sign-in still sends the same email; only its path inside the server changes.
- **Stripe:** none.

## Global Constraints

- **Repo and branch.** Repo `../CMS` (`extraspace-tech/cms`, 🔴 PUBLIC). Work on branch `s1-1-sites-sitelink`, cut from `main` at `25b1cb0`. **Never `git commit`, `push`, `stash` or `reset`.** The owner commits.
- **No secrets in the repo.** No SiteLink login, licence key, API key, connection string, AWS account id or real address in any committed file. Test values must say "test" (`test-user:::test-key`). Real values come from user-secrets locally and from Secrets Manager `es/<env>/sitelink` on AWS. 🔴 Never open the old system's config files to find the SiteLink login (`.claude/rules/old-backend.md`).
- **SiteLink PDFs are vendor-confidential.** Paraphrase them; never paste their text into code, comments or tests. Fixtures are **synthetic** (made-up units, ids and names).
- **Agent limits.** Subagents never run `dotnet user-secrets`, `docker compose` or any AWS command, and never dispatch subagents.
- **Files.** No new `.md` file inside `../CMS`. LF line endings. Follow `.editorconfig` and the surrounding idiom:
  - low comment density, one-line "why" comments
  - file-scoped namespaces, primary constructors
  - `internal sealed` unless a test or another layer needs the type
  - request DTOs `public` (the .NET 10 validation generator skips internal types)
- **Package versions** live only in `Directory.Packages.props`. ASP.NET Core packages stay at **10.0.11**.
- **Namespaces:**
  - `ExtraSpace.Engines`
  - `ExtraSpace.Api.Platform.Outbox`
  - `ExtraSpace.Api.Integrations.SiteLink`
  - `ExtraSpace.Api.Features.Sites` (`.Admin` for the admin endpoints and services)
- **Banned in `src/`** (RS0030): `DateTime.Now/UtcNow/Today`, `DateTimeOffset.Now/UtcNow` and `Guid.NewGuid`. Use the injected `TimeProvider` and `Guid.CreateVersion7()`.
- **Endpoints are Minimal APIs:**
  - Routes start with a slash.
  - Handlers take services as parameters, call a service (never `AppDbContext`) and return `TypedResults`.
  - Errors are thrown as `AppException(status, code, title)`, or as an exception that implements `IProblemException` (Task 4).
  - Admin routes hang off `/admin/api` through `MapGroup("")` + full paths (built-so-far, S0-4 gotchas).
- **Log property names are lowerCamel**, hot lines use `[LoggerMessage]`, and nothing logs an object with `{obj}`.
  - 🔴 Never log a SiteLink request or response body, the logon block, a password or the API key.
  - Never name a property with `token`, `secret`, `password`, `authorization`, `cookie` or `connectionstring` in it: it gets masked.
- **Data rules (S0 + S1 spec §5):**
  - Tables are `snake_case`, singular, with UUID v7 ids set in code.
  - Money is `numeric(12,2)` + `char(3)` currency.
  - Instants are `timestamptz` (C# `DateTime` Kind Utc).
  - Statuses and enums are stored as text with `.HasConversion<string>()`.
  - SiteLink ids are `int`.
  - Admin-edited tables have `uint Version` `.IsRowVersion()` (xmin), `IAudited` and `IHasStaffStamps`.
  - `ExecuteUpdate`, `ExecuteDelete` and raw SQL skip `TimestampsInterceptor` and the audit: set `updated_at` yourself, and never use them for an admin write.
- **Transactions.** Every `BeginTransactionAsync` has a `CommitAsync` on every path that must keep its writes. Reads that feed a write run inside the same transaction.
- **Migrations.** One migration per task that changes the schema. After `dotnet ef migrations add`, strip the BOM from the 3 generated files. Never `migrations remove` a migration that was edited by hand.
- **Tests:**
  - Test environment `Testing`. `ExtraSpace.Api.Tests` needs Docker.
  - Filter form: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*SiteLinkClientTests"`.
  - Every `WithWebHostBuilder` host sets `App:Role=Api`.
  - Tests run in parallel against one database, so each test makes its own site (`SitesTestData.NewCode()`) and its own SiteLink operation names where it counts calls.
- **Spec values (verbatim):**
  - SiteLink: 30 s per attempt, 60 s total, 2 jittered retries for reads only, one circuit breaker, 2 calls/s per instance (§6.3, §6.6)
  - outbox back-off 1, 5, 15, 60 min (§9.10)
  - unit refresh nightly at 03:00 site time (§6.7)
  - SiteLink null date = any year before 1800 (§6.5)
  - `available` = `rentable AND NOT rented AND NOT waiting_list_reserved AND deleted_at IS NULL` (§5.1)
- **Admin UI:**
  - TypeScript stays **6.0.3**.
  - `src/lib/zod-config.ts` stays the first import of `main.tsx`.
  - No dots in route segments.
  - `src/api/schema.d.ts` is generated, never edited: run `UPDATE_OPENAPI=1 dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*OpenApiSnapshotTests"`, then `npm run gen:api`.
  - Desktop only (owner, 2026-10-14).

## Review Focus

1. **An absent, blank or `"false"` SiteLink value.** This was the demo's truthy-string bug, and the risk is also a missing rate column wiping a stored price.
   - Expected: an absent column keeps the stored value, `"false"` is false, and a blank number counts as absent.
   - Pinned by Task 5 `Absent_and_false_values_map_strictly` and Task 6 `An_incremental_refresh_keeps_absent_columns_and_marks_deleted_units`.
2. **A refresh that fails half-way**, for example a database error on one row of the batch.
   - Expected: no unit changes, the cursor does not move, and the site's sync state shows the error.
   - Pinned by Task 6 `A_failing_row_rolls_back_the_whole_batch`.
3. **Two refreshes of one site at once** (the nightly run and a staff "Sync now").
   - Expected: the second is skipped without calling SiteLink, and no duplicate unit rows appear.
   - Pinned by Task 6 `A_second_refresh_of_the_same_site_is_skipped`.
4. **A SiteLink write aimed at a real site from a developer machine or staging, or a write that timed out being sent again.**
   - Expected: the write is blocked before any HTTP request, and a write is sent once only.
   - Pinned by Task 4 `A_write_outside_the_allow_list_never_leaves_the_process` and `A_read_is_retried_on_a_server_error_but_a_write_is_not`.
5. **The login-code email after it moves onto the outbox.** It must not be lost on commit, sent on a rollback, or stored in clear.
   - Expected: one email, a sealed outbox payload, and nothing when the transaction rolls back.
   - Pinned by Task 2 `The_login_code_email_goes_through_the_outbox_sealed` and `A_rolled_back_transaction_leaves_no_step`.

## Decisions this plan makes (owner to confirm with the plan)

1. **Outbox sweep every minute, plus a nudge right after each commit.** The spec says every 30 s. Hangfire recurring jobs are minute-based, and the nudge makes the normal delay about a second.
2. **The email goes through the outbox.** The outbox handler hands the sealed email to the existing `EmailJob`, so its 10–160 s retries stay. `IEmailSender.Enqueue` is now called **inside** the caller's transaction and returns nothing. The outbox payload holds only the sealed (Data Protection) blob, never the code or the address.
3. **The SiteLink write guard.** The default `SiteLink:WriteAllowList` is `["LSETUP"]` (in `appsettings.json`). Production opts in with `SiteLink:AllowWritesToAllSites=true`, and every other environment refuses to start with that flag. The spec said "production = empty list = all sites", but a configuration array cannot be emptied by an environment variable, so an explicit flag is safer.
4. **Writes never wait for the rate limiter.** This is how "writes first" is met. Only reads wait for the 2 calls/s bucket.
5. **The monthly call counter is a table**, `sitelink_call_month` (UTC months, one row per operation plus a `*` total). One Error line is logged when the total crosses `SiteLink:MonthlyCallAlarm` (0 = off). CloudWatch cannot alarm on a monthly sum, so Task 8 alarms on that line.
6. **Missing SiteLink credentials do not stop start-up.** Each call answers 503 `SITELINK_UNAVAILABLE` and logs a Warning. CDK creates the secret empty, and the owner fills it.
7. **The nightly refresh is an hourly job.** It refreshes each active site in the hour that is 03:00 in that site's zone. SG and MY are UTC+8 and KR is UTC+9, so one fixed cron cannot serve all of them. Only the nightly run checks `iCurrencyDecimals` (one extra call per site per day).
8. **A first or full refresh calls `UnitsInformation_v3(0, bReturnExcludedFromWebsiteUnits = true)`**, as the spec says. The demo saw ticks 0 return no `Table` when the flag was false, and the vendor PDF suggests "ticks older than a month" for a first poll, so a full refresh that returns **no units fails** and keeps the old cursor. Two LSETUP checks (Task 12) settle this: whether units hidden from the website come back, and whether the first pull is complete.
9. **Unit size comes from the area.** The size chosen is the first one, by `sort_order` then `key`, whose storage type is the unit's (or empty) and whose range holds the area (min inclusive, max exclusive). Every unit is recomputed in one SQL statement when a size is created, changed or deleted, so staff edits apply at once without a SiteLink call.
10. **Site country rules.** `site.currency` follows the country (SG → SGD, MY → MYR, KR → KRW) and is read-only in the form. The time zone and tax label default from the country on create and stay editable.
11. **`site.sitelink_site_id`** is optional, staff-entered and unique when set. Nothing reads it in S1-1. It stays because the spec lists it.
12. **PATCH semantics.**
    - A field that is absent or `null` is unchanged.
    - `""` clears an optional text field.
    - A nullable number or link is cleared by naming it in `clear: ["latitude"]`.
    - Setting and clearing the same field is 400.
    - This follows S0's `UpdateStaffBody` ("null = unchanged; empty = clear").
13. **Storage types.** The key cannot be changed after creation. Two storage types are seeded: `self-storage` (active) and `workspace` (inactive, kept for S2 BizPlus).
14. **Moved to the plan that first uses them:**
    - the on-demand refresh when the copy is older than 60 min (S1-3 browsing)
    - the live unit read `UnitsInformationByUnitID` (S1-3 reserve / move-in)
    - the `ISiteDirectory` and `IUnitCatalog` contracts (S1-2 / S1-3)
    - the `customerId` on the summary line for binding failures (S1-2, the first signed-in POST)
15. **QOL additions on Units** (to be listed in spec §15): a Site filter and a "SiteLink sync" panel (last sync per site, last error, "Sync now", "Full resync").
16. **`sites.manage`** covers the writes on Sites, Storage Types and Unit Sizes and the two sync actions. Any staff member can read them (spec §11.3).
17. **Admin labels.** The brand subtitle becomes "Self Storage" (demo). The S0 pages sit under "Access Control" with the demo's labels: Admin Users, Audit Log, Jobs, Roles. Items are sorted alphabetically inside each group.
18. **Money.** `Money.Round(amount, currency)` replaces `Money.Round(amount)`. KRW rounds to whole won, SGD and MYR to cents. `default(Money).Currency` throws. `ToString` uses the invariant culture.

## File map

| Area | Files |
|---|---|
| Engines | `src/ExtraSpace.Engines/Currencies.cs` (new), `Money.cs`, `SiteClock.cs` (new); `tests/ExtraSpace.Engines.Tests/MoneyTests.cs`, `SiteClockTests.cs` (new) |
| Outbox | `src/ExtraSpace.Api/Platform/Outbox/{OutboxMessage,OutboxConfiguration,Outbox,IOutboxHandler,OutboxDispatchJob,OutboxNudge,OutboxSetup}.cs`; `Platform/Hosting/PlatformServices.cs` |
| Email | `Integrations/Email/{EmailSealer,EmailJobQueue,OutboxEmailSender,EmailOutboxHandler,IEmailSender,EmailSetup,EmailJob}.cs`; delete `HangfireEmailSender.cs`; `Features/Identity/LoginCodeService.cs` |
| SiteLink | `Integrations/SiteLink/{SiteLinkOptions,SiteLinkSetup,SiteLinkClient,SiteLinkClient.Units,SiteLinkFields,SoapEnvelope,SiteLinkReply,SiteLinkValues,SiteLinkExceptions,SiteLinkAttemptHandler,SiteLinkCallCounter,SiteLinkUnit}.cs`; `Platform/Errors/{IProblemException,AppExceptionHandler}.cs` |
| Sites | `Features/Sites/{Site,StorageType,UnitSize,Unit,UnitSyncState,SiteCountries,SitesEntityConfigurations,SitesSetup,SitesPermissions,SitesErrors,UnitRefreshService,UnitRefreshJob,UnitSizeMap}.cs`; `Features/Sites/Admin/{SitesAdminEndpoints,SitesAdminDtos,SiteAdminService,StorageTypeAdminService,UnitSizeAdminService,UnitAdminQuery,UnitRefreshRequests}.cs`; `Platform/Data/Paging.cs`, `Platform/Http/Patch.cs` |
| Wiring | `Program.cs`, `appsettings.json`, `Directory.Packages.props`, `ExtraSpace.Api.csproj` |
| Migrations | `Outbox`, `Sites`, `SiteLinkCallMonth` |
| Tests | `TestSupport/{FakeSiteLink,SiteLinkXml,SitesTestData,TestOutboxHandler}.cs`, `ApiFactory.cs`, `TestSupport/TestEndpoints.cs`; `Platform/OutboxTests.cs`; `Integrations/{SiteLinkClientTests,SiteLinkUnitTests,EmailTests}.cs`; `Features/Sites/{SitesDataTests,UnitRefreshTests,UnitSizeMapTests,SitesAdminTests,TaxonomyAdminTests,UnitsAdminTests}.cs`; `Platform/ExceptionClassifyTests.cs` |
| Infra | `infra/ExtraSpace.Infra/{EnvConfig,Stacks/AppStack,Stacks/Observability}.cs`; `tests/ExtraSpace.Infra.Tests/{AppStackTests,ObservabilityTests}.cs` |
| Admin UI | `admin-ui/src/app/{nav.ts,Shell.tsx,routes.tsx}`; `components/{DataTable,ListPage,Pagination,RecordPage,RecordFields,RecordEditor}.tsx`; `lib/{forms.ts,money.ts,list.ts,zod-fields.ts}`; `features/{sites,storage-types,unit-sizes,units}/*`; `features/audit/AuditPage.tsx`; `test/data.ts` |

---

### Task 1: Engines — currencies, money carry-overs, site clock

**Files:**
- Create: `src/ExtraSpace.Engines/Currencies.cs`, `src/ExtraSpace.Engines/SiteClock.cs`
- Modify: `src/ExtraSpace.Engines/Money.cs`
- Test: `tests/ExtraSpace.Engines.Tests/MoneyTests.cs`, `tests/ExtraSpace.Engines.Tests/SiteClockTests.cs`

**Interfaces:**
- Produces:
  - `Currencies.Decimals(string currency) → int` (SGD 2, MYR 2, KRW 0; any other code → `ArgumentException`)
  - `Currencies.IsSupported(string?) → bool`
  - `Money.Round(decimal amount, string currency) → decimal`
  - `SiteClock.Zone(string id) → TimeZoneInfo`
  - `SiteClock.ToLocal(DateTimeOffset, TimeZoneInfo) → DateTime` (Kind Unspecified)
  - `SiteClock.Today(DateTimeOffset, TimeZoneInfo) → DateOnly`
  - `SiteClock.LocalToUtc(DateOnly, int minutes, TimeZoneInfo) → DateTime` (Kind Utc)

- [ ] **Step 1: Write the failing tests**

Replace the first theory of `MoneyTests.cs`, and add new tests to it:

```csharp
    [Theory]
    [InlineData("0.005", "0.01")]
    [InlineData("-0.005", "-0.01")]
    [InlineData("2.675", "2.68")]
    [InlineData("1.004", "1.00")]
    [InlineData("1.015", "1.02")]
    [InlineData("-1.015", "-1.02")]
    [InlineData("10.999", "11.00")]
    [InlineData("0", "0.00")]
    public void Round_is_half_away_from_zero_to_two_places_for_SGD(string input, string expected) =>
        Money.Round(D(input), "SGD").Should().Be(D(expected));

    [Theory]
    [InlineData("1234.5", "1235")]
    [InlineData("-0.5", "-1")]
    [InlineData("1.4", "1")]
    public void KRW_rounds_to_whole_won(string input, string expected) =>
        Money.Round(D(input), "KRW").Should().Be(D(expected));

    [Fact]
    public void An_unsupported_currency_cannot_be_rounded()
    {
        var round = () => Money.Round(1m, "USD");
        round.Should().Throw<ArgumentException>().WithMessage("*USD*");
    }

    [Fact]
    public void Default_money_has_no_currency()
    {
        var money = default(Money);
        var read = () => money.Currency;
        read.Should().Throw<InvalidOperationException>().WithMessage("*Money.Zero*");
        var add = () => money + new Money(1m, "SGD");
        add.Should().Throw<InvalidOperationException>();
        money.ToString().Should().Be("0.00 (none)");
    }

    [Fact]
    public void ToString_ignores_the_current_culture()
    {
        var previous = CultureInfo.CurrentCulture;
        CultureInfo.CurrentCulture = new CultureInfo("de-DE");
        try
        {
            new Money(1234.5m, "SGD").ToString().Should().Be("1234.50 SGD");
        }
        finally
        {
            CultureInfo.CurrentCulture = previous;
        }
    }
```

Create `SiteClockTests.cs`. The rows are the demo's Z1–Z3, plus our MY and KR rows (spec §14):

```csharp
using ExtraSpace.Engines;

namespace ExtraSpace.Engines.Tests;

public sealed class SiteClockTests
{
    private static readonly TimeZoneInfo Sg = SiteClock.Zone("Asia/Singapore");
    private static readonly TimeZoneInfo My = SiteClock.Zone("Asia/Kuala_Lumpur");
    private static readonly TimeZoneInfo Kr = SiteClock.Zone("Asia/Seoul");

    private static DateTimeOffset At(string utc) => DateTimeOffset.Parse(utc, System.Globalization.CultureInfo.InvariantCulture);

    [Fact]
    public void Z1_a_UTC_instant_in_Singapore_time()
    {
        var local = SiteClock.ToLocal(At("2026-10-07T16:30:00Z"), Sg);
        local.Should().Be(new DateTime(2026, 10, 8, 0, 30, 0));
        local.DayOfWeek.Should().Be(DayOfWeek.Thursday);
        SiteClock.Today(At("2026-10-07T16:30:00Z"), Sg).Should().Be(new DateOnly(2026, 10, 8));
    }

    [Theory]
    [InlineData(540, "2026-10-08T01:00:00Z")]   // Z2
    [InlineData(1440, "2026-10-08T16:00:00Z")]  // Z3: 24:00 is the next midnight
    public void Z2_Z3_a_Singapore_wall_time_as_UTC(int minutes, string expected)
    {
        var utc = SiteClock.LocalToUtc(new DateOnly(2026, 10, 8), minutes, Sg);
        utc.Should().Be(At(expected).UtcDateTime);
        utc.Kind.Should().Be(DateTimeKind.Utc);
    }

    [Fact]
    public void Malaysia_is_the_same_as_Singapore() =>
        SiteClock.LocalToUtc(new DateOnly(2026, 10, 8), 540, My).Should().Be(At("2026-10-08T01:00:00Z").UtcDateTime);

    [Fact]
    public void Korea_is_one_hour_ahead()
    {
        SiteClock.LocalToUtc(new DateOnly(2026, 10, 8), 540, Kr).Should().Be(At("2026-10-08T00:00:00Z").UtcDateTime);
        SiteClock.ToLocal(At("2026-10-07T15:30:00Z"), Kr).Should().Be(new DateTime(2026, 10, 8, 0, 30, 0));
        SiteClock.Today(At("2026-10-07T14:59:00Z"), Kr).Should().Be(new DateOnly(2026, 10, 7));
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `dotnet test tests/ExtraSpace.Engines.Tests`
Expected: compile errors: `Round(decimal, string)`, `SiteClock` and `Currencies` do not exist yet.

- [ ] **Step 3: Implement**

`src/ExtraSpace.Engines/Currencies.cs`:

```csharp
namespace ExtraSpace.Engines;

/// <summary>The currencies our sites use and their minor-unit places (S1 spec §5, §9.1). KRW has none.</summary>
public static class Currencies
{
    private static readonly Dictionary<string, int> Places = new(StringComparer.Ordinal) { ["SGD"] = 2, ["MYR"] = 2, ["KRW"] = 0 };

    public static bool IsSupported(string? currency) => currency is not null && Places.ContainsKey(currency);

    public static int Decimals(string currency) =>
        Places.TryGetValue(currency, out var places) ? places : throw new ArgumentException($"Unsupported currency '{currency}'.", nameof(currency));
}
```

`src/ExtraSpace.Engines/Money.cs` (whole file):

```csharp
using System.Globalization;

namespace ExtraSpace.Engines;

/// <summary>An exact amount in one currency. Rounding happens only where a feature spec says so, through <see cref="Round()"/>.</summary>
public readonly record struct Money
{
    private readonly string? _currency;

    public decimal Amount { get; }

    /// <summary><c>default(Money)</c> has no currency and throws here; start from <see cref="Zero"/>.</summary>
    public string Currency => _currency ?? throw new InvalidOperationException("default(Money) has no currency; use Money.Zero(currency).");

    public Money(decimal amount, string currency)
    {
        if (currency is not { Length: 3 } || !currency.All(char.IsAsciiLetterUpper))
            throw new ArgumentException($"Currency must be a 3-letter upper-case ISO 4217 code, got '{currency}'.", nameof(currency));
        Amount = amount;
        _currency = currency;
    }

    public static Money Zero(string currency) => new(0m, currency);

    /// <summary>Half away from zero to the currency's places (SGD/MYR 2, KRW 0; S0 spec §4.6, S1 spec §8.2). The only money rounding rule.</summary>
    public static decimal Round(decimal amount, string currency) =>
        decimal.Round(amount, Currencies.Decimals(currency), MidpointRounding.AwayFromZero);

    public Money Round() => new(Round(Amount, Currency), Currency);

    public static Money operator +(Money a, Money b) => new(a.Amount + b.Amount, SameCurrency(a, b));
    public static Money operator -(Money a, Money b) => new(a.Amount - b.Amount, SameCurrency(a, b));
    public static Money operator -(Money a) => new(-a.Amount, a.Currency);
    public static Money operator *(Money a, decimal factor) => new(a.Amount * factor, a.Currency);

    private static string SameCurrency(Money a, Money b) =>
        a.Currency == b.Currency ? a.Currency : throw new InvalidOperationException($"Cannot combine {a.Currency} and {b.Currency}.");

    public override string ToString() => $"{Amount.ToString("0.00##", CultureInfo.InvariantCulture)} {_currency ?? "(none)"}";
}
```

`src/ExtraSpace.Engines/SiteClock.cs`:

```csharp
namespace ExtraSpace.Engines;

/// <summary>Business dates and wall-clock times in a site's own time zone (house rule 2); storage stays UTC.</summary>
public static class SiteClock
{
    public static TimeZoneInfo Zone(string timeZoneId) => TimeZoneInfo.FindSystemTimeZoneById(timeZoneId);

    public static DateTime ToLocal(DateTimeOffset instant, TimeZoneInfo zone) => TimeZoneInfo.ConvertTime(instant, zone).DateTime;

    public static DateOnly Today(DateTimeOffset now, TimeZoneInfo zone) => DateOnly.FromDateTime(ToLocal(now, zone));

    /// <summary>A local date + minutes after midnight (1440 = the next midnight) as a UTC instant.</summary>
    public static DateTime LocalToUtc(DateOnly date, int minutes, TimeZoneInfo zone) =>
        TimeZoneInfo.ConvertTimeToUtc(date.ToDateTime(TimeOnly.MinValue, DateTimeKind.Unspecified).AddMinutes(minutes), zone);
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `dotnet test tests/ExtraSpace.Engines.Tests`
Expected: all pass, including the 3 existing tests that use the instance `Round()` (SGD/MYR).

- [ ] **Step 5: Stop and report** (no commit).

---

### Task 2: Platform outbox, and the email on it

**Files:**
- Create: `src/ExtraSpace.Api/Platform/Outbox/OutboxMessage.cs`, `OutboxConfiguration.cs`, `Outbox.cs`, `IOutboxHandler.cs`, `OutboxDispatchJob.cs`, `OutboxNudge.cs`, `OutboxSetup.cs`
- Create: `src/ExtraSpace.Api/Integrations/Email/EmailSealer.cs`, `EmailJobQueue.cs`, `OutboxEmailSender.cs`, `EmailOutboxHandler.cs`
- Delete: `src/ExtraSpace.Api/Integrations/Email/HangfireEmailSender.cs` (its code moves to `EmailSealer` + `EmailJobQueue`)
- Modify:
  - `Integrations/Email/IEmailSender.cs` and `EmailSetup.cs`
  - `EmailJob.cs`: it reads `HangfireEmailSender.Purpose`; point it at `EmailSealer.Purpose`
  - `Features/Identity/LoginCodeService.cs`
  - `Platform/Hosting/PlatformServices.cs`
- Migration: `Outbox`
- Test: `tests/ExtraSpace.Api.Tests/Platform/OutboxTests.cs`, `TestSupport/TestOutboxHandler.cs`, `TestSupport/TestEndpoints.cs` (`/test/email`), `ApiFactory.cs`, `Integrations/EmailTests.cs` (only where it relied on `IEmailSender` returning a job id)

**Interfaces:**
- Produces:
  - `IOutbox.Enqueue<T>(string kind, T payload, string idempotencyKey)` (scoped). It adds the row to the caller's `AppDbContext`, and the caller's `SaveChanges` saves it.
  - `IOutboxHandler { string Kind; Task HandleAsync(OutboxItem item, CancellationToken) }` with `OutboxItem(Guid Id, string IdempotencyKey, JsonElement Payload, int Attempt)`.
  - `services.AddOutboxHandler<T>()`.
  - `OutboxDispatchJob.Name = "OutboxDispatcher"`, `OutboxDispatchJob.RetryDelays`.
  - `IEmailSender.Enqueue(EmailMessage)` now returns `void` and must be called **before** the caller's `SaveChanges`/commit.

- [ ] **Step 1: Write the failing tests**

`tests/ExtraSpace.Api.Tests/TestSupport/TestOutboxHandler.cs`:

```csharp
using System.Collections.Concurrent;
using ExtraSpace.Api.Platform.Outbox;

namespace ExtraSpace.Api.Tests.TestSupport;

/// <summary>Kind "Test": counts runs per idempotency key; fails the first <c>failTimes</c> runs when the payload says so.</summary>
public sealed class TestOutboxHandler : IOutboxHandler
{
    public const string KindName = "Test";
    public static readonly ConcurrentDictionary<string, int> Runs = new();

    public string Kind => KindName;

    public Task HandleAsync(OutboxItem item, CancellationToken cancellationToken)
    {
        var runs = Runs.AddOrUpdate(item.IdempotencyKey, 1, (_, n) => n + 1);
        if (item.Payload.TryGetProperty("failTimes", out var failTimes) && runs <= failTimes.GetInt32())
            throw new InvalidOperationException("test-outbox-failure");
        return Task.CompletedTask;
    }
}
```

Register it in `ApiFactory.ConfigureTestServices`: `services.AddOutboxHandler<TestOutboxHandler>();`.

`tests/ExtraSpace.Api.Tests/Platform/OutboxTests.cs`:

```csharp
using System.Text.Json;
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Outbox;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Time.Testing;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class OutboxTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private static string NewKey() => "test:" + Guid.NewGuid().ToString("N");

    private async Task<OutboxMessage?> FindAsync(string key)
    {
        OutboxMessage? row = null;
        await api.WithDbAsync(async db => row = await db.Set<OutboxMessage>().AsNoTracking().SingleOrDefaultAsync(m => m.IdempotencyKey == key, Ct));
        return row;
    }

    private async Task WaitUntilAsync(Func<Task<bool>> done)
    {
        for (var i = 0; i < 100 && !await done(); i++) await Task.Delay(100, Ct);
        (await done()).Should().BeTrue();
    }

    [Fact]
    public async Task A_step_saved_with_its_change_runs_once_soon()
    {
        var key = NewKey();
        await using (var scope = api.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await using var transaction = await db.Database.BeginTransactionAsync(Ct);
            scope.ServiceProvider.GetRequiredService<IOutbox>().Enqueue(TestOutboxHandler.KindName, new { note = "hello" }, key);
            await db.SaveChangesAsync(Ct);
            await transaction.CommitAsync(Ct);
        }

        // The nudge after commit runs it well before the minute sweep.
        await WaitUntilAsync(async () => (await FindAsync(key))?.ProcessedAt is not null);
        TestOutboxHandler.Runs[key].Should().Be(1);
        (await FindAsync(key))!.Attempts.Should().Be(0);
    }

    [Fact]
    public async Task A_rolled_back_transaction_leaves_no_step()
    {
        var key = NewKey();
        await using (var scope = api.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await using var transaction = await db.Database.BeginTransactionAsync(Ct);
            scope.ServiceProvider.GetRequiredService<IOutbox>().Enqueue(TestOutboxHandler.KindName, new { }, key);
            await db.SaveChangesAsync(Ct);
            await transaction.RollbackAsync(Ct);
        }

        await Task.Delay(1500, Ct);
        (await FindAsync(key)).Should().BeNull();
        TestOutboxHandler.Runs.ContainsKey(key).Should().BeFalse();
    }

    [Fact]
    public async Task The_same_idempotency_key_cannot_be_saved_twice()
    {
        var key = NewKey();
        await using var scope = api.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var outbox = scope.ServiceProvider.GetRequiredService<IOutbox>();
        outbox.Enqueue(TestOutboxHandler.KindName, new { }, key);
        await db.SaveChangesAsync(Ct);
        outbox.Enqueue(TestOutboxHandler.KindName, new { }, key);

        var save = () => db.SaveChangesAsync(Ct);
        await save.Should().ThrowAsync<DbUpdateException>();
    }

    [Fact]
    public async Task A_failing_step_backs_off_then_is_marked_failed()
    {
        // Fake time a day ahead: the host's own dispatcher (real clock) never sees these rows as due.
        var time = new FakeTimeProvider(DateTimeOffset.UtcNow.AddDays(1));
        var key = NewKey();
        await api.WithDbAsync(async db =>
        {
            db.Add(new OutboxMessage
            {
                Kind = TestOutboxHandler.KindName, IdempotencyKey = key,
                Payload = JsonSerializer.SerializeToDocument(new { failTimes = 99 }),
                CreatedAt = time.GetUtcNow().UtcDateTime, AvailableAt = time.GetUtcNow().UtcDateTime,
            });
            await db.SaveChangesAsync(Ct);
        });

        var expectedDelays = new[] { 1, 5, 15, 60 };
        for (var attempt = 1; attempt <= 5; attempt++)
        {
            await using (var scope = api.Services.CreateAsyncScope())
                await ActivatorUtilities.CreateInstance<OutboxDispatchJob>(scope.ServiceProvider, time).RunAsync(Ct);
            var row = (await FindAsync(key))!;
            row.Attempts.Should().Be(attempt);
            row.LastError.Should().Be("InvalidOperationException: test-outbox-failure");
            if (attempt < 5)
            {
                row.FailedAt.Should().BeNull();
                row.AvailableAt.Should().BeCloseTo(time.GetUtcNow().UtcDateTime.AddMinutes(expectedDelays[attempt - 1]), TimeSpan.FromSeconds(1));
                time.Advance(TimeSpan.FromMinutes(expectedDelays[attempt - 1]));
            }
            else
            {
                row.FailedAt.Should().NotBeNull();
            }
        }
        var failed = (await FindAsync(key))!;
        (await api.Logs.WaitForAsync(line => line.Contains("failed permanently") && line.Contains(failed.Id.ToString()))).Should().NotBeNull();
    }

    [Fact]
    public async Task Parallel_dispatchers_run_each_step_once()
    {
        var time = new FakeTimeProvider(DateTimeOffset.UtcNow.AddDays(2));
        var keys = Enumerable.Range(0, 20).Select(_ => NewKey()).ToList();
        await api.WithDbAsync(async db =>
        {
            foreach (var key in keys)
                db.Add(new OutboxMessage
                {
                    Kind = TestOutboxHandler.KindName, IdempotencyKey = key, Payload = JsonSerializer.SerializeToDocument(new { }),
                    CreatedAt = time.GetUtcNow().UtcDateTime, AvailableAt = time.GetUtcNow().UtcDateTime,
                });
            await db.SaveChangesAsync(Ct);
        });

        await Task.WhenAll(Enumerable.Range(0, 3).Select(async _ =>
        {
            await using var scope = api.Services.CreateAsyncScope();
            await ActivatorUtilities.CreateInstance<OutboxDispatchJob>(scope.ServiceProvider, time).RunAsync(Ct);
        }));

        keys.Should().AllSatisfy(key => TestOutboxHandler.Runs[key].Should().Be(1));
    }

    [Fact]
    public async Task The_login_code_email_goes_through_the_outbox_sealed()
    {
        var started = DateTime.UtcNow.AddSeconds(-1);
        var client = api.ClientWithIp();
        var email = IdentityTestData.NewEmail("outbox");

        await client.RequestCodeAsync(email);
        var code = await api.Emails.CodeForAsync(email);

        List<string> payloads = [];
        await api.WithDbAsync(async db => payloads = await db.Database
            .SqlQuery<string>($"SELECT payload::text AS \"Value\" FROM outbox_message WHERE kind = 'Email' AND created_at >= {started}")
            .ToListAsync(Ct));
        payloads.Should().NotBeEmpty();
        payloads.Should().AllSatisfy(p =>
        {
            p.Should().NotContain(email);
            p.Should().NotContain(code);
        });
    }
}
```

> The `LogCapture.WaitForAsync` predicate shape must match the helper in `TestSupport/LogCapture.cs` (read it first). The check is: one line whose message contains `failed permanently` with `kind` = `Test`. `AuthFlow.RequestCodeAsync` and `api.Emails.CodeForAsync` are the S0-3 helpers; use their real names from `TestSupport/AuthFlow.cs` and `FakeEmailTransport.cs`.

- [ ] **Step 2: Run and watch them fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*OutboxTests"`
Expected: compile errors: `OutboxMessage`, `IOutbox`, `IOutboxHandler` and `OutboxDispatchJob` do not exist.

- [ ] **Step 3: Implement the outbox**

`Platform/Outbox/OutboxMessage.cs`:

```csharp
using System.Text.Json;

namespace ExtraSpace.Api.Platform.Outbox;

/// <summary>A side effect saved in the same transaction as the change that causes it (S1 spec §5.6, §9.10).</summary>
public sealed class OutboxMessage
{
    public Guid Id { get; init; } = Guid.CreateVersion7();
    public required string Kind { get; init; }
    public required JsonDocument Payload { get; init; }
    public required string IdempotencyKey { get; init; }
    public string? CorrelationId { get; init; }
    public DateTime CreatedAt { get; init; }
    public DateTime AvailableAt { get; set; }
    public int Attempts { get; set; }
    public string? LastError { get; set; }
    public DateTime? ProcessedAt { get; set; }
    public DateTime? FailedAt { get; set; }
    public DateTime? ResolvedAt { get; set; }
    public Guid? ResolvedByStaffId { get; set; }
    public string? ResolutionNote { get; set; }
}
```

`Platform/Outbox/OutboxConfiguration.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace ExtraSpace.Api.Platform.Outbox;

internal sealed class OutboxConfiguration : IEntityTypeConfiguration<OutboxMessage>
{
    public void Configure(EntityTypeBuilder<OutboxMessage> builder)
    {
        builder.ToTable("outbox_message");
        builder.Property(m => m.Id).ValueGeneratedNever();
        builder.Property(m => m.Kind).HasMaxLength(100);
        builder.Property(m => m.Payload).HasColumnType("jsonb");
        builder.Property(m => m.IdempotencyKey).HasMaxLength(200);
        builder.HasIndex(m => m.IdempotencyKey).IsUnique();
        builder.Property(m => m.CorrelationId).HasMaxLength(64);
        builder.Property(m => m.LastError).HasMaxLength(1000);
        builder.Property(m => m.ResolutionNote).HasMaxLength(1000);
        // The dispatcher's only query: due rows that are neither done nor failed.
        builder.HasIndex(m => m.AvailableAt).HasFilter("processed_at IS NULL AND failed_at IS NULL");
    }
}
```

`Platform/Outbox/IOutboxHandler.cs`:

```csharp
using System.Text.Json;

namespace ExtraSpace.Api.Platform.Outbox;

public sealed record OutboxItem(Guid Id, string IdempotencyKey, JsonElement Payload, int Attempt);

/// <summary>
/// Runs one kind of outbox step. It must be idempotent: a crash after the work but before the row is marked done runs it again.
/// Exception messages are stored in <c>last_error</c> and shown to staff, so they must never hold personal data.
/// </summary>
public interface IOutboxHandler
{
    string Kind { get; }

    Task HandleAsync(OutboxItem item, CancellationToken cancellationToken);
}

public interface IOutbox
{
    /// <summary>
    /// Adds a step to the caller's unit of work. The caller's SaveChanges saves it in the caller's transaction, and it runs only
    /// if that commits (S1 spec §9.10). A second step with the same key fails the save.
    /// </summary>
    void Enqueue<T>(string kind, T payload, string idempotencyKey);
}
```

`Platform/Outbox/Outbox.cs`:

```csharp
using System.Diagnostics;
using System.Text.Json;
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Tracing;

namespace ExtraSpace.Api.Platform.Outbox;

internal sealed class Outbox(AppDbContext db, TimeProvider time) : IOutbox
{
    public void Enqueue<T>(string kind, T payload, string idempotencyKey)
    {
        var now = time.GetUtcNow().UtcDateTime;
        db.Add(new OutboxMessage
        {
            Kind = kind,
            Payload = JsonSerializer.SerializeToDocument(payload, JsonSerializerOptions.Web),
            IdempotencyKey = idempotencyKey,
            CorrelationId = Correlation.CurrentId ?? Activity.Current?.TraceId.ToHexString(),
            CreatedAt = now,
            AvailableAt = now,
        });
    }
}
```

`Platform/Outbox/OutboxNudge.cs`:

```csharp
using System.Data.Common;
using Hangfire;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace ExtraSpace.Api.Platform.Outbox;

/// <summary>
/// Starts a dispatcher run right after a commit that saved outbox rows, so steps run within a second instead of at the minute
/// sweep. A failed nudge only delays the step until the sweep.
/// </summary>
internal sealed partial class OutboxNudge(IBackgroundJobClient jobs, ILogger<OutboxNudge> logger) : SaveChangesInterceptor, IDbTransactionInterceptor
{
    private bool _pending;

    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        Note(eventData.Context);
        return result;
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData eventData, InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        Note(eventData.Context);
        return ValueTask.FromResult(result);
    }

    public override int SavedChanges(SaveChangesCompletedEventData eventData, int result)
    {
        if (eventData.Context?.Database.CurrentTransaction is null) Nudge();
        return result;
    }

    public override ValueTask<int> SavedChangesAsync(SaveChangesCompletedEventData eventData, int result, CancellationToken cancellationToken = default)
    {
        if (eventData.Context?.Database.CurrentTransaction is null) Nudge();
        return ValueTask.FromResult(result);
    }

    public void TransactionCommitted(DbTransaction transaction, TransactionEndEventData eventData) => Nudge();

    public Task TransactionCommittedAsync(DbTransaction transaction, TransactionEndEventData eventData, CancellationToken cancellationToken = default)
    {
        Nudge();
        return Task.CompletedTask;
    }

    public void TransactionRolledBack(DbTransaction transaction, TransactionEndEventData eventData) => _pending = false;

    public Task TransactionRolledBackAsync(DbTransaction transaction, TransactionEndEventData eventData, CancellationToken cancellationToken = default)
    {
        _pending = false;
        return Task.CompletedTask;
    }

    private void Note(DbContext? context)
    {
        if (context?.ChangeTracker.Entries<OutboxMessage>().Any(e => e.State == EntityState.Added) == true) _pending = true;
    }

    private void Nudge()
    {
        if (!_pending) return;
        _pending = false;
        try
        {
            jobs.Enqueue<OutboxDispatchJob>(job => job.RunAsync(CancellationToken.None));
        }
        catch (Exception exception)
        {
            LogNudgeFailed(logger, exception);
        }
    }

    [LoggerMessage(Level = LogLevel.Warning, Message = "Outbox nudge failed; the minute sweep will run the step")]
    private static partial void LogNudgeFailed(ILogger logger, Exception exception);
}
```

`Platform/Outbox/OutboxDispatchJob.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Jobs;
using ExtraSpace.Api.Platform.Tracing;
using Hangfire;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Platform.Outbox;

/// <summary>Runs due outbox steps one at a time (S1 spec §9.10). Several runs at once are safe: each row is claimed with SKIP LOCKED.</summary>
internal sealed partial class OutboxDispatchJob(IServiceScopeFactory scopes, TimeProvider time, ILogger<OutboxDispatchJob> logger) : IRecurringJob
{
    public const string Name = "OutboxDispatcher";
    public const string Cron = "* * * * *";
    internal const int MaxPerRun = 100;
    internal static readonly TimeSpan[] RetryDelays =
        [TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(15), TimeSpan.FromMinutes(60)];

    [AutomaticRetry(Attempts = 0, LogEvents = false)]
    public async Task RunAsync(CancellationToken cancellationToken)
    {
        for (var i = 0; i < MaxPerRun; i++)
            if (!await DispatchNextAsync(cancellationToken)) return;
    }

    private async Task<bool> DispatchNextAsync(CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        var now = time.GetUtcNow().UtcDateTime;
        var message = await db.Set<OutboxMessage>()
            .FromSql($"""
                SELECT * FROM outbox_message
                WHERE processed_at IS NULL AND failed_at IS NULL AND available_at <= {now}
                ORDER BY available_at, id LIMIT 1 FOR UPDATE SKIP LOCKED
                """)
            .SingleOrDefaultAsync(cancellationToken);
        if (message is null) return false;

        using (Correlation.Begin(message.CorrelationId ?? message.Id.ToString("N")))
        {
            try
            {
                await HandleAsync(message, cancellationToken);
                message.ProcessedAt = time.GetUtcNow().UtcDateTime;
                LogDone(logger, message.Kind, message.Id);
            }
            catch (Exception exception) when (!cancellationToken.IsCancellationRequested)
            {
                Fail(message, exception, time.GetUtcNow().UtcDateTime);
            }
        }
        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return true;
    }

    // Its own scope: the handler's DbContext and transaction are its own, while the row lock above is held until it ends.
    private async Task HandleAsync(OutboxMessage message, CancellationToken cancellationToken)
    {
        await using var scope = scopes.CreateAsyncScope();
        var handler = scope.ServiceProvider.GetServices<IOutboxHandler>().SingleOrDefault(h => h.Kind == message.Kind)
            ?? throw new InvalidOperationException($"No outbox handler for kind '{message.Kind}'.");
        await handler.HandleAsync(new OutboxItem(message.Id, message.IdempotencyKey, message.Payload.RootElement, message.Attempts + 1), cancellationToken);
    }

    private void Fail(OutboxMessage message, Exception exception, DateTime now)
    {
        message.Attempts++;
        var error = $"{exception.GetType().Name}: {exception.Message}";
        message.LastError = error.Length <= 1000 ? error : error[..1000];
        if (message.Attempts > RetryDelays.Length)
        {
            message.FailedAt = now;
            LogFailedPermanently(logger, exception, message.Id, message.Kind, message.Attempts);
            return;
        }
        message.AvailableAt = now + RetryDelays[message.Attempts - 1];
        LogRetry(logger, exception, message.Kind, message.Id, message.Attempts, message.AvailableAt);
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "Outbox {kind} message {outboxId} done")]
    private static partial void LogDone(ILogger logger, string kind, Guid outboxId);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Outbox {kind} message {outboxId} failed (attempt {attempt}); next try at {availableAt}")]
    private static partial void LogRetry(ILogger logger, Exception exception, string kind, Guid outboxId, int attempt, DateTime availableAt);

    // Task 8's alarm matches this template text exactly.
    [LoggerMessage(Level = LogLevel.Error, Message = "Outbox message {outboxId} of kind {kind} failed permanently after {attempt} attempts")]
    private static partial void LogFailedPermanently(ILogger logger, Exception exception, Guid outboxId, string kind, int attempt);
}
```

`Platform/Outbox/OutboxSetup.cs`:

```csharp
using ExtraSpace.Api.Platform.Jobs;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace ExtraSpace.Api.Platform.Outbox;

public static class OutboxSetup
{
    internal static IServiceCollection AddOutbox(this IServiceCollection services)
    {
        services.AddScoped<IOutbox, Outbox>();
        // One per DbContext scope: it remembers whether this unit of work added rows. EF also calls its transaction methods.
        services.AddScoped<ISaveChangesInterceptor, OutboxNudge>();
        services.AddRecurringJob<OutboxDispatchJob>(OutboxDispatchJob.Name, OutboxDispatchJob.Cron);
        return services;
    }

    public static IServiceCollection AddOutboxHandler<THandler>(this IServiceCollection services) where THandler : class, IOutboxHandler =>
        services.AddScoped<IOutboxHandler, THandler>();
}
```

In `PlatformServices.AddPlatform`, add `services.AddOutbox();` right after `services.AddPlatformJobs(configuration);`. The DbContext options already add every `ISaveChangesInterceptor` from the scope, so `OutboxNudge` is picked up there. Because EF registers an interceptor for every interceptor interface it implements, its `IDbTransactionInterceptor` methods run too.

- [ ] **Step 4: Move the email onto the outbox**

`Integrations/Email/EmailSealer.cs` takes the sealing code from `HangfireEmailSender`:

```csharp
using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;

namespace ExtraSpace.Api.Integrations.Email;

internal sealed record EmailPayload(string To, Dictionary<string, string> Values);

/// <summary>An email whose address and values are encrypted; safe to store in the outbox and the job tables.</summary>
internal sealed record SealedEmail(string Template, DateTimeOffset ExpiresAt, string Payload);

internal sealed class EmailSealer(IDataProtectionProvider protection, TimeProvider time)
{
    internal const string Purpose = "ExtraSpace.Integrations.Email.v1";

    public SealedEmail Seal(EmailMessage message)
    {
        // A missing value or unknown template fails this request, not every attempt of the job.
        _ = EmailTemplates.Render(message.Template, message.To, message.Values);
        var payload = JsonSerializer.Serialize(new EmailPayload(message.To, new Dictionary<string, string>(message.Values)));
        // The job checks ExpiresAt itself; the protector lives a minute longer so an unreadable payload is a real failure.
        var sealedPayload = protection.CreateProtector(Purpose).ToTimeLimitedDataProtector()
            .Protect(payload, message.ValidFor + TimeSpan.FromMinutes(1));
        return new SealedEmail(message.Template, time.GetUtcNow() + message.ValidFor, sealedPayload);
    }
}
```

`Integrations/Email/EmailJobQueue.cs`:

```csharp
using Hangfire;

namespace ExtraSpace.Api.Integrations.Email;

internal sealed class EmailJobQueue(IBackgroundJobClient jobs)
{
    public string Enqueue(SealedEmail email) =>
        jobs.Enqueue<EmailJob>(job => job.SendAsync(email.Template, email.ExpiresAt, email.Payload, CancellationToken.None));
}
```

`Integrations/Email/EmailOutboxHandler.cs`:

```csharp
using System.Text.Json;
using ExtraSpace.Api.Platform.Outbox;

namespace ExtraSpace.Api.Integrations.Email;

/// <summary>Hands a sealed email to <see cref="EmailJob"/>, which keeps its own short retries. At least once: a crash between the two can send it twice.</summary>
internal sealed class EmailOutboxHandler(EmailJobQueue queue) : IOutboxHandler
{
    public const string KindName = "Email";

    public string Kind => KindName;

    public Task HandleAsync(OutboxItem item, CancellationToken cancellationToken)
    {
        queue.Enqueue(item.Payload.Deserialize<SealedEmail>(JsonSerializerOptions.Web) ?? throw new InvalidOperationException("Empty email payload."));
        return Task.CompletedTask;
    }
}
```

`Integrations/Email/OutboxEmailSender.cs`:

```csharp
using ExtraSpace.Api.Platform.Outbox;

namespace ExtraSpace.Api.Integrations.Email;

internal sealed class OutboxEmailSender(IOutbox outbox, EmailSealer sealer) : IEmailSender
{
    // No natural key: every email request is its own step.
    public void Enqueue(EmailMessage message) =>
        outbox.Enqueue(EmailOutboxHandler.KindName, sealer.Seal(message), $"email:{Guid.CreateVersion7()}");
}
```

`IEmailSender.cs`: change the method to `void Enqueue(EmailMessage message);` with this summary: "Adds the email to the caller's unit of work (outbox). Call it before the caller's SaveChanges/commit: the email goes out only if that commits (S1 spec §9.10)."

`EmailSetup.AddEmail`: replace the `HangfireEmailSender` registration with:

```csharp
        services.AddSingleton<EmailSealer>();
        services.AddSingleton<EmailJobQueue>();
        services.AddScoped<IEmailSender, OutboxEmailSender>();
        services.AddOutboxHandler<EmailOutboxHandler>();
```

Delete `HangfireEmailSender.cs`, and change every `HangfireEmailSender.Purpose` to `EmailSealer.Purpose` (grep it).

`LoginCodeService.SendAsync`: move the `sender.Enqueue(new EmailMessage("login-code", …))` call **inside** the transaction, just before `await db.SaveChangesAsync(cancellationToken);`, so the email row commits with the code row. Keep the log line where it is (after the commit).

`TestEndpoints.cs` `/test/email`: keep it returning a Hangfire job id for the existing job-level tests:

```csharp
        test.MapPost("/email", (string to, string code, int? validForMs, EmailSealer sealer, EmailJobQueue queue) =>
        {
            var jobId = queue.Enqueue(sealer.Seal(new EmailMessage("login-code", to,
                new Dictionary<string, string> { ["code"] = code, ["minutes"] = "10" },
                TimeSpan.FromMilliseconds(validForMs ?? 600_000))));
            return TypedResults.Ok(new { jobId });
        });
```

In `EmailTests.cs`, fix only the test that calls `sender.Enqueue(...)` directly (around line 107). It now checks that `EmailSealer.Seal` throws for an unknown template or a missing value. That was the old `Enqueue` behaviour, so assert the same exception on `sealer.Seal(...)`.

- [ ] **Step 5: Add the migration**

```bash
dotnet ef migrations add Outbox --project src/ExtraSpace.Api
```

Strip the BOM from the 3 files. Check that the migration creates `outbox_message` with the unique index on `idempotency_key` and the filtered index on `available_at`.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*OutboxTests"`, then the S0 sign-in suites: `--filter-class "*LoginCodeTests"`, `"*StaffCodeSignInTests"`, `"*EmailTests"`, `"*SignInLoggingTests"`.
Expected: all pass. The sign-in tests now get their email through the outbox (nudge → dispatcher → `EmailJob`).

- [ ] **Step 7: Stop and report** (no commit). List the callers of `IEmailSender` you checked (`LoginCodeService`, `TestEndpoints`) and say why nothing else needs a change.

---

### Task 3: Sites data model

**Files:**
- Create: `src/ExtraSpace.Api/Features/Sites/Site.cs`, `StorageType.cs`, `UnitSize.cs`, `Unit.cs`, `UnitSyncState.cs`, `SiteCountries.cs`, `SitesEntityConfigurations.cs`, `SitesSetup.cs`
- Modify: `Program.cs` (`builder.Services.AddSitesFeature();` after `AddAdminFeature`)
- Migration: `Sites`
- Test: `tests/ExtraSpace.Api.Tests/Features/Sites/SitesDataTests.cs`, `TestSupport/SitesTestData.cs`

**Interfaces:**
- Produces:
  - entities `Site`, `StorageType` (seeded ids `StorageType.SelfStorageId`, `StorageType.WorkspaceId`; keys `"self-storage"`, `"workspace"`), `UnitSize`, `Unit` (navigations `Site`, `StorageType`, `UnitSize`; DB-computed `Available`) and `UnitSyncState`
  - the `public enum FacilityType { SelfStorage, Workspace }`
  - `SiteCountries.Get(string) → SiteCountry(Code, Currency, TimeZone, TaxLabel)`
  - `StorageType.KeyFor(string siteLinkTypeName)`
  - test helpers `SitesTestData.NewCode()`, `api.CreateSiteAsync(country, code)` and `api.CreateUnitAsync(siteId, change)`

- [ ] **Step 1: Write the failing tests**

`tests/ExtraSpace.Api.Tests/TestSupport/SitesTestData.cs`:

```csharp
using ExtraSpace.Api.Features.Sites;

namespace ExtraSpace.Api.Tests.TestSupport;

internal static class SitesTestData
{
    /// <summary>A location code no other test uses (tests share one database and run in parallel).</summary>
    public static string NewCode() => "T" + Guid.NewGuid().ToString("N")[..9].ToUpperInvariant();

    public static async Task<Site> CreateSiteAsync(this ApiFactory api, string country = "SG", string? code = null)
    {
        var defaults = SiteCountries.Get(country);
        var site = new Site
        {
            LocationCode = code ?? NewCode(), Name = "Test site", Country = defaults.Code, Currency = defaults.Currency,
            TimeZone = defaults.TimeZone, TaxPercentage = 9m, TaxLabel = defaults.TaxLabel, Active = true,
        };
        await api.WithDbAsync(async db =>
        {
            db.Add(site);
            await db.SaveChangesAsync();
        });
        return site;
    }

    public static async Task<Unit> CreateUnitAsync(this ApiFactory api, Guid siteId, Action<Unit>? change = null)
    {
        var unit = new Unit
        {
            SiteId = siteId, SiteLinkUnitId = Random.Shared.Next(1, int.MaxValue), UnitName = "U" + Random.Shared.Next(100000, 999999),
            Width = 5, Length = 10, AreaSqft = 50, Rentable = true, StorageTypeId = StorageType.SelfStorageId,
        };
        change?.Invoke(unit);
        await api.WithDbAsync(async db =>
        {
            db.Add(unit);
            await db.SaveChangesAsync();
        });
        return unit;
    }
}
```

`tests/ExtraSpace.Api.Tests/Features/Sites/SitesDataTests.cs`:

```csharp
using ExtraSpace.Api.Features.Sites;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace ExtraSpace.Api.Tests.Features.Sites;

public sealed class SitesDataTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private async Task<Unit> ReloadAsync(Guid id)
    {
        Unit? unit = null;
        await api.WithDbAsync(async db => unit = await db.Set<Unit>().AsNoTracking().SingleAsync(u => u.Id == id, Ct));
        return unit!;
    }

    [Fact]
    public async Task Available_is_computed_by_the_database()
    {
        var site = await api.CreateSiteAsync();
        var unit = await api.CreateUnitAsync(site.Id);
        (await ReloadAsync(unit.Id)).Available.Should().BeTrue();

        await api.WithDbAsync(async db =>
        {
            var row = await db.Set<Unit>().SingleAsync(u => u.Id == unit.Id, Ct);
            row.Rented = true;
            await db.SaveChangesAsync(Ct);
        });
        (await ReloadAsync(unit.Id)).Available.Should().BeFalse();

        var deleted = await api.CreateUnitAsync(site.Id, u => u.DeletedAt = DateTime.UtcNow);
        (await ReloadAsync(deleted.Id)).Available.Should().BeFalse();
        var waiting = await api.CreateUnitAsync(site.Id, u => u.WaitingListReserved = true);
        (await ReloadAsync(waiting.Id)).Available.Should().BeFalse();
        var unrentable = await api.CreateUnitAsync(site.Id, u => u.Rentable = false);
        (await ReloadAsync(unrentable.Id)).Available.Should().BeFalse();
    }

    [Fact]
    public async Task A_SiteLink_unit_id_is_unique_within_a_site()
    {
        var site = await api.CreateSiteAsync();
        var unit = await api.CreateUnitAsync(site.Id);
        var duplicate = () => api.CreateUnitAsync(site.Id, u => u.SiteLinkUnitId = unit.SiteLinkUnitId);
        (await duplicate.Should().ThrowAsync<DbUpdateException>()).WithInnerException<PostgresException>()
            .Which.SqlState.Should().Be(PostgresErrorCodes.UniqueViolation);

        var other = await api.CreateSiteAsync();
        await api.CreateUnitAsync(other.Id, u => u.SiteLinkUnitId = unit.SiteLinkUnitId);   // another site may reuse it
    }

    [Theory]
    [InlineData("US", "SGD")]
    [InlineData("SG", "USD")]
    public async Task Country_and_currency_are_checked(string country, string currency)
    {
        var save = () => api.WithDbAsync(async db =>
        {
            db.Add(new Site
            {
                LocationCode = SitesTestData.NewCode(), Name = "x", Country = country, Currency = currency,
                TimeZone = "Asia/Singapore", TaxPercentage = 9m, TaxLabel = "GST", Active = true,
            });
            await db.SaveChangesAsync(Ct);
        });
        (await save.Should().ThrowAsync<DbUpdateException>()).WithInnerException<PostgresException>()
            .Which.SqlState.Should().Be(PostgresErrorCodes.CheckViolation);
    }

    [Fact]
    public async Task The_two_storage_types_are_seeded()
    {
        List<StorageType> types = [];
        await api.WithDbAsync(async db => types = await db.Set<StorageType>().AsNoTracking()
            .Where(t => t.Id == StorageType.SelfStorageId || t.Id == StorageType.WorkspaceId).ToListAsync(Ct));
        types.Should().HaveCount(2);
        types.Single(t => t.Key == "self-storage").Active.Should().BeTrue();
        types.Single(t => t.Key == "workspace").Active.Should().BeFalse();
    }

    [Theory]
    [InlineData(" BizPlus ", "workspace")]
    [InlineData("bizplus", "workspace")]
    [InlineData("Walk In", "self-storage")]
    [InlineData("", "self-storage")]
    public void C7_BizPlus_units_are_workspace(string typeName, string key) =>
        StorageType.KeyFor(typeName).Should().Be(key);
}
```

- [ ] **Step 2: Run and watch them fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*SitesDataTests"`
Expected: compile errors (no `Site`, `Unit`, …).

- [ ] **Step 3: Implement the entities**

`Features/Sites/Site.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;

namespace ExtraSpace.Api.Features.Sites;

public enum FacilityType { SelfStorage, Workspace }

/// <summary>A SiteLink facility (S1 spec §5.1). Staff-edited; the unit sync never writes it.</summary>
internal sealed class Site : IHasTimestamps, IHasStaffStamps, IAudited
{
    public Guid Id { get; init; } = Guid.CreateVersion7();
    public required string LocationCode { get; set; }
    public int? SiteLinkSiteId { get; set; }
    public required string Name { get; set; }
    public string? DisplayName { get; set; }
    public string? Description { get; set; }
    public string? HeroImageUrl { get; set; }
    public string? Address1 { get; set; }
    public string? City { get; set; }
    public string? Region { get; set; }
    public string? PostalCode { get; set; }
    public required string Country { get; set; }
    public string? Phone { get; set; }
    public decimal? Latitude { get; set; }
    public decimal? Longitude { get; set; }
    public required string TimeZone { get; set; }
    public required string Currency { get; set; }
    public decimal TaxPercentage { get; set; }
    public required string TaxLabel { get; set; }
    public FacilityType FacilityType { get; set; } = FacilityType.SelfStorage;
    public bool Active { get; set; } = true;
    /// <summary>The reused Stripe connected account of this facility; null = no in-app payments here.</summary>
    public string? StripeAccountId { get; set; }
    public Guid? CreatedByStaffId { get; set; }
    public Guid? UpdatedByStaffId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public uint Version { get; set; }
}
```

`Features/Sites/StorageType.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;

namespace ExtraSpace.Api.Features.Sites;

internal sealed class StorageType : IHasTimestamps, IHasStaffStamps, IAudited
{
    public static readonly Guid SelfStorageId = Guid.Parse("0199e000-0000-7000-8000-000000000001");
    public static readonly Guid WorkspaceId = Guid.Parse("0199e000-0000-7000-8000-000000000002");
    public const string SelfStorageKey = "self-storage";
    public const string WorkspaceKey = "workspace";

    public Guid Id { get; init; } = Guid.CreateVersion7();
    /// <summary>Cannot change after creation: the unit sync finds the two seeded types by key.</summary>
    public required string Key { get; init; }
    public required string Name { get; set; }
    public string? DisplayName { get; set; }
    public string? IconPath { get; set; }
    public string? ImagePath { get; set; }
    public int SortOrder { get; set; }
    public bool Active { get; set; } = true;
    public Guid? CreatedByStaffId { get; set; }
    public Guid? UpdatedByStaffId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public uint Version { get; set; }

    /// <summary>SiteLink type name "BizPlus" (any case, trimmed) is a workspace unit; everything else self-storage (demo 03 §4.1.3).</summary>
    public static string KeyFor(string siteLinkTypeName) =>
        siteLinkTypeName.Trim().Equals("bizplus", StringComparison.OrdinalIgnoreCase) ? WorkspaceKey : SelfStorageKey;
}
```

`Features/Sites/UnitSize.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;

namespace ExtraSpace.Api.Features.Sites;

internal sealed class UnitSize : IHasTimestamps, IHasStaffStamps, IAudited
{
    public Guid Id { get; init; } = Guid.CreateVersion7();
    public required string Key { get; set; }
    public required string Label { get; set; }
    public string? DisplayName { get; set; }
    public string? Description { get; set; }
    public string? UnitGroup { get; set; }
    public string? ImagePath { get; set; }
    public decimal? MinAreaSqft { get; set; }
    public decimal? MaxAreaSqft { get; set; }
    public int SortOrder { get; set; }
    public Guid? StorageTypeId { get; set; }
    public Guid? CreatedByStaffId { get; set; }
    public Guid? UpdatedByStaffId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public uint Version { get; set; }
}
```

`Features/Sites/Unit.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;

namespace ExtraSpace.Api.Features.Sites;

/// <summary>Our copy of a SiteLink unit (S1 spec §5.1). Written only by the unit sync; read-only in the admin.</summary>
internal sealed class Unit : IHasTimestamps
{
    public Guid Id { get; init; } = Guid.CreateVersion7();
    public Guid SiteId { get; init; }
    public Site Site { get; private set; } = null!;
    public int SiteLinkUnitId { get; init; }
    public int SiteLinkUnitTypeId { get; set; }
    public required string UnitName { get; set; }
    public string? Description { get; set; }
    public decimal Width { get; set; }
    public decimal Length { get; set; }
    public decimal AreaSqft { get; set; }
    public int? Floor { get; set; }
    public bool Climate { get; set; }
    public bool Inside { get; set; }
    public bool Power { get; set; }
    public bool Alarm { get; set; }
    public bool Ada { get; set; }
    public bool Mobile { get; set; }
    public decimal? StandardRate { get; set; }
    public decimal? WebRate { get; set; }
    public decimal? BoardRate { get; set; }
    public decimal? PushRate { get; set; }
    public decimal? PreferredRate { get; set; }
    public decimal? StandardSecurityDeposit { get; set; }
    public bool Rented { get; set; }
    public bool Rentable { get; set; } = true;
    public bool WaitingListReserved { get; set; }
    public DateTime? DeletedAt { get; set; }
    /// <summary>Stored generated column: rentable AND NOT rented AND NOT waiting_list_reserved AND deleted_at IS NULL.</summary>
    public bool Available { get; private set; }
    public Guid? StorageTypeId { get; set; }
    public StorageType? StorageType { get; private set; }
    public Guid? UnitSizeId { get; set; }
    public UnitSize? UnitSize { get; private set; }
    public DateTime? LastSyncedAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
```

`Features/Sites/UnitSyncState.cs`:

```csharp
namespace ExtraSpace.Api.Features.Sites;

/// <summary>The unit sync's own row per site, so the sync never writes the staff-edited <see cref="Site"/> (S1 spec §5.1).</summary>
internal sealed class UnitSyncState
{
    public Guid SiteId { get; init; }
    /// <summary>SiteLink's .NET-ticks cursor, round-tripped only; null = no successful pull yet.</summary>
    public long? LastTimePolledTicks { get; set; }
    public DateTime? LastSyncedAt { get; set; }
    public DateTime? LastAttemptAt { get; set; }
    public string? LastError { get; set; }
}
```

`Features/Sites/SiteCountries.cs`:

```csharp
using ExtraSpace.Api.Platform.Errors;

namespace ExtraSpace.Api.Features.Sites;

public sealed record SiteCountry(string Code, string Currency, string TimeZone, string TaxLabel);

/// <summary>The three countries of release 1 (S1 spec §1). The currency follows the country; zone and tax label are defaults.</summary>
internal static class SiteCountries
{
    private static readonly Dictionary<string, SiteCountry> All = new(StringComparer.Ordinal)
    {
        ["SG"] = new("SG", "SGD", "Asia/Singapore", "GST"),
        ["MY"] = new("MY", "MYR", "Asia/Kuala_Lumpur", "SST"),
        ["KR"] = new("KR", "KRW", "Asia/Seoul", "VAT"),
    };

    public static SiteCountry Get(string code) =>
        All.TryGetValue(code, out var country) ? country : throw new AppException(400, ErrorCodes.ValidationFailed, $"Unknown country '{code}'.");
}
```

`Features/Sites/SitesEntityConfigurations.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace ExtraSpace.Api.Features.Sites;

internal sealed class SiteConfiguration : IEntityTypeConfiguration<Site>
{
    public void Configure(EntityTypeBuilder<Site> builder)
    {
        builder.ToTable("site", t =>
        {
            t.HasCheckConstraint("ck_site_country", "country IN ('SG', 'MY', 'KR')");
            t.HasCheckConstraint("ck_site_currency", "currency IN ('SGD', 'MYR', 'KRW')");
            t.HasCheckConstraint("ck_site_tax_percentage", "tax_percentage >= 0 AND tax_percentage <= 100");
        });
        builder.Property(s => s.Id).ValueGeneratedNever();
        builder.Property(s => s.LocationCode).HasMaxLength(20);
        builder.HasIndex(s => s.LocationCode).IsUnique();
        builder.HasIndex(s => s.SiteLinkSiteId).IsUnique();   // NULLs never clash in PostgreSQL
        builder.Property(s => s.Name).HasMaxLength(200);
        builder.Property(s => s.DisplayName).HasMaxLength(200);
        builder.Property(s => s.Description).HasMaxLength(4000);
        builder.Property(s => s.HeroImageUrl).HasMaxLength(1000);
        builder.Property(s => s.Address1).HasMaxLength(300);
        builder.Property(s => s.City).HasMaxLength(100);
        builder.Property(s => s.Region).HasMaxLength(100);
        builder.Property(s => s.PostalCode).HasMaxLength(20);
        builder.Property(s => s.Country).HasMaxLength(2).IsFixedLength();
        builder.Property(s => s.Phone).HasMaxLength(50);
        builder.Property(s => s.Latitude).HasPrecision(9, 6);
        builder.Property(s => s.Longitude).HasPrecision(9, 6);
        builder.Property(s => s.TimeZone).HasMaxLength(64);
        builder.Property(s => s.Currency).HasMaxLength(3).IsFixedLength();
        builder.Property(s => s.TaxPercentage).HasPrecision(5, 2);
        builder.Property(s => s.TaxLabel).HasMaxLength(20);
        builder.Property(s => s.FacilityType).HasConversion<string>().HasMaxLength(20);
        builder.Property(s => s.StripeAccountId).HasMaxLength(100);
        builder.Property(s => s.Version).IsRowVersion();
    }
}

internal sealed class StorageTypeConfiguration : IEntityTypeConfiguration<StorageType>
{
    private static readonly DateTime Seeded = new(2026, 10, 14, 0, 0, 0, DateTimeKind.Utc);

    public void Configure(EntityTypeBuilder<StorageType> builder)
    {
        builder.ToTable("storage_type");
        builder.Property(t => t.Id).ValueGeneratedNever();
        builder.Property(t => t.Key).HasMaxLength(50);
        builder.HasIndex(t => t.Key).IsUnique();
        builder.Property(t => t.Name).HasMaxLength(100);
        builder.Property(t => t.DisplayName).HasMaxLength(100);
        builder.Property(t => t.IconPath).HasMaxLength(500);
        builder.Property(t => t.ImagePath).HasMaxLength(500);
        builder.Property(t => t.Version).IsRowVersion();
        builder.HasData(
            new StorageType { Id = StorageType.SelfStorageId, Key = StorageType.SelfStorageKey, Name = "Self Storage", SortOrder = 1, Active = true, CreatedAt = Seeded, UpdatedAt = Seeded },
            new StorageType { Id = StorageType.WorkspaceId, Key = StorageType.WorkspaceKey, Name = "Workspace", SortOrder = 2, Active = false, CreatedAt = Seeded, UpdatedAt = Seeded });
    }
}

internal sealed class UnitSizeConfiguration : IEntityTypeConfiguration<UnitSize>
{
    public void Configure(EntityTypeBuilder<UnitSize> builder)
    {
        builder.ToTable("unit_size", t => t.HasCheckConstraint("ck_unit_size_range",
            "min_area_sqft IS NULL OR max_area_sqft IS NULL OR min_area_sqft <= max_area_sqft"));
        builder.Property(s => s.Id).ValueGeneratedNever();
        builder.Property(s => s.Key).HasMaxLength(50);
        builder.HasIndex(s => s.Key).IsUnique();
        builder.Property(s => s.Label).HasMaxLength(100);
        builder.Property(s => s.DisplayName).HasMaxLength(100);
        builder.Property(s => s.Description).HasMaxLength(1000);
        builder.Property(s => s.UnitGroup).HasMaxLength(100);
        builder.Property(s => s.ImagePath).HasMaxLength(500);
        builder.Property(s => s.MinAreaSqft).HasPrecision(10, 2);
        builder.Property(s => s.MaxAreaSqft).HasPrecision(10, 2);
        builder.HasOne<StorageType>().WithMany().HasForeignKey(s => s.StorageTypeId).OnDelete(DeleteBehavior.Restrict);
        builder.Property(s => s.Version).IsRowVersion();
    }
}

internal sealed class UnitConfiguration : IEntityTypeConfiguration<Unit>
{
    public void Configure(EntityTypeBuilder<Unit> builder)
    {
        builder.ToTable("unit");
        builder.Property(u => u.Id).ValueGeneratedNever();
        builder.HasOne(u => u.Site).WithMany().HasForeignKey(u => u.SiteId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(u => u.StorageType).WithMany().HasForeignKey(u => u.StorageTypeId).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(u => u.UnitSize).WithMany().HasForeignKey(u => u.UnitSizeId).OnDelete(DeleteBehavior.Restrict);
        builder.HasIndex(u => new { u.SiteId, u.SiteLinkUnitId }).IsUnique();
        builder.HasIndex(u => new { u.SiteId, u.UnitName });   // S1-2 matches ledgers by (site, unit name)
        builder.Property(u => u.UnitName).HasMaxLength(100);
        builder.Property(u => u.Description).HasMaxLength(1000);
        builder.Property(u => u.Width).HasPrecision(10, 2);
        builder.Property(u => u.Length).HasPrecision(10, 2);
        builder.Property(u => u.Available)
            .HasComputedColumnSql("rentable AND NOT rented AND NOT waiting_list_reserved AND deleted_at IS NULL", stored: true);
    }
}

internal sealed class UnitSyncStateConfiguration : IEntityTypeConfiguration<UnitSyncState>
{
    public void Configure(EntityTypeBuilder<UnitSyncState> builder)
    {
        builder.ToTable("unit_sync_state");
        builder.HasKey(s => s.SiteId);
        builder.Property(s => s.SiteId).ValueGeneratedNever();
        builder.HasOne<Site>().WithOne().HasForeignKey<UnitSyncState>(s => s.SiteId).OnDelete(DeleteBehavior.Cascade);
        builder.Property(s => s.LastError).HasMaxLength(1000);
    }
}
```

`Features/Sites/SitesSetup.cs` (Tasks 6 and 7 add to it):

```csharp
namespace ExtraSpace.Api.Features.Sites;

internal static class SitesSetup
{
    public static IServiceCollection AddSitesFeature(this IServiceCollection services) => services;
}
```

`Program.cs`: add `builder.Services.AddSitesFeature();` after `AddAdminFeature(...)`.

- [ ] **Step 4: Add the migration**

```bash
dotnet ef migrations add Sites --project src/ExtraSpace.Api
```

Strip the BOM. Check by reading the migration:
- `unit.available` is `GENERATED ALWAYS AS (…) STORED`
- the three check constraints are present
- the two `storage_type` rows are seeded
- `unit_sync_state` cascades on site delete

- [ ] **Step 5: Run the tests and watch them pass**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*SitesDataTests"`, then `--filter-class "*ArchitectureTests"`.
Expected: all pass.

- [ ] **Step 6: Stop and report** (no commit).

---

### Task 4: SiteLink client core

**Files:**
- Create in `src/ExtraSpace.Api/Integrations/SiteLink/`: `SiteLinkOptions.cs`, `SiteLinkSetup.cs`, `SiteLinkClient.cs`, `SiteLinkFields.cs`, `SoapEnvelope.cs`, `SiteLinkReply.cs`, `SiteLinkValues.cs`, `SiteLinkExceptions.cs`, `SiteLinkAttemptHandler.cs`, `SiteLinkCallCounter.cs`
- Create: `src/ExtraSpace.Api/Platform/Errors/IProblemException.cs`
- Modify:
  - `Platform/Errors/AppExceptionHandler.cs` (one `Classify` arm)
  - `Program.cs` (`builder.Services.AddSiteLink(builder.Configuration, builder.Environment);` after `AddEmail`)
  - `appsettings.json` (a `SiteLink` section)
  - `Directory.Packages.props` + `src/ExtraSpace.Api/ExtraSpace.Api.csproj` (`Microsoft.Extensions.Http.Resilience` 10.10.0)
- Migration: `SiteLinkCallMonth`
- Test: `tests/ExtraSpace.Api.Tests/TestSupport/FakeSiteLink.cs`, `SiteLinkXml.cs`, `ApiFactory.cs`; `Integrations/SiteLinkClientTests.cs`, `Integrations/SiteLinkReplyTests.cs`, `Integrations/SiteLinkAttemptHandlerTests.cs`; `Platform/ExceptionClassifyTests.cs`

**Interfaces:**
- Produces (all `internal`):
  - `SiteLinkClient.CallAsync(string operation, string locationCode, SiteLinkCallKind kind, SiteLinkFields fields, CancellationToken) → Task<SiteLinkReply>`
  - `SiteLinkReply.Table(name)`, `.RetCode`, `.RetMessage`, `.ThrowIfRefused(operation)`
  - `SiteLinkRow.Has/Text/Int/Long/Decimal/Bool/UtcDate(column, zone)`
  - `SiteLinkValues.ParseBool`, `SiteLinkValues.ParseDate`, `SiteLinkValues.NullDate`
  - `SiteLinkException(operation, returnCode, siteLinkMessage)` → 502 `SITELINK_ERROR`
  - `SiteLinkUnavailableException(operation, reason)` → 503 `SITELINK_UNAVAILABLE`
  - `SiteLinkCallCounter.CrossedAlarm(total, added, alarm)`
  - `public interface IProblemException { int Status; string Code; string Title; }` in `Platform/Errors`
- Test support: `api.SiteLink` (`FakeSiteLink`: `Reply(operation, location, xml | Func<SiteLinkRequest, HttpResponseMessage>)`, `RequestsFor(location[, operation])`) and `SiteLinkXml.Reply(operation, params (string Table, Dictionary<string,string?> Row)[])` / `SiteLinkXml.Row(params (string, string?)[])`.

- [ ] **Step 1: Add the test fakes**

`tests/ExtraSpace.Api.Tests/TestSupport/SiteLinkXml.cs`:

```csharp
using System.Xml.Linq;

namespace ExtraSpace.Api.Tests.TestSupport;

/// <summary>Synthetic SiteLink replies in the DataSet/diffgram shape (demo spec 02 §4.4). Never real data: the repo is public.</summary>
public static class SiteLinkXml
{
    private static readonly XNamespace Soap = "http://schemas.xmlsoap.org/soap/envelope/";
    private static readonly XNamespace Service = "http://tempuri.org/CallCenterWs/CallCenterWs";
    private static readonly XNamespace Diffgram = "urn:schemas-microsoft-com:xml-diffgram-v1";
    private static readonly XNamespace MsData = "urn:schemas-microsoft-com:xml-msdata";

    /// <summary>A row; a null value leaves the column out, as a DataSet does for NULL.</summary>
    public static Dictionary<string, string?> Row(params (string Column, string? Value)[] columns) =>
        columns.ToDictionary(c => c.Column, c => c.Value);

    public static string Reply(string operation, params (string Table, Dictionary<string, string?> Row)[] rows)
    {
        var dataSet = new XElement("NewDataSet", rows.Select((row, i) => new XElement(row.Table,
            new XAttribute(Diffgram + "id", row.Table + (i + 1)), new XAttribute(MsData + "rowOrder", i),
            row.Row.Where(c => c.Value is not null).Select(c => new XElement(c.Key, c.Value)))));
        return new XDocument(new XElement(Soap + "Envelope", new XAttribute(XNamespace.Xmlns + "soap", Soap),
            new XElement(Soap + "Body",
                new XElement(Service + (operation + "Response"),
                    new XElement(Service + (operation + "Result"),
                        new XElement(XNamespace.Get("http://www.w3.org/2001/XMLSchema") + "schema", new XAttribute("id", "NewDataSet")),
                        new XElement(Diffgram + "diffgram",
                            new XAttribute(XNamespace.Xmlns + "diffgr", Diffgram), new XAttribute(XNamespace.Xmlns + "msdata", MsData),
                            dataSet)))))).ToString();
    }
}
```

`tests/ExtraSpace.Api.Tests/TestSupport/FakeSiteLink.cs`:

```csharp
using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Xml.Linq;

namespace ExtraSpace.Api.Tests.TestSupport;

public sealed record SiteLinkRequest(string Operation, string Location, string SoapAction, IReadOnlyList<string> Names,
    IReadOnlyDictionary<string, string> Fields, string? ApiKey);

/// <summary>
/// Stands in for SiteLink for the whole test run. Replies are keyed by (operation, sLocationCode), so parallel tests that each use
/// their own location code never see each other. An unknown pair answers HTTP 500.
/// </summary>
public sealed class FakeSiteLink : HttpMessageHandler
{
    private readonly ConcurrentDictionary<(string Operation, string Location), Func<SiteLinkRequest, HttpResponseMessage>> _replies = new();
    private readonly ConcurrentQueue<SiteLinkRequest> _requests = new();

    public void Reply(string operation, string location, Func<SiteLinkRequest, HttpResponseMessage> reply) => _replies[(operation, location)] = reply;

    public void Reply(string operation, string location, string xml) => Reply(operation, location, _ => Ok(xml));

    public IReadOnlyList<SiteLinkRequest> RequestsFor(string location, string? operation = null) =>
        _requests.Where(r => r.Location == location && (operation is null || r.Operation == operation)).ToList();

    public static HttpResponseMessage Ok(string xml) => new(HttpStatusCode.OK) { Content = new StringContent(xml, Encoding.UTF8, "text/xml") };

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = XDocument.Parse(await request.Content!.ReadAsStringAsync(cancellationToken));
        var operation = body.Root!.Elements().Single().Elements().Single();   // Envelope / Body / <Operation>
        var names = operation.Elements().Select(e => e.Name.LocalName).ToList();
        var fields = operation.Elements().ToDictionary(e => e.Name.LocalName, e => e.Value);
        var parsed = new SiteLinkRequest(operation.Name.LocalName, fields.GetValueOrDefault("sLocationCode") ?? "",
            request.Headers.GetValues("SOAPAction").Single(), names, fields,
            request.Headers.TryGetValues("sApiKey", out var key) ? key.Single() : null);
        _requests.Enqueue(parsed);
        return _replies.TryGetValue((parsed.Operation, parsed.Location), out var reply)
            ? reply(parsed) : new HttpResponseMessage(HttpStatusCode.InternalServerError);
    }

    // Shared by the whole run: the client factory must never dispose it when a handler expires.
    protected override void Dispose(bool disposing) { }
}
```

In `ApiFactory`:

```csharp
    public FakeSiteLink SiteLink { get; } = new();

    // in ConfigureWebHost, with the other UseSetting lines:
        builder.UseSetting("SiteLink:BaseUrl", "https://sitelink.example.test/CallCenterWs.asmx");
        builder.UseSetting("SiteLink:CorpCode", "TESTCORP");
        builder.UseSetting("SiteLink:CorpUserName", "test-user:::test-key");
        builder.UseSetting("SiteLink:CorpPassword", "test-password");
        builder.UseSetting("SiteLink:CallsPerSecond", "1000");
        builder.UseSetting("SiteLink:RetryDelay", "00:00:00.010");
        // One host serves every test: failures in one test must not open the breaker for the others.
        builder.UseSetting("SiteLink:BreakerMinimumThroughput", "1000000");

    // in ConfigureTestServices:
            services.AddHttpClient<SiteLinkClient>().ConfigurePrimaryHttpMessageHandler(() => SiteLink).SetHandlerLifetime(Timeout.InfiniteTimeSpan);
```

- [ ] **Step 2: Write the failing tests**

`tests/ExtraSpace.Api.Tests/Integrations/SiteLinkReplyTests.cs` (pure, no host):

```csharp
using ExtraSpace.Api.Integrations.SiteLink;
using ExtraSpace.Api.Tests.TestSupport;

namespace ExtraSpace.Api.Tests.Integrations;

public sealed class SiteLinkReplyTests
{
    private static readonly TimeZoneInfo Sg = TimeZoneInfo.FindSystemTimeZoneById("Asia/Singapore");

    [Fact]
    public void Rows_are_grouped_by_table_and_absent_columns_stay_absent()
    {
        var reply = SiteLinkReply.Parse(SiteLinkXml.Reply("Op",
            ("Table", SiteLinkXml.Row(("UnitID", "7"), ("dcWebRate", null), ("dcStdRate", "120.50"))),
            ("Table", SiteLinkXml.Row(("UnitID", "8"), ("dcWebRate", ""))),
            ("Table1", SiteLinkXml.Row(("lngLastTimePolled", "638000000000000001")))));

        reply.Table("Table").Should().HaveCount(2);
        var first = reply.Table("Table")[0];
        first.Has("dcWebRate").Should().BeFalse();
        first.Decimal("dcWebRate").Should().BeNull();
        first.Decimal("dcStdRate").Should().Be(120.50m);
        reply.Table("Table")[1].Decimal("dcWebRate").Should().BeNull();   // blank number = absent
        reply.Table("Table1")[0].Long("lngLastTimePolled").Should().Be(638000000000000001L);
        reply.Table("Missing").Should().BeEmpty();
        reply.RetCode.Should().BeNull();
    }

    [Fact]
    public void The_first_RT_row_gives_the_return_code()
    {
        var reply = SiteLinkReply.Parse(SiteLinkXml.Reply("Op", ("RT", SiteLinkXml.Row(("Ret_Code", "-95"), ("Ret_Msg", "Invalid Tenant ID")))));
        reply.RetCode.Should().Be(-95);
        reply.RetMessage.Should().Be("Invalid Tenant ID");
        SiteLinkReply.Parse(SiteLinkXml.Reply("Op", ("RT", SiteLinkXml.Row(("Ret_Code", "abc"))))).RetCode.Should().BeNull();
    }

    [Fact]
    public void A_reply_without_a_data_set_has_no_tables() =>
        SiteLinkReply.Parse("<Envelope><Body><OpResponse/></Body></Envelope>").Table("Table").Should().BeEmpty();

    [Theory]
    [InlineData("true", true)]
    [InlineData(" True ", true)]
    [InlineData("1", true)]
    [InlineData("false", false)]
    [InlineData("FALSE", false)]
    [InlineData("0", false)]
    public void Booleans_are_read_strictly(string text, bool expected) => SiteLinkValues.ParseBool(text).Should().Be(expected);

    [Fact]
    public void Anything_else_is_not_a_boolean()
    {
        var parse = () => SiteLinkValues.ParseBool("yes");
        parse.Should().Throw<FormatException>();
    }

    [Theory]
    [InlineData("2026-09-30T23:59:59", "2026-09-30T15:59:59Z")]          // site-local, no offset
    [InlineData("2026-09-30T23:59:59+08:00", "2026-09-30T15:59:59Z")]    // an offset is taken as sent
    [InlineData("2026-09-30T15:59:59Z", "2026-09-30T15:59:59Z")]
    [InlineData("2026-09-30T23:59:59.123", "2026-09-30T15:59:59.123Z")]
    public void Dates_are_site_local_unless_they_carry_an_offset(string text, string utc) =>
        SiteLinkValues.ParseDate(text, Sg).Should().Be(DateTime.Parse(utc, null, System.Globalization.DateTimeStyles.AdjustToUniversal | System.Globalization.DateTimeStyles.AssumeUniversal));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("1700-01-01T00:00:00")]
    [InlineData("1799-12-31T23:59:59")]
    public void Blank_and_pre_1800_dates_are_null(string? text) => SiteLinkValues.ParseDate(text, Sg).Should().BeNull();

    [Fact]
    public void A_parsed_date_is_UTC() => SiteLinkValues.ParseDate("2026-09-30T23:59:59", Sg)!.Value.Kind.Should().Be(DateTimeKind.Utc);
}
```

`tests/ExtraSpace.Api.Tests/Integrations/SiteLinkClientTests.cs`:

```csharp
using System.Net;
using ExtraSpace.Api.Integrations.SiteLink;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace ExtraSpace.Api.Tests.Integrations;

public sealed class SiteLinkClientTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private async Task<SiteLinkReply> CallAsync(string operation, string code, SiteLinkCallKind kind, SiteLinkFields? fields = null)
    {
        await using var scope = api.Services.CreateAsyncScope();
        return await scope.ServiceProvider.GetRequiredService<SiteLinkClient>().CallAsync(operation, code, kind, fields ?? new SiteLinkFields(), Ct);
    }

    [Fact]
    public async Task A_call_sends_the_logon_block_first_then_the_fields_in_order()
    {
        var code = SitesTestData.NewCode();
        api.SiteLink.Reply("TestRead", code, SiteLinkXml.Reply("TestRead", ("Table", SiteLinkXml.Row(("sName", "first")))));

        var reply = await CallAsync("TestRead", code, SiteLinkCallKind.Read,
            new SiteLinkFields().Add("lngLastTimePolled", "0").Add("bFlag", true).Add("iCount", 3).Add("dcAmount", 12.50m));

        reply.Table("Table").Single().Text("sName").Should().Be("first");
        var request = api.SiteLink.RequestsFor(code).Single();
        request.Names.Should().Equal("sCorpCode", "sLocationCode", "sCorpUserName", "sCorpPassword", "lngLastTimePolled", "bFlag", "iCount", "dcAmount");
        request.Fields["sLocationCode"].Should().Be(code);
        request.Fields["sCorpUserName"].Should().Be("test-user:::test-key");
        request.Fields["bFlag"].Should().Be("true");
        request.Fields["dcAmount"].Should().Be("12.50");
        request.SoapAction.Should().Be("\"http://tempuri.org/CallCenterWs/CallCenterWs/TestRead\"");
    }

    [Fact]
    public async Task A_negative_return_code_is_a_refusal_and_the_call_is_logged_without_bodies()
    {
        var code = SitesTestData.NewCode();
        api.SiteLink.Reply("TestRefused", code, SiteLinkXml.Reply("TestRefused", ("RT", SiteLinkXml.Row(("Ret_Code", "-25"), ("Ret_Msg", "Invalid UnitID")))));

        var reply = await CallAsync("TestRefused", code, SiteLinkCallKind.Read);
        var refuse = () => reply.ThrowIfRefused("TestRefused");

        var error = refuse.Should().Throw<SiteLinkException>().Which;
        error.ReturnCode.Should().Be(-25);
        error.SiteLinkMessage.Should().Be("Invalid UnitID");
        var line = await api.Logs.WaitForAsync(l => l.Contains("TestRefused") && l.Contains(code));
        line.Should().Contain("refused").And.Contain("-25");
        line.Should().NotContain("test-password").And.NotContain("Invalid UnitID");
    }

    [Fact]
    public async Task A_read_is_retried_on_a_server_error_but_a_write_is_not()
    {
        const string code = "LSETUP";   // the only site a write may reach outside production
        var reads = 0;
        api.SiteLink.Reply("TestRetryRead", code, _ => Interlocked.Increment(ref reads) == 1
            ? new HttpResponseMessage(HttpStatusCode.InternalServerError)
            : FakeSiteLink.Ok(SiteLinkXml.Reply("TestRetryRead")));
        api.SiteLink.Reply("TestRetryWrite", code, _ => new HttpResponseMessage(HttpStatusCode.InternalServerError));

        await CallAsync("TestRetryRead", code, SiteLinkCallKind.Read);
        var write = () => CallAsync("TestRetryWrite", code, SiteLinkCallKind.Write);

        (await write.Should().ThrowAsync<SiteLinkUnavailableException>()).Which.Status.Should().Be(503);
        api.SiteLink.RequestsFor(code, "TestRetryRead").Should().HaveCount(2);
        api.SiteLink.RequestsFor(code, "TestRetryWrite").Should().HaveCount(1);
    }

    [Fact]
    public async Task A_write_outside_the_allow_list_never_leaves_the_process()
    {
        var code = SitesTestData.NewCode();
        api.SiteLink.Reply("TestBlockedWrite", code, SiteLinkXml.Reply("TestBlockedWrite"));

        var write = () => CallAsync("TestBlockedWrite", code, SiteLinkCallKind.Write);

        (await write.Should().ThrowAsync<InvalidOperationException>()).WithMessage("*WriteAllowList*");
        api.SiteLink.RequestsFor(code).Should().BeEmpty();
    }

    [Fact]
    public async Task Each_call_is_counted_for_the_month()
    {
        var operation = "TestCount" + Guid.NewGuid().ToString("N")[..8];
        var code = SitesTestData.NewCode();
        api.SiteLink.Reply(operation, code, SiteLinkXml.Reply(operation));

        for (var i = 0; i < 3; i++) await CallAsync(operation, code, SiteLinkCallKind.Read);

        long calls = 0;
        await api.WithDbAsync(async db => calls = await db.Set<SiteLinkCallMonth>().Where(m => m.Operation == operation).SumAsync(m => m.Calls, Ct));
        calls.Should().Be(3);
    }

    [Theory]
    [InlineData(100, 1, 100, true)]
    [InlineData(101, 2, 100, true)]
    [InlineData(102, 1, 100, false)]
    [InlineData(99, 1, 100, false)]
    [InlineData(500, 1, 0, false)]
    public void The_monthly_alarm_fires_only_when_the_total_crosses_it(long total, int added, long alarm, bool fires) =>
        SiteLinkCallCounter.CrossedAlarm(total, added, alarm).Should().Be(fires);

    [Fact]
    public async Task Without_credentials_a_call_is_unavailable_and_sends_nothing()
    {
        await using var host = api.WithWebHostBuilder(b =>
        {
            b.UseSetting("App:Role", "Api");
            b.UseSetting("SiteLink:CorpPassword", "");
        });
        var code = SitesTestData.NewCode();
        await using var scope = host.Services.CreateAsyncScope();

        var call = () => scope.ServiceProvider.GetRequiredService<SiteLinkClient>().CallAsync("TestRead", code, SiteLinkCallKind.Read, new SiteLinkFields(), Ct);

        await call.Should().ThrowAsync<SiteLinkUnavailableException>();
        api.SiteLink.RequestsFor(code).Should().BeEmpty();
    }

    [Fact]
    public void Writing_to_every_site_is_refused_outside_production()
    {
        using var host = api.WithWebHostBuilder(b =>
        {
            b.UseSetting("App:Role", "Api");
            b.UseSetting("SiteLink:AllowWritesToAllSites", "true");
        });
        // Assert the start-up refusal the same way DataProtectionTests does (read it first); the message names the setting.
        var start = () => host.Services;
        start.Should().Throw<Exception>().WithMessage("*AllowWritesToAllSites*");
    }
}
```

`tests/ExtraSpace.Api.Tests/Integrations/SiteLinkAttemptHandlerTests.cs`:

```csharp
using System.Diagnostics;
using System.Net;
using ExtraSpace.Api.Integrations.SiteLink;
using Polly;

namespace ExtraSpace.Api.Tests.Integrations;

public sealed class SiteLinkAttemptHandlerTests
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private sealed class Ok : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK));
    }

    private static (HttpRequestMessage Request, ResilienceContext Context) Request(SiteLinkCallKind kind)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, "https://sitelink.example.test/");
        var context = ResilienceContextPool.Shared.Get();
        context.Properties.Set(SiteLinkClient.KindKey, kind);
        request.SetResilienceContext(context);
        return (request, context);
    }

    [Fact]
    public async Task Reads_wait_for_the_limit_and_writes_do_not()
    {
        using var limiter = new SiteLinkRateLimiter(2);
        using var invoker = new HttpMessageInvoker(new SiteLinkAttemptHandler(limiter) { InnerHandler = new Ok() });

        var clock = Stopwatch.StartNew();
        for (var i = 0; i < 5; i++) await invoker.SendAsync(Request(SiteLinkCallKind.Write).Request, Ct);
        clock.Elapsed.Should().BeLessThan(TimeSpan.FromMilliseconds(500));

        clock.Restart();
        for (var i = 0; i < 5; i++) await invoker.SendAsync(Request(SiteLinkCallKind.Read).Request, Ct);
        clock.Elapsed.Should().BeGreaterThan(TimeSpan.FromMilliseconds(900));   // 2 at once, 2 after 1 s, 1 after 2 s
    }

    [Fact]
    public async Task Each_attempt_is_counted_on_the_context()
    {
        using var limiter = new SiteLinkRateLimiter(100);
        using var invoker = new HttpMessageInvoker(new SiteLinkAttemptHandler(limiter) { InnerHandler = new Ok() });
        var (request, context) = Request(SiteLinkCallKind.Read);

        await invoker.SendAsync(request, Ct);
        await invoker.SendAsync(request, Ct);

        context.Properties.GetValue(SiteLinkClient.AttemptsKey, 0).Should().Be(2);
    }
}
```

Add to `tests/ExtraSpace.Api.Tests/Platform/ExceptionClassifyTests.cs`:

```csharp
    [Fact]
    public void A_problem_exception_keeps_its_status_and_code()
    {
        AppExceptionHandler.Classify(new SiteLinkException("UnitsInformation_v3", -1, "x")).Should()
            .Be((502, "SITELINK_ERROR", "The storage system refused the request. Try again later or contact the facility."));
        AppExceptionHandler.Classify(new SiteLinkUnavailableException("UnitsInformation_v3", "HTTP 503")).Status.Should().Be(503);
    }
```

- [ ] **Step 3: Run and watch them fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*SiteLink*"`
Expected: compile errors.

- [ ] **Step 4: Implement**

Add the package `Microsoft.Extensions.Http.Resilience` `10.10.0` to `Directory.Packages.props` (group "Api"), and a `<PackageReference>` without a version to `ExtraSpace.Api.csproj`. Run `dotnet restore`.

`Platform/Errors/IProblemException.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Errors;

/// <summary>An exception from an outside system that knows its own HTTP answer (S1: SiteLink; S1-4: Stripe).</summary>
public interface IProblemException
{
    int Status { get; }
    string Code { get; }
    string Title { get; }
}
```

In `AppExceptionHandler.Classify`, add this arm right after `AppException app => …`:

```csharp
        IProblemException problem => (problem.Status, problem.Code, problem.Title),
```

`Integrations/SiteLink/SiteLinkExceptions.cs`:

```csharp
using ExtraSpace.Api.Platform.Errors;

namespace ExtraSpace.Api.Integrations.SiteLink;

/// <summary>SiteLink answered with a refusal. What a code means depends on the operation (API PDF), so callers map their own codes first.</summary>
internal sealed class SiteLinkException(string operation, int returnCode, string? siteLinkMessage)
    : Exception($"SiteLink {operation} refused the call with code {returnCode}."), IProblemException
{
    public string Operation { get; } = operation;
    public int ReturnCode { get; } = returnCode;
    /// <summary>SiteLink's own text: for staff screens and outbox errors, never for the app or the log.</summary>
    public string? SiteLinkMessage { get; } = siteLinkMessage;
    public int Status => 502;
    public string Code => "SITELINK_ERROR";
    public string Title => "The storage system refused the request. Try again later or contact the facility.";
}

/// <summary>SiteLink could not be reached, timed out, failed with HTTP 5xx, the breaker is open, or we have no login.</summary>
internal sealed class SiteLinkUnavailableException(string operation, string reason, Exception? inner = null)
    : Exception($"SiteLink {operation} is unavailable: {reason}.", inner), IProblemException
{
    public int Status => 503;
    public string Code => "SITELINK_UNAVAILABLE";
    public string Title => "The storage system cannot be reached right now. Try again in a few minutes.";
}
```

`Integrations/SiteLink/SiteLinkOptions.cs`:

```csharp
namespace ExtraSpace.Api.Integrations.SiteLink;

internal sealed class SiteLinkOptions
{
    public const string Section = "SiteLink";

    public string BaseUrl { get; set; } = "";
    public string? CorpCode { get; set; }
    /// <summary>Must be <c>user:::licence key</c>; a bare user name fails with -98 / -89.</summary>
    public string? CorpUserName { get; set; }
    public string? CorpPassword { get; set; }
    public string? ApiKey { get; set; }
    /// <summary>Location codes a write may reach (S1 spec §6.2). Default <c>LSETUP</c> (appsettings.json).</summary>
    public string[] WriteAllowList { get; set; } = [];
    /// <summary>Production only: writes may reach every site. Other environments refuse to start with it.</summary>
    public bool AllowWritesToAllSites { get; set; }
    public int CallsPerSecond { get; set; } = 2;
    public TimeSpan RetryDelay { get; set; } = TimeSpan.FromSeconds(1);
    public int BreakerMinimumThroughput { get; set; } = 5;
    /// <summary>Monthly total that raises one Error line; 0 = off (SiteLink's limit is unknown, spec open item 6).</summary>
    public long MonthlyCallAlarm { get; set; }

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(CorpCode) && !string.IsNullOrWhiteSpace(CorpUserName) && !string.IsNullOrWhiteSpace(CorpPassword);

    public bool MayWriteTo(string locationCode) =>
        AllowWritesToAllSites || WriteAllowList.Contains(locationCode, StringComparer.OrdinalIgnoreCase);
}
```

`appsettings.json`, a new section:

```json
  "SiteLink": {
    "BaseUrl": "https://api.smdservers.net/CCWs_3.5/CallCenterWs.asmx",
    "WriteAllowList": [ "LSETUP" ],
    "AllowWritesToAllSites": false,
    "CallsPerSecond": 2,
    "MonthlyCallAlarm": 0
  },
```

`Integrations/SiteLink/SiteLinkFields.cs`:

```csharp
using System.Collections;
using System.Globalization;

namespace ExtraSpace.Api.Integrations.SiteLink;

/// <summary>Request elements in WSDL sequence order (the order they are added). Values are written in the invariant culture.</summary>
internal sealed class SiteLinkFields : IEnumerable<KeyValuePair<string, string>>
{
    private readonly List<KeyValuePair<string, string>> _items = [];

    public SiteLinkFields Add(string name, string? value)
    {
        _items.Add(new(name, value ?? ""));
        return this;
    }

    public SiteLinkFields Add(string name, int value) => Add(name, value.ToString(CultureInfo.InvariantCulture));

    public SiteLinkFields Add(string name, decimal value) => Add(name, value.ToString(CultureInfo.InvariantCulture));

    public SiteLinkFields Add(string name, bool value) => Add(name, value ? "true" : "false");

    public IEnumerator<KeyValuePair<string, string>> GetEnumerator() => _items.GetEnumerator();

    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}
```

`Integrations/SiteLink/SoapEnvelope.cs`:

```csharp
using System.Xml.Linq;

namespace ExtraSpace.Api.Integrations.SiteLink;

/// <summary>SOAP 1.1, document/literal wrapped (demo spec 02 §4.2).</summary>
internal static class SoapEnvelope
{
    public const string Namespace = "http://tempuri.org/CallCenterWs/CallCenterWs";
    private static readonly XNamespace Soap = "http://schemas.xmlsoap.org/soap/envelope/";

    public static string Build(string operation, IEnumerable<KeyValuePair<string, string>> elements)
    {
        XNamespace service = Namespace;
        return new XElement(Soap + "Envelope", new XAttribute(XNamespace.Xmlns + "soap", Soap),
                new XElement(Soap + "Body",
                    new XElement(service + operation, elements.Select(e => new XElement(service + e.Key, e.Value)))))
            .ToString(SaveOptions.DisableFormatting);
    }
}
```

`Integrations/SiteLink/SiteLinkValues.cs`:

```csharp
using System.Globalization;
using System.Text.RegularExpressions;

namespace ExtraSpace.Api.Integrations.SiteLink;

internal static partial class SiteLinkValues
{
    /// <summary>SiteLink's null date: any year before 1800 (API PDF, wire rules).</summary>
    public const string NullDate = "1700-01-01T00:00:00";

    /// <summary>Strict: "true"/"1" and "false"/"0", any case. The demo's truthy-string bug made every flag true.</summary>
    public static bool ParseBool(string value) => value.Trim().ToLowerInvariant() switch
    {
        "true" or "1" => true,
        "false" or "0" => false,
        _ => throw new FormatException($"Not a SiteLink boolean: '{value}'."),
    };

    /// <summary>
    /// SiteLink sends site-local times without an offset; a value with an offset is taken as sent. Returns UTC, or null for a
    /// blank value or a year before 1800.
    /// </summary>
    public static DateTime? ParseDate(string? value, TimeZoneInfo zone)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var text = value.Trim();
        if (HasOffset().IsMatch(text))
        {
            var instant = DateTimeOffset.Parse(text, CultureInfo.InvariantCulture);
            return instant.Year < 1800 ? null : instant.UtcDateTime;
        }
        var local = DateTime.Parse(text, CultureInfo.InvariantCulture, DateTimeStyles.None);
        return local.Year < 1800 ? null : TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(local, DateTimeKind.Unspecified), zone);
    }

    [GeneratedRegex(@"(Z|[+-]\d{2}:\d{2})$")]
    private static partial Regex HasOffset();
}
```

`Integrations/SiteLink/SiteLinkReply.cs`:

```csharp
using System.Globalization;
using System.Xml.Linq;

namespace ExtraSpace.Api.Integrations.SiteLink;

/// <summary>A DataSet reply: tables of rows of string columns. A NULL column is absent from its row (demo spec 02 §4.4).</summary>
internal sealed class SiteLinkReply(Dictionary<string, List<SiteLinkRow>> tables)
{
    public IReadOnlyList<SiteLinkRow> Table(string name) => tables.TryGetValue(name, out var rows) ? rows : [];

    /// <summary>The first RT row's Ret_Code; null without an RT table or when it is not a number.</summary>
    public int? RetCode =>
        Table("RT").FirstOrDefault()?.Text("Ret_Code") is { } text
        && int.TryParse(text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var code) ? code : null;

    public string? RetMessage => Table("RT").FirstOrDefault()?.Text("Ret_Msg");

    /// <summary>Any negative Ret_Code becomes <see cref="SiteLinkException"/>; an operation with codes of its own maps them before calling this.</summary>
    public SiteLinkReply ThrowIfRefused(string operation) =>
        RetCode is { } code && code < 0 ? throw new SiteLinkException(operation, code, RetMessage) : this;

    public static SiteLinkReply Parse(string xml)
    {
        var dataSet = XDocument.Parse(xml).Descendants().FirstOrDefault(e => e.Name.LocalName == "NewDataSet");
        var tables = new Dictionary<string, List<SiteLinkRow>>(StringComparer.Ordinal);
        foreach (var row in dataSet?.Elements() ?? [])
        {
            if (!tables.TryGetValue(row.Name.LocalName, out var rows)) tables[row.Name.LocalName] = rows = [];
            rows.Add(new SiteLinkRow(row.Elements()
                .GroupBy(column => column.Name.LocalName, StringComparer.Ordinal)
                .ToDictionary(g => g.Key, g => g.First().Value, StringComparer.Ordinal)));
        }
        return new SiteLinkReply(tables);
    }
}

internal sealed class SiteLinkRow(IReadOnlyDictionary<string, string> columns)
{
    public bool Has(string column) => columns.ContainsKey(column);

    public string? Text(string column) => columns.GetValueOrDefault(column);

    public int? Int(string column) => Number(column) is { } s ? int.Parse(s, NumberStyles.Integer, CultureInfo.InvariantCulture) : null;

    public long? Long(string column) => Number(column) is { } s ? long.Parse(s, NumberStyles.Integer, CultureInfo.InvariantCulture) : null;

    public decimal? Decimal(string column) =>
        Number(column) is { } s ? decimal.Parse(s, NumberStyles.Number | NumberStyles.AllowExponent, CultureInfo.InvariantCulture) : null;

    public bool? Bool(string column) => Number(column) is { } s ? SiteLinkValues.ParseBool(s) : null;

    public DateTime? UtcDate(string column, TimeZoneInfo zone) => SiteLinkValues.ParseDate(Text(column), zone);

    // A blank number or flag counts as absent.
    private string? Number(string column) => Text(column) is { } s && !string.IsNullOrWhiteSpace(s) ? s.Trim() : null;
}
```

`Integrations/SiteLink/SiteLinkAttemptHandler.cs`:

```csharp
using System.Threading.RateLimiting;
using Polly;

namespace ExtraSpace.Api.Integrations.SiteLink;

/// <summary>The per-instance read budget (S1 spec §6.6): a token bucket of <c>CallsPerSecond</c>.</summary>
internal sealed class SiteLinkRateLimiter(int callsPerSecond) : IDisposable
{
    public RateLimiter Limiter { get; } = new TokenBucketRateLimiter(new TokenBucketRateLimiterOptions
    {
        TokenLimit = callsPerSecond,
        TokensPerPeriod = callsPerSecond,
        ReplenishmentPeriod = TimeSpan.FromSeconds(1),
        QueueLimit = 500,
        QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
        AutoReplenishment = true,
    });

    public void Dispose() => Limiter.Dispose();
}

/// <summary>Runs once per HTTP attempt, inside the retry: reads wait for the rate limit, writes never wait, and every attempt is counted.</summary>
internal sealed class SiteLinkAttemptHandler(SiteLinkRateLimiter limiter) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var context = request.GetResilienceContext();
        if (context?.Properties.GetValue(SiteLinkClient.KindKey, SiteLinkCallKind.Read) != SiteLinkCallKind.Write)
        {
            using var lease = await limiter.Limiter.AcquireAsync(1, cancellationToken);
            if (!lease.IsAcquired) throw new SiteLinkUnavailableException("(queued call)", "the rate-limit queue is full");
            return await SendCountedAsync(request, context, cancellationToken);
        }
        return await SendCountedAsync(request, context, cancellationToken);
    }

    private Task<HttpResponseMessage> SendCountedAsync(HttpRequestMessage request, ResilienceContext? context, CancellationToken cancellationToken)
    {
        context?.Properties.Set(SiteLinkClient.AttemptsKey, context.Properties.GetValue(SiteLinkClient.AttemptsKey, 0) + 1);
        return base.SendAsync(request, cancellationToken);
    }
}
```

`Integrations/SiteLink/SiteLinkCallCounter.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Microsoft.Extensions.Options;

namespace ExtraSpace.Api.Integrations.SiteLink;

/// <summary>Calls per UTC month and operation; the row with operation <c>*</c> is the month's total (S1 spec §6.4).</summary>
internal sealed class SiteLinkCallMonth
{
    public DateOnly Month { get; init; }
    public required string Operation { get; init; }
    public long Calls { get; set; }
}

internal sealed class SiteLinkCallMonthConfiguration : IEntityTypeConfiguration<SiteLinkCallMonth>
{
    public void Configure(EntityTypeBuilder<SiteLinkCallMonth> builder)
    {
        builder.ToTable("sitelink_call_month");
        builder.HasKey(m => new { m.Month, m.Operation });
        builder.Property(m => m.Operation).HasMaxLength(100);
    }
}

internal sealed partial class SiteLinkCallCounter(
    IServiceScopeFactory scopes, IOptionsMonitor<SiteLinkOptions> options, TimeProvider time, ILogger<SiteLinkCallCounter> logger)
{
    public const string Total = "*";

    /// <summary>Adds the attempts to this month's rows. Its own scope and connection, so a caller's rollback never undoes it; never throws.</summary>
    public async Task CountAsync(string operation, int calls)
    {
        if (calls <= 0) return;
        try
        {
            var now = time.GetUtcNow();
            var month = new DateOnly(now.Year, now.Month, 1);
            long added = calls;
            await using var scope = scopes.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var totals = await db.Database.SqlQuery<long>($"""
                INSERT INTO sitelink_call_month AS m (month, operation, calls)
                VALUES ({month}, {operation}, {added}), ({month}, {Total}, {added})
                ON CONFLICT (month, operation) DO UPDATE SET calls = m.calls + excluded.calls
                RETURNING CASE WHEN m.operation = {Total} THEN m.calls ELSE 0 END AS "Value"
                """).ToListAsync();
            var total = totals.Max();
            var alarm = options.CurrentValue.MonthlyCallAlarm;
            if (CrossedAlarm(total, calls, alarm)) LogAlarm(logger, total, alarm);
        }
        catch (Exception exception)
        {
            LogCountFailed(logger, exception, operation);
        }
    }

    /// <summary>True only for the call that moves the total from below the alarm to at or above it: one line per month.</summary>
    internal static bool CrossedAlarm(long total, int added, long alarm) => alarm > 0 && total >= alarm && total - added < alarm;

    // Task 8's alarm matches this template text exactly.
    [LoggerMessage(Level = LogLevel.Error, Message = "SiteLink calls this month reached {total}, past the alarm level {alarm}")]
    private static partial void LogAlarm(ILogger logger, long total, long alarm);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Could not count a SiteLink call to {operation}")]
    private static partial void LogCountFailed(ILogger logger, Exception exception, string operation);
}
```

`Integrations/SiteLink/SiteLinkClient.cs`:

```csharp
using System.Text;
using Microsoft.Extensions.Options;
using Polly;
using Polly.CircuitBreaker;
using Polly.Timeout;

namespace ExtraSpace.Api.Integrations.SiteLink;

internal enum SiteLinkCallKind { Read, Write }

/// <summary>SiteLink CCWs 3.5 over raw SOAP (S1 spec §6.1). One method per operation lives in the partial files.</summary>
internal sealed partial class SiteLinkClient(
    HttpClient http, IOptionsMonitor<SiteLinkOptions> options, SiteLinkCallCounter counter, TimeProvider time, ILogger<SiteLinkClient> logger)
{
    internal static readonly ResiliencePropertyKey<SiteLinkCallKind> KindKey = new("sitelink.kind");
    internal static readonly ResiliencePropertyKey<int> AttemptsKey = new("sitelink.attempts");

    /// <summary>
    /// One call. The logon block goes first, then <paramref name="fields"/> in their order (the WSDL sequence). A write to a site
    /// outside <c>SiteLink:WriteAllowList</c> throws before anything is sent. Reads are retried; writes never are.
    /// </summary>
    internal async Task<SiteLinkReply> CallAsync(string operation, string locationCode, SiteLinkCallKind kind, SiteLinkFields fields,
        CancellationToken cancellationToken)
    {
        var settings = options.CurrentValue;
        if (kind == SiteLinkCallKind.Write && !settings.MayWriteTo(locationCode))
            throw new InvalidOperationException($"SiteLink write {operation} to {locationCode} is blocked: the site is not in SiteLink:WriteAllowList.");
        if (!settings.IsConfigured)
        {
            LogNotConfigured(logger, operation);
            throw new SiteLinkUnavailableException(operation, "SiteLink is not configured");
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, settings.BaseUrl)
        {
            Content = new StringContent(SoapEnvelope.Build(operation, Logon(settings, locationCode).Concat(fields)), Encoding.UTF8, "text/xml"),
        };
        request.Headers.TryAddWithoutValidation("SOAPAction", $"\"{SoapEnvelope.Namespace}/{operation}\"");
        if (!string.IsNullOrEmpty(settings.ApiKey)) request.Headers.TryAddWithoutValidation("sApiKey", settings.ApiKey);
        var context = ResilienceContextPool.Shared.Get(cancellationToken);
        context.Properties.Set(KindKey, kind);
        request.SetResilienceContext(context);

        var started = time.GetTimestamp();
        var outcome = "unavailable";
        int? retCode = null;
        try
        {
            using var response = await http.SendAsync(request, cancellationToken);
            if (!response.IsSuccessStatusCode) throw new SiteLinkUnavailableException(operation, $"HTTP {(int)response.StatusCode}");
            var reply = SiteLinkReply.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
            retCode = reply.RetCode;
            outcome = retCode < 0 ? "refused" : "ok";
            return reply;
        }
        catch (Exception exception) when (exception is HttpRequestException or TimeoutRejectedException or BrokenCircuitException
                                          || (exception is TaskCanceledException && !cancellationToken.IsCancellationRequested))
        {
            throw new SiteLinkUnavailableException(operation, exception.GetType().Name, exception);
        }
        finally
        {
            var attempts = context.Properties.GetValue(AttemptsKey, 0);
            ResilienceContextPool.Shared.Return(context);
            var elapsedMs = (long)time.GetElapsedTime(started).TotalMilliseconds;
            // Lower-case values, as SES logs them: the outside-call alarm counts every outcome that is not "ok".
            if (outcome == "ok") LogCall(logger, "sitelink", operation, locationCode, outcome, elapsedMs, retCode, attempts);
            else LogCallFailed(logger, "sitelink", operation, locationCode, outcome, elapsedMs, retCode, attempts);
            await counter.CountAsync(operation, attempts);
        }
    }

    private static KeyValuePair<string, string>[] Logon(SiteLinkOptions settings, string locationCode) =>
    [
        new("sCorpCode", settings.CorpCode!),
        new("sLocationCode", locationCode),
        new("sCorpUserName", settings.CorpUserName!),
        new("sCorpPassword", settings.CorpPassword!),
    ];

    // Same template as every outside call (S0 spec §4.4), plus the site and SiteLink's code. Never a body or the logon block.
    [LoggerMessage(Level = LogLevel.Information, Message = "Outside call {integration} {operation} for {siteCode}: {outcome} in {elapsedMs} ms (retCode {retCode}, attempts {attempt})")]
    private static partial void LogCall(ILogger logger, string integration, string operation, string siteCode, string outcome, long elapsedMs, int? retCode, int attempt);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Outside call {integration} {operation} for {siteCode}: {outcome} in {elapsedMs} ms (retCode {retCode}, attempts {attempt})")]
    private static partial void LogCallFailed(ILogger logger, string integration, string operation, string siteCode, string outcome, long elapsedMs, int? retCode, int attempt);

    [LoggerMessage(Level = LogLevel.Warning, Message = "SiteLink {operation} not sent: SiteLink:CorpCode, CorpUserName or CorpPassword is not set")]
    private static partial void LogNotConfigured(ILogger logger, string operation);
}
```

`Integrations/SiteLink/SiteLinkSetup.cs`:

```csharp
using Microsoft.Extensions.Http.Resilience;
using Microsoft.Extensions.Options;
using Polly;

namespace ExtraSpace.Api.Integrations.SiteLink;

internal static class SiteLinkSetup
{
    public static IServiceCollection AddSiteLink(this IServiceCollection services, IConfiguration configuration, IHostEnvironment environment)
    {
        services.AddOptions<SiteLinkOptions>().Bind(configuration.GetSection(SiteLinkOptions.Section))
            .Validate(o => Uri.TryCreate(o.BaseUrl, UriKind.Absolute, out var url) && url.Scheme == Uri.UriSchemeHttps,
                "SiteLink:BaseUrl must be an https URL.")
            .Validate(o => string.IsNullOrEmpty(o.CorpUserName) || o.CorpUserName.Contains(":::", StringComparison.Ordinal),
                "SiteLink:CorpUserName must be <user>:::<licence key>.")
            .Validate(o => o.CallsPerSecond is > 0 and <= 1000, "SiteLink:CallsPerSecond must be between 1 and 1000.")
            .Validate(o => environment.IsProduction() || !o.AllowWritesToAllSites,
                "SiteLink:AllowWritesToAllSites is for production only; other environments write only to SiteLink:WriteAllowList.")
            .ValidateOnStart();

        services.AddSingleton<SiteLinkCallCounter>();
        services.AddSingleton(sp => new SiteLinkRateLimiter(sp.GetRequiredService<IOptions<SiteLinkOptions>>().Value.CallsPerSecond));
        services.AddTransient<SiteLinkAttemptHandler>();
        // The pipeline owns every timeout (S1 spec §6.3): 60 s total, 30 s per attempt, 2 jittered retries for reads, one breaker.
        services.AddHttpClient<SiteLinkClient>(client => client.Timeout = Timeout.InfiniteTimeSpan)
            .AddResilienceHandler("sitelink", (builder, context) =>
            {
                var settings = context.ServiceProvider.GetRequiredService<IOptions<SiteLinkOptions>>().Value;
                builder
                    .AddTimeout(TimeSpan.FromSeconds(60))
                    .AddRetry(new HttpRetryStrategyOptions
                    {
                        MaxRetryAttempts = 2,
                        Delay = settings.RetryDelay,
                        BackoffType = DelayBackoffType.Exponential,
                        UseJitter = true,
                        // A write that timed out may have happened in SiteLink: never send it again (S1 spec §6.3).
                        ShouldHandle = args => ValueTask.FromResult(
                            args.Context.Properties.GetValue(SiteLinkClient.KindKey, SiteLinkCallKind.Write) == SiteLinkCallKind.Read
                            && HttpClientResiliencePredicates.IsTransient(args.Outcome)),
                    })
                    .AddCircuitBreaker(new HttpCircuitBreakerStrategyOptions
                    {
                        FailureRatio = 0.5,
                        MinimumThroughput = settings.BreakerMinimumThroughput,
                        SamplingDuration = TimeSpan.FromSeconds(60),
                        BreakDuration = TimeSpan.FromSeconds(30),
                    })
                    .AddTimeout(TimeSpan.FromSeconds(30));
            })
            .AddHttpMessageHandler<SiteLinkAttemptHandler>();   // after the resilience handler = inside it = once per attempt
        return services;
    }
}
```

> If `HttpClientResiliencePredicates.IsTransient(Outcome<HttpResponseMessage>)` is not public in the restored version, keep the same rule with the strategy's default predicate: `new HttpRetryStrategyOptions().ShouldHandle(args)` behind the read check. Say which you used in the report.

`Program.cs`: `builder.Services.AddSiteLink(builder.Configuration, builder.Environment);` after `AddEmail`.

- [ ] **Step 5: Add the migration**

```bash
dotnet ef migrations add SiteLinkCallMonth --project src/ExtraSpace.Api
```

Strip the BOM. The table is `sitelink_call_month (month date, operation varchar(100), calls bigint, PK (month, operation))`.

- [ ] **Step 6: Run the tests and watch them pass**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*SiteLink*"`, then `--filter-class "*ExceptionClassifyTests"` and `--filter-class "*ArchitectureTests"`.
Expected: all pass. The retry test takes well under a second (`RetryDelay` = 10 ms in tests).

- [ ] **Step 7: Stop and report** (no commit). Name the `IsTransient` form you used, and paste the call log line from one test run so the reviewer can see that it has no body and no password.

---

### Task 5: SiteLink unit operations and the row mapping

**Files:**
- Create: `src/ExtraSpace.Api/Integrations/SiteLink/SiteLinkUnit.cs`, `SiteLinkClient.Units.cs`
- Test: `tests/ExtraSpace.Api.Tests/Integrations/SiteLinkUnitTests.cs`

**Interfaces:**
- Consumes: `SiteLinkClient.CallAsync`, `SiteLinkReply`, `SiteLinkRow` (Task 4).
- Produces:
  - `SiteLinkUnit` (record; a null property = the column was absent; `AreaSqft` = width × length)
  - `SiteLinkUnitsPage(IReadOnlyList<SiteLinkUnit> Units, long? NextTicks)`
  - `SiteLinkClient.UnitsInformationAsync(string locationCode, long? sinceTicks, bool includeExcludedFromWebsite, TimeZoneInfo zone, CancellationToken) → Task<SiteLinkUnitsPage>`
  - `SiteLinkClient.CurrencyDecimalsAsync(string locationCode, CancellationToken) → Task<int?>`

- [ ] **Step 1: Write the failing tests**

`tests/ExtraSpace.Api.Tests/Integrations/SiteLinkUnitTests.cs`:

```csharp
using ExtraSpace.Api.Integrations.SiteLink;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.Extensions.DependencyInjection;

namespace ExtraSpace.Api.Tests.Integrations;

public sealed class SiteLinkUnitTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;
    private static readonly TimeZoneInfo Sg = TimeZoneInfo.FindSystemTimeZoneById("Asia/Singapore");

    private static SiteLinkUnit Map(params (string, string?)[] columns) =>
        SiteLinkUnit.From(SiteLinkReply.Parse(SiteLinkXml.Reply("Op", ("Table", SiteLinkXml.Row(columns)))).Table("Table")[0], Sg);

    [Fact]
    public void A_full_row_maps_every_field()
    {
        var unit = Map(("UnitID", "101"), ("UnitTypeID", "7"), ("sUnitName", " A101 "), ("sTypeName", "Walk In"),
            ("dcWidth", "9"), ("dcLength", "9"), ("bClimate", "true"), ("bInside", "true"), ("bPower", "false"), ("bAlarm", "false"),
            ("iADA", "1"), ("bMobile", "false"), ("bRented", "false"), ("bRentable", "true"), ("bWaitingListReserved", "false"),
            ("iFloor", "2"), ("sUnitDesc", "near lift"), ("dcStdRate", "120.00"), ("dcWebRate", "100.00"), ("dcBoardRate", "130"),
            ("dcPushRate", "95.5"), ("dcPreferredRate", "90"), ("dcStdSecDep", "50"), ("dDeleted", null));

        unit.UnitId.Should().Be(101);
        unit.UnitTypeId.Should().Be(7);
        unit.UnitName.Should().Be("A101");
        unit.AreaSqft.Should().Be(81m);   // C8
        unit.Climate.Should().BeTrue();
        unit.Ada.Should().BeTrue();
        unit.Floor.Should().Be(2);
        unit.WebRate.Should().Be(100.00m);
        unit.StandardSecurityDeposit.Should().Be(50m);
        unit.DeletedAt.Should().BeNull();
    }

    [Fact]
    public void Absent_and_false_values_map_strictly()
    {
        var unit = Map(("UnitID", "102"), ("sUnitName", "B1"), ("bRented", "false"), ("dcWebRate", ""), ("dDeleted", "1700-01-01T00:00:00"));

        unit.Rented.Should().BeFalse();                // C9
        unit.Rentable.Should().BeTrue();               // C10: no bRentable column
        unit.WebRate.Should().BeNull();                // blank = absent: the refresh keeps the stored rate
        unit.StandardRate.Should().BeNull();
        unit.Description.Should().BeNull();
        unit.Floor.Should().BeNull();
        unit.DeletedAt.Should().BeNull();              // SiteLink's null date
        unit.Width.Should().Be(0m);
    }

    [Fact]
    public void A_deleted_date_is_site_local() =>
        Map(("UnitID", "103"), ("sUnitName", "C1"), ("dDeleted", "2026-10-01T10:00:00")).DeletedAt
            .Should().Be(new DateTime(2026, 10, 1, 2, 0, 0, DateTimeKind.Utc));

    [Theory]
    [InlineData(null, "A1")]
    [InlineData("5", null)]
    [InlineData("5", " ")]
    public void A_row_without_an_id_or_a_name_is_unreadable(string? unitId, string? name)
    {
        var map = () => Map(("UnitID", unitId), ("sUnitName", name));
        map.Should().Throw<FormatException>();
    }

    [Fact]
    public async Task UnitsInformation_sends_the_cursor_and_reads_the_next_one()
    {
        var code = SitesTestData.NewCode();
        api.SiteLink.Reply("UnitsInformation_v3", code, SiteLinkXml.Reply("UnitsInformation_v3",
            ("Table", SiteLinkXml.Row(("UnitID", "1"), ("sUnitName", "A1"))),
            ("Table", SiteLinkXml.Row(("UnitID", "2"), ("sUnitName", "A2"))),
            ("Table1", SiteLinkXml.Row(("lngLastTimePolled", "638900000000000000"), ("dLatestUpdated", "2026-10-14T03:00:00")))));
        await using var scope = api.Services.CreateAsyncScope();
        var client = scope.ServiceProvider.GetRequiredService<SiteLinkClient>();

        var page = await client.UnitsInformationAsync(code, 638800000000000000, includeExcludedFromWebsite: false, Sg, Ct);

        page.Units.Select(u => u.UnitName).Should().Equal("A1", "A2");
        page.NextTicks.Should().Be(638900000000000000);
        var request = api.SiteLink.RequestsFor(code).Single();
        request.Names.Skip(4).Should().Equal("lngLastTimePolled", "bReturnExcludedFromWebsiteUnits");
        request.Fields["lngLastTimePolled"].Should().Be("638800000000000000");
        request.Fields["bReturnExcludedFromWebsiteUnits"].Should().Be("false");
    }

    [Fact]
    public async Task A_first_pull_sends_zero_and_a_missing_cursor_row_is_null()
    {
        var code = SitesTestData.NewCode();
        api.SiteLink.Reply("UnitsInformation_v3", code, SiteLinkXml.Reply("UnitsInformation_v3", ("Table", SiteLinkXml.Row(("UnitID", "1"), ("sUnitName", "A1")))));
        await using var scope = api.Services.CreateAsyncScope();

        var page = await scope.ServiceProvider.GetRequiredService<SiteLinkClient>().UnitsInformationAsync(code, null, true, Sg, Ct);

        page.NextTicks.Should().BeNull();
        api.SiteLink.RequestsFor(code).Single().Fields["lngLastTimePolled"].Should().Be("0");
        api.SiteLink.RequestsFor(code).Single().Fields["bReturnExcludedFromWebsiteUnits"].Should().Be("true");
    }

    [Fact]
    public async Task The_price_list_gives_the_currency_decimals()
    {
        var code = SitesTestData.NewCode();
        api.SiteLink.Reply("UnitTypePriceList_v2", code, SiteLinkXml.Reply("UnitTypePriceList_v2",
            ("Table", SiteLinkXml.Row(("SiteID", "9"), ("iCurrencyDecimals", "2"), ("UnitTypeID", "7")))));
        await using var scope = api.Services.CreateAsyncScope();

        (await scope.ServiceProvider.GetRequiredService<SiteLinkClient>().CurrencyDecimalsAsync(code, Ct)).Should().Be(2);
        api.SiteLink.RequestsFor(code).Single().Names.Should().HaveCount(4);   // the logon block only
    }
}
```

- [ ] **Step 2: Run and watch them fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*SiteLinkUnitTests"`
Expected: compile errors.

- [ ] **Step 3: Implement**

`Integrations/SiteLink/SiteLinkUnit.cs`:

```csharp
namespace ExtraSpace.Api.Integrations.SiteLink;

/// <summary>
/// One <c>UnitsInformation_v3</c> row (demo 03 §4.1.2, booleans strict). A null nullable property means the column was absent,
/// so the caller keeps its stored value.
/// </summary>
internal sealed record SiteLinkUnit(
    int UnitId, int UnitTypeId, string UnitName, string TypeName, decimal Width, decimal Length,
    bool Climate, bool Inside, bool Power, bool Alarm, bool Ada, bool Mobile,
    bool Rented, bool Rentable, bool WaitingListReserved,
    int? Floor, string? Description,
    decimal? StandardRate, decimal? WebRate, decimal? BoardRate, decimal? PushRate, decimal? PreferredRate, decimal? StandardSecurityDeposit,
    DateTime? DeletedAt)
{
    public decimal AreaSqft => Width * Length;

    public static SiteLinkUnit From(SiteLinkRow row, TimeZoneInfo zone) => new(
        UnitId: row.Int("UnitID") ?? throw new FormatException("A unit row has no UnitID."),
        UnitTypeId: row.Int("UnitTypeID") ?? 0,
        UnitName: row.Text("sUnitName")?.Trim() is { Length: > 0 } name ? name : throw new FormatException("A unit row has no sUnitName."),
        TypeName: row.Text("sTypeName") ?? "",
        Width: row.Decimal("dcWidth") ?? 0m,
        Length: row.Decimal("dcLength") ?? 0m,
        Climate: row.Bool("bClimate") ?? false,
        Inside: row.Bool("bInside") ?? false,
        Power: row.Bool("bPower") ?? false,
        Alarm: row.Bool("bAlarm") ?? false,
        Ada: row.Int("iADA") == 1,
        Mobile: row.Bool("bMobile") ?? false,
        Rented: row.Bool("bRented") ?? false,
        Rentable: row.Bool("bRentable") ?? true,
        WaitingListReserved: row.Bool("bWaitingListReserved") ?? false,
        Floor: row.Int("iFloor"),
        Description: row.Text("sUnitDesc"),
        StandardRate: row.Decimal("dcStdRate"),
        WebRate: row.Decimal("dcWebRate"),
        BoardRate: row.Decimal("dcBoardRate"),
        PushRate: row.Decimal("dcPushRate"),
        PreferredRate: row.Decimal("dcPreferredRate"),
        StandardSecurityDeposit: row.Decimal("dcStdSecDep"),
        DeletedAt: row.UtcDate("dDeleted", zone));
}

internal sealed record SiteLinkUnitsPage(IReadOnlyList<SiteLinkUnit> Units, long? NextTicks);
```

`Integrations/SiteLink/SiteLinkClient.Units.cs`:

```csharp
using System.Globalization;

namespace ExtraSpace.Api.Integrations.SiteLink;

internal sealed partial class SiteLinkClient
{
    /// <summary>
    /// <c>UnitsInformation_v3</c>: the units changed since <paramref name="sinceTicks"/> (null = from the beginning, sent as "0"), and
    /// SiteLink's next cursor (null when the reply has none). The ticks are round-tripped, never computed.
    /// </summary>
    public async Task<SiteLinkUnitsPage> UnitsInformationAsync(string locationCode, long? sinceTicks, bool includeExcludedFromWebsite,
        TimeZoneInfo zone, CancellationToken cancellationToken)
    {
        const string operation = "UnitsInformation_v3";
        var reply = (await CallAsync(operation, locationCode, SiteLinkCallKind.Read, new SiteLinkFields()
                .Add("lngLastTimePolled", (sinceTicks ?? 0).ToString(CultureInfo.InvariantCulture))
                .Add("bReturnExcludedFromWebsiteUnits", includeExcludedFromWebsite), cancellationToken))
            .ThrowIfRefused(operation);
        var next = reply.Table("Table1").FirstOrDefault()?.Long("lngLastTimePolled");
        return new SiteLinkUnitsPage(reply.Table("Table").Select(row => SiteLinkUnit.From(row, zone)).ToList(), next is > 0 ? next : null);
    }

    /// <summary><c>UnitTypePriceList_v2</c>, read only for the site's currency decimals in S1-1 (spec §6.5); S1-3 reads the fees.</summary>
    public async Task<int?> CurrencyDecimalsAsync(string locationCode, CancellationToken cancellationToken)
    {
        const string operation = "UnitTypePriceList_v2";
        var reply = (await CallAsync(operation, locationCode, SiteLinkCallKind.Read, new SiteLinkFields(), cancellationToken))
            .ThrowIfRefused(operation);
        return reply.Table("Table").FirstOrDefault()?.Int("iCurrencyDecimals");
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*SiteLinkUnitTests"`
Expected: all pass.

- [ ] **Step 5: Stop and report** (no commit).

---

### Task 6: Unit refresh — service, size mapping, jobs

**Files:**
- Create: `src/ExtraSpace.Api/Features/Sites/UnitRefreshService.cs`, `UnitRefreshJob.cs`, `UnitSizeMap.cs`
- Modify: `Features/Sites/SitesSetup.cs`; `tests/ExtraSpace.Api.Tests/ApiFactory.cs` (`Jobs:UnitRefresh:Enabled=false`)
- Test: `tests/ExtraSpace.Api.Tests/Features/Sites/UnitRefreshTests.cs`, `UnitSizeMapTests.cs`

**Interfaces:**
- Consumes: `SiteLinkClient.UnitsInformationAsync`, `.CurrencyDecimalsAsync` (Task 5); the entities (Task 3); `SiteClock`, `Currencies` (Task 1).
- Produces:
  - `UnitRefreshMode { Incremental, Nightly, Full }`
  - `UnitRefreshService.RefreshAsync(Guid siteId, UnitRefreshMode mode, CancellationToken) → Task<UnitRefreshResult(UnitRefreshOutcome Outcome, int Units)>` with `UnitRefreshOutcome { Refreshed, Skipped }`
  - `UnitRefreshJob.Name = "UnitRefresh"`, `.RunAsync` (hourly), `.RefreshSiteAsync(siteId, mode, ct)` (staff action), `.IsDue(timeZone, now)`
  - `UnitSizeMap.RemapAsync(AppDbContext, Guid? siteId, CancellationToken)`

- [ ] **Step 1: Write the failing tests**

In `ApiFactory.ConfigureWebHost` add `builder.UseSetting("Jobs:UnitRefresh:Enabled", "false");`. The hourly job must never fire into the shared test database.

`tests/ExtraSpace.Api.Tests/Features/Sites/UnitRefreshTests.cs`:

```csharp
using ExtraSpace.Api.Features.Sites;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace ExtraSpace.Api.Tests.Features.Sites;

public sealed class UnitRefreshTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;
    private const string Op = "UnitsInformation_v3";

    private async Task<UnitRefreshResult> RefreshAsync(Guid siteId, UnitRefreshMode mode)
    {
        await using var scope = api.Services.CreateAsyncScope();
        return await scope.ServiceProvider.GetRequiredService<UnitRefreshService>().RefreshAsync(siteId, mode, Ct);
    }

    private async Task<(List<Unit> Units, UnitSyncState? State)> ReadAsync(Guid siteId)
    {
        List<Unit> units = [];
        UnitSyncState? state = null;
        await api.WithDbAsync(async db =>
        {
            units = await db.Set<Unit>().AsNoTracking().Where(u => u.SiteId == siteId).OrderBy(u => u.SiteLinkUnitId).ToListAsync(Ct);
            state = await db.Set<UnitSyncState>().AsNoTracking().SingleOrDefaultAsync(s => s.SiteId == siteId, Ct);
        });
        return (units, state);
    }

    private static Dictionary<string, string?> UnitRow(int id, string name, params (string, string?)[] more) =>
        SiteLinkXml.Row([("UnitID", id.ToString()), ("UnitTypeID", "7"), ("sUnitName", name), ("sTypeName", "Walk In"),
            ("dcWidth", "5"), ("dcLength", "10"), ("bRentable", "true"), ("bRented", "false"), .. more]);

    [Fact]
    public async Task The_first_refresh_pulls_every_unit_and_saves_the_cursor()
    {
        var site = await api.CreateSiteAsync();
        api.SiteLink.Reply(Op, site.LocationCode, SiteLinkXml.Reply(Op,
            ("Table", UnitRow(1, "A1", ("dcWebRate", "100"))),
            ("Table", UnitRow(2, "A2", ("bRented", "true"))),
            ("Table", UnitRow(3, "W1", ("sTypeName", " BizPlus "))),
            ("Table1", SiteLinkXml.Row(("lngLastTimePolled", "638900000000000001")))));

        var result = await RefreshAsync(site.Id, UnitRefreshMode.Incremental);   // no cursor yet: a full pull

        result.Should().Be(new UnitRefreshResult(UnitRefreshOutcome.Refreshed, 3));
        var request = api.SiteLink.RequestsFor(site.LocationCode, Op).Single();
        request.Fields["lngLastTimePolled"].Should().Be("0");
        request.Fields["bReturnExcludedFromWebsiteUnits"].Should().Be("true");
        var (units, state) = await ReadAsync(site.Id);
        units.Select(u => (u.UnitName, u.Available)).Should().Equal(("A1", true), ("A2", false), ("W1", true));
        units[0].WebRate.Should().Be(100m);
        units[0].AreaSqft.Should().Be(50m);
        units[0].StorageTypeId.Should().Be(StorageType.SelfStorageId);
        units[2].StorageTypeId.Should().Be(StorageType.WorkspaceId);
        units.Should().AllSatisfy(u => u.LastSyncedAt.Should().NotBeNull());
        state!.LastTimePolledTicks.Should().Be(638900000000000001);
        state.LastSyncedAt.Should().NotBeNull();
        state.LastError.Should().BeNull();
    }

    [Fact]
    public async Task An_incremental_refresh_keeps_absent_columns_and_marks_deleted_units()
    {
        var site = await api.CreateSiteAsync();
        var unit = await api.CreateUnitAsync(site.Id, u =>
        {
            u.SiteLinkUnitId = 41;
            u.WebRate = 50m;
            u.Description = "old";
        });
        await api.WithDbAsync(async db =>
        {
            db.Add(new UnitSyncState { SiteId = site.Id, LastTimePolledTicks = 638800000000000000 });
            await db.SaveChangesAsync(Ct);
        });
        api.SiteLink.Reply(Op, site.LocationCode, SiteLinkXml.Reply(Op,
            ("Table", UnitRow(41, unit.UnitName, ("dDeleted", "2026-10-01T10:00:00")))));   // no dcWebRate, no sUnitDesc, no Table1

        await RefreshAsync(site.Id, UnitRefreshMode.Incremental);

        var request = api.SiteLink.RequestsFor(site.LocationCode, Op).Single();
        request.Fields["lngLastTimePolled"].Should().Be("638800000000000000");
        request.Fields["bReturnExcludedFromWebsiteUnits"].Should().Be("false");
        var (units, state) = await ReadAsync(site.Id);
        var row = units.Single();
        row.WebRate.Should().Be(50m);
        row.Description.Should().Be("old");
        row.DeletedAt.Should().Be(new DateTime(2026, 10, 1, 2, 0, 0, DateTimeKind.Utc));
        row.Available.Should().BeFalse();
        state!.LastTimePolledTicks.Should().Be(638800000000000000);   // no Table1: the cursor stays
    }

    [Fact]
    public async Task A_full_refresh_with_no_units_fails_and_keeps_the_cursor()
    {
        var site = await api.CreateSiteAsync();
        await api.WithDbAsync(async db =>
        {
            db.Add(new UnitSyncState { SiteId = site.Id, LastTimePolledTicks = 638800000000000000 });
            await db.SaveChangesAsync(Ct);
        });
        api.SiteLink.Reply(Op, site.LocationCode, SiteLinkXml.Reply(Op));

        var refresh = () => RefreshAsync(site.Id, UnitRefreshMode.Full);

        await refresh.Should().ThrowAsync<UnitRefreshException>();
        var (units, state) = await ReadAsync(site.Id);
        units.Should().BeEmpty();
        state!.LastTimePolledTicks.Should().Be(638800000000000000);
        state.LastError.Should().Be("SiteLink returned no units for a full refresh.");
        state.LastAttemptAt.Should().NotBeNull();
    }

    [Fact]
    public async Task A_failing_row_rolls_back_the_whole_batch()
    {
        var site = await api.CreateSiteAsync();
        api.SiteLink.Reply(Op, site.LocationCode, SiteLinkXml.Reply(Op,
            ("Table", UnitRow(1, "GOOD")),
            ("Table", UnitRow(2, new string('X', 101))),   // longer than unit_name allows: the save fails
            ("Table1", SiteLinkXml.Row(("lngLastTimePolled", "638900000000000009")))));

        var refresh = () => RefreshAsync(site.Id, UnitRefreshMode.Incremental);

        await refresh.Should().ThrowAsync<DbUpdateException>();
        var (units, state) = await ReadAsync(site.Id);
        units.Should().BeEmpty();
        state!.LastTimePolledTicks.Should().BeNull();
        state.LastError.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public async Task A_second_refresh_of_the_same_site_is_skipped()
    {
        var site = await api.CreateSiteAsync();
        await using var holder = new NpgsqlConnection(api.ConnectionString);
        await holder.OpenAsync(Ct);
        await using var transaction = await holder.BeginTransactionAsync(Ct);
        await using (var lockCommand = new NpgsqlCommand("SELECT pg_advisory_xact_lock(hashtextextended(@key, 0))", holder, transaction))
        {
            lockCommand.Parameters.AddWithValue("key", $"unit-refresh:{site.Id}");
            await lockCommand.ExecuteNonQueryAsync(Ct);
        }

        var result = await RefreshAsync(site.Id, UnitRefreshMode.Incremental);

        result.Outcome.Should().Be(UnitRefreshOutcome.Skipped);
        api.SiteLink.RequestsFor(site.LocationCode).Should().BeEmpty();
    }

    [Fact]
    public async Task The_nightly_run_checks_the_currency_decimals()
    {
        var site = await api.CreateSiteAsync("SG");
        api.SiteLink.Reply("UnitTypePriceList_v2", site.LocationCode, SiteLinkXml.Reply("UnitTypePriceList_v2",
            ("Table", SiteLinkXml.Row(("iCurrencyDecimals", "0")))));

        var refresh = () => RefreshAsync(site.Id, UnitRefreshMode.Nightly);

        (await refresh.Should().ThrowAsync<UnitRefreshException>()).WithMessage("*0 currency decimals*SGD has 2*");
        api.SiteLink.RequestsFor(site.LocationCode, Op).Should().BeEmpty();

        api.SiteLink.Reply("UnitTypePriceList_v2", site.LocationCode, SiteLinkXml.Reply("UnitTypePriceList_v2",
            ("Table", SiteLinkXml.Row(("iCurrencyDecimals", "2")))));
        api.SiteLink.Reply(Op, site.LocationCode, SiteLinkXml.Reply(Op, ("Table", UnitRow(1, "A1"))));
        (await RefreshAsync(site.Id, UnitRefreshMode.Nightly)).Outcome.Should().Be(UnitRefreshOutcome.Refreshed);
        (await ReadAsync(site.Id)).State!.LastError.Should().BeNull();
    }

    [Theory]
    [InlineData("Asia/Singapore", "2026-10-14T19:00:00Z", true)]     // 03:00 SGT
    [InlineData("Asia/Singapore", "2026-10-14T19:59:00Z", true)]
    [InlineData("Asia/Singapore", "2026-10-14T18:59:00Z", false)]
    [InlineData("Asia/Kuala_Lumpur", "2026-10-14T19:30:00Z", true)]
    [InlineData("Asia/Seoul", "2026-10-14T18:00:00Z", true)]         // 03:00 KST
    [InlineData("Asia/Seoul", "2026-10-14T19:00:00Z", false)]
    public void Each_site_is_due_at_3am_in_its_own_zone(string zone, string utc, bool due) =>
        UnitRefreshJob.IsDue(zone, DateTimeOffset.Parse(utc, System.Globalization.CultureInfo.InvariantCulture)).Should().Be(due);
}
```

`tests/ExtraSpace.Api.Tests/Features/Sites/UnitSizeMapTests.cs` runs on a fresh database of its own, because unit sizes are global and other tests create them:

```csharp
using ExtraSpace.Api.Features.Sites;
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Tests.Features.Sites;

public sealed class UnitSizeMapTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Each_unit_gets_the_first_size_whose_range_and_type_fit()
    {
        var connection = await api.CreateDatabaseAsync("sizes");
        var options = new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(connection).UseSnakeCaseNamingConvention().Options;
        await using var db = new AppDbContext(options);
        await db.Database.MigrateAsync(Ct);

        var site = new Site { LocationCode = "S1", Name = "s", Country = "SG", Currency = "SGD", TimeZone = "Asia/Singapore", TaxPercentage = 9, TaxLabel = "GST" };
        var small = new UnitSize { Key = "small", Label = "Small", MinAreaSqft = 0, MaxAreaSqft = 50, SortOrder = 1, StorageTypeId = StorageType.SelfStorageId };
        var medium = new UnitSize { Key = "medium", Label = "Medium", MinAreaSqft = 50, MaxAreaSqft = 100, SortOrder = 2 };
        var large = new UnitSize { Key = "large", Label = "Large", MinAreaSqft = 100, SortOrder = 3 };
        var desk = new UnitSize { Key = "desk", Label = "Desk", MaxAreaSqft = 30, SortOrder = 0, StorageTypeId = StorageType.WorkspaceId };
        db.AddRange(site, small, medium, large, desk);
        Unit NewUnit(int id, decimal area, Guid type) => new()
        {
            SiteId = site.Id, SiteLinkUnitId = id, UnitName = "U" + id, AreaSqft = area, StorageTypeId = type, Rentable = true,
        };
        var units = new[]
        {
            NewUnit(1, 25, StorageType.SelfStorageId), NewUnit(2, 50, StorageType.SelfStorageId),
            NewUnit(3, 150, StorageType.SelfStorageId), NewUnit(4, 10, StorageType.WorkspaceId),
        };
        db.AddRange(units);
        await db.SaveChangesAsync(Ct);

        (await UnitSizeMap.RemapAsync(db, null, Ct)).Should().Be(4);

        var sizes = await db.Set<Unit>().AsNoTracking().OrderBy(u => u.SiteLinkUnitId).Select(u => u.UnitSizeId).ToListAsync(Ct);
        sizes.Should().Equal(small.Id, medium.Id, large.Id, desk.Id);   // min inclusive, max exclusive; the desk size is workspace-only
        (await UnitSizeMap.RemapAsync(db, site.Id, Ct)).Should().Be(0);   // nothing changed: nothing written
    }
}
```

- [ ] **Step 2: Run and watch them fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*UnitRefreshTests"` and `"*UnitSizeMapTests"`.
Expected: compile errors.

- [ ] **Step 3: Implement**

`Features/Sites/UnitSizeMap.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Sites;

internal static class UnitSizeMap
{
    /// <summary>
    /// Sets each unit's size from its area (S1 spec §5.1): the first size, by sort order then key, whose storage type is the unit's
    /// (or none) and whose range holds the area (min inclusive, max exclusive). One SQL rule for the sync and for size edits;
    /// only rows that change are written. <paramref name="siteId"/> null = every unit.
    /// </summary>
    public static Task<int> RemapAsync(AppDbContext db, Guid? siteId, CancellationToken cancellationToken) =>
        db.Database.ExecuteSqlAsync($"""
            UPDATE unit AS u SET unit_size_id = m.size_id, updated_at = now()
            FROM unit AS x
            LEFT JOIN LATERAL (
                SELECT s.id AS size_id FROM unit_size AS s
                WHERE (s.storage_type_id IS NULL OR s.storage_type_id = x.storage_type_id)
                  AND x.area_sqft >= COALESCE(s.min_area_sqft, 0)
                  AND (s.max_area_sqft IS NULL OR x.area_sqft < s.max_area_sqft)
                ORDER BY s.sort_order, s.key
                LIMIT 1) AS m ON true
            WHERE u.id = x.id
              AND ({siteId}::uuid IS NULL OR x.site_id = {siteId})
              AND u.unit_size_id IS DISTINCT FROM m.size_id
            """, cancellationToken);
}
```

`Features/Sites/UnitRefreshService.cs`:

```csharp
using ExtraSpace.Api.Integrations.SiteLink;
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Engines;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Sites;

internal enum UnitRefreshMode { Incremental, Nightly, Full }

internal enum UnitRefreshOutcome { Refreshed, Skipped }

internal sealed record UnitRefreshResult(UnitRefreshOutcome Outcome, int Units);

internal sealed class UnitRefreshException(string message) : Exception(message);

internal sealed partial class UnitRefreshService(AppDbContext db, SiteLinkClient sitelink, TimeProvider time, ILogger<UnitRefreshService> logger)
{
    /// <summary>
    /// Copies a site's changed units from SiteLink (S1 spec §6.7). The upserts, the size mapping and the cursor commit together.
    /// A refresh of a site that is already being refreshed is skipped. A failure is written to the site's sync state and rethrown.
    /// </summary>
    public async Task<UnitRefreshResult> RefreshAsync(Guid siteId, UnitRefreshMode mode, CancellationToken cancellationToken)
    {
        var site = await db.Set<Site>().AsNoTracking().SingleOrDefaultAsync(s => s.Id == siteId, cancellationToken)
            ?? throw new InvalidOperationException($"Site {siteId} does not exist.");
        try
        {
            await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
            if (!await TryLockAsync(siteId, cancellationToken))
            {
                LogSkipped(logger, site.LocationCode);
                return new UnitRefreshResult(UnitRefreshOutcome.Skipped, 0);
            }
            var state = await db.Set<UnitSyncState>().SingleOrDefaultAsync(s => s.SiteId == siteId, cancellationToken);
            if (state is null) db.Add(state = new UnitSyncState { SiteId = siteId });

            if (mode == UnitRefreshMode.Nightly) await CheckCurrencyAsync(site, cancellationToken);
            var full = mode == UnitRefreshMode.Full || state.LastTimePolledTicks is null;
            var page = await sitelink.UnitsInformationAsync(site.LocationCode, full ? null : state.LastTimePolledTicks,
                includeExcludedFromWebsite: full, SiteClock.Zone(site.TimeZone), cancellationToken);
            if (full && page.Units.Count == 0) throw new UnitRefreshException("SiteLink returned no units for a full refresh.");

            var now = time.GetUtcNow().UtcDateTime;
            await UpsertAsync(siteId, page.Units, now, cancellationToken);
            await db.SaveChangesAsync(cancellationToken);
            await UnitSizeMap.RemapAsync(db, siteId, cancellationToken);
            state.LastTimePolledTicks = page.NextTicks ?? state.LastTimePolledTicks;
            state.LastSyncedAt = now;
            state.LastAttemptAt = now;
            state.LastError = null;
            await db.SaveChangesAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            LogRefreshed(logger, site.LocationCode, mode, page.Units.Count);
            return new UnitRefreshResult(UnitRefreshOutcome.Refreshed, page.Units.Count);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            // The transaction was rolled back when it was disposed, on the way out of the try block.
            db.ChangeTracker.Clear();
            await RecordFailureAsync(siteId, site.LocationCode, exception);
            throw;
        }
    }

    private async Task<bool> TryLockAsync(Guid siteId, CancellationToken cancellationToken) =>
        await db.Database.SqlQuery<bool>($"SELECT pg_try_advisory_xact_lock(hashtextextended({"unit-refresh:" + siteId}, 0)) AS \"Value\"")
            .SingleAsync(cancellationToken);

    private async Task CheckCurrencyAsync(Site site, CancellationToken cancellationToken)
    {
        var expected = Currencies.Decimals(site.Currency);
        if (await sitelink.CurrencyDecimalsAsync(site.LocationCode, cancellationToken) is { } decimals && decimals != expected)
            throw new UnitRefreshException($"SiteLink uses {decimals} currency decimals at this site, but {site.Currency} has {expected}.");
    }

    private async Task UpsertAsync(Guid siteId, IReadOnlyList<SiteLinkUnit> rows, DateTime now, CancellationToken cancellationToken)
    {
        if (rows.Count == 0) return;
        var ids = rows.Select(r => r.UnitId).Distinct().ToArray();
        var existing = await db.Set<Unit>().Where(u => u.SiteId == siteId && ids.Contains(u.SiteLinkUnitId))
            .ToDictionaryAsync(u => u.SiteLinkUnitId, cancellationToken);
        var storageTypes = await db.Set<StorageType>().AsNoTracking().ToDictionaryAsync(t => t.Key, t => (Guid?)t.Id, cancellationToken);
        foreach (var row in rows)
        {
            if (!existing.TryGetValue(row.UnitId, out var unit))
            {
                unit = new Unit { SiteId = siteId, SiteLinkUnitId = row.UnitId, UnitName = row.UnitName };
                db.Add(unit);
                existing[row.UnitId] = unit;
            }
            Apply(unit, row, storageTypes.GetValueOrDefault(StorageType.KeyFor(row.TypeName)), now);
        }
    }

    internal static void Apply(Unit unit, SiteLinkUnit row, Guid? storageTypeId, DateTime now)
    {
        unit.SiteLinkUnitTypeId = row.UnitTypeId;
        unit.UnitName = row.UnitName;
        unit.Width = row.Width;
        unit.Length = row.Length;
        unit.AreaSqft = row.AreaSqft;
        unit.Climate = row.Climate;
        unit.Inside = row.Inside;
        unit.Power = row.Power;
        unit.Alarm = row.Alarm;
        unit.Ada = row.Ada;
        unit.Mobile = row.Mobile;
        unit.Rented = row.Rented;
        unit.Rentable = row.Rentable;
        unit.WaitingListReserved = row.WaitingListReserved;
        unit.DeletedAt = row.DeletedAt;
        unit.StorageTypeId = storageTypeId;
        unit.LastSyncedAt = now;
        // An absent column keeps the stored value (demo 03 §4.1.1).
        unit.Floor = row.Floor ?? unit.Floor;
        unit.Description = row.Description ?? unit.Description;
        unit.StandardRate = row.StandardRate ?? unit.StandardRate;
        unit.WebRate = row.WebRate ?? unit.WebRate;
        unit.BoardRate = row.BoardRate ?? unit.BoardRate;
        unit.PushRate = row.PushRate ?? unit.PushRate;
        unit.PreferredRate = row.PreferredRate ?? unit.PreferredRate;
        unit.StandardSecurityDeposit = row.StandardSecurityDeposit ?? unit.StandardSecurityDeposit;
    }

    private async Task RecordFailureAsync(Guid siteId, string siteCode, Exception exception)
    {
        try
        {
            var now = time.GetUtcNow().UtcDateTime;
            var error = Describe(exception);
            await db.Database.ExecuteSqlAsync($"""
                INSERT INTO unit_sync_state (site_id, last_attempt_at, last_error) VALUES ({siteId}, {now}, {error})
                ON CONFLICT (site_id) DO UPDATE SET last_attempt_at = excluded.last_attempt_at, last_error = excluded.last_error
                """, CancellationToken.None);
        }
        catch (Exception recordFailure)
        {
            LogRecordFailed(logger, recordFailure, siteCode);   // keep the original error the caller sees
        }
    }

    /// <summary>What staff see on the Units page: no SiteLink text, no data values beyond our own messages.</summary>
    internal static string Describe(Exception exception)
    {
        var text = exception switch
        {
            SiteLinkException e => $"SiteLink refused the call (code {e.ReturnCode}).",
            SiteLinkUnavailableException => "SiteLink could not be reached.",
            UnitRefreshException e => e.Message,
            FormatException e => "SiteLink sent a value we could not read: " + e.Message,
            DbUpdateException => "Saving the units failed.",
            _ => exception.GetType().Name,
        };
        return text.Length <= 1000 ? text : text[..1000];
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "Unit refresh of {siteCode} ({mode}): {units} units")]
    private static partial void LogRefreshed(ILogger logger, string siteCode, UnitRefreshMode mode, int units);

    [LoggerMessage(Level = LogLevel.Information, Message = "Unit refresh of {siteCode} skipped: another refresh of that site is running")]
    private static partial void LogSkipped(ILogger logger, string siteCode);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Could not record the failed unit refresh of {siteCode}")]
    private static partial void LogRecordFailed(ILogger logger, Exception exception, string siteCode);
}
```

> In `A_failing_row_rolls_back_the_whole_batch` the test expects `state.LastError` to be set while `LastTimePolledTicks` is still null. `RecordFailureAsync` creates the row when it is missing, which makes that true.

`Features/Sites/UnitRefreshJob.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Jobs;
using ExtraSpace.Engines;
using Hangfire;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Sites;

internal sealed partial class UnitRefreshJob(AppDbContext db, IServiceScopeFactory scopes, TimeProvider time, ILogger<UnitRefreshJob> logger)
    : IRecurringJob
{
    public const string Name = "UnitRefresh";
    /// <summary>Hourly: each active site is refreshed in the hour that is 03:00 in its own zone (S1 spec §6.7; SG/MY UTC+8, KR UTC+9).</summary>
    public const string Cron = "0 * * * *";

    [DisableConcurrentExecution(timeoutInSeconds: 3600)]
    [AutomaticRetry(Attempts = 0, LogEvents = false)]
    public async Task RunAsync(CancellationToken cancellationToken)
    {
        var now = time.GetUtcNow();
        var sites = await db.Set<Site>().AsNoTracking().Where(s => s.Active)
            .Select(s => new { s.Id, s.LocationCode, s.TimeZone }).ToListAsync(cancellationToken);
        foreach (var site in sites.Where(s => IsDue(s.TimeZone, now)))
        {
            try
            {
                // A scope per site: a failed site must not leave tracked rows behind for the next one.
                await using var scope = scopes.CreateAsyncScope();
                await scope.ServiceProvider.GetRequiredService<UnitRefreshService>().RefreshAsync(site.Id, UnitRefreshMode.Nightly, cancellationToken);
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                LogSiteFailed(logger, exception, site.LocationCode);   // one site's failure never stops the others
            }
        }
    }

    /// <summary>Staff "Sync now" / "Full resync". Not retried, and never a failed job: the result shows on the Units page.</summary>
    [AutomaticRetry(Attempts = 0, LogEvents = false)]
    public async Task RefreshSiteAsync(Guid siteId, UnitRefreshMode mode, CancellationToken cancellationToken)
    {
        try
        {
            await using var scope = scopes.CreateAsyncScope();
            await scope.ServiceProvider.GetRequiredService<UnitRefreshService>().RefreshAsync(siteId, mode, cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            LogStaffRefreshFailed(logger, exception, siteId);
        }
    }

    internal static bool IsDue(string timeZone, DateTimeOffset now) => SiteClock.ToLocal(now, SiteClock.Zone(timeZone)).Hour == 3;

    [LoggerMessage(Level = LogLevel.Error, Message = "Nightly unit refresh of {siteCode} failed")]
    private static partial void LogSiteFailed(ILogger logger, Exception exception, string siteCode);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Unit refresh of site {siteId} requested by staff failed")]
    private static partial void LogStaffRefreshFailed(ILogger logger, Exception exception, Guid siteId);
}
```

`SitesSetup.AddSitesFeature`:

```csharp
    public static IServiceCollection AddSitesFeature(this IServiceCollection services)
    {
        services.AddScoped<UnitRefreshService>();
        services.AddRecurringJob<UnitRefreshJob>(UnitRefreshJob.Name, UnitRefreshJob.Cron);
        return services;
    }
```

- [ ] **Step 4: Run the tests and watch them pass**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*UnitRefreshTests"`, `"*UnitSizeMapTests"` and `"*JobsTests"`.
Expected: all pass. `JobsTests` may list the recurring jobs: if it asserts an exact set, add `OutboxDispatcher` and `UnitRefresh` on purpose.

- [ ] **Step 5: Stop and report** (no commit).

---

### Task 7: Admin API — sites, storage types, unit sizes, units, unit sync

**Files:**
- Create: `src/ExtraSpace.Api/Platform/Data/Paging.cs`, `src/ExtraSpace.Api/Platform/Http/Patch.cs`
- Create: `src/ExtraSpace.Api/Features/Sites/SitesPermissions.cs`, `SitesErrors.cs`
- Create: `src/ExtraSpace.Api/Features/Sites/Admin/SitesAdminEndpoints.cs`, `SitesAdminDtos.cs`, `SiteAdminService.cs`, `StorageTypeAdminService.cs`, `UnitSizeAdminService.cs`, `UnitAdminQuery.cs`, `UnitRefreshRequests.cs`
- Modify: `Features/Sites/SitesSetup.cs`, `Program.cs` (`admin.MapSitesAdminEndpoints();` after `admin.MapAdminEndpoints();`), `admin-ui/openapi.json` (snapshot)
- Test: `tests/ExtraSpace.Api.Tests/Features/Sites/SitesAdminTests.cs`, `TaxonomyAdminTests.cs`, `UnitsAdminTests.cs`

**Interfaces:**
- Consumes: entities (Task 3), `UnitSizeMap` and `UnitRefreshJob.RefreshSiteAsync` (Task 6).
- Produces (wire contract for Tasks 9–11):
  - `GET /admin/api/sites?search&page&pageSize` → `PageOf<SiteListItem>`; `GET /admin/api/sites/{id}` → `SiteResponse`; `POST` → 201 `SiteResponse`; `PATCH /sites/{id}` (`UpdateSiteBody` + `version`, `clear`) → 200; `DELETE /sites/{id}?version=` → 204 / 409 `SITE_IN_USE`
  - the same five routes for `/storage-types` (`StorageTypeResponse`; 409 `STORAGE_TYPE_IN_USE`) and `/unit-sizes` (`UnitSizeResponse`; 409 `UNIT_SIZE_IN_USE`)
  - `GET /admin/api/units?search&siteId&available&page&pageSize` → `PageOf<UnitListItem>`; `GET /admin/api/units/{id}` → `UnitResponse`
  - `GET /admin/api/unit-sync` → `List<UnitSyncStatus>`; `POST /admin/api/sites/{id}/unit-sync` `{ full: bool }` → 202
  - permission `sites.manage` on every write and on the sync POST; every read is open to any signed-in staff member
  - `PageOf<T>(IReadOnlyList<T> Items, int Total, int Page, int PageSize)`; `Paging.ToPageAsync`, `Paging.Contains(text)`
  - `Patch.Text`, `Patch.Value`, `Patch.Clears`

- [ ] **Step 1: Write the failing tests**

`tests/ExtraSpace.Api.Tests/Features/Sites/SitesAdminTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ExtraSpace.Api.Features.Sites;
using ExtraSpace.Api.Tests.TestSupport;

namespace ExtraSpace.Api.Tests.Features.Sites;

public sealed class SitesAdminTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private Task<(HttpClient Client, global::ExtraSpace.Api.Features.Admin.StaffUser Staff)> ManagerAsync() => api.StaffClientAsync(SitesPermissions.Manage);

    private static async Task<JsonElement> JsonAsync(HttpResponseMessage response) => await response.Content.ReadFromJsonAsync<JsonElement>(Ct);

    private static object NewSite(string code, string country = "MY") =>
        new { locationCode = code, name = "Bukit " + code, country, taxPercentage = 6m, city = "Kuala Lumpur" };

    [Fact]
    public async Task Creating_a_site_fills_currency_zone_and_tax_label_from_the_country_and_is_audited()
    {
        var (client, actor) = await ManagerAsync();
        var code = SitesTestData.NewCode();

        var response = await client.PostAsJsonAsync("/admin/api/sites", NewSite(code), Ct);

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        var site = await JsonAsync(response);
        site.GetProperty("currency").GetString().Should().Be("MYR");
        site.GetProperty("timeZone").GetString().Should().Be("Asia/Kuala_Lumpur");
        site.GetProperty("taxLabel").GetString().Should().Be("SST");
        site.GetProperty("facilityType").GetString().Should().Be("SelfStorage");
        site.GetProperty("active").GetBoolean().Should().BeTrue();
        var audit = (await api.AuditRowsForAsync(site.GetProperty("id").GetGuid())).Should().ContainSingle().Subject;
        audit.EntityType.Should().Be("site");
        audit.StaffUserId.Should().Be(actor.Id);
    }

    [Fact]
    public async Task Any_staff_can_read_sites_but_only_sites_manage_can_write()
    {
        var (reader, _) = await api.StaffClientAsync();
        (await reader.GetAsync("/admin/api/sites", Ct)).StatusCode.Should().Be(HttpStatusCode.OK);
        (await reader.PostAsJsonAsync("/admin/api/sites", NewSite(SitesTestData.NewCode()), Ct)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task A_patch_changes_only_what_it_sends_clears_on_request_and_needs_the_version()
    {
        var (client, _) = await ManagerAsync();
        var created = await JsonAsync(await client.PostAsJsonAsync("/admin/api/sites",
            new { locationCode = SitesTestData.NewCode(), name = "N", country = "SG", taxPercentage = 9m, displayName = "Shown", latitude = 1.3m, city = "Singapore" }, Ct));
        var id = created.GetProperty("id").GetGuid();
        var version = created.GetProperty("version").GetUInt32();

        var response = await client.PatchAsJsonAsync($"/admin/api/sites/{id}",
            new { displayName = "", clear = new[] { "latitude" }, phone = "+65 6000 0000", version }, Ct);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var site = await JsonAsync(response);
        site.GetProperty("displayName").ValueKind.Should().Be(JsonValueKind.Null);
        site.GetProperty("latitude").ValueKind.Should().Be(JsonValueKind.Null);
        site.GetProperty("phone").GetString().Should().Be("+65 6000 0000");
        site.GetProperty("city").GetString().Should().Be("Singapore");

        (await client.PatchAsJsonAsync($"/admin/api/sites/{id}", new { name = "Again", version }, Ct)).StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await client.PatchAsJsonAsync($"/admin/api/sites/{id}", new { clear = new[] { "name" }, version = site.GetProperty("version").GetUInt32() }, Ct))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Changing_the_country_changes_the_currency()
    {
        var (client, _) = await ManagerAsync();
        var created = await JsonAsync(await client.PostAsJsonAsync("/admin/api/sites", NewSite(SitesTestData.NewCode(), "SG"), Ct));

        var site = await JsonAsync(await client.PatchAsJsonAsync($"/admin/api/sites/{created.GetProperty("id").GetGuid()}",
            new { country = "KR", version = created.GetProperty("version").GetUInt32() }, Ct));

        site.GetProperty("currency").GetString().Should().Be("KRW");
        site.GetProperty("timeZone").GetString().Should().Be("Asia/Singapore");   // only a default on create
    }

    [Theory]
    [InlineData("timeZone", "Mars/Olympus")]
    [InlineData("heroImageUrl", "http://example.test/a.png")]
    [InlineData("stripeAccountId", "cus_123")]
    [InlineData("country", "US")]
    public async Task Bad_values_are_400(string field, string value)
    {
        var (client, _) = await ManagerAsync();
        var body = new Dictionary<string, object?>
        {
            ["locationCode"] = SitesTestData.NewCode(), ["name"] = "N", ["country"] = "SG", ["taxPercentage"] = 9m, [field] = value,
        };
        (await client.PostAsJsonAsync("/admin/api/sites", body, Ct)).StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task A_taken_location_code_is_409()
    {
        var (client, _) = await ManagerAsync();
        var code = SitesTestData.NewCode();
        await client.PostAsJsonAsync("/admin/api/sites", NewSite(code), Ct);
        (await client.PostAsJsonAsync("/admin/api/sites", NewSite(code), Ct)).StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task A_site_with_units_cannot_be_deleted()
    {
        var (client, _) = await ManagerAsync();
        var site = await api.CreateSiteAsync();
        await api.CreateUnitAsync(site.Id);
        var current = await JsonAsync(await client.GetAsync($"/admin/api/sites/{site.Id}", Ct));

        var response = await client.DeleteAsync($"/admin/api/sites/{site.Id}?version={current.GetProperty("version").GetUInt32()}", Ct);

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await JsonAsync(response)).GetProperty("code").GetString().Should().Be("SITE_IN_USE");

        var empty = await JsonAsync(await client.PostAsJsonAsync("/admin/api/sites", NewSite(SitesTestData.NewCode()), Ct));
        (await client.DeleteAsync($"/admin/api/sites/{empty.GetProperty("id").GetGuid()}?version={empty.GetProperty("version").GetUInt32()}", Ct))
            .StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task The_list_pages_and_searches_name_code_and_city()
    {
        var (client, _) = await ManagerAsync();
        var tag = "Srch" + Guid.NewGuid().ToString("N")[..6];
        for (var i = 0; i < 3; i++)
            await client.PostAsJsonAsync("/admin/api/sites",
                new { locationCode = SitesTestData.NewCode(), name = $"{tag} {i}", country = "SG", taxPercentage = 9m }, Ct);

        var page = await JsonAsync(await client.GetAsync($"/admin/api/sites?search={tag.ToLowerInvariant()}&pageSize=2", Ct));

        page.GetProperty("total").GetInt32().Should().Be(3);
        page.GetProperty("items").GetArrayLength().Should().Be(2);
        page.GetProperty("pageSize").GetInt32().Should().Be(2);
        (await client.GetAsync("/admin/api/sites?search=100%25_off", Ct)).StatusCode.Should().Be(HttpStatusCode.OK);   // % and _ are literal
        (await client.GetAsync("/admin/api/sites?pageSize=101", Ct)).StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }
}
```

`tests/ExtraSpace.Api.Tests/Features/Sites/TaxonomyAdminTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ExtraSpace.Api.Features.Sites;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Tests.Features.Sites;

public sealed class TaxonomyAdminTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private static async Task<JsonElement> JsonAsync(HttpResponseMessage response) => await response.Content.ReadFromJsonAsync<JsonElement>(Ct);

    private static string NewKey() => "k-" + Guid.NewGuid().ToString("N")[..10];

    [Fact]
    public async Task A_storage_type_key_cannot_change_and_a_type_in_use_cannot_be_deleted()
    {
        var (client, _) = await api.StaffClientAsync(SitesPermissions.Manage);
        var created = await JsonAsync(await client.PostAsJsonAsync("/admin/api/storage-types", new { key = NewKey(), name = "Lockers", sortOrder = 5 }, Ct));
        var id = created.GetProperty("id").GetGuid();

        var patched = await JsonAsync(await client.PatchAsJsonAsync($"/admin/api/storage-types/{id}",
            new { key = "other", name = "Big lockers", version = created.GetProperty("version").GetUInt32() }, Ct));
        patched.GetProperty("key").GetString().Should().Be(created.GetProperty("key").GetString());   // UpdateStorageTypeBody has no key
        patched.GetProperty("name").GetString().Should().Be("Big lockers");

        var site = await api.CreateSiteAsync();
        await api.CreateUnitAsync(site.Id, u => u.StorageTypeId = id);
        var response = await client.DeleteAsync($"/admin/api/storage-types/{id}?version={patched.GetProperty("version").GetUInt32()}", Ct);
        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
        (await JsonAsync(response)).GetProperty("code").GetString().Should().Be("STORAGE_TYPE_IN_USE");
    }

    [Fact]
    public async Task A_unit_size_needs_min_not_above_max()
    {
        var (client, _) = await api.StaffClientAsync(SitesPermissions.Manage);
        (await client.PostAsJsonAsync("/admin/api/unit-sizes", new { key = NewKey(), label = "Odd", minAreaSqft = 50m, maxAreaSqft = 10m }, Ct))
            .StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Saving_a_unit_size_maps_the_units_it_covers_at_once()
    {
        var (client, _) = await api.StaffClientAsync(SitesPermissions.Manage);
        var site = await api.CreateSiteAsync();
        var unit = await api.CreateUnitAsync(site.Id, u => u.AreaSqft = 98765.43m);   // an area no other test uses

        var size = await JsonAsync(await client.PostAsJsonAsync("/admin/api/unit-sizes",
            new { key = NewKey(), label = "Huge", minAreaSqft = 98765m, maxAreaSqft = 98766m, sortOrder = -2_000_000_000 }, Ct));

        Guid? mapped = null;
        await api.WithDbAsync(async db => mapped = await db.Set<Unit>().Where(u => u.Id == unit.Id).Select(u => u.UnitSizeId).SingleAsync(Ct));
        mapped.Should().Be(size.GetProperty("id").GetGuid());

        var response = await client.DeleteAsync($"/admin/api/unit-sizes/{size.GetProperty("id").GetGuid()}?version={size.GetProperty("version").GetUInt32()}", Ct);
        (await JsonAsync(response)).GetProperty("code").GetString().Should().Be("UNIT_SIZE_IN_USE");
    }
}
```

`tests/ExtraSpace.Api.Tests/Features/Sites/UnitsAdminTests.cs`:

```csharp
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ExtraSpace.Api.Features.Sites;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Tests.Features.Sites;

public sealed class UnitsAdminTests(ApiFactory api)
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    private static async Task<JsonElement> JsonAsync(HttpResponseMessage response) => await response.Content.ReadFromJsonAsync<JsonElement>(Ct);

    [Fact]
    public async Task Units_filter_by_site_and_availability_and_show_the_site_currency()
    {
        var (client, _) = await api.StaffClientAsync();
        var site = await api.CreateSiteAsync("MY");
        await api.CreateUnitAsync(site.Id, u => { u.UnitName = "A1"; u.StandardRate = 120m; });
        await api.CreateUnitAsync(site.Id, u => { u.UnitName = "A2"; u.Rented = true; });

        var all = await JsonAsync(await client.GetAsync($"/admin/api/units?siteId={site.Id}", Ct));
        var available = await JsonAsync(await client.GetAsync($"/admin/api/units?siteId={site.Id}&available=true", Ct));

        all.GetProperty("total").GetInt32().Should().Be(2);
        all.GetProperty("items")[0].GetProperty("unitName").GetString().Should().Be("A1");   // ordered by unit name
        all.GetProperty("items")[0].GetProperty("currency").GetString().Should().Be("MYR");
        all.GetProperty("items")[0].GetProperty("standardRate").GetDecimal().Should().Be(120m);
        available.GetProperty("total").GetInt32().Should().Be(1);
        (await client.GetAsync($"/admin/api/units/{Guid.CreateVersion7()}", Ct)).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Sync_now_queues_a_refresh_that_updates_the_status()
    {
        var (client, _) = await api.StaffClientAsync(SitesPermissions.Manage);
        var site = await api.CreateSiteAsync();
        api.SiteLink.Reply("UnitsInformation_v3", site.LocationCode, SiteLinkXml.Reply("UnitsInformation_v3",
            ("Table", SiteLinkXml.Row(("UnitID", "1"), ("sUnitName", "A1"))),
            ("Table1", SiteLinkXml.Row(("lngLastTimePolled", "638900000000000002")))));

        (await client.PostAsJsonAsync($"/admin/api/sites/{site.Id}/unit-sync", new { full = false }, Ct)).StatusCode.Should().Be(HttpStatusCode.Accepted);

        JsonElement status = default;
        for (var i = 0; i < 100; i++)
        {
            var list = await JsonAsync(await client.GetAsync("/admin/api/unit-sync", Ct));
            status = list.EnumerateArray().Single(s => s.GetProperty("siteId").GetGuid() == site.Id);
            if (status.GetProperty("lastSyncedAt").ValueKind != JsonValueKind.Null) break;
            await Task.Delay(100, Ct);
        }
        status.GetProperty("units").GetInt32().Should().Be(1);
        status.GetProperty("lastError").ValueKind.Should().Be(JsonValueKind.Null);
    }

    [Fact]
    public async Task Starting_a_sync_needs_sites_manage()
    {
        var (client, _) = await api.StaffClientAsync();
        var site = await api.CreateSiteAsync();
        (await client.PostAsJsonAsync($"/admin/api/sites/{site.Id}/unit-sync", new { full = true }, Ct)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
        (await (await api.StaffClientAsync(SitesPermissions.Manage)).Client
            .PostAsJsonAsync($"/admin/api/sites/{Guid.CreateVersion7()}/unit-sync", new { full = true }, Ct)).StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
```

> `api.StaffClientAsync(params string[] permissions)` returns a signed-in client that already carries the CSRF header (`TestSupport/AdminTestData.cs:85`). With no permissions it is a plain staff member.

- [ ] **Step 2: Run and watch them fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*SitesAdminTests"` (and the other two classes).
Expected: compile errors.

- [ ] **Step 3: Implement the shared helpers**

`Platform/Data/Paging.cs`:

```csharp
using ExtraSpace.Api.Platform.Errors;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Platform.Data;

public sealed record PageOf<T>(IReadOnlyList<T> Items, int Total, int Page, int PageSize);

public static class Paging
{
    /// <summary>The demo's list page size (S1 spec §11.1).</summary>
    public const int DefaultPageSize = 20;

    /// <summary>One page of an already ordered query (order before projecting into a positional record).</summary>
    public static async Task<PageOf<T>> ToPageAsync<T>(this IQueryable<T> ordered, int page, int pageSize, CancellationToken cancellationToken)
    {
        if (pageSize is < 1 or > 100) throw new AppException(400, ErrorCodes.ValidationFailed, "The page size must be between 1 and 100.");
        if (page < 1 || page > int.MaxValue / pageSize) throw new AppException(400, ErrorCodes.ValidationFailed, "The page is out of range.");
        var total = await ordered.CountAsync(cancellationToken);
        var items = await ordered.Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(cancellationToken);
        return new PageOf<T>(items, total, page, pageSize);
    }

    /// <summary>An ILIKE pattern matching the text anywhere; its own %, _ and \ are literal (PostgreSQL's default escape is \).</summary>
    public static string Contains(string text) =>
        "%" + text.Trim().Replace(@"\", @"\\").Replace("%", @"\%").Replace("_", @"\_") + "%";
}
```

`Platform/Http/Patch.cs`:

```csharp
using ExtraSpace.Api.Platform.Errors;

namespace ExtraSpace.Api.Platform.Http;

/// <summary>
/// Admin PATCH rules (S1-1 decision 12, extending S0's UpdateStaffBody): null = unchanged; for text "" clears; a nullable number
/// or link is cleared by naming it in <c>clear</c>.
/// </summary>
public static class Patch
{
    public static ISet<string> Clears(string[]? clear, params string[] clearable)
    {
        var names = new HashSet<string>(clear ?? [], StringComparer.Ordinal);
        foreach (var name in names)
            if (!clearable.Contains(name)) throw Invalid($"'{name}' cannot be cleared.");
        return names;
    }

    public static void Text(string? value, Action<string?> set)
    {
        if (value is not null) set(string.IsNullOrWhiteSpace(value) ? null : value.Trim());
    }

    public static void Value<T>(T? value, string name, ISet<string> clear, Action<T?> set) where T : struct
    {
        if (value is not null && clear.Contains(name)) throw Invalid($"'{name}' cannot be set and cleared at once.");
        if (value is not null) set(value);
        else if (clear.Contains(name)) set(null);
    }

    private static AppException Invalid(string title) => new(400, ErrorCodes.ValidationFailed, title);
}
```

`Features/Sites/SitesPermissions.cs`:

```csharp
namespace ExtraSpace.Api.Features.Sites;

internal static class SitesPermissions
{
    public const string Manage = "sites.manage";
}
```

`Features/Sites/SitesErrors.cs`:

```csharp
using ExtraSpace.Api.Platform.Errors;

namespace ExtraSpace.Api.Features.Sites;

internal static class SitesErrors
{
    public static AppException NotFound(string what) => new(404, ErrorCodes.NotFound, $"{what} not found.");
    public static AppException Invalid(string title) => new(400, ErrorCodes.ValidationFailed, title);
    public static AppException SiteInUse() => new(409, "SITE_IN_USE", "Units still belong to this site.");
    public static AppException StorageTypeInUse() => new(409, "STORAGE_TYPE_IN_USE", "Units or unit sizes still use this storage type.");
    public static AppException UnitSizeInUse() => new(409, "UNIT_SIZE_IN_USE", "Units still have this size. Change its area range first.");
}
```

- [ ] **Step 4: Implement the DTOs**

`Features/Sites/Admin/SitesAdminDtos.cs`:

```csharp
using System.ComponentModel.DataAnnotations;

namespace ExtraSpace.Api.Features.Sites.Admin;

public sealed record SiteListItem(Guid Id, string LocationCode, string Name, FacilityType FacilityType, string? City, string Country, bool Active, uint Version);

public sealed record SiteResponse(
    Guid Id, string LocationCode, int? SiteLinkSiteId, string Name, string? DisplayName, string? Description, string? HeroImageUrl,
    string? Address1, string? City, string? Region, string? PostalCode, string Country, string? Phone, decimal? Latitude, decimal? Longitude,
    string TimeZone, string Currency, decimal TaxPercentage, string TaxLabel, FacilityType FacilityType, bool Active, string? StripeAccountId,
    uint Version);

public sealed class CreateSiteBody
{
    [Required, MaxLength(20), RegularExpression("^[A-Za-z0-9_-]+$")] public string? LocationCode { get; init; }
    [Range(1, int.MaxValue)] public int? SiteLinkSiteId { get; init; }
    [Required, MaxLength(200)] public string? Name { get; init; }
    [MaxLength(200)] public string? DisplayName { get; init; }
    [MaxLength(4000)] public string? Description { get; init; }
    [MaxLength(1000)] public string? HeroImageUrl { get; init; }
    [MaxLength(300)] public string? Address1 { get; init; }
    [MaxLength(100)] public string? City { get; init; }
    [MaxLength(100)] public string? Region { get; init; }
    [MaxLength(20)] public string? PostalCode { get; init; }
    [Required, AllowedValues("SG", "MY", "KR")] public string? Country { get; init; }
    [MaxLength(50)] public string? Phone { get; init; }
    [Range(typeof(decimal), "-90", "90")] public decimal? Latitude { get; init; }
    [Range(typeof(decimal), "-180", "180")] public decimal? Longitude { get; init; }
    /// <summary>Default: the country's zone.</summary>
    [MaxLength(64)] public string? TimeZone { get; init; }
    [Required, Range(typeof(decimal), "0", "100")] public decimal? TaxPercentage { get; init; }
    /// <summary>Default: the country's (GST / SST / VAT).</summary>
    [MaxLength(20)] public string? TaxLabel { get; init; }
    public FacilityType? FacilityType { get; init; }
    public bool? Active { get; init; }
    [MaxLength(100), RegularExpression("^acct_[A-Za-z0-9]+$")] public string? StripeAccountId { get; init; }
}

/// <summary>Null = unchanged; "" clears a text; <see cref="Clear"/> names the numbers to empty (siteLinkSiteId, latitude, longitude).</summary>
public sealed class UpdateSiteBody
{
    [MaxLength(20), RegularExpression("^[A-Za-z0-9_-]+$")] public string? LocationCode { get; init; }
    [Range(1, int.MaxValue)] public int? SiteLinkSiteId { get; init; }
    [MaxLength(200)] public string? Name { get; init; }
    [MaxLength(200)] public string? DisplayName { get; init; }
    [MaxLength(4000)] public string? Description { get; init; }
    [MaxLength(1000)] public string? HeroImageUrl { get; init; }
    [MaxLength(300)] public string? Address1 { get; init; }
    [MaxLength(100)] public string? City { get; init; }
    [MaxLength(100)] public string? Region { get; init; }
    [MaxLength(20)] public string? PostalCode { get; init; }
    [AllowedValues("SG", "MY", "KR", null)] public string? Country { get; init; }
    [MaxLength(50)] public string? Phone { get; init; }
    [Range(typeof(decimal), "-90", "90")] public decimal? Latitude { get; init; }
    [Range(typeof(decimal), "-180", "180")] public decimal? Longitude { get; init; }
    [MaxLength(64)] public string? TimeZone { get; init; }
    [Range(typeof(decimal), "0", "100")] public decimal? TaxPercentage { get; init; }
    [MaxLength(20)] public string? TaxLabel { get; init; }
    public FacilityType? FacilityType { get; init; }
    public bool? Active { get; init; }
    [MaxLength(100), RegularExpression("^(acct_[A-Za-z0-9]+)?$")] public string? StripeAccountId { get; init; }
    public string[]? Clear { get; init; }
    [Required] public uint? Version { get; init; }
}

public sealed record StorageTypeResponse(Guid Id, string Key, string Name, string? DisplayName, string? IconPath, string? ImagePath,
    int SortOrder, bool Active, uint Version);

public sealed class CreateStorageTypeBody
{
    [Required, MaxLength(50), RegularExpression("^[a-z0-9-]+$")] public string? Key { get; init; }
    [Required, MaxLength(100)] public string? Name { get; init; }
    [MaxLength(100)] public string? DisplayName { get; init; }
    [MaxLength(500)] public string? IconPath { get; init; }
    [MaxLength(500)] public string? ImagePath { get; init; }
    public int? SortOrder { get; init; }
    public bool? Active { get; init; }
}

/// <summary>No key: it cannot change after creation (S1-1 decision 13).</summary>
public sealed class UpdateStorageTypeBody
{
    [MaxLength(100)] public string? Name { get; init; }
    [MaxLength(100)] public string? DisplayName { get; init; }
    [MaxLength(500)] public string? IconPath { get; init; }
    [MaxLength(500)] public string? ImagePath { get; init; }
    public int? SortOrder { get; init; }
    public bool? Active { get; init; }
    [Required] public uint? Version { get; init; }
}

public sealed record UnitSizeResponse(Guid Id, string Key, string Label, string? DisplayName, string? Description, string? UnitGroup,
    string? ImagePath, decimal? MinAreaSqft, decimal? MaxAreaSqft, int SortOrder, Guid? StorageTypeId, string? StorageTypeName, uint Version);

public sealed class CreateUnitSizeBody
{
    [Required, MaxLength(50), RegularExpression("^[a-z0-9-]+$")] public string? Key { get; init; }
    [Required, MaxLength(100)] public string? Label { get; init; }
    [MaxLength(100)] public string? DisplayName { get; init; }
    [MaxLength(1000)] public string? Description { get; init; }
    [MaxLength(100)] public string? UnitGroup { get; init; }
    [MaxLength(500)] public string? ImagePath { get; init; }
    [Range(typeof(decimal), "0", "99999999")] public decimal? MinAreaSqft { get; init; }
    [Range(typeof(decimal), "0", "99999999")] public decimal? MaxAreaSqft { get; init; }
    public int? SortOrder { get; init; }
    public Guid? StorageTypeId { get; init; }
}

/// <summary><see cref="Clear"/> may name minAreaSqft, maxAreaSqft, storageTypeId.</summary>
public sealed class UpdateUnitSizeBody
{
    [MaxLength(50), RegularExpression("^[a-z0-9-]+$")] public string? Key { get; init; }
    [MaxLength(100)] public string? Label { get; init; }
    [MaxLength(100)] public string? DisplayName { get; init; }
    [MaxLength(1000)] public string? Description { get; init; }
    [MaxLength(100)] public string? UnitGroup { get; init; }
    [MaxLength(500)] public string? ImagePath { get; init; }
    [Range(typeof(decimal), "0", "99999999")] public decimal? MinAreaSqft { get; init; }
    [Range(typeof(decimal), "0", "99999999")] public decimal? MaxAreaSqft { get; init; }
    public int? SortOrder { get; init; }
    public Guid? StorageTypeId { get; init; }
    public string[]? Clear { get; init; }
    [Required] public uint? Version { get; init; }
}

public sealed record UnitListItem(Guid Id, string UnitName, Guid SiteId, string SiteName, string Currency, string? StorageTypeName,
    string? UnitSizeLabel, decimal? StandardRate, bool Available, bool Rented);

public sealed record UnitResponse(Guid Id, string UnitName, Guid SiteId, string SiteName, string Currency, string? StorageTypeName,
    string? UnitSizeLabel, decimal Width, decimal Length, decimal AreaSqft, int? Floor, bool Climate, decimal? StandardRate, decimal? WebRate,
    bool Rented, bool Available, DateTime? DeletedAt, DateTime? LastSyncedAt);

public sealed record UnitSyncStatus(Guid SiteId, string LocationCode, string SiteName, bool Active, int Units,
    DateTime? LastSyncedAt, DateTime? LastAttemptAt, string? LastError);

public sealed class UnitSyncBody
{
    /// <summary>True = "Full resync": every unit again from the beginning, then a new cursor.</summary>
    public bool Full { get; init; }
}
```

> `AllowedValues("SG", "MY", "KR", null)` lets a PATCH leave the country out. If the .NET 10 validation generator mishandles `AllowedValues`, check the value in the service with `SiteCountries.Get` (which is already 400) and drop the attribute. Say which you did.

- [ ] **Step 5: Implement the services**

`Features/Sites/Admin/SiteAdminService.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Http;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Sites.Admin;

internal sealed class SiteAdminService(AppDbContext db)
{
    private static readonly string[] Clearable = ["siteLinkSiteId", "latitude", "longitude"];

    public Task<PageOf<SiteListItem>> ListAsync(string? search, int page, int pageSize, CancellationToken cancellationToken)
    {
        var rows = db.Set<Site>().AsNoTracking();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var pattern = Paging.Contains(search);
            rows = rows.Where(s => EF.Functions.ILike(s.Name, pattern) || EF.Functions.ILike(s.LocationCode, pattern)
                || (s.City != null && EF.Functions.ILike(s.City, pattern)));
        }
        return rows.OrderByDescending(s => s.CreatedAt).ThenByDescending(s => s.Id)
            .Select(s => new SiteListItem(s.Id, s.LocationCode, s.Name, s.FacilityType, s.City, s.Country, s.Active, s.Version))
            .ToPageAsync(page, pageSize, cancellationToken);
    }

    public async Task<SiteResponse> GetAsync(Guid id, CancellationToken cancellationToken) =>
        Response(await db.Set<Site>().AsNoTracking().SingleOrDefaultAsync(s => s.Id == id, cancellationToken) ?? throw SitesErrors.NotFound("Site"));

    public async Task<SiteResponse> CreateAsync(CreateSiteBody body, CancellationToken cancellationToken)
    {
        var country = SiteCountries.Get(body.Country!);
        var site = new Site
        {
            LocationCode = Code(body.LocationCode!),
            SiteLinkSiteId = body.SiteLinkSiteId,
            Name = Required(body.Name!, "Name"),
            Country = country.Code,
            Currency = country.Currency,
            TimeZone = Zone(body.TimeZone ?? country.TimeZone),
            TaxPercentage = body.TaxPercentage!.Value,
            TaxLabel = Blank(body.TaxLabel) ?? country.TaxLabel,
            FacilityType = body.FacilityType ?? FacilityType.SelfStorage,
            Active = body.Active ?? true,
            DisplayName = Blank(body.DisplayName),
            Description = Blank(body.Description),
            HeroImageUrl = Https(Blank(body.HeroImageUrl)),
            Address1 = Blank(body.Address1),
            City = Blank(body.City),
            Region = Blank(body.Region),
            PostalCode = Blank(body.PostalCode),
            Phone = Blank(body.Phone),
            Latitude = body.Latitude,
            Longitude = body.Longitude,
            StripeAccountId = Blank(body.StripeAccountId),
        };
        db.Add(site);
        await db.SaveChangesAsync(cancellationToken);   // a taken location code → unique violation → 409 CONFLICT
        return Response(site);
    }

    public async Task<SiteResponse> UpdateAsync(Guid id, UpdateSiteBody body, CancellationToken cancellationToken)
    {
        var site = await db.Set<Site>().SingleOrDefaultAsync(s => s.Id == id, cancellationToken) ?? throw SitesErrors.NotFound("Site");
        db.Entry(site).Property(s => s.Version).OriginalValue = body.Version!.Value;   // stale → 409
        var clear = Patch.Clears(body.Clear, Clearable);
        if (body.LocationCode is not null) site.LocationCode = Code(body.LocationCode);
        if (body.Name is not null) site.Name = Required(body.Name, "Name");
        if (body.Country is not null)
        {
            var country = SiteCountries.Get(body.Country);
            site.Country = country.Code;
            site.Currency = country.Currency;
        }
        if (body.TimeZone is not null) site.TimeZone = Zone(body.TimeZone);
        if (body.TaxPercentage is { } tax) site.TaxPercentage = tax;
        if (body.TaxLabel is not null) site.TaxLabel = Required(body.TaxLabel, "Tax label");
        if (body.FacilityType is { } facility) site.FacilityType = facility;
        if (body.Active is { } active) site.Active = active;
        Patch.Value(body.SiteLinkSiteId, "siteLinkSiteId", clear, v => site.SiteLinkSiteId = v);
        Patch.Value(body.Latitude, "latitude", clear, v => site.Latitude = v);
        Patch.Value(body.Longitude, "longitude", clear, v => site.Longitude = v);
        Patch.Text(body.DisplayName, v => site.DisplayName = v);
        Patch.Text(body.Description, v => site.Description = v);
        Patch.Text(body.HeroImageUrl, v => site.HeroImageUrl = Https(v));
        Patch.Text(body.Address1, v => site.Address1 = v);
        Patch.Text(body.City, v => site.City = v);
        Patch.Text(body.Region, v => site.Region = v);
        Patch.Text(body.PostalCode, v => site.PostalCode = v);
        Patch.Text(body.Phone, v => site.Phone = v);
        Patch.Text(body.StripeAccountId, v => site.StripeAccountId = v);
        await db.SaveChangesAsync(cancellationToken);
        return Response(site);
    }

    public async Task DeleteAsync(Guid id, uint version, CancellationToken cancellationToken)
    {
        var site = await db.Set<Site>().SingleOrDefaultAsync(s => s.Id == id, cancellationToken) ?? throw SitesErrors.NotFound("Site");
        db.Entry(site).Property(s => s.Version).OriginalValue = version;
        if (await db.Set<Unit>().AnyAsync(u => u.SiteId == id, cancellationToken)) throw SitesErrors.SiteInUse();
        db.Remove(site);
        await db.SaveChangesAsync(cancellationToken);   // a unit synced since the check → foreign-key violation → 409 CONFLICT
    }

    private static string Code(string code) =>
        code.Trim().ToUpperInvariant() is { Length: > 0 } trimmed ? trimmed : throw SitesErrors.Invalid("The location code cannot be blank.");

    private static string Required(string value, string name) =>
        value.Trim() is { Length: > 0 } trimmed ? trimmed : throw SitesErrors.Invalid($"{name} cannot be blank.");

    private static string? Blank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string Zone(string id) =>
        TimeZoneInfo.TryFindSystemTimeZoneById(id.Trim(), out _) ? id.Trim() : throw SitesErrors.Invalid($"Unknown time zone '{id}'.");

    private static string? Https(string? url) =>
        url is null || (Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps)
            ? url : throw SitesErrors.Invalid("The image address must be an https URL.");

    private static SiteResponse Response(Site s) => new(s.Id, s.LocationCode, s.SiteLinkSiteId, s.Name, s.DisplayName, s.Description,
        s.HeroImageUrl, s.Address1, s.City, s.Region, s.PostalCode, s.Country, s.Phone, s.Latitude, s.Longitude, s.TimeZone, s.Currency,
        s.TaxPercentage, s.TaxLabel, s.FacilityType, s.Active, s.StripeAccountId, s.Version);
}
```

> After `SaveChangesAsync`, `site.Version` holds the new xmin (EF reads concurrency tokens back), so `Response(site)` is current. If a test shows a stale version, re-read with `GetAsync` as `RoleService` does.

`Features/Sites/Admin/StorageTypeAdminService.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Http;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Sites.Admin;

internal sealed class StorageTypeAdminService(AppDbContext db)
{
    public Task<PageOf<StorageTypeResponse>> ListAsync(string? search, int page, int pageSize, CancellationToken cancellationToken)
    {
        var rows = db.Set<StorageType>().AsNoTracking();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var pattern = Paging.Contains(search);
            rows = rows.Where(t => EF.Functions.ILike(t.Key, pattern) || EF.Functions.ILike(t.Name, pattern));
        }
        return rows.OrderByDescending(t => t.CreatedAt).ThenByDescending(t => t.Id)
            .Select(t => new StorageTypeResponse(t.Id, t.Key, t.Name, t.DisplayName, t.IconPath, t.ImagePath, t.SortOrder, t.Active, t.Version))
            .ToPageAsync(page, pageSize, cancellationToken);
    }

    public async Task<StorageTypeResponse> GetAsync(Guid id, CancellationToken cancellationToken) =>
        Response(await db.Set<StorageType>().AsNoTracking().SingleOrDefaultAsync(t => t.Id == id, cancellationToken)
            ?? throw SitesErrors.NotFound("Storage type"));

    public async Task<StorageTypeResponse> CreateAsync(CreateStorageTypeBody body, CancellationToken cancellationToken)
    {
        var type = new StorageType
        {
            Key = body.Key!.Trim(), Name = Required(body.Name!), DisplayName = Blank(body.DisplayName), IconPath = Blank(body.IconPath),
            ImagePath = Blank(body.ImagePath), SortOrder = body.SortOrder ?? 0, Active = body.Active ?? true,
        };
        db.Add(type);
        await db.SaveChangesAsync(cancellationToken);   // a taken key → 409 CONFLICT
        return Response(type);
    }

    public async Task<StorageTypeResponse> UpdateAsync(Guid id, UpdateStorageTypeBody body, CancellationToken cancellationToken)
    {
        var type = await db.Set<StorageType>().SingleOrDefaultAsync(t => t.Id == id, cancellationToken) ?? throw SitesErrors.NotFound("Storage type");
        db.Entry(type).Property(t => t.Version).OriginalValue = body.Version!.Value;
        if (body.Name is not null) type.Name = Required(body.Name);
        if (body.SortOrder is { } order) type.SortOrder = order;
        if (body.Active is { } active) type.Active = active;
        Patch.Text(body.DisplayName, v => type.DisplayName = v);
        Patch.Text(body.IconPath, v => type.IconPath = v);
        Patch.Text(body.ImagePath, v => type.ImagePath = v);
        await db.SaveChangesAsync(cancellationToken);
        return Response(type);
    }

    public async Task DeleteAsync(Guid id, uint version, CancellationToken cancellationToken)
    {
        var type = await db.Set<StorageType>().SingleOrDefaultAsync(t => t.Id == id, cancellationToken) ?? throw SitesErrors.NotFound("Storage type");
        db.Entry(type).Property(t => t.Version).OriginalValue = version;
        if (await db.Set<Unit>().AnyAsync(u => u.StorageTypeId == id, cancellationToken)
            || await db.Set<UnitSize>().AnyAsync(s => s.StorageTypeId == id, cancellationToken)) throw SitesErrors.StorageTypeInUse();
        db.Remove(type);
        await db.SaveChangesAsync(cancellationToken);
    }

    private static string Required(string value) =>
        value.Trim() is { Length: > 0 } trimmed ? trimmed : throw SitesErrors.Invalid("Name cannot be blank.");

    private static string? Blank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static StorageTypeResponse Response(StorageType t) =>
        new(t.Id, t.Key, t.Name, t.DisplayName, t.IconPath, t.ImagePath, t.SortOrder, t.Active, t.Version);
}
```

`Features/Sites/Admin/UnitSizeAdminService.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Http;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Sites.Admin;

/// <summary>Each write re-maps every unit's size in the same transaction (S1-1 decision 9), so the Units page is right at once.</summary>
internal sealed class UnitSizeAdminService(AppDbContext db)
{
    private static readonly string[] Clearable = ["minAreaSqft", "maxAreaSqft", "storageTypeId"];

    public Task<PageOf<UnitSizeResponse>> ListAsync(string? search, int page, int pageSize, CancellationToken cancellationToken)
    {
        var rows = db.Set<UnitSize>().AsNoTracking();
        if (!string.IsNullOrWhiteSpace(search))
        {
            var pattern = Paging.Contains(search);
            rows = rows.Where(s => EF.Functions.ILike(s.Key, pattern) || EF.Functions.ILike(s.Label, pattern));
        }
        return Project(rows.OrderByDescending(s => s.CreatedAt).ThenByDescending(s => s.Id)).ToPageAsync(page, pageSize, cancellationToken);
    }

    public async Task<UnitSizeResponse> GetAsync(Guid id, CancellationToken cancellationToken) =>
        await Project(db.Set<UnitSize>().AsNoTracking().Where(s => s.Id == id)).SingleOrDefaultAsync(cancellationToken)
            ?? throw SitesErrors.NotFound("Unit size");

    public async Task<UnitSizeResponse> CreateAsync(CreateUnitSizeBody body, CancellationToken cancellationToken)
    {
        var size = new UnitSize
        {
            Key = body.Key!.Trim(), Label = Required(body.Label!), DisplayName = Blank(body.DisplayName), Description = Blank(body.Description),
            UnitGroup = Blank(body.UnitGroup), ImagePath = Blank(body.ImagePath), MinAreaSqft = body.MinAreaSqft, MaxAreaSqft = body.MaxAreaSqft,
            SortOrder = body.SortOrder ?? 0, StorageTypeId = body.StorageTypeId,
        };
        await SaveAndRemapAsync(size, add: true, cancellationToken);
        return await GetAsync(size.Id, cancellationToken);
    }

    public async Task<UnitSizeResponse> UpdateAsync(Guid id, UpdateUnitSizeBody body, CancellationToken cancellationToken)
    {
        var size = await db.Set<UnitSize>().SingleOrDefaultAsync(s => s.Id == id, cancellationToken) ?? throw SitesErrors.NotFound("Unit size");
        db.Entry(size).Property(s => s.Version).OriginalValue = body.Version!.Value;
        var clear = Patch.Clears(body.Clear, Clearable);
        if (body.Key is not null) size.Key = body.Key.Trim();
        if (body.Label is not null) size.Label = Required(body.Label);
        if (body.SortOrder is { } order) size.SortOrder = order;
        Patch.Value(body.MinAreaSqft, "minAreaSqft", clear, v => size.MinAreaSqft = v);
        Patch.Value(body.MaxAreaSqft, "maxAreaSqft", clear, v => size.MaxAreaSqft = v);
        Patch.Value(body.StorageTypeId, "storageTypeId", clear, v => size.StorageTypeId = v);
        Patch.Text(body.DisplayName, v => size.DisplayName = v);
        Patch.Text(body.Description, v => size.Description = v);
        Patch.Text(body.UnitGroup, v => size.UnitGroup = v);
        Patch.Text(body.ImagePath, v => size.ImagePath = v);
        await SaveAndRemapAsync(size, add: false, cancellationToken);
        return await GetAsync(id, cancellationToken);
    }

    public async Task DeleteAsync(Guid id, uint version, CancellationToken cancellationToken)
    {
        var size = await db.Set<UnitSize>().SingleOrDefaultAsync(s => s.Id == id, cancellationToken) ?? throw SitesErrors.NotFound("Unit size");
        db.Entry(size).Property(s => s.Version).OriginalValue = version;
        if (await db.Set<Unit>().AnyAsync(u => u.UnitSizeId == id, cancellationToken)) throw SitesErrors.UnitSizeInUse();
        db.Remove(size);
        await db.SaveChangesAsync(cancellationToken);
    }

    private async Task SaveAndRemapAsync(UnitSize size, bool add, CancellationToken cancellationToken)
    {
        if (size.MinAreaSqft is { } min && size.MaxAreaSqft is { } max && min > max)
            throw SitesErrors.Invalid("The minimum area must not be above the maximum.");
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        if (add) db.Add(size);
        await db.SaveChangesAsync(cancellationToken);
        await UnitSizeMap.RemapAsync(db, null, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }

    private IQueryable<UnitSizeResponse> Project(IQueryable<UnitSize> sizes) =>
        from s in sizes
        join t in db.Set<StorageType>() on s.StorageTypeId equals (Guid?)t.Id into types
        from t in types.DefaultIfEmpty()
        select new UnitSizeResponse(s.Id, s.Key, s.Label, s.DisplayName, s.Description, s.UnitGroup, s.ImagePath, s.MinAreaSqft, s.MaxAreaSqft,
            s.SortOrder, s.StorageTypeId, t == null ? null : t.Name, s.Version);

    private static string Required(string value) =>
        value.Trim() is { Length: > 0 } trimmed ? trimmed : throw SitesErrors.Invalid("Label cannot be blank.");

    private static string? Blank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
```

`Features/Sites/Admin/UnitAdminQuery.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Sites.Admin;

internal sealed class UnitAdminQuery(AppDbContext db)
{
    public Task<PageOf<UnitListItem>> ListAsync(string? search, Guid? siteId, bool? available, int page, int pageSize,
        CancellationToken cancellationToken)
    {
        var rows = db.Set<Unit>().AsNoTracking();
        if (siteId is { } site) rows = rows.Where(u => u.SiteId == site);
        if (available is { } flag) rows = rows.Where(u => u.Available == flag);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var pattern = Paging.Contains(search);
            rows = rows.Where(u => EF.Functions.ILike(u.UnitName, pattern) || (u.Description != null && EF.Functions.ILike(u.Description, pattern)));
        }
        return rows.OrderBy(u => u.UnitName).ThenBy(u => u.Id)
            .Select(u => new UnitListItem(u.Id, u.UnitName, u.SiteId, u.Site.Name, u.Site.Currency,
                u.StorageType == null ? null : u.StorageType.Name, u.UnitSize == null ? null : u.UnitSize.Label,
                u.StandardRate, u.Available, u.Rented))
            .ToPageAsync(page, pageSize, cancellationToken);
    }

    public async Task<UnitResponse> GetAsync(Guid id, CancellationToken cancellationToken) =>
        await db.Set<Unit>().AsNoTracking().Where(u => u.Id == id)
            .Select(u => new UnitResponse(u.Id, u.UnitName, u.SiteId, u.Site.Name, u.Site.Currency,
                u.StorageType == null ? null : u.StorageType.Name, u.UnitSize == null ? null : u.UnitSize.Label,
                u.Width, u.Length, u.AreaSqft, u.Floor, u.Climate, u.StandardRate, u.WebRate, u.Rented, u.Available, u.DeletedAt, u.LastSyncedAt))
            .SingleOrDefaultAsync(cancellationToken) ?? throw SitesErrors.NotFound("Unit");

    public Task<List<UnitSyncStatus>> SyncStatusAsync(CancellationToken cancellationToken) =>
        (from s in db.Set<Site>().AsNoTracking()
         join st in db.Set<UnitSyncState>() on s.Id equals st.SiteId into states
         from st in states.DefaultIfEmpty()
         orderby s.LocationCode
         select new UnitSyncStatus(s.Id, s.LocationCode, s.Name, s.Active, db.Set<Unit>().Count(u => u.SiteId == s.Id),
             st == null ? null : st.LastSyncedAt, st == null ? null : st.LastAttemptAt, st == null ? null : st.LastError))
        .ToListAsync(cancellationToken);
}
```

`Features/Sites/Admin/UnitRefreshRequests.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using Hangfire;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Sites.Admin;

/// <summary>Staff "Sync now" / "Full resync": queued, not awaited (a pull can take a minute). The result shows on the Units page.</summary>
internal sealed partial class UnitRefreshRequests(AppDbContext db, IBackgroundJobClient jobs, ILogger<UnitRefreshRequests> logger)
{
    public async Task StartAsync(Guid siteId, bool full, CancellationToken cancellationToken)
    {
        var code = await db.Set<Site>().Where(s => s.Id == siteId).Select(s => s.LocationCode).SingleOrDefaultAsync(cancellationToken)
            ?? throw SitesErrors.NotFound("Site");
        var mode = full ? UnitRefreshMode.Full : UnitRefreshMode.Incremental;
        jobs.Enqueue<UnitRefreshJob>(job => job.RefreshSiteAsync(siteId, mode, CancellationToken.None));
        LogRequested(logger, code, mode);
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "Unit refresh of {siteCode} ({mode}) requested by staff")]
    private static partial void LogRequested(ILogger logger, string siteCode, UnitRefreshMode mode);
}
```

- [ ] **Step 6: Implement the endpoints**

`Features/Sites/Admin/SitesAdminEndpoints.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;

namespace ExtraSpace.Api.Features.Sites.Admin;

internal static class SitesAdminEndpoints
{
    // Reads: any staff (S1 spec §11.3). Writes and sync: sites.manage.
    public static RouteGroupBuilder MapSitesAdminEndpoints(this RouteGroupBuilder admin)
    {
        var sites = admin.MapGroup("").WithTags("Sites");
        sites.MapGet("/sites", ListSites);
        sites.MapGet("/sites/{id:guid}", GetSite);
        sites.MapPost("/sites", CreateSite).RequireAuthorization(SitesPermissions.Manage);
        sites.MapPatch("/sites/{id:guid}", UpdateSite).RequireAuthorization(SitesPermissions.Manage);
        sites.MapDelete("/sites/{id:guid}", DeleteSite).RequireAuthorization(SitesPermissions.Manage);

        var types = admin.MapGroup("").WithTags("Storage types");
        types.MapGet("/storage-types", ListTypes);
        types.MapGet("/storage-types/{id:guid}", GetStorageType);
        types.MapPost("/storage-types", CreateType).RequireAuthorization(SitesPermissions.Manage);
        types.MapPatch("/storage-types/{id:guid}", UpdateType).RequireAuthorization(SitesPermissions.Manage);
        types.MapDelete("/storage-types/{id:guid}", DeleteType).RequireAuthorization(SitesPermissions.Manage);

        var sizes = admin.MapGroup("").WithTags("Unit sizes");
        sizes.MapGet("/unit-sizes", ListSizes);
        sizes.MapGet("/unit-sizes/{id:guid}", GetSize);
        sizes.MapPost("/unit-sizes", CreateSize).RequireAuthorization(SitesPermissions.Manage);
        sizes.MapPatch("/unit-sizes/{id:guid}", UpdateSize).RequireAuthorization(SitesPermissions.Manage);
        sizes.MapDelete("/unit-sizes/{id:guid}", DeleteSize).RequireAuthorization(SitesPermissions.Manage);

        var units = admin.MapGroup("").WithTags("Units");
        units.MapGet("/units", ListUnits);
        units.MapGet("/units/{id:guid}", GetUnit);
        units.MapGet("/unit-sync", SyncStatus);
        units.MapPost("/sites/{id:guid}/unit-sync", StartSync).RequireAuthorization(SitesPermissions.Manage);
        return admin;
    }

    private static async Task<Ok<PageOf<SiteListItem>>> ListSites(SiteAdminService service, CancellationToken cancellationToken,
        string? search = null, int page = 1, int pageSize = Paging.DefaultPageSize) =>
        TypedResults.Ok(await service.ListAsync(search, page, pageSize, cancellationToken));

    private static async Task<Ok<SiteResponse>> GetSite(Guid id, SiteAdminService service, CancellationToken cancellationToken) =>
        TypedResults.Ok(await service.GetAsync(id, cancellationToken));

    private static async Task<Created<SiteResponse>> CreateSite(CreateSiteBody body, SiteAdminService service, CancellationToken cancellationToken) =>
        TypedResults.Created((string?)null, await service.CreateAsync(body, cancellationToken));

    private static async Task<Ok<SiteResponse>> UpdateSite(Guid id, UpdateSiteBody body, SiteAdminService service, CancellationToken cancellationToken) =>
        TypedResults.Ok(await service.UpdateAsync(id, body, cancellationToken));

    private static async Task<NoContent> DeleteSite(Guid id, [FromQuery] uint version, SiteAdminService service, CancellationToken cancellationToken)
    {
        await service.DeleteAsync(id, version, cancellationToken);
        return TypedResults.NoContent();
    }

    private static async Task<Ok<PageOf<StorageTypeResponse>>> ListTypes(StorageTypeAdminService service, CancellationToken cancellationToken,
        string? search = null, int page = 1, int pageSize = Paging.DefaultPageSize) =>
        TypedResults.Ok(await service.ListAsync(search, page, pageSize, cancellationToken));

    private static async Task<Ok<StorageTypeResponse>> GetStorageType(Guid id, StorageTypeAdminService service, CancellationToken cancellationToken) =>
        TypedResults.Ok(await service.GetAsync(id, cancellationToken));

    private static async Task<Created<StorageTypeResponse>> CreateType(CreateStorageTypeBody body, StorageTypeAdminService service, CancellationToken cancellationToken) =>
        TypedResults.Created((string?)null, await service.CreateAsync(body, cancellationToken));

    private static async Task<Ok<StorageTypeResponse>> UpdateType(Guid id, UpdateStorageTypeBody body, StorageTypeAdminService service, CancellationToken cancellationToken) =>
        TypedResults.Ok(await service.UpdateAsync(id, body, cancellationToken));

    private static async Task<NoContent> DeleteType(Guid id, [FromQuery] uint version, StorageTypeAdminService service, CancellationToken cancellationToken)
    {
        await service.DeleteAsync(id, version, cancellationToken);
        return TypedResults.NoContent();
    }

    private static async Task<Ok<PageOf<UnitSizeResponse>>> ListSizes(UnitSizeAdminService service, CancellationToken cancellationToken,
        string? search = null, int page = 1, int pageSize = Paging.DefaultPageSize) =>
        TypedResults.Ok(await service.ListAsync(search, page, pageSize, cancellationToken));

    private static async Task<Ok<UnitSizeResponse>> GetSize(Guid id, UnitSizeAdminService service, CancellationToken cancellationToken) =>
        TypedResults.Ok(await service.GetAsync(id, cancellationToken));

    private static async Task<Created<UnitSizeResponse>> CreateSize(CreateUnitSizeBody body, UnitSizeAdminService service, CancellationToken cancellationToken) =>
        TypedResults.Created((string?)null, await service.CreateAsync(body, cancellationToken));

    private static async Task<Ok<UnitSizeResponse>> UpdateSize(Guid id, UpdateUnitSizeBody body, UnitSizeAdminService service, CancellationToken cancellationToken) =>
        TypedResults.Ok(await service.UpdateAsync(id, body, cancellationToken));

    private static async Task<NoContent> DeleteSize(Guid id, [FromQuery] uint version, UnitSizeAdminService service, CancellationToken cancellationToken)
    {
        await service.DeleteAsync(id, version, cancellationToken);
        return TypedResults.NoContent();
    }

    private static async Task<Ok<PageOf<UnitListItem>>> ListUnits(UnitAdminQuery query, CancellationToken cancellationToken,
        string? search = null, Guid? siteId = null, bool? available = null, int page = 1, int pageSize = Paging.DefaultPageSize) =>
        TypedResults.Ok(await query.ListAsync(search, siteId, available, page, pageSize, cancellationToken));

    private static async Task<Ok<UnitResponse>> GetUnit(Guid id, UnitAdminQuery query, CancellationToken cancellationToken) =>
        TypedResults.Ok(await query.GetAsync(id, cancellationToken));

    private static async Task<Ok<List<UnitSyncStatus>>> SyncStatus(UnitAdminQuery query, CancellationToken cancellationToken) =>
        TypedResults.Ok(await query.SyncStatusAsync(cancellationToken));

    private static async Task<Accepted> StartSync(Guid id, UnitSyncBody body, UnitRefreshRequests requests, CancellationToken cancellationToken)
    {
        await requests.StartAsync(id, body.Full, cancellationToken);
        return TypedResults.Accepted((string?)null);
    }
}
```

`SitesSetup.AddSitesFeature` grows to:

```csharp
    public static IServiceCollection AddSitesFeature(this IServiceCollection services)
    {
        services.AddPermissions(new Permission(SitesPermissions.Manage, "Edit sites, storage types and unit sizes, and start unit syncs"));
        services.AddScoped<UnitRefreshService>();
        services.AddScoped<SiteAdminService>();
        services.AddScoped<StorageTypeAdminService>();
        services.AddScoped<UnitSizeAdminService>();
        services.AddScoped<UnitAdminQuery>();
        services.AddScoped<UnitRefreshRequests>();
        services.AddRecurringJob<UnitRefreshJob>(UnitRefreshJob.Name, UnitRefreshJob.Cron);
        return services;
    }
```

(`Permission` and `AddPermissions` come from `Features.Admin.Contracts`, which the architecture rule allows.)

`Program.cs`, step 14: `admin.MapSitesAdminEndpoints();` right after `admin.MapAdminEndpoints();`.

- [ ] **Step 7: Run the tests, then update the OpenAPI snapshot**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*SitesAdminTests"`, `"*TaxonomyAdminTests"`, `"*UnitsAdminTests"`, `"*ArchitectureTests"`, `"*ApiDocsTests"`.
Then: `UPDATE_OPENAPI=1 dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*OpenApiSnapshotTests"`, and read the `admin-ui/openapi.json` diff:
- the new paths
- `FacilityType` as a string enum
- the `PageOf…` schema names
- `version` typed as integer

Expected: all green. `ApiDocsTests` guards every enum in the document.

- [ ] **Step 8: Run the whole suite**

Run: `dotnet build` (0 errors), then `dotnet test tests/ExtraSpace.Api.Tests` and `dotnet test tests/ExtraSpace.Engines.Tests`.
Expected: everything passes. Report the counts.

- [ ] **Step 9: Stop and report** (no commit).

---

### Task 8: Infra — SiteLink secret, settings and alarms (devops agent)

**Files:**
- Modify: `infra/ExtraSpace.Infra/EnvConfig.cs`, `infra/ExtraSpace.Infra/Stacks/AppStack.cs`, `infra/ExtraSpace.Infra/Stacks/Observability.cs`
- Test: `tests/ExtraSpace.Infra.Tests/AppStackTests.cs`, `tests/ExtraSpace.Infra.Tests/ObservabilityTests.cs`

**Interfaces:**
- Consumes these exact app setting names (Task 4):
  - `SiteLink__CorpCode`, `SiteLink__CorpUserName`, `SiteLink__CorpPassword`, `SiteLink__ApiKey`
  - `SiteLink__WriteAllowList__0`, `SiteLink__AllowWritesToAllSites`, `SiteLink__MonthlyCallAlarm`
- Consumes these exact log templates (Tasks 2 and 4):
  - `Outbox message {outboxId} of kind {kind} failed permanently after {attempt} attempts`
  - `SiteLink calls this month reached {total}, past the alarm level {alarm}`
- Produces:
  - the secret `es/<env>/sitelink` (JSON keys `CorpCode`, `CorpUserName`, `CorpPassword`, `ApiKey`, created with empty values)
  - alarms `es-<env>-outbox-failed` and `es-<env>-sitelink-monthly-calls`

Rules for this task:
- 🔴 No `cdk deploy`, and no AWS command of any kind. Code and infra tests only; the owner deploys (built-so-far, S0-6).
- Offline synth only, with the S0-1 environment (`AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null CDK_DEFAULT_ACCOUNT=123456789012`).
- The infra tests are structural. Add each new variable, secret and alarm to the expected sets **on purpose**; never loosen an assertion.

- [ ] **Step 1: Write the failing tests**

In `AppStackTests.cs`, extend the exact expected sets for both task definitions (`api` and `jobs`):
- The secrets gain `SiteLink__ApiKey`, `SiteLink__CorpCode`, `SiteLink__CorpPassword` and `SiteLink__CorpUserName`. Each is a `ValueFrom` of the `es/<env>/sitelink` secret ARN with its JSON key.
- On staging the environment gains `SiteLink__WriteAllowList__0` = `LSETUP`. On production it gains `SiteLink__AllowWritesToAllSites` = `true`. `SiteLink__MonthlyCallAlarm` appears only when `EnvConfig.SiteLinkMonthlyCallAlarm > 0` (both are 0 today, so it is absent).
- A new assertion: a `AWS::SecretsManager::Secret` named `es/<env>/sitelink`, whose `GenerateSecretString.SecretStringTemplate` is `{"CorpCode":"","CorpUserName":"","CorpPassword":"","ApiKey":""}`, and whose deletion policy is `Retain` on production. Staging follows whatever the existing `removal` policy gives the signing-key secret.
- Add the execution role's read of the new secret to the role's exact (action → resource) set.

In `ObservabilityTests.cs`, add two metric filters per log group and two alarms:
- `OutboxFailedPermanently` with pattern `{ $.messageTemplate = "Outbox message {outboxId} of kind {kind} failed permanently after {attempt} attempts" }`, and alarm `es-<env>-outbox-failed` (≥ 1 in 5 minutes).
- `SiteLinkMonthlyCalls` with pattern `{ $.messageTemplate = "SiteLink calls this month reached {total}, past the alarm level {alarm}" }`, and alarm `es-<env>-sitelink-monthly-calls` (≥ 1 in 60 minutes).

- [ ] **Step 2: Run and watch them fail**

Run: `dotnet test tests/ExtraSpace.Infra.Tests -- --filter-class "*AppStackTests"` and `"*ObservabilityTests"`.

- [ ] **Step 3: Implement**

`EnvConfig`: add `string[] SiteLinkWriteAllowList`, `bool SiteLinkAllowAllWrites` and `long SiteLinkMonthlyCallAlarm`.
- Staging: `["LSETUP"]`, `false`, `0`.
- Production: `[]`, `true`, `0`.
- Comment on the alarm field: "the owner sets it once SiteLink states the monthly limit (S1 spec open item 6)".

`AppStack`, next to the signing key:

```csharp
        // Created empty; the owner puts the SiteLink login in by hand (never in this repo). GenerateSecretString only fills a
        // value at creation, so a later deploy never overwrites what the owner stored.
        var siteLink = new Secret(this, "SiteLink", new SecretProps
        {
            SecretName = $"es/{env}/sitelink",
            Description = $"SiteLink CCWs login ({env})",
            GenerateSecretString = new SecretStringGenerator
            {
                SecretStringTemplate = "{\"CorpCode\":\"\",\"CorpUserName\":\"\",\"CorpPassword\":\"\",\"ApiKey\":\"\"}",
                GenerateStringKey = "Unused",
                ExcludePunctuation = true,
            },
            RemovalPolicy = removal,
        });
```

The template plus `GenerateStringKey` also writes an `Unused` key. If the test must pin the exact JSON, it pins the template, not the generated value. Add to `secrets`:

```csharp
            ["SiteLink__ApiKey"] = EcsSecret.FromSecretsManager(siteLink, "ApiKey"),
            ["SiteLink__CorpCode"] = EcsSecret.FromSecretsManager(siteLink, "CorpCode"),
            ["SiteLink__CorpPassword"] = EcsSecret.FromSecretsManager(siteLink, "CorpPassword"),
            ["SiteLink__CorpUserName"] = EcsSecret.FromSecretsManager(siteLink, "CorpUserName"),
```

and to `settings`:

```csharp
        AddList(settings, "SiteLink__WriteAllowList", config.SiteLinkWriteAllowList);
        if (config.SiteLinkAllowAllWrites) settings["SiteLink__AllowWritesToAllSites"] = "true";
        if (config.SiteLinkMonthlyCallAlarm > 0) settings["SiteLink__MonthlyCallAlarm"] = config.SiteLinkMonthlyCallAlarm.ToString(CultureInfo.InvariantCulture);
```

`Observability`, following the `jobsFailed` pattern:

```csharp
        var outboxFailed = LogMetric(props.LogGroups, "OutboxFailedPermanently",
            "{ $.messageTemplate = \"Outbox message {outboxId} of kind {kind} failed permanently after {attempt} attempts\" }");
        var siteLinkMonthly = LogMetric(props.LogGroups, "SiteLinkMonthlyCalls",
            "{ $.messageTemplate = \"SiteLink calls this month reached {total}, past the alarm level {alarm}\" }");
        // …
        Alarm("outbox-failed", outboxFailed(5), 1, 1, ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD, "an outbox step used up its retries (Needs attention)");
        Alarm("sitelink-monthly-calls", siteLinkMonthly(60), 1, 1, ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD, "SiteLink calls this month passed SiteLink:MonthlyCallAlarm");
```

The SiteLink call line already feeds the existing `OutsideCallFailures` metric: Task 4 logs `integration = "sitelink"` and every outcome other than `"ok"`.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `dotnet test tests/ExtraSpace.Infra.Tests` (all), then an offline `cdk synth EsApp-staging` with the S0-1 environment. Expected: green, and the synth contains the new secret and the env names.

- [ ] **Step 5: Stop and report** (no commit). The report includes the owner's runbook line, as a command for them to run (not run by the agent): fill the secret from a local file with `aws secretsmanager put-secret-value --secret-id es/staging/sitelink --secret-string file://<file> --profile extraspace`, and delete the file after. The values never pass through chat.

---

### Task 9: Admin UI shell — grouped sidebar and the two page templates

**Files:**
- Modify:
  - `admin-ui/src/app/nav.ts`, `admin-ui/src/app/Shell.tsx`, `admin-ui/src/components/DataTable.tsx`, `admin-ui/src/lib/forms.ts`
  - `admin-ui/src/features/staff/StaffPage.tsx` (title "Admin Users"), `admin-ui/src/features/audit/AuditPage.tsx` (title "Audit Log")
  - the tests that read those titles or nav labels (grep `'Staff'`, `'Audit log'`)
- Create:
  - `admin-ui/src/components/Pagination.tsx`, `ListPage.tsx`, `RecordPage.tsx`, `RecordFields.tsx`, `RecordEditor.tsx`, `cells.tsx`
  - `admin-ui/src/lib/list.ts`, `money.ts`, `zod-fields.ts`
- Test: `admin-ui/src/app/App.test.tsx`, `admin-ui/src/lib/forms.test.ts`, `admin-ui/src/lib/money.test.ts`, `admin-ui/src/components/Pagination.test.tsx`

**Interfaces:**
- Produces (used by Tasks 10–11):
  - `ListPage<T>` props `{ title, noun, singular, list, query, columns, rowId, rowLabel, rowTo, searchable?, filters?, newTo?, onDelete?, actions?, children? }`
  - `RecordEditor<R, V>` props `{ backTo, backLabel, title, record?, schema, defaults, fields, numberFields?, clearable?, canWrite, create(body), update(id, body) }`
  - `RecordPage` `{ backTo, backLabel, title, readOnly?, children }`
  - `FieldSpec<V>` `{ name, label, kind?: 'text'|'textarea'|'number'|'checkbox'|'select', required?, options?, readOnly?, help? }`
  - `useListParams(filterNames)` → `{ page, search, filters, setPage, setSearch, setFilter }`
  - `formatMoney(amount, currency)`
  - `patchBody(changed, numberFields, clearable)`, `createBody(values, numberFields)`, `numberText(n)`
  - `optionalNumber(min, max)`, `requiredNumber(min, max)`, `wholeNumber()`
  - `Dash`, `YesNo`, `StatusBadge`
  - `DataTable` gains `onRowClick?` and `rowActions?`

- [ ] **Step 1: Write the failing tests**

`admin-ui/src/lib/forms.test.ts` (add):

```ts
import { createBody, numberText, patchBody } from './forms'

describe('patchBody', () => {
  it('sends text as typed, numbers as numbers and emptied clearable numbers in clear', () => {
    expect(patchBody({ name: 'A', displayName: '', latitude: '', taxPercentage: '7.5', sortOrder: '' },
      ['latitude', 'taxPercentage', 'sortOrder'], ['latitude']))
      .toEqual({ name: 'A', displayName: '', taxPercentage: 7.5, clear: ['latitude'] })
  })
  it('leaves clear out when nothing is cleared', () => {
    expect(patchBody({ city: 'KL' }, [], [])).toEqual({ city: 'KL' })
  })
})

describe('createBody', () => {
  it('drops empty text so the server defaults apply, and converts numbers', () => {
    expect(createBody({ name: 'A', timeZone: '', taxPercentage: '9', active: true }, ['taxPercentage']))
      .toEqual({ name: 'A', taxPercentage: 9, active: true })
  })
})

it('numberText shows a stored number as form text', () => {
  expect(numberText(null)).toBe('')
  expect(numberText(1.25)).toBe('1.25')
})
```

`admin-ui/src/lib/money.test.ts`:

```ts
import { formatMoney } from './money'

describe('formatMoney', () => {
  it('uses the currency places: cents for SGD and MYR, none for KRW', () => {
    expect(formatMoney(1234.5, 'SGD')).toMatch(/1,234\.50$/)
    expect(formatMoney(99, 'MYR')).toMatch(/99\.00$/)
    expect(formatMoney(1234.5, 'KRW')).toMatch(/1,235$/)
  })
  it('shows a dash for no amount', () => {
    expect(formatMoney(null, 'SGD')).toBe('—')
  })
})
```

`admin-ui/src/components/Pagination.test.tsx`:

```tsx
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Pagination } from './Pagination'

it('shows start–end of total and pages forward', async () => {
  const onPage = vi.fn()
  render(<Pagination page={2} pageSize={20} total={45} onPage={onPage} />)
  expect(screen.getByText('21–40 of 45')).toBeInTheDocument()
  await userEvent.click(screen.getByRole('button', { name: 'Next' }))
  expect(onPage).toHaveBeenCalledWith(3)
})

it('disables Next on the last page', () => {
  render(<Pagination page={3} pageSize={20} total={45} onPage={() => {}} />)
  expect(screen.getByText('41–45 of 45')).toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Next' })).toBeDisabled()
})
```

In `admin-ui/src/app/App.test.tsx`, add:

```tsx
it('groups the sidebar like the demo and hides what the staff member may not use', async () => {
  renderApp('/admin/')
  const nav = within(await screen.findByRole('navigation'))
  expect(nav.getByText('Platform')).toBeInTheDocument()
  expect(nav.getByText('Access Control')).toBeInTheDocument()
  const platform = ['Sites', 'Storage Types', 'Unit Sizes', 'Units']
  const access = ['Admin Users', 'Audit Log', 'Jobs', 'Roles']
  const labels = nav.getAllByRole('link').map((link) => link.textContent)
  expect(labels).toEqual(['Dashboard', ...platform, ...access])
})

it('shows only the allowed Access Control items to a non-Owner', async () => {
  renderApp('/admin/', { me: staffMe })   // staff.manage only
  const nav = within(await screen.findByRole('navigation'))
  expect(nav.getByText('Admin Users')).toBeInTheDocument()
  expect(nav.queryByText('Roles')).not.toBeInTheDocument()
  expect(nav.getByText('Sites')).toBeInTheDocument()   // Platform pages are readable by any staff member
})
```

- [ ] **Step 2: Run and watch them fail**

Run (in `admin-ui/`): `npm test`.

- [ ] **Step 3: Implement the helpers**

`admin-ui/src/lib/forms.ts`, add:

```ts
/** A stored number as form text ('' for none). */
export function numberText(value: number | null | undefined): string {
  return value === null || value === undefined ? '' : String(value)
}

/**
 * A PATCH body from the changed fields (S1-1 decision 12): text as typed ('' clears it on the server), numbers converted, an
 * emptied clearable number or link named in `clear`. An emptied number that cannot be cleared is left unchanged.
 */
export function patchBody(changed: Record<string, unknown>, numberFields: readonly string[], clearable: readonly string[]) {
  const body: Record<string, unknown> = {}
  const clear: string[] = []
  for (const [name, value] of Object.entries(changed)) {
    if (value === '' && clearable.includes(name)) clear.push(name)
    else if (numberFields.includes(name)) { if (value !== '') body[name] = Number(value) }
    else body[name] = value
  }
  if (clear.length > 0) body.clear = clear
  return body
}

/** A POST body: empty text left out (the server applies its defaults), numbers converted. */
export function createBody(values: Record<string, unknown>, numberFields: readonly string[]) {
  const body: Record<string, unknown> = {}
  for (const [name, value] of Object.entries(values)) {
    if (value === '') continue
    body[name] = numberFields.includes(name) ? Number(value) : value
  }
  return body
}
```

`admin-ui/src/lib/money.ts`:

```ts
const places: Record<string, number> = { SGD: 2, MYR: 2, KRW: 0 }

/** An amount in its own currency, with that currency's places (KRW has none); "—" when there is none. */
export function formatMoney(amount: number | null | undefined, currency: string): string {
  if (amount === null || amount === undefined) return '—'
  const digits = places[currency] ?? 2
  return new Intl.NumberFormat('en-SG', { style: 'currency', currency, minimumFractionDigits: digits, maximumFractionDigits: digits }).format(amount)
}
```

`admin-ui/src/lib/zod-fields.ts`:

```ts
import { z } from 'zod'

const inRange = (value: string, min: number, max: number) => Number.isFinite(Number(value)) && Number(value) >= min && Number(value) <= max

/** Number inputs stay text in the form (an empty box is ''); the page converts them when it builds the body. */
export function optionalNumber(min: number, max: number) {
  return z.string().trim().refine((value) => value === '' || inRange(value, min, max), `Enter a number from ${min} to ${max}.`)
}

export function requiredNumber(min: number, max: number) {
  return z.string().trim().min(1, 'Required.').refine((value) => inRange(value, min, max), `Enter a number from ${min} to ${max}.`)
}

export function wholeNumber() {
  return z.string().trim().refine((value) => value === '' || Number.isInteger(Number(value)), 'Enter a whole number.')
}
```

`admin-ui/src/lib/list.ts`:

```ts
import { useCallback } from 'react'
import { useSearchParams } from 'react-router'

/** List state lives in the address (Back and reload keep it). A new search or filter starts again at page 1. */
export function useListParams<F extends string = never>(filterNames: readonly F[] = []) {
  const [params, setParams] = useSearchParams()
  const page = Math.max(1, Number(params.get('page')) || 1)
  const search = params.get('search') ?? ''
  const filters = Object.fromEntries(filterNames.map((name) => [name, params.get(name) ?? ''])) as Record<F, string>

  const update = useCallback((changes: Record<string, string | number>) => {
    setParams((current) => {
      const next = new URLSearchParams(current)
      for (const [key, value] of Object.entries(changes)) {
        if (value === '' || (key === 'page' && value === 1)) next.delete(key)
        else next.set(key, String(value))
      }
      if (!('page' in changes)) next.delete('page')
      return next
    }, { replace: true })
  }, [setParams])

  const setPage = useCallback((value: number) => update({ page: value }), [update])
  const setSearch = useCallback((value: string) => update({ search: value }), [update])
  const setFilter = useCallback((name: F, value: string) => update({ [name]: value }), [update])
  return { page, search, filters, setPage, setSearch, setFilter }
}
```

- [ ] **Step 4: Implement the components**

`admin-ui/src/components/cells.tsx`:

```tsx
import { Badge } from '@/components/ui/badge'

/** The demo's cell rules (S1 research crosscutting §1.1): empty = grey dash, booleans = Yes/No badge, statuses = badge. */
export function Dash({ value }: { value: string | number | null | undefined }) {
  return value === null || value === undefined || value === '' ? <span className="text-muted-foreground">—</span> : <>{value}</>
}

export function YesNo({ value }: { value: boolean }) {
  return <Badge variant={value ? 'default' : 'secondary'}>{value ? 'Yes' : 'No'}</Badge>
}

export function StatusBadge({ value }: { value: string }) {
  return <Badge variant="outline">{value}</Badge>
}
```

`admin-ui/src/components/DataTable.tsx`: export the `Columns` type and add `onRowClick` and `rowActions`:

```tsx
export type Columns<T extends RowData> = TableOptions<typeof features, T>['columns']

type Props<T extends RowData> = {
  columns: Columns<T>
  data: T[]
  rowId: (row: T) => string
  empty?: ReactNode
  /** Row click (and Enter on a focused row) opens the record. */
  onRowClick?: (row: T) => void
  /** A trailing cell per row (buttons); its clicks never reach onRowClick. */
  rowActions?: (row: T) => ReactNode
}

export function DataTable<T extends RowData>({ columns, data, rowId, empty, onRowClick, rowActions }: Props<T>) {
  const table = useTable({ features, columns, data, getRowId: rowId })
  const rows = table.getRowModel().rows
  const width = table.getAllColumns().length + (rowActions ? 1 : 0)
  return (
    <div className="rounded-xl border bg-card">
      <Table>
        <TableHeader>
          {table.getHeaderGroups().map((group) => (
            <TableRow key={group.id}>
              {group.headers.map((header) => (
                <TableHead key={header.id}>{header.isPlaceholder ? null : <table.FlexRender header={header} />}</TableHead>
              ))}
              {rowActions ? <TableHead><span className="sr-only">Actions</span></TableHead> : null}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {rows.length === 0 ? (
            empty ? (
              <TableRow>
                <TableCell colSpan={width} className="py-10 text-center text-sm text-muted-foreground">{empty}</TableCell>
              </TableRow>
            ) : null
          ) : (
            rows.map((row) => (
              <TableRow
                key={row.id}
                className={onRowClick ? 'cursor-pointer' : undefined}
                tabIndex={onRowClick ? 0 : undefined}
                onClick={onRowClick ? () => onRowClick(row.original) : undefined}
                onKeyDown={onRowClick ? (event) => { if (event.key === 'Enter') onRowClick(row.original) } : undefined}
              >
                {row.getAllCells().map((cell) => (
                  <TableCell key={cell.id}><table.FlexRender cell={cell} /></TableCell>
                ))}
                {rowActions ? (
                  <TableCell className="text-right" onClick={(event) => event.stopPropagation()} onKeyDown={(event) => event.stopPropagation()}>
                    {rowActions(row.original)}
                  </TableCell>
                ) : null}
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
    </div>
  )
}
```

`admin-ui/src/components/Pagination.tsx`:

```tsx
import { Button } from '@/components/ui/button'

export function Pagination({ page, pageSize, total, onPage }: { page: number; pageSize: number; total: number; onPage: (page: number) => void }) {
  const start = total === 0 ? 0 : (page - 1) * pageSize + 1
  const end = Math.min(page * pageSize, total)
  return (
    <div className="flex items-center justify-between text-sm text-muted-foreground">
      <span>{start}–{end} of {total}</span>
      <div className="flex gap-2">
        <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => onPage(page - 1)}>Previous</Button>
        <Button variant="outline" size="sm" disabled={end >= total} onClick={() => onPage(page + 1)}>Next</Button>
      </div>
    </div>
  )
}
```

`admin-ui/src/components/ListPage.tsx`:

```tsx
import { useEffect, useState, type ReactNode } from 'react'
import { useMutation, type UseQueryResult } from '@tanstack/react-query'
import type { RowData } from '@tanstack/react-table'
import { Plus, Trash2 } from 'lucide-react'
import { useNavigate } from 'react-router'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import { DataTable, type Columns } from '@/components/DataTable'
import { ErrorNote } from '@/components/ErrorNote'
import { PageShell } from '@/components/PageShell'
import { Pagination } from '@/components/Pagination'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

export type Page<T> = { items: T[]; total: number; page: number; pageSize: number }

type Props<T extends RowData> = {
  title: string
  /** Plural, lower case ("sites"): the search placeholder and the empty state. */
  noun: string
  /** Singular, lower case ("site"): the delete question. */
  singular: string
  list: { search: string; setSearch: (value: string) => void; setPage: (page: number) => void }
  query: UseQueryResult<Page<T>>
  columns: Columns<T>
  rowId: (row: T) => string
  rowLabel: (row: T) => string
  rowTo: (row: T) => string
  searchable?: boolean
  filters?: ReactNode
  /** Set only for staff who may write (hiding only: the server decides). */
  newTo?: string
  onDelete?: (row: T) => Promise<unknown>
  actions?: ReactNode
  children?: ReactNode
}

/** The demo's list page (S1 spec §11.1): search, filters, 20 rows, "start–end of total", row click → record page. */
export function ListPage<T extends RowData>(props: Props<T>) {
  const { title, noun, singular, list, query, columns, rowId, rowLabel, rowTo, searchable = true, filters, newTo, onDelete, actions, children } = props
  const navigate = useNavigate()
  const { search, setSearch } = list
  const [text, setText] = useState(search)
  const [target, setTarget] = useState<T | null>(null)
  const remove = useMutation({ mutationFn: (row: T) => onDelete!(row), onSuccess: () => setTarget(null) })

  // Search as you type, a moment after the last key.
  useEffect(() => {
    if (text === search) return
    const timer = setTimeout(() => setSearch(text), 300)
    return () => clearTimeout(timer)
  }, [text, search, setSearch])

  const data = query.data
  return (
    <PageShell title={title} actions={<>{actions}{newTo ? <Button onClick={() => navigate(newTo)}><Plus className="size-4" />New</Button> : null}</>}>
      {searchable || filters ? (
        <div className="flex flex-wrap items-center gap-2">
          {searchable ? (
            <Input className="max-w-xs" placeholder={`Search ${noun}…`} aria-label={`Search ${noun}`} value={text} onChange={(event) => setText(event.target.value)} />
          ) : null}
          {filters}
        </div>
      ) : null}
      {query.isError ? <ErrorNote error={query.error} /> : null}
      <DataTable
        columns={columns}
        data={data?.items ?? []}
        rowId={rowId}
        onRowClick={(row) => navigate(rowTo(row))}
        rowActions={onDelete ? (row) => (
          <Button size="icon" variant="ghost" aria-label={`Delete ${singular} ${rowLabel(row)}`} onClick={() => setTarget(row)}>
            <Trash2 className="size-4" />
          </Button>
        ) : undefined}
        empty={data ? `No ${noun} yet` : query.isPending ? 'Loading…' : null}
      />
      {data && data.total > 0 ? <Pagination page={data.page} pageSize={data.pageSize} total={data.total} onPage={list.setPage} /> : null}
      {children}
      <ConfirmDialog
        open={target !== null}
        title={`Delete ${singular}?`}
        description="This action can't be undone."
        confirmLabel="Delete"
        destructive
        pending={remove.isPending}
        error={remove.error}
        onConfirm={() => { if (target !== null) remove.mutate(target) }}
        onCancel={() => { remove.reset(); setTarget(null) }}
      />
    </PageShell>
  )
}
```

`admin-ui/src/components/RecordPage.tsx`:

```tsx
import type { ReactNode } from 'react'
import { Link } from 'react-router'

/** The demo's record page frame: "← Back to …", one card, title, the read-only note. */
export function RecordPage({ backTo, backLabel, title, readOnly, children }: { backTo: string; backLabel: string; title: string; readOnly?: boolean; children: ReactNode }) {
  return (
    <section className="max-w-2xl space-y-4">
      <Link to={backTo} className="text-sm text-muted-foreground hover:text-foreground">← Back to {backLabel}</Link>
      <div className="space-y-5 rounded-xl border bg-card p-6">
        <h1 className="text-lg font-semibold">{title}</h1>
        {readOnly ? <p className="text-sm text-muted-foreground">This record is read-only.</p> : null}
        {children}
      </div>
    </section>
  )
}
```

`admin-ui/src/components/RecordFields.tsx`:

```tsx
import type { FieldValues, Path, UseFormReturn } from 'react-hook-form'
import { FormField } from '@/components/FormField'
import { NativeSelect } from '@/components/NativeSelect'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

export type FieldSpec<V extends FieldValues> = {
  name: Path<V>
  label: string
  kind?: 'text' | 'textarea' | 'number' | 'checkbox' | 'select'
  required?: boolean
  options?: { value: string; label: string }[]
  /** Shown, never sent. */
  readOnly?: boolean
  help?: string
}

const textareaClass = 'w-full rounded-md border border-input bg-background px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring'

/** The demo's edit form: every field in its order, required ones marked with *. */
export function RecordFields<V extends FieldValues>({ form, fields }: { form: UseFormReturn<V>; fields: FieldSpec<V>[] }) {
  const errors = form.formState.errors as Record<string, { message?: string } | undefined>
  return (
    <>
      {fields.map((field) => {
        const id = `field-${field.name}`
        if (field.kind === 'checkbox') {
          return (
            <div key={field.name} className="flex items-center gap-2">
              <input id={id} type="checkbox" className="size-4" disabled={field.readOnly} {...form.register(field.name)} />
              <Label htmlFor={id}>{field.label}</Label>
            </div>
          )
        }
        const control = field.kind === 'textarea' ? (
          <textarea id={id} rows={4} className={textareaClass} readOnly={field.readOnly} {...form.register(field.name)} />
        ) : field.kind === 'select' ? (
          <NativeSelect id={id} disabled={field.readOnly} {...form.register(field.name)}>
            <option value="">— select —</option>
            {field.options?.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </NativeSelect>
        ) : (
          <Input id={id} inputMode={field.kind === 'number' ? 'decimal' : undefined} readOnly={field.readOnly} {...form.register(field.name)} />
        )
        return (
          <div key={field.name} className="space-y-1">
            <FormField label={field.required ? `${field.label} *` : field.label} htmlFor={id} error={errors[field.name]?.message}>{control}</FormField>
            {field.help ? <p className="text-xs text-muted-foreground">{field.help}</p> : null}
          </div>
        )
      })}
    </>
  )
}
```

`admin-ui/src/components/RecordEditor.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm, type DefaultValues, type FieldValues } from 'react-hook-form'
import { useNavigate } from 'react-router'
import type { z } from 'zod'
import { ApiError } from '@/api/errors'
import { ErrorNote } from '@/components/ErrorNote'
import { RecordFields, type FieldSpec } from '@/components/RecordFields'
import { RecordPage } from '@/components/RecordPage'
import { Button } from '@/components/ui/button'
import { applyServerErrors, conflictMessage, createBody, dirtyValues, patchBody } from '@/lib/forms'

type Props<R extends { id: string; version: number }, V extends FieldValues> = {
  backTo: string
  backLabel: string
  title: string
  /** Unset = a new record. Always the freshest copy: after a 409 the page reloads it. */
  record?: R
  schema: z.ZodType<V>
  defaults: V
  fields: FieldSpec<V>[]
  numberFields?: readonly string[]
  clearable?: readonly string[]
  canWrite: boolean
  create: (body: Record<string, unknown>) => Promise<unknown>
  update: (id: string, body: Record<string, unknown>) => Promise<unknown>
}

/** A record page with its form: POST for a new record, PATCH of only the changed fields + version for an edit (S1 spec §11.1). */
export function RecordEditor<R extends { id: string; version: number }, V extends FieldValues>(props: Props<R, V>) {
  const { record, fields, numberFields = [], clearable = [] } = props
  const navigate = useNavigate()
  const [failure, setFailure] = useState<unknown>(null)
  const [saving, setSaving] = useState(false)
  const form = useForm<V>({ resolver: zodResolver(props.schema), defaultValues: props.defaults as DefaultValues<V> })
  const readOnlyNames = new Set(fields.filter((f) => f.readOnly).map((f) => f.name as string))

  // After a 409 the record is reloaded: show the other person's values in the fields this user did not touch.
  const { reset } = form
  const defaultsKey = JSON.stringify(props.defaults)
  useEffect(() => {
    reset(JSON.parse(defaultsKey) as V, { keepDirtyValues: true })
  }, [reset, defaultsKey])

  async function onSubmit(values: V) {
    setFailure(null)
    setSaving(true)
    try {
      const sendable = Object.fromEntries(Object.entries(values).filter(([name]) => !readOnlyNames.has(name)))
      if (record) {
        const changed = dirtyValues(sendable, form.formState.dirtyFields as Partial<Record<string, unknown>>)
        if (Object.keys(changed).length > 0) await props.update(record.id, { ...patchBody(changed, numberFields, clearable), version: record.version })
      } else {
        await props.create(createBody(sendable, numberFields))
      }
      navigate(props.backTo)
    } catch (error) {
      if (!applyServerErrors(error, form.setError, fields.map((f) => f.name))) setFailure(error)
    } finally {
      setSaving(false)
    }
  }

  const stale = record !== undefined && failure instanceof ApiError && failure.code === 'CONFLICT'
  const readOnly = !props.canWrite
  return (
    <RecordPage backTo={props.backTo} backLabel={props.backLabel} title={props.title} readOnly={readOnly}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4" noValidate>
        <fieldset disabled={readOnly} className="space-y-4">
          <RecordFields form={form} fields={fields} />
        </fieldset>
        {stale ? <p role="alert" className="text-sm text-destructive">{conflictMessage}</p> : null}
        {failure && !stale ? <ErrorNote error={failure} /> : null}
        {readOnly ? null : (
          <div className="flex gap-2">
            <Button type="submit" disabled={saving}>{record ? 'Save changes' : 'Create'}</Button>
            <Button type="button" variant="outline" onClick={() => navigate(props.backTo)}>Cancel</Button>
          </div>
        )}
      </form>
    </RecordPage>
  )
}
```

> A record that sits in a 409 loop because someone keeps saving is fine: each failed save reloads the record and shows the message. Type friction with `zodResolver` + generic `V` is expected. Resolve it with the narrowest cast that keeps `npm run typecheck` green, and say where.

- [ ] **Step 5: The grouped sidebar**

`admin-ui/src/app/nav.ts`:

```ts
import { Box, Grid3x3, LayoutDashboard, MapPin, Maximize, ScrollText, ShieldCheck, Timer, Users, type LucideIcon } from 'lucide-react'

export type NavItem = {
  label: string
  to: string
  icon: LucideIcon
  /** Hidden without it. */
  permission?: string
  /** A page outside this app (a full page load, not a route). */
  external?: boolean
}

export type NavGroup = { label?: string; items: NavItem[] }

const byLabel = (a: NavItem, b: NavItem) => a.label.localeCompare(b.label)

/** The demo's sidebar (S1 spec §11.1): Dashboard first, then one section per group, items alphabetical inside a group. */
export const navGroups: NavGroup[] = [
  { items: [{ label: 'Dashboard', to: '/', icon: LayoutDashboard }] },
  {
    label: 'Platform',
    items: [
      { label: 'Sites', to: '/sites', icon: MapPin },
      { label: 'Storage Types', to: '/storage-types', icon: Grid3x3 },
      { label: 'Unit Sizes', to: '/unit-sizes', icon: Maximize },
      { label: 'Units', to: '/units', icon: Box },
    ].sort(byLabel),
  },
  {
    label: 'Access Control',
    items: [
      { label: 'Admin Users', to: '/staff', icon: Users, permission: 'staff.manage' },
      { label: 'Audit Log', to: '/audit', icon: ScrollText, permission: 'audit.read' },
      { label: 'Jobs', to: '/admin/jobs', icon: Timer, permission: 'jobs.manage', external: true },
      { label: 'Roles', to: '/roles', icon: ShieldCheck, permission: 'roles.manage' },
    ].sort(byLabel),
  },
]
```

In `Shell.tsx`:
- Replace `navItems` with `navGroups`.
- Render each group that still has a visible item: a small uppercase label (when the group has one), then its items, rendered the same way as today.
- Change the brand subtitle from "Admin" to "Self Storage".

```tsx
  const groups = navGroups
    .map((group) => ({ ...group, items: group.items.filter((item) => !item.permission || can(item.permission)) }))
    .filter((group) => group.items.length > 0)
  // …
        <nav className="flex-1 space-y-5 overflow-y-auto px-3 py-4">
          {groups.map((group, index) => (
            <div key={group.label ?? index} className="space-y-1">
              {group.label ? <p className="px-3 pb-1 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{group.label}</p> : null}
              {group.items.map(({ label, to, icon: Icon, external }) => /* the existing <a> / <NavLink> rendering, unchanged */)}
            </div>
          ))}
        </nav>
```

Rename the page titles: `StaffPage` "Staff" becomes "Admin Users", and `AuditPage` "Audit log" becomes "Audit Log". Fix the tests that look for the old names (grep the `admin-ui/src` tests for `'Staff'` and `'Audit log'`; change only label and title lookups).

- [ ] **Step 6: Run the checks**

Run (in `admin-ui/`): `npm run typecheck && npm test`.
Expected: green, with the S0-5 suites still passing after the renames.

- [ ] **Step 7: Stop and report** (no commit).

---

### Task 10: Admin UI — Sites, Storage Types, Unit Sizes

**Files:**
- Create:
  - `admin-ui/src/features/sites/api.ts`, `SitesPage.tsx`, `SitePage.tsx`, `SitesPage.test.tsx`
  - `admin-ui/src/features/storage-types/api.ts`, `StorageTypesPage.tsx`, `StorageTypePage.tsx`, `StorageTypesPage.test.tsx`
  - `admin-ui/src/features/unit-sizes/api.ts`, `UnitSizesPage.tsx`, `UnitSizePage.tsx`, `UnitSizesPage.test.tsx`
- Modify:
  - `admin-ui/src/app/routes.tsx` (routes `sites`, `sites/:id`, `storage-types`, `storage-types/:id`, `unit-sizes`, `unit-sizes/:id`, no guard: any staff member reads)
  - `admin-ui/src/test/data.ts` (`ownerMe.permissions` gains `'sites.manage'`)
  - `admin-ui/src/api/schema.d.ts` (generated: `npm run gen:api`)

**Interfaces:**
- Consumes: the Task 7 OpenAPI types and the Task 9 components.
- Produces: `useSiteOptions()` and `useStorageTypeOptions()` (every row, `pageSize: 100`, for selects). Task 11 uses `useSiteOptions`.

- [ ] **Step 1: Regenerate the API types**

Run (in `admin-ui/`): `npm run gen:api`. `schema.d.ts` gains the Sites, Storage types, Unit sizes and Units operations.

- [ ] **Step 2: Write the failing tests**

`admin-ui/src/features/sites/SitesPage.test.tsx`:

```tsx
import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { staffMe } from '@/test/data'
import { problem } from '@/test/problems'
import { renderApp } from '@/test/render'
import { server } from '@/test/server'

const row = { id: '0199e000-0000-7000-8000-0000000000a1', locationCode: 'LSETUP', name: 'Setup site', facilityType: 'SelfStorage', city: null, country: 'SG', active: true, version: 7 }
const site = {
  ...row, siteLinkSiteId: null, displayName: null, description: null, heroImageUrl: null, address1: null, region: null, postalCode: null,
  phone: null, latitude: 1.3, longitude: 103.8, timeZone: 'Asia/Singapore', currency: 'SGD', taxPercentage: 9, taxLabel: 'GST', stripeAccountId: null,
}

function serveList(items = [row]) {
  const queries: URLSearchParams[] = []
  server.use(http.get('*/admin/api/sites', ({ request }) => {
    const query = new URL(request.url).searchParams
    queries.push(query)
    return HttpResponse.json({ items, total: items.length, page: Number(query.get('page') ?? 1), pageSize: 20 })
  }))
  return queries
}

describe('Sites', () => {
  it('lists sites with the demo cells and the row count', async () => {
    serveList()
    renderApp('/admin/sites')
    expect(await screen.findByText('LSETUP')).toBeInTheDocument()
    expect(screen.getByText('1–1 of 1')).toBeInTheDocument()
    expect(screen.getByText('—')).toBeInTheDocument()
    expect(screen.getByText('Yes')).toBeInTheDocument()
  })

  it('searches as you type', async () => {
    const queries = serveList()
    const { user } = renderApp('/admin/sites')
    await user.type(await screen.findByLabelText('Search sites'), 'setup')
    await waitFor(() => expect(queries.at(-1)?.get('search')).toBe('setup'))
  })

  it('saves only the changed fields, clears an emptied number and sends the version', async () => {
    serveList()
    let body: unknown
    server.use(
      http.get('*/admin/api/sites/:id', () => HttpResponse.json(site)),
      http.patch('*/admin/api/sites/:id', async ({ request }) => { body = await request.json(); return HttpResponse.json(site) }),
    )
    const { user } = renderApp(`/admin/sites/${site.id}`)
    const name = await screen.findByLabelText('Name *')
    await user.clear(name)
    await user.type(name, 'New name')
    await user.clear(screen.getByLabelText('Latitude'))
    await user.click(screen.getByRole('button', { name: 'Save changes' }))
    await waitFor(() => expect(body).toEqual({ name: 'New name', clear: ['latitude'], version: 7 }))
    expect(await screen.findByText('LSETUP')).toBeInTheDocument()   // back on the list
  })

  it('tells the user when someone else saved first', async () => {
    serveList()
    server.use(
      http.get('*/admin/api/sites/:id', () => HttpResponse.json(site)),
      http.patch('*/admin/api/sites/:id', () => problem(409, 'CONFLICT', 'The record was changed by someone else.')),
    )
    const { user } = renderApp(`/admin/sites/${site.id}`)
    await user.type(await screen.findByLabelText('City'), 'Singapore')
    await user.click(screen.getByRole('button', { name: 'Save changes' }))
    expect(await screen.findByText(/Someone else changed this record/)).toBeInTheDocument()
  })

  it('creates a site with only the filled fields', async () => {
    serveList()
    let body: unknown
    server.use(http.post('*/admin/api/sites', async ({ request }) => { body = await request.json(); return HttpResponse.json(site, { status: 201 }) }))
    const { user } = renderApp('/admin/sites/new')
    await user.type(await screen.findByLabelText('Location Code *'), 'L099')
    await user.type(screen.getByLabelText('Name *'), 'Tampines')
    await user.selectOptions(screen.getByLabelText('Country *'), 'SG')
    await user.type(screen.getByLabelText('Tax % *'), '9')
    await user.click(screen.getByRole('button', { name: 'Create' }))
    await waitFor(() => expect(body).toEqual({ locationCode: 'L099', facilityType: 'SelfStorage', name: 'Tampines', country: 'SG', taxPercentage: 9, active: true }))
  })

  it('deletes after a confirm, sending the row version', async () => {
    serveList()
    let url = ''
    server.use(http.delete('*/admin/api/sites/:id', ({ request }) => { url = request.url; return new HttpResponse(null, { status: 204 }) }))
    const { user } = renderApp('/admin/sites')
    await user.click(await screen.findByRole('button', { name: 'Delete site LSETUP' }))
    await user.click(screen.getByRole('button', { name: 'Delete' }))
    await waitFor(() => expect(url).toContain(`/admin/api/sites/${row.id}?version=7`))
  })

  it('is read-only for staff without sites.manage', async () => {
    serveList()
    server.use(http.get('*/admin/api/sites/:id', () => HttpResponse.json(site)))
    renderApp('/admin/sites', { me: staffMe })
    expect(await screen.findByText('LSETUP')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'New' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Delete site/ })).not.toBeInTheDocument()
  })
})
```

`admin-ui/src/features/storage-types/StorageTypesPage.test.tsx`:

```tsx
import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { renderApp } from '@/test/render'
import { server } from '@/test/server'

const type = { id: '0199e000-0000-7000-8000-000000000001', key: 'self-storage', name: 'Self Storage', displayName: null, iconPath: null, imagePath: null, sortOrder: 1, active: true, version: 3 }

it('shows the key read-only on an edit and never sends it', async () => {
  let body: unknown
  server.use(
    http.get('*/admin/api/storage-types', () => HttpResponse.json({ items: [type], total: 1, page: 1, pageSize: 20 })),
    http.get('*/admin/api/storage-types/:id', () => HttpResponse.json(type)),
    http.patch('*/admin/api/storage-types/:id', async ({ request }) => { body = await request.json(); return HttpResponse.json(type) }),
  )
  const { user } = renderApp(`/admin/storage-types/${type.id}`)
  expect(await screen.findByLabelText('Key *')).toHaveAttribute('readonly')
  const sort = screen.getByLabelText('Sort Order')
  await user.clear(sort)
  await user.type(sort, '4')
  await user.click(screen.getByRole('button', { name: 'Save changes' }))
  await waitFor(() => expect(body).toEqual({ sortOrder: 4, version: 3 }))
})
```

`admin-ui/src/features/unit-sizes/UnitSizesPage.test.tsx`:

```tsx
import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { renderApp } from '@/test/render'
import { server } from '@/test/server'

const types = [{ id: '0199e000-0000-7000-8000-000000000001', key: 'self-storage', name: 'Self Storage', displayName: null, iconPath: null, imagePath: null, sortOrder: 1, active: true, version: 1 }]
const size = {
  id: '0199e000-0000-7000-8000-0000000000b1', key: 'small', label: 'Small', displayName: null, description: null, unitGroup: 'S', imagePath: null,
  minAreaSqft: 0, maxAreaSqft: 50, sortOrder: 1, storageTypeId: types[0].id, storageTypeName: 'Self Storage', version: 5,
}

it('clears the storage type and the max area when they are emptied', async () => {
  let body: unknown
  server.use(
    http.get('*/admin/api/storage-types', () => HttpResponse.json({ items: types, total: 1, page: 1, pageSize: 100 })),
    http.get('*/admin/api/unit-sizes', () => HttpResponse.json({ items: [size], total: 1, page: 1, pageSize: 20 })),
    http.get('*/admin/api/unit-sizes/:id', () => HttpResponse.json(size)),
    http.patch('*/admin/api/unit-sizes/:id', async ({ request }) => { body = await request.json(); return HttpResponse.json(size) }),
  )
  const { user } = renderApp(`/admin/unit-sizes/${size.id}`)
  await screen.findByDisplayValue('Small')
  await user.selectOptions(screen.getByLabelText('Storage Type'), '')
  await user.clear(screen.getByLabelText('Max Area (sq ft)'))
  await user.click(screen.getByRole('button', { name: 'Save changes' }))
  await waitFor(() => expect(body).toEqual({ clear: ['maxAreaSqft', 'storageTypeId'], version: 5 }))   // form field order
})
```

- [ ] **Step 3: Run and watch them fail**

Run (in `admin-ui/`): `npm test`.

- [ ] **Step 4: Implement the Sites feature**

`admin-ui/src/features/sites/api.ts`:

```ts
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api, call } from '@/api/client'
import { ApiError } from '@/api/errors'
import type { components } from '@/api/schema'

export type SiteListItem = components['schemas']['SiteListItem']
export type Site = components['schemas']['SiteResponse']
export type CreateSite = components['schemas']['CreateSiteBody']
export type UpdateSite = components['schemas']['UpdateSiteBody']

export const sitesKey = ['sites'] as const

export function useSites(page: number, search: string) {
  return useQuery({
    queryKey: [...sitesKey, 'list', page, search],
    queryFn: () => call(() => api.GET('/admin/api/sites', { params: { query: { page, search: search || undefined } } })),
    placeholderData: keepPreviousData,
  })
}

// shortcut: one page of 100 covers the ~24 facilities; page the select if sites ever pass 100.
export function useSiteOptions() {
  return useQuery({ queryKey: [...sitesKey, 'options'], queryFn: () => call(() => api.GET('/admin/api/sites', { params: { query: { pageSize: 100 } } })) })
}

export function useSite(id: string | undefined) {
  return useQuery({
    queryKey: [...sitesKey, 'one', id],
    enabled: id !== undefined,
    queryFn: () => call(() => api.GET('/admin/api/sites/{id}', { params: { path: { id: id! } } })),
  })
}

/** After any write, and after a 409: the list and the open record must be fresh before the next try. */
export function useSiteWrites() {
  const queryClient = useQueryClient()
  const reload = () => queryClient.invalidateQueries({ queryKey: sitesKey })
  const onError = (error: unknown) => (error instanceof ApiError && error.status === 409 ? reload() : undefined)
  return {
    create: useMutation({ mutationFn: (body: CreateSite) => call(() => api.POST('/admin/api/sites', { body })), onSuccess: reload }),
    update: useMutation({
      mutationFn: ({ id, body }: { id: string; body: UpdateSite }) => call(() => api.PATCH('/admin/api/sites/{id}', { params: { path: { id } }, body })),
      onSuccess: reload,
      onError,
    }),
    remove: useMutation({
      mutationFn: (row: SiteListItem) => call(() => api.DELETE('/admin/api/sites/{id}', { params: { path: { id: row.id }, query: { version: row.version } } })),
      onSuccess: reload,
      onError,
    }),
  }
}
```

`admin-ui/src/features/sites/SitesPage.tsx`:

```tsx
import { Dash, StatusBadge, YesNo } from '@/components/cells'
import { columnsFor } from '@/components/DataTable'
import { ListPage } from '@/components/ListPage'
import { useSession } from '@/features/auth/session'
import { useListParams } from '@/lib/list'
import { useSites, useSiteWrites, type SiteListItem } from './api'

export const facilityLabels: Record<string, string> = { SelfStorage: 'Self Storage', Workspace: 'Workspace' }

export function SitesPage() {
  const list = useListParams()
  const sites = useSites(list.page, list.search)
  const { remove } = useSiteWrites()
  const write = useSession().can('sites.manage')
  const helper = columnsFor<SiteListItem>()
  const columns = helper.columns([
    helper.accessor('locationCode', { header: 'Location Code' }),
    helper.accessor('name', { header: 'Name' }),
    helper.accessor('facilityType', { header: 'Facility Type', cell: (c) => <StatusBadge value={facilityLabels[c.getValue()] ?? c.getValue()} /> }),
    helper.accessor('city', { header: 'City', cell: (c) => <Dash value={c.getValue()} /> }),
    helper.accessor('country', { header: 'Country' }),
    helper.accessor('active', { header: 'Active', cell: (c) => <YesNo value={c.getValue()} /> }),
  ])
  return (
    <ListPage title="Sites" noun="sites" singular="site" list={list} query={sites} columns={columns}
      rowId={(s) => s.id} rowLabel={(s) => s.locationCode} rowTo={(s) => `/sites/${s.id}`}
      newTo={write ? '/sites/new' : undefined} onDelete={write ? (s) => remove.mutateAsync(s) : undefined} />
  )
}
```

`admin-ui/src/features/sites/SitePage.tsx`:

```tsx
import { useParams } from 'react-router'
import { z } from 'zod'
import { ErrorNote } from '@/components/ErrorNote'
import { RecordEditor } from '@/components/RecordEditor'
import type { FieldSpec } from '@/components/RecordFields'
import { useSession } from '@/features/auth/session'
import { numberText } from '@/lib/forms'
import { optionalNumber, requiredNumber } from '@/lib/zod-fields'
import { useSite, useSiteWrites, type CreateSite, type Site, type UpdateSite } from './api'

const countries = [{ value: 'SG', label: 'Singapore' }, { value: 'MY', label: 'Malaysia' }, { value: 'KR', label: 'Korea' }]
const facilityTypes = [{ value: 'SelfStorage', label: 'Self Storage' }, { value: 'Workspace', label: 'Workspace' }]

// The server validates again and is the authority; this only saves a round trip.
const schema = z.object({
  locationCode: z.string().trim().min(1, 'Required.').max(20, 'At most 20 characters.').regex(/^[A-Za-z0-9_-]+$/, 'Letters, digits, - and _ only.'),
  facilityType: z.enum(['SelfStorage', 'Workspace']),
  name: z.string().trim().min(1, 'Required.').max(200),
  displayName: z.string().max(200),
  description: z.string().max(4000),
  heroImageUrl: z.string().trim().max(1000).refine((v) => v === '' || v.startsWith('https://'), 'Must start with https://.'),
  address1: z.string().max(300),
  city: z.string().max(100),
  region: z.string().max(100),
  postalCode: z.string().max(20),
  country: z.enum(['SG', 'MY', 'KR'], 'Choose a country.'),
  phone: z.string().max(50),
  latitude: optionalNumber(-90, 90),
  longitude: optionalNumber(-180, 180),
  timeZone: z.string().max(64),
  taxPercentage: requiredNumber(0, 100),
  taxLabel: z.string().max(20),
  currency: z.string(),
  siteLinkSiteId: optionalNumber(1, 2147483647),
  stripeAccountId: z.string().trim().max(100).regex(/^(acct_[A-Za-z0-9]+)?$/, 'Starts with acct_.'),
  active: z.boolean(),
})
type Values = z.infer<typeof schema>

// The demo's order (SiteLink corp code dropped: it is configuration), then our additions.
const fields: FieldSpec<Values>[] = [
  { name: 'locationCode', label: 'Location Code', required: true },
  { name: 'facilityType', label: 'Facility Type', kind: 'select', options: facilityTypes },
  { name: 'name', label: 'Name', required: true },
  { name: 'displayName', label: 'Display Name' },
  { name: 'description', label: 'Description', kind: 'textarea' },
  { name: 'heroImageUrl', label: 'Hero Image URL' },
  { name: 'address1', label: 'Address' },
  { name: 'city', label: 'City' },
  { name: 'region', label: 'Region' },
  { name: 'postalCode', label: 'Postal Code' },
  { name: 'country', label: 'Country', kind: 'select', options: countries, required: true },
  { name: 'phone', label: 'Phone' },
  { name: 'latitude', label: 'Latitude', kind: 'number' },
  { name: 'longitude', label: 'Longitude', kind: 'number' },
  { name: 'timeZone', label: 'Time Zone', help: "Empty on a new site = the country's zone." },
  { name: 'taxPercentage', label: 'Tax %', kind: 'number', required: true },
  { name: 'taxLabel', label: 'Tax Label', help: "Empty on a new site = the country's (GST, SST or VAT)." },
  { name: 'currency', label: 'Currency', readOnly: true, help: 'Follows the country.' },
  { name: 'siteLinkSiteId', label: 'SiteLink Site ID', kind: 'number' },
  { name: 'stripeAccountId', label: 'Stripe Account', help: 'acct_…; empty = no in-app payments at this site.' },
  { name: 'active', label: 'Active', kind: 'checkbox' },
]
const numberFields = ['latitude', 'longitude', 'taxPercentage', 'siteLinkSiteId']
const clearable = ['latitude', 'longitude', 'siteLinkSiteId']

function values(site?: Site): Values {
  return {
    locationCode: site?.locationCode ?? '', facilityType: site?.facilityType ?? 'SelfStorage', name: site?.name ?? '',
    displayName: site?.displayName ?? '', description: site?.description ?? '', heroImageUrl: site?.heroImageUrl ?? '',
    address1: site?.address1 ?? '', city: site?.city ?? '', region: site?.region ?? '', postalCode: site?.postalCode ?? '',
    country: (site?.country ?? '') as Values['country'], phone: site?.phone ?? '',
    latitude: numberText(site?.latitude), longitude: numberText(site?.longitude), timeZone: site?.timeZone ?? '',
    taxPercentage: numberText(site?.taxPercentage), taxLabel: site?.taxLabel ?? '', currency: site?.currency ?? '—',
    siteLinkSiteId: numberText(site?.siteLinkSiteId), stripeAccountId: site?.stripeAccountId ?? '', active: site?.active ?? true,
  }
}

export function SitePage() {
  const { id } = useParams()
  const isNew = id === 'new'
  const site = useSite(isNew ? undefined : id)
  const { create, update } = useSiteWrites()
  const canWrite = useSession().can('sites.manage')
  if (!isNew && !site.data) return site.isError ? <ErrorNote error={site.error} /> : <p className="text-sm text-muted-foreground">Loading…</p>
  return (
    <RecordEditor
      backTo="/sites" backLabel="Sites" title={isNew ? 'New Site' : 'Site'} record={site.data}
      schema={schema} defaults={values(site.data)} fields={fields} numberFields={numberFields} clearable={clearable} canWrite={canWrite}
      create={(body) => create.mutateAsync(body as CreateSite)}
      update={(recordId, body) => update.mutateAsync({ id: recordId, body: body as UpdateSite })}
    />
  )
}
```

- [ ] **Step 5: Implement Storage Types and Unit Sizes**

Both features have the same shape as Sites: an `api.ts` with list, one record, options and writes; a list page; a record page. Write them in full, with these specifics.

`admin-ui/src/features/storage-types/api.ts`: the same as `sites/api.ts`, with:
- `StorageType = components['schemas']['StorageTypeResponse']`, `CreateStorageType` and `UpdateStorageType`
- key `['storage-types']`
- paths `/admin/api/storage-types` and `/admin/api/storage-types/{id}`
- `useStorageTypes(page, search)`, `useStorageTypeOptions()` (pageSize 100), `useStorageType(id)` and `useStorageTypeWrites()`

`StorageTypesPage.tsx`:
- columns Key, Name, Active (`YesNo`), Sort Order
- `noun="storage types"`, `singular="storage type"`, `rowLabel={(t) => t.key}`
- New and delete only with `sites.manage`

`StorageTypePage.tsx`:

```tsx
const schema = z.object({
  key: z.string().trim().min(1, 'Required.').max(50).regex(/^[a-z0-9-]+$/, 'Lower-case letters, digits and - only.'),
  name: z.string().trim().min(1, 'Required.').max(100),
  displayName: z.string().max(100),
  iconPath: z.string().max(500),
  imagePath: z.string().max(500),
  sortOrder: wholeNumber(),
  active: z.boolean(),
})
type Values = z.infer<typeof schema>

function fieldsFor(editing: boolean): FieldSpec<Values>[] {
  return [
    // The key cannot change once saved: the unit sync finds the two seeded types by it.
    { name: 'key', label: 'Key', required: true, readOnly: editing },
    { name: 'name', label: 'Name', required: true },
    { name: 'displayName', label: 'Display Name' },
    { name: 'iconPath', label: 'Icon Path' },
    { name: 'imagePath', label: 'Image Path' },
    { name: 'sortOrder', label: 'Sort Order', kind: 'number' },
    { name: 'active', label: 'Active', kind: 'checkbox' },
  ]
}
// numberFields ['sortOrder'], clearable [] ; defaults from the record (sortOrder via numberText), title 'New Storage Type' / 'Storage Type'.
```

`admin-ui/src/features/unit-sizes/api.ts`: the same shape, with `UnitSize = components['schemas']['UnitSizeResponse']`, key `['unit-sizes']` and paths `/admin/api/unit-sizes[/{id}]`.

`UnitSizesPage.tsx`: columns Key, Label, Unit Group (`Dash`), Sort Order.

`UnitSizePage.tsx`:

```tsx
const schema = z.object({
  key: z.string().trim().min(1, 'Required.').max(50).regex(/^[a-z0-9-]+$/, 'Lower-case letters, digits and - only.'),
  label: z.string().trim().min(1, 'Required.').max(100),
  displayName: z.string().max(100),
  description: z.string().max(1000),
  unitGroup: z.string().max(100),
  imagePath: z.string().max(500),
  minAreaSqft: optionalNumber(0, 99999999),
  maxAreaSqft: optionalNumber(0, 99999999),
  sortOrder: wholeNumber(),
  storageTypeId: z.string(),
}).refine((v) => v.minAreaSqft === '' || v.maxAreaSqft === '' || Number(v.minAreaSqft) <= Number(v.maxAreaSqft),
  { message: 'Must not be above the max area.', path: ['minAreaSqft'] })
type Values = z.infer<typeof schema>

// The page builds the storage-type options from useStorageTypeOptions().
function fieldsFor(types: { value: string; label: string }[]): FieldSpec<Values>[] {
  return [
    { name: 'key', label: 'Key', required: true },
    { name: 'label', label: 'Label', required: true },
    { name: 'displayName', label: 'Display Name' },
    { name: 'description', label: 'Description', kind: 'textarea' },
    { name: 'unitGroup', label: 'Unit Group' },
    { name: 'imagePath', label: 'Image Path' },
    { name: 'minAreaSqft', label: 'Min Area (sq ft)', kind: 'number' },
    { name: 'maxAreaSqft', label: 'Max Area (sq ft)', kind: 'number' },
    { name: 'sortOrder', label: 'Sort Order', kind: 'number' },
    { name: 'storageTypeId', label: 'Storage Type', kind: 'select', options: types, help: 'Empty = units of any type.' },
  ]
}
// numberFields ['minAreaSqft', 'maxAreaSqft', 'sortOrder']; clearable ['minAreaSqft', 'maxAreaSqft', 'storageTypeId'].
```

Wait for `useStorageTypeOptions()` before rendering the editor. Otherwise the select mounts without its options and the record's `storageTypeId` cannot be selected.

`routes.tsx`, inside `shellRoutes([...])` before the `*` route:

```tsx
  { path: 'sites', Component: SitesPage },
  { path: 'sites/:id', Component: SitePage },
  { path: 'storage-types', Component: StorageTypesPage },
  { path: 'storage-types/:id', Component: StorageTypePage },
  { path: 'unit-sizes', Component: UnitSizesPage },
  { path: 'unit-sizes/:id', Component: UnitSizePage },
```

`test/data.ts`: `ownerMe.permissions` gains `'sites.manage'`.

- [ ] **Step 6: Run the checks**

Run (in `admin-ui/`): `npm run typecheck && npm test && npm run check:api`.
Expected: green.

- [ ] **Step 7: Stop and report** (no commit).

---

### Task 11: Admin UI — Units, the SiteLink sync panel, audit record types

**Files:**
- Create: `admin-ui/src/features/units/api.ts`, `UnitsPage.tsx`, `UnitPage.tsx`, `UnitSyncPanel.tsx`, `UnitsPage.test.tsx`
- Modify: `admin-ui/src/app/routes.tsx` (`units`, `units/:id`), `admin-ui/src/features/audit/AuditPage.tsx` (record types `site`, `storage_type`, `unit_size`: read how `recordTypes` is written and add three lines in the same form, labelled "Site", "Storage Type", "Unit Size")

**Interfaces:**
- Consumes: `useSiteOptions` (Task 10), `ListPage`, `RecordPage`, `DataTable`, `ConfirmDialog`, `formatMoney`, `formatInstant`, `zoneName` (Task 9 and S0-5).

- [ ] **Step 1: Write the failing tests**

`admin-ui/src/features/units/UnitsPage.test.tsx`:

```tsx
import { screen, waitFor, within } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { staffMe } from '@/test/data'
import { renderApp } from '@/test/render'
import { server } from '@/test/server'

const siteRow = { id: '0199e000-0000-7000-8000-0000000000a1', locationCode: 'L013', name: 'Gasan', facilityType: 'SelfStorage', city: 'Seoul', country: 'KR', active: true, version: 2 }
const unit = { id: '0199e000-0000-7000-8000-0000000000c1', unitName: 'A101', siteId: siteRow.id, siteName: 'Gasan', currency: 'KRW', storageTypeName: 'Self Storage', unitSizeLabel: null, standardRate: 85000.4, available: true, rented: false }
const status = { siteId: siteRow.id, locationCode: 'L013', siteName: 'Gasan', active: true, units: 1, lastSyncedAt: null, lastAttemptAt: '2026-10-14T19:00:05Z', lastError: 'SiteLink could not be reached.' }

function serve() {
  const queries: URLSearchParams[] = []
  const syncs: unknown[] = []
  server.use(
    http.get('*/admin/api/sites', () => HttpResponse.json({ items: [siteRow], total: 1, page: 1, pageSize: 100 })),
    http.get('*/admin/api/units', ({ request }) => {
      queries.push(new URL(request.url).searchParams)
      return HttpResponse.json({ items: [unit], total: 1, page: 1, pageSize: 20 })
    }),
    http.get('*/admin/api/unit-sync', () => HttpResponse.json([status])),
    http.post('*/admin/api/sites/:id/unit-sync', async ({ request }) => { syncs.push(await request.json()); return new HttpResponse(null, { status: 202 }) }),
  )
  return { queries, syncs }
}

describe('Units', () => {
  it('lists units with the site currency and filters by site and status', async () => {
    const { queries } = serve()
    const { user } = renderApp('/admin/units')
    const table = within((await screen.findAllByRole('table'))[0])
    expect(await table.findByText('A101')).toBeInTheDocument()
    expect(table.getByText(/85,000$/)).toBeInTheDocument()   // KRW: no decimals
    await user.selectOptions(screen.getByLabelText('Site'), siteRow.id)
    await user.selectOptions(screen.getByLabelText('Status'), 'false')
    await waitFor(() => {
      expect(queries.at(-1)?.get('siteId')).toBe(siteRow.id)
      expect(queries.at(-1)?.get('available')).toBe('false')
    })
  })

  it('shows the sync state per site and starts a sync or a confirmed full resync', async () => {
    const { syncs } = serve()
    const { user } = renderApp('/admin/units')
    expect(await screen.findByText('SiteLink could not be reached.')).toBeInTheDocument()
    expect(screen.getByText('Never')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Sync now L013' }))
    await user.click(screen.getByRole('button', { name: 'Full resync L013' }))
    await user.click(screen.getByRole('button', { name: 'Start' }))
    await waitFor(() => expect(syncs).toEqual([{ full: false }, { full: true }]))
  })

  it('has no sync buttons and no New button without sites.manage', async () => {
    serve()
    renderApp('/admin/units', { me: staffMe })
    expect(await screen.findByText('SiteLink could not be reached.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Sync now/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'New' })).not.toBeInTheDocument()
  })

  it('shows a unit read-only', async () => {
    serve()
    server.use(http.get('*/admin/api/units/:id', () => HttpResponse.json({
      ...unit, width: 5, length: 10, areaSqft: 50, floor: 2, climate: true, webRate: null, deletedAt: null, lastSyncedAt: '2026-10-14T19:00:00Z',
    })))
    renderApp(`/admin/units/${unit.id}`)
    expect(await screen.findByText('This record is read-only.')).toBeInTheDocument()
    expect(screen.getByText('A101')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Save changes' })).not.toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run and watch them fail**

Run (in `admin-ui/`): `npm test`.

- [ ] **Step 3: Implement**

`admin-ui/src/features/units/api.ts`:

```ts
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { api, call } from '@/api/client'
import type { components } from '@/api/schema'

export type UnitListItem = components['schemas']['UnitListItem']
export type UnitSyncStatus = components['schemas']['UnitSyncStatus']

export function useUnits(page: number, search: string, siteId: string, available: string) {
  return useQuery({
    queryKey: ['units', 'list', page, search, siteId, available],
    queryFn: () => call(() => api.GET('/admin/api/units', { params: { query: {
      page, search: search || undefined, siteId: siteId || undefined, available: available === '' ? undefined : available === 'true',
    } } })),
    placeholderData: keepPreviousData,
  })
}

export function useUnit(id: string) {
  return useQuery({ queryKey: ['units', 'one', id], queryFn: () => call(() => api.GET('/admin/api/units/{id}', { params: { path: { id } } })) })
}

/** Re-read every 10 s while the page is open: a sync runs in the background and ends on its own. */
export function useUnitSync() {
  return useQuery({ queryKey: ['unit-sync'], queryFn: () => call(() => api.GET('/admin/api/unit-sync')), refetchInterval: 10_000 })
}

export function useStartUnitSync() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: ({ siteId, full }: { siteId: string; full: boolean }) =>
      call(() => api.POST('/admin/api/sites/{id}/unit-sync', { params: { path: { id: siteId } }, body: { full } })),
    onSuccess: () => {
      toast.success('Sync started. The table updates when it finishes.')
      return queryClient.invalidateQueries({ queryKey: ['unit-sync'] })
    },
  })
}
```

`admin-ui/src/features/units/UnitSyncPanel.tsx`:

```tsx
import { useState } from 'react'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import { Dash } from '@/components/cells'
import { columnsFor, DataTable } from '@/components/DataTable'
import { ErrorNote } from '@/components/ErrorNote'
import { Button } from '@/components/ui/button'
import { useSession } from '@/features/auth/session'
import { formatInstant, zoneName } from '@/lib/time'
import { useStartUnitSync, useUnitSync, type UnitSyncStatus } from './api'

/** QOL addition (spec §15): the last SiteLink pull per site, its error, and "Sync now" / "Full resync" for sites.manage. */
export function UnitSyncPanel() {
  const status = useUnitSync()
  const start = useStartUnitSync()
  const canSync = useSession().can('sites.manage')
  const [full, setFull] = useState<UnitSyncStatus | null>(null)
  const helper = columnsFor<UnitSyncStatus>()
  const columns = helper.columns([
    helper.accessor('locationCode', { header: 'Site', cell: (c) => `${c.getValue()} · ${c.row.original.siteName}` }),
    helper.accessor('units', { header: 'Units' }),
    helper.accessor('lastSyncedAt', { header: `Last synced (${zoneName()})`, cell: (c) => { const at = c.getValue(); return at ? formatInstant(at) : 'Never' } }),
    helper.accessor('lastError', { header: 'Last error', cell: (c) => c.getValue() ? <span className="text-destructive">{c.getValue()}</span> : <Dash value={null} /> }),
  ])
  return (
    <section className="space-y-3 pt-4">
      <h2 className="text-base font-semibold">SiteLink sync</h2>
      {status.isError ? <ErrorNote error={status.error} /> : null}
      <DataTable
        columns={columns}
        data={status.data ?? []}
        rowId={(s) => s.siteId}
        empty={status.data ? 'No sites yet' : 'Loading…'}
        rowActions={canSync ? (s) => (
          <div className="flex justify-end gap-2">
            <Button size="sm" variant="outline" disabled={start.isPending} aria-label={`Sync now ${s.locationCode}`} onClick={() => start.mutate({ siteId: s.siteId, full: false })}>Sync now</Button>
            <Button size="sm" variant="outline" aria-label={`Full resync ${s.locationCode}`} onClick={() => setFull(s)}>Full resync</Button>
          </div>
        ) : undefined}
      />
      <ConfirmDialog
        open={full !== null}
        title="Full resync?"
        description={`Pulls every unit of ${full?.locationCode ?? ''} from SiteLink again. Use it when a normal sync missed a change.`}
        confirmLabel="Start"
        pending={start.isPending}
        error={start.error}
        onConfirm={() => { if (full) start.mutate({ siteId: full.siteId, full: true }, { onSuccess: () => setFull(null) }) }}
        onCancel={() => { start.reset(); setFull(null) }}
      />
    </section>
  )
}
```

`admin-ui/src/features/units/UnitsPage.tsx`:

```tsx
import { Dash, YesNo } from '@/components/cells'
import { columnsFor } from '@/components/DataTable'
import { ListPage } from '@/components/ListPage'
import { NativeSelect } from '@/components/NativeSelect'
import { useSiteOptions } from '@/features/sites/api'
import { useListParams } from '@/lib/list'
import { formatMoney } from '@/lib/money'
import { useUnits, type UnitListItem } from './api'
import { UnitSyncPanel } from './UnitSyncPanel'

const filterNames = ['siteId', 'available'] as const

/** Read-only (S1 spec §11.2): units come from SiteLink only. No New, no delete. */
export function UnitsPage() {
  const list = useListParams(filterNames)
  const units = useUnits(list.page, list.search, list.filters.siteId, list.filters.available)
  const sites = useSiteOptions()
  const helper = columnsFor<UnitListItem>()
  const columns = helper.columns([
    helper.accessor('unitName', { header: 'Unit Name' }),
    helper.accessor('siteName', { header: 'Site' }),
    helper.accessor('storageTypeName', { header: 'Storage Type', cell: (c) => <Dash value={c.getValue()} /> }),
    helper.accessor('unitSizeLabel', { header: 'Unit Size', cell: (c) => <Dash value={c.getValue()} /> }),
    helper.accessor('standardRate', { header: 'Standard Rate', cell: (c) => formatMoney(c.getValue(), c.row.original.currency) }),
    helper.accessor('available', { header: 'Available', cell: (c) => <YesNo value={c.getValue()} /> }),
    helper.accessor('rented', { header: 'Rented', cell: (c) => <YesNo value={c.getValue()} /> }),
  ])
  return (
    <ListPage
      title="Units" noun="units" singular="unit" list={list} query={units} columns={columns}
      rowId={(u) => u.id} rowLabel={(u) => u.unitName} rowTo={(u) => `/units/${u.id}`}
      filters={
        <>
          <NativeSelect aria-label="Site" className="w-56" value={list.filters.siteId} onChange={(e) => list.setFilter('siteId', e.target.value)}>
            <option value="">All sites</option>
            {sites.data?.items.map((s) => <option key={s.id} value={s.id}>{s.locationCode} · {s.name}</option>)}
          </NativeSelect>
          <NativeSelect aria-label="Status" className="w-44" value={list.filters.available} onChange={(e) => list.setFilter('available', e.target.value)}>
            <option value="">All statuses</option>
            <option value="true">Available</option>
            <option value="false">Unavailable</option>
          </NativeSelect>
        </>
      }
    >
      <UnitSyncPanel />
    </ListPage>
  )
}
```

`admin-ui/src/features/units/UnitPage.tsx`:

```tsx
import { Fragment, type ReactNode } from 'react'
import { useParams } from 'react-router'
import { YesNo } from '@/components/cells'
import { ErrorNote } from '@/components/ErrorNote'
import { RecordPage } from '@/components/RecordPage'
import { formatMoney } from '@/lib/money'
import { formatInstant } from '@/lib/time'
import { useUnit } from './api'

/** The demo's read-only unit record (fields in its order), plus when SiteLink deleted it. */
export function UnitPage() {
  const { id } = useParams()
  const unit = useUnit(id!)
  if (!unit.data) return unit.isError ? <ErrorNote error={unit.error} /> : <p className="text-sm text-muted-foreground">Loading…</p>
  const u = unit.data
  const rows: [string, ReactNode][] = [
    ['Unit Name', u.unitName],
    ['Site', u.siteName],
    ['Storage Type', u.storageTypeName ?? '—'],
    ['Unit Size', u.unitSizeLabel ?? '—'],
    ['Width', u.width],
    ['Length', u.length],
    ['Area (sq ft)', u.areaSqft],
    ['Floor', u.floor ?? '—'],
    ['Climate', <YesNo value={u.climate} />],
    ['Standard Rate', formatMoney(u.standardRate, u.currency)],
    ['Web Rate', formatMoney(u.webRate, u.currency)],
    ['Rented', <YesNo value={u.rented} />],
    ['Available', <YesNo value={u.available} />],
    ['Deleted in SiteLink', u.deletedAt ? formatInstant(u.deletedAt) : '—'],
    ['Last Synced At', u.lastSyncedAt ? formatInstant(u.lastSyncedAt) : '—'],
  ]
  return (
    <RecordPage backTo="/units" backLabel="Units" title="Unit" readOnly>
      <dl className="grid grid-cols-[12rem_1fr] gap-x-4 gap-y-2 text-sm">
        {rows.map(([label, value]) => (
          <Fragment key={label}>
            <dt className="text-muted-foreground">{label}</dt>
            <dd>{value}</dd>
          </Fragment>
        ))}
      </dl>
    </RecordPage>
  )
}
```

Add the routes `{ path: 'units', Component: UnitsPage }` and `{ path: 'units/:id', Component: UnitPage }`, and the three audit record types.

- [ ] **Step 4: Run the checks**

Run (in `admin-ui/`): `npm run typecheck && npm test && npm run build`.
Expected: green. The build writes `src/ExtraSpace.Api/wwwroot/admin` (git-ignored).

- [ ] **Step 5: Stop and report** (no commit).

---

### Task 12: Wrap-up — docs, migration script, full checks, walk (main session)

**Files:**
- Modify: `docs/notes/cms/built-so-far.md` (an "S1-1" section), `.claude/rules/cms.md` (house rule 11: "outbox row (S1-1, `Platform/Outbox`)"; the `SiteLink` running-locally note), `docs/superpowers/specs/2026-10-14-s1-self-storage-design.md` §15 (the QOL additions of decision 15)
- Create: `docs/migrations/2026-10-14-s1-1-sites-sitelink.sql`

- [ ] **Step 1: Run the whole build and test suite**

From `../CMS`:
- `dotnet build` (0 errors)
- `dotnet test tests/ExtraSpace.Engines.Tests`
- `dotnet test tests/ExtraSpace.Api.Tests`
- `dotnet test tests/ExtraSpace.Infra.Tests`
- in `admin-ui/`: `npm run typecheck && npm test && npm run check:api && npm run build`

Write down each count.

- [ ] **Step 2: Write the migration script**

```bash
dotnet ef migrations script DropEntraObjectId SiteLinkCallMonth --idempotent --project src/ExtraSpace.Api \
  -o "../Claude/docs/migrations/2026-10-14-s1-1-sites-sitelink.sql"
```

Strip the BOM. Check that it holds `outbox_message`, `site`, `storage_type` (two seed rows), `unit_size`, `unit` (with the generated column), `unit_sync_state` and `sitelink_call_month`.

- [ ] **Step 3: Update the notes**

`built-so-far.md` "S1-1" section, one bullet each:
- outbox (`IOutbox.Enqueue` inside the caller's transaction; handlers idempotent; `AddOutboxHandler`; back-off; `failed_at`; nudge)
- email through the outbox (`IEmailSender.Enqueue` before the commit)
- SiteLink client (`CallAsync` kinds; logon block; allow-list and `AllowWritesToAllSites`; `IProblemException`; lower-case outcome values; counter table; test fake `api.SiteLink` keyed by location code; unique location codes and operation names per test)
- unit refresh (modes, lock key `unit-refresh:<siteId>`, failure recorded on `unit_sync_state`)
- the `UnitSizeMap` rule
- admin paging, `Patch` and `clear`
- the UI templates (`ListPage`, `RecordEditor`, `useListParams`, `formatMoney`)
- `Jobs:UnitRefresh:Enabled=false` in the test host

- [ ] **Step 4: Local walk (dev-walker, GET-first; local Docker only)**

Brief the `dev-walker` with built-so-far and this plan. Cases:
1. Sign in as staff (the console code). Then create a site (`SG`), a storage type and a unit size through the admin API. Check the currency, zone and tax label defaults, and the audit rows.
2. Run `GET /admin/api/units` and `GET /admin/api/unit-sync`.
3. `POST /admin/api/sites/{id}/unit-sync` with no SiteLink login set locally. Then `GET /admin/api/unit-sync` must show `lastError` = "SiteLink could not be reached." and the log must have `SiteLink … not sent` (Warning).
4. Request a customer login code. The email arrives in the console through the outbox: the `outbox_message` row has `processed_at` set and its payload has no code and no address (read with `postgres-local`).
5. Delete the walk rows afterwards (sites, types, sizes, outbox rows of the walk).

- [ ] **Step 5: LSETUP checks (owner, once our SiteLink API user exists; spec open item 5)**

With the owner's login in user-secrets (filled with a no-print command), one run each:
1. "Full resync" of LSETUP. Record the unit count, and compare it with SiteLink's own count of all units, rented ones included. Units hidden from the website: do any appear (decision 8)?
2. "Sync now" right after must send the saved cursor and return few or no rows.
3. `iCurrencyDecimals` for LSETUP = 2.
4. `sitelink_call_month` shows one row per operation and the `*` total.

Write the answers into `docs/notes/s1-research/brainstorm-decisions.md`. If units hidden from the website come back on a full pull, raise a fix before S1-3 (for example a second full pull with `false` to tell them apart).

- [ ] **Step 6: Report** ACCEPT / FIX NEEDED / BLOCKED per task, with what was verified and what was not. Do not commit.

---

## Spec coverage (self-review)

| Spec | Where |
|---|---|
| §4 layout (`Features/Sites`, `Integrations/SiteLink`, `Platform/Outbox`) | Tasks 2–7 |
| §5.1 `site`, `unit_sync_state`, `storage_type`, `unit_size`, `unit` (+ generated `available`, size from area) | Tasks 3, 6 |
| §5.6 `outbox_message` | Task 2 |
| §6.1 client, per-operation codes, sensitive replies not read, `bTestMode` never (no operation here takes it) | Tasks 4, 5 |
| §6.1 card guard for the move-in operations | **S1-3** (no card-carrying operation exists until then) |
| §6.2 config, write allow-list, own API user | Task 4 (decision 3); Task 8 secret; the API user is open item 5 |
| §6.3 resilience, 503/502 | Task 4 |
| §6.4 one log line per call, counter, monthly alarm | Tasks 4, 8 |
| §6.5 site-local dates, null date, `iCurrencyDecimals` check | Tasks 4, 6 |
| §6.6 rate limiter (writes never wait), caches | Task 4; price-list / discount / move-in-cost caches are **S1-3** |
| §6.7 nightly refresh, first full pull, incremental cursor, mapping, staff Sync now / Full resync | Tasks 5, 6, 7, 11 |
| §6.7 on-demand refresh and the live unit read | **S1-3** (decision 14) |
| §9.10 outbox, retries, failed rows, login email moved | Task 2 (the Retry / Mark resolved actions are **S1-4** Needs attention) |
| §11.1 look, list and record templates, Recharts | Tasks 9–11 (Recharts is **S1-5**, the Dashboard) |
| §11.2 Platform pages (Sites, Storage Types, Unit Sizes, Units) | Tasks 7, 10, 11 |
| §11.3 `sites.manage`, reads open to staff, audit record types | Tasks 7, 11 |
| §13 jobs `OutboxDispatcher`, `UnitRefresh`; config keys `SiteLink:*` | Tasks 2, 4, 6, 8 |
| §14 tests: site clock (Z1–Z3 + MY + KR), mapping C5–C10, return codes, write allow-list | Tasks 1, 3, 4, 5, 6 |
| S0 carry-overs: Money (`default`, invariant culture), enums as strings, outbox for the login email | Tasks 1, 2, 3 |

**Not in this plan (and where it goes):**
- `customerId` on the summary line for binding failures (S1-2)
- the WAF body-size rule (S1-4)
- the Hangfire heartbeat / queue-age alarm and the job stop timeout (S0-6 carry-overs: the first long job here is `UnitRefresh`, which rarely runs past a minute, so they wait until S1-4's reconciliation jobs)
- outbox housekeeping (deleting old processed rows): nothing grows fast yet

Risk to watch: until the LSETUP checks run (Task 12 step 5), the first-pull behaviour (decision 8) is only verified against our fake.

---

## Execution record (2026-10-14, subagent-driven, uncommitted on branch `s1-1-sites-sitelink`)

Every task was implemented by an Opus implementer (Task 8: devops), reviewed per task, then reviewed as a whole branch; one final fix wave. Final checks: build 0 warnings; Engines 29, Api 478, Infra 257, admin UI 138 tests green; local walk 4/4 PASS. The rulings below change the plan text above where they differ.

### Rulings

- PF1 Ruling: `Unit.SiteLinkUnitId` is `{ get; set; }` (not init) — test lambdas set it (CS8852) — cost if wrong: none, entity property mutability only. Tasks 3, 6.
- PF2 Ruling: log assertions use LogCapture's real API (`WaitForAsync(Func<JsonElement,bool>)` → `IReadOnlyList<JsonElement>`); match on messageTemplate/properties or `GetRawText().Contains`, same intent as the plan's text — cost if wrong: test wording only. Tasks 2, 4.
- PF3 Ruling: Site edit form requires Time Zone and Tax Label (zod `.min(1)` on edit too), server stays strict — spec has both as required site fields — cost if wrong: staff cannot blank a field the server would refuse anyway. Task 10.
- PF4 Ruling: `values()` / form defaults list keys in field order so `clear` follows field order (`['maxAreaSqft','storageTypeId']`) — cost: test ordering only. Task 10.
- PF5 Ruling: UnitSizeMapTests set CreatedAt/UpdatedAt explicitly (UTC) on rows inserted through the bare context — cost: none. Task 6.
- PF6 Ruling: the no-write transaction paths (UnitRefreshService skipped, OutboxDispatchJob empty queue) get a one-line comment saying dispose rolls back and releases the lock; no commit — cost: none. Tasks 2, 6.
- PF7 Ruling: `SiteLinkValues.ParseBool` (and any parse helper) throws a FormatException whose message names the column/kind but NOT the raw value, so `Describe` may keep `e.Message` without leaking SiteLink data into logs/sync state — cost: a slightly less detailed error. Task 4 (helper), Task 6 (Describe).
- PF8 Ruling: the `Blank` / `Required` helpers used by the three admin services live once in `Platform/Http/Patch.cs` (Task 7 creates it) — cost: none.
- PF9 Ruling: `UnitSizeMap` sets `updated_at` from the injected `TimeProvider` (parameter), not `now()` — house rule "never DB/now clock drift"; cost: none. Task 6.
- PF10 Ruling: accepted as is (fake-time dispatchers in OutboxTests may process other classes' due rows; nothing asserts on them) — cost if wrong: a flaky test later; reviewer may raise it.
- PF11 Ruling: parked to S1-3 — a SiteLink 502/503 reaching AppExceptionHandler would log "Unhandled exception" at Error; nothing in S1-1 calls SiteLink inside a request — cost if wrong: S1-3 noise on the error-lines alarm; S1-3 plan must log IProblemException 5xx as a Warning outside-call line.
- PF12 Ruling: Task 2 also updates `tests/.../Integrations/EmailAllowListTests.cs` (uses `HangfireEmailSender.Purpose`).
- PF13 Ruling: Task 2 test matches on the outbox id (code wins over note).
- PF16 Ruling: Task 9 creates `admin-ui/src/lib/forms.test.ts` (does not exist yet).
- T3 Ruling: SiteLink id columns use the spec spelling sitelink_site_id / sitelink_unit_id / sitelink_unit_type_id (HasColumnName), not EF's site_link_* — spec §5.1 binds and future raw SQL follows the spec — cost if wrong: a column rename migration.
- T4 Ruling (I1): RT Ret_Code <= 0 is a refusal (not just < 0), read `Ret_Code ?? Ret_Cod` — the demo's live-tested rule (parse-dataset.ts:70-71, spec 02 P9/P11); a 0 is never a valid created id; spec §6.1's "negative" did not consider 0 — cost if wrong: an op that answers RT Ret_Code 0 as success would be refused; LSETUP checks would show it.
- T4 Ruling: take M1 (Polly severity via TelemetryOptions.SeverityProvider, drop the category override), M2 (XmlException -> SiteLinkUnavailableException without inner/raw text) and M5 (GUID op names in the retry test) in the same fix round — Task 6 builds on this client and M1 would trip the error-lines alarm — cost: one fix round.
- T5 Ruling: SiteLinkUnit's boolean flags become `bool?` (absent → null); defaults (Rented false, Rentable true, WaitingListReserved false, feature flags false) apply only when Task 6 INSERTS a new unit; an update keeps the stored value for a null flag — spec §6.5 "an absent column keeps the old value" binds over the demo's C9/C10 defaults, which now apply to new rows — cost if wrong: a few `??` lines; behaviour for a well-formed SiteLink reply is identical.
- T5 Ruling (extended): UnitTypeId int?, TypeName string?, Width/Length decimal?, AreaSqft null when either is null — same reason as T5 — cost: a few `??` lines in Task 6.
- T6 Ruling (carried): a blank sTypeName (present, "") keeps the stored type name and the storage type (treat blank like absent for TypeName only) — a blank type name carries no information and would move a workspace unit to self-storage — cost if wrong: a deliberate SiteLink blanking of a type name is ignored.
- T6 Ruling (I1): per-site lock becomes a SESSION advisory lock (pg_try_advisory_lock on an opened connection, same key) taken before the SiteLink calls; the transaction opens only after the SiteLink replies are in hand; failure is recorded before unlocking; unlock in finally (Npgsql's DISCARD ALL on pool return is the safety net) — keeps Review Focus 3 (skip without calling SiteLink) — cost if wrong: RDS Proxy pins the connection for the refresh duration (acceptable: one refresh per site, sequential).
- T6 Ruling: also take M1 (IsDue inside the per-site try), M2 (record failure before unlock — part of I1), M3 (pg_advisory_xact_lock('unit-size-map') at the top of UnitSizeMap.RemapAsync; lock order site-session → size-map-xact, admin takes only size-map), M5 (currency-mismatch test asserts LastError/LastAttemptAt; a null CurrencyDecimalsAsync case), M6 (Describe: database branch with readable text).
- T7 Ruling (carried): UnitSizeAdminService create/update takes UnitSizeMap.LockAsync after BeginTransaction and before SaveChanges, then RemapAsync(db, null, time, ct); DeleteAsync takes LockAsync inside a transaction before the in-use check — avoids the key-change deadlock and the check/delete race found in the Task 6 re-review — cost: none.
- T7 Ruling: also take M1 (time zone must have an IANA id: TryFind && HasIanaId), M2 (refuse delete of the two seeded storage types with 409 STORAGE_TYPE_IN_USE — the refresh finds them by key), M3 (rename PageOf<T> → Page<T> so schemas read PageOfX, not PageOfOfX — cheapest now), M4 (staffId on the Sync now / Full resync log line), M6 (tests: lower-case country 400, set+clear same field 400, stale-version DELETE 409) — cost: one fix round.
- T7 Ruling (fix round): PageOf<T> renamed Paged<T> (Page<T> clashes with its Page property, CS0542); schemas PagedOfX — cost: none.
- T7 Ruling (fix round): M4 accepted as done via the staffId property every staff-request line already carries (+ test); no message-text change, no new Admin contract — cost: none.
- T8 Ruling: offline `cdk synth` (brief Step 4) not run — subagents may not run CDK here; the in-process infra tests synthesize the stacks; the owner's `cdk diff --profile extraspace` before deploy covers it — cost if wrong: a synth-only failure found at owner deploy time.
- T9 Ruling (I1): UI-only fix (a): on CONFLICT show the server's title through ErrorNote (with traceId); the page still reloads the record; no new wire codes now (option b, distinct codes, is an S0-wide contract change — deferred to the owner) — cost if wrong: messages rely on server titles.
- T9 Ruling: also take M1 (keep two probe cases as committed tests: ListPage outside-search sync, RecordEditor 409 keep-dirty merge), M2 (Math.floor page), M3 (step back a page when items empty and total > 0), M4 (conflict wording "the record was reloaded").
- Final Ruling (I2): every poll passes bReturnExcludedFromWebsiteUnits=true (our copy holds all units consistently); storing bExcludeFromWebsite (new column) and hiding those units moves to S1-3 as a blocker before browsing — cost if wrong: an incremental poll with true might return more than changed rows (LSETUP check added).
- Final Ruling (I3): refuse changing location_code or country while the site has units (409 SITE_IN_USE) — the cursor/currency would silently go wrong; owner can relax later — cost if wrong: staff must ask for a scripted fix to re-point a site.
- Final Ruling (I1): S1-1 adds only an IOutboxHandler summary line ("must finish within seconds; no outside calls"); the lease-based claim is an S1-2 plan item before the first slow handler — cost if wrong: none in S1-1 (Email handler only enqueues).
- Final Ruling: take M1 (clear the sealed payload when a row is processed), M2 (area 0 → no unit size), M3 (malformed CorpUserName = not configured + Warning, not a start-up failure; Decision 6), M5 (JobTracingFilter added once, no remove/re-add window — likely JobsTests flake), T11 must-fix pair, `derive` implies read-only, last error shows its time — all small — cost: one fix wave.
- Final Ruling: M4 (Sync now ignores Active; first refresh via Sync now skips the currency check) and "Sync now leaves no audit_log row" are recorded in built-so-far / spec as deliberate.
Final: parked — I3 first-refresh race: a PATCH of location code/country during a site's first refresh (no units yet, SiteLink call in flight) can commit; the units then land under the new code — Ruling: real, P2, deferred to S1-3 (refresh re-reads location_code/country FOR SHARE in its write tx, or PATCH takes the site refresh lock) — cost if wrong: a scripted fix for one site.

### Parked and carried to later plans

- Task 2: minor (deferred, owner): sign-in email is now 2 Hangfire queue hops (~10 s worst case on AWS with 5 s polls) vs Decision 1's "about a second" — option: Hangfire.PostgreSql long polling
- Task 2: minor (deferred, S1 Needs-attention plan): outbox Email row is processed once EmailJob is enqueued; a permanently failed EmailJob never shows as a failed outbox row
- Task 2: minor (deferred, S1-2): unknown outbox kinds burn their 5 attempts during a rolling deploy
- Task 4: minor (deferred, S1-3): Hangfire AutomaticRetry must not re-send a SiteLink write job that ended SiteLinkUnavailableException (settle by read-back)
- Task 4: minor (deferred, S1-3): SocketsHttpHandler may re-send a request on a dropped pooled connection — write design must use read-back
- Task 4: minor (deferred, S1-3): limiter wait counts against the 30 s attempt timeout; many queued reads could open the breaker
- Task 5: minor (deferred, final review): one unnamed flaky failure in 1 of 6 full API runs — identify in the final full run
- Task 5: minor -> Task 12 LSETUP checks: does an incremental row for a deleted unit always carry dDeleted (Task 6 assigns DeletedAt unconditionally)? does UnitTypePriceList_v2 return iCurrencyDecimals on every row / what for a site with no unit types?
- Task 6: minor -> Task 12 LSETUP checks: does SiteLink send more than 2 decimals for rates/width/length (column rounds silently)?
- Task 7: minor (deferred, OWNER): changing a site's country while it has units re-labels stored rates in the new currency — refuse with 409, or allow? (owner call)
- Task 7: minor (deferred, S1-3): each "Sync now" click enqueues another job; repeated clicks each call SiteLink (call budget)
- Task 7: minor (deferred, final run): JobsTests.A_job_enqueued_by_a_request_carries_its_correlation_id flaky (2/9 full runs)
- Task 8: minor -> Task 12 docs: rollback note must add `aws secretsmanager restore-secret --secret-id es/staging/sitelink --profile extraspace` (deleted secret blocks re-create in the recovery window)
- Task 7: note -> Task 12: record PageOf<T> → Paged<T> in built-so-far.md (plan text still says PageOf)
- Task 9: minor (deferred, OWNER): distinct codes for unique/FK violations (DUPLICATE_VALUE / IN_USE) instead of CONFLICT — S0 StaffDialog/RoleDialog have the same pattern
- Final: parked — I3 first-refresh race: a PATCH of location code/country during a site's first refresh (no units yet, SiteLink call in flight) can commit; the units then land under the new code — Ruling: real, P2, deferred to S1-3 (refresh re-reads location_code/country FOR SHARE in its write tx, or PATCH takes the site refresh lock) — cost if wrong: a scripted fix for one site.

### Other deferred minors

- Task 1: minor (deferred): Money.ToString prints "0.00" for KRW (format not from Currencies.Decimals)
- Task 1: minor (deferred): Money ctor accepts any 3-letter code; fails late at Round (validate with Currencies.IsSupported on write)
- Task 1: minor (deferred): Currencies.IsSupported has no direct test
- Task 1: minor (deferred): SiteClock.LocalToUtc does not guard minutes 0..1440
- Task 2: minor (deferred): parallel-dispatcher test can pass by chance; implicit-transaction nudge path has no assertion
- Task 3: minor (deferred): no test pins OutboxNudge's lazy resolve (a revert to ctor injection stays green)
- Task 3: minor (deferred, ruled): unit.area_sqft numeric(12,2) vs width/length numeric(10,2)
- Task 4: minor (deferred): no tests for breaker / 30-60 s timeouts / alarm line end-to-end / sApiKey
- Task 4: minor (deferred): year-0001 date with positive offset throws instead of null (vendor sends no offset)
- Task 4: minor (deferred): empty <Ret_Code/> is not a refusal (demo would treat as 0)
- Task 6: minor (deferred, accepted by T6 ruling): RDS Proxy pins the pooled client connection after pg_try_advisory_lock; a lock granted then cancelled before read could leak until the pooled connection is reused/pruned (~5 min)
- Task 6: minor (deferred): size-map xact lock serialises all sites' write phases and admin size edits (fine at our load)
- Task 7: minor (deferred): unknown storageTypeId on a unit-size write answers 409 CONFLICT, not 400
- Task 8: minor (deferred): one-line comment at EnvConfig.cs:78 (prod binds WriteAllowList LSETUP but AllowWritesToAllSites overrides)
- Task 8: minor (deferred): AppStackTests presence checks overlap the exact-set test
- Task 7: minor (deferred): seeded storage type can be PATCHed active=false (check whether the refresh filters on Active)
- Task 9: minor (deferred): zod-fields Number() accepts 0x1A / 1e3; money.ts Intl throws on an invalid currency code; App.test title vs content; vite 500 kB chunk warning (check pre-existing)
- Task 9: minor (deferred): "No {noun} yet" also shown when a search finds nothing
- Task 10: minor (deferred): request bodies cast `as CreateX` (no tsc key check); repeated write-hook boilerplate across api.ts files
- Task 11: minor (deferred): permission test doesn't check Full resync absent; null webRate "—" and KRW record formatting untested; dialog close after 202 untested; country→currency map duplicated in SitePage; last error has no time
- Final: minor (deferred): OutboxDispatchJob replaces the payload JsonDocument without disposing it; site page lets staff type a new code/country on a site with units (server refuses)

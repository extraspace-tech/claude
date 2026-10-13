# S0-4 Admin back end — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this workspace the implementer is the Opus `implementer` agent and the reviewer the Opus `code-reviewer` agent; Task 6 is run by the main session only. Agents never commit (memory `feedback-sdd-without-commits`).

**Goal:** Staff sign in to the admin with Microsoft Entra ID and get the `__Host-es-admin` cookie. Every admin write is CSRF-checked, permission-checked and audited in the same transaction. Staff, roles, the permission catalogue and the audit log have their endpoints, and the Hangfire dashboard opens only for `jobs.manage`. Admin edits use `xmin` and get 409 when they are stale. 🔴 First of all, the Data Protection key ring leaves the database: on AWS it lives in SSM Parameter Store (SecureString, encrypted with KMS).

**Architecture:**
- `Platform/Hosting` chooses where the key ring lives: SSM on AWS, the `data_protection_keys` table in Development and Testing only.
- `Features/Admin` holds everything else:
  - the tables `staff_user`, `role` (system role Owner seeded) and `audit_log`;
  - the permission catalogue (`Contracts/`, so later features register their own permissions);
  - the audit pair: `AdminRequestFilter` (endpoint filter on the `/admin/api` group: `staffId` log property, CSRF check, audit context) and `AuditInterceptor` (EF SaveChanges interceptor that writes `audit_log` rows inside the same save);
  - the `Staff` cookie scheme and the `Entra` OpenID Connect scheme, `StaffSignIn` (callback and dev sign-in), `StaffAccess` (reloads the staff member on every request);
  - the services and endpoints for staff, roles, permissions and audit, and the Hangfire dashboard mapping.
- `Program.cs` creates the `/admin/api` group once: `app.MapGroup("/admin/api").RequireStaff().WithEnumGuard()`.

**Tech Stack:**
- .NET 10 (SDK 10.0.400, runtime 10.0.11), Minimal APIs, EF Core 10 + Npgsql 10.0.3, Hangfire 1.8.25.
- **New:** `Microsoft.AspNetCore.Authentication.OpenIdConnect` 10.0.11, `Amazon.AspNetCore.DataProtection.SSM` 4.0.3 (net10 target; depends on `AWSSDK.SimpleSystemsManagement` 4.0.7.3 and `AWSSDK.Extensions.NETCore.Setup`, which we already reference).
- Built in, no package: cookie authentication, antiforgery.
- Tests: xUnit v3 + AwesomeAssertions + Testcontainers (PostgreSQL 18.6).

**Spec:** `docs/superpowers/specs/2026-10-09-s0-foundation-design.md`: §4.4 logging (`staffId`), §5 / §5.1 data (concurrency `xmin`, `staff_user`, `role`, `audit_log`, `data_protection_keys`), §6.2 staff sign-in, §6.3 permissions and audit, §7 dashboard, §10 must-have tests, §11 items 4–6. Also read `docs/superpowers/plans/2026-10-12-s0-plan-index.md` ("Carry-overs from S0-2" and "from S0-3" → S0-4), `docs/notes/cms/built-so-far.md`, `.claude/rules/cms.md` and the guide `docs/notes/cms/minimal-apis-vs-mvc.md`.

**Clients affected:**
- **Admin UI (S0-5):** the whole admin contract below. Sign-in is a full-page navigation to `/admin/api/auth/login`; fetch the CSRF token after sign-in; send `version` on every PATCH/DELETE.
- **Cron:** the Hangfire dashboard moves behind admin sign-in + `jobs.manage`.
- **S0-6 infra:** SSM path + IAM on the task role, the Entra secret, new env vars (list in Task 6).
- **Flutter:** none (`/api/v1` unchanged). **Stripe:** none.

## Global Constraints

- **Repo and branch.** Repo `../CMS` (`extraspace-tech/cms`, 🔴 PUBLIC). Work on branch `s0-4-admin-backend`, cut from `main` at `9c678ce`. **Never `git commit`, `push`, `stash` or `reset`.** The owner commits.
- **No secrets in the repo.** No client secret, tenant id of the client, signing key, connection string, AWS account id or real email address in any committed file. Test-only values must say "test" in their text (`test-tenant`, `test-client-secret`).
- **No AWS or Microsoft calls from tests.** Never start a test host with `DataProtection:SsmPath` set (the key ring would call SSM at start-up). Never let the OIDC handler fetch its metadata (Task 3 gives the test host a static configuration).
- **Agent limits.** Subagents never run `dotnet user-secrets`, `docker compose` or any AWS command, and never dispatch subagents.
- **Files.** No new `.md` file inside `../CMS`. LF line endings. Match `.editorconfig` and the surrounding idiom: low comment density, one-line "why" comments, file-scoped namespaces, primary constructors, `internal sealed` unless a test or another layer needs the type.
- **Package versions** live only in `Directory.Packages.props`. ASP.NET Core packages are pinned to **10.0.11**.
- **Namespaces:** `ExtraSpace.Api.Features.Admin` (`.Contracts` for what other features may use), `ExtraSpace.Api.Platform.Data` for the two marker interfaces and the attribute.
- **Banned in `src/`** (RS0030): `DateTime.Now/UtcNow/Today`, `DateTimeOffset.Now/UtcNow`, `Guid.NewGuid`. Use the injected `TimeProvider` and `Guid.CreateVersion7()`.
- **Endpoints are Minimal APIs.** Handlers take services as parameters, call a service (never `AppDbContext`) and return `TypedResults`. Errors are thrown as `AppException(status, code, title)`. Request DTOs are **`public`** classes with `{ get; init; }` properties and DataAnnotations, with no `[JsonPropertyName]`. A group's own root route is `""` (gives `/admin/api/staff`, not `/admin/api/staff/`).
- **Endpoint filters are top-level classes** that resolve scoped services from `context.HttpContext.RequestServices` inside `InvokeAsync`, never through their constructor (a typed filter is built once per endpoint).
- **Log property names are lowerCamel.** 🔴 Never log a cookie, a CSRF token, an Entra token or code, the client secret or an unmasked email. Emails only through `Pii.MaskEmail`. The id property is `staffId`.
- **Data rules.** Tables `snake_case` and singular, UUID v7 ids set in code, `timestamptz` with Kind Utc. `created_at` / `updated_at` by `TimestampsInterceptor`.
- **Admin writes go through tracked entities.** `ExecuteUpdate` / `ExecuteDelete` skip the audit interceptor and are banned in admin write paths (test helpers excepted).
- **Transactions.** Every `BeginTransactionAsync` has a `CommitAsync` on every path that must keep its writes (engineering checklist §2). Advisory-lock keys are namespaced: `staff-owners`.
- **Migrations.** After `dotnet ef migrations add`, strip the BOM from the 3 generated files.
- **Tests.** Test environment `Testing`. `ExtraSpace.Api.Tests` needs Docker. Filter form: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*StaffEndpointsTests"`. Every `WithWebHostBuilder` host sets `App:Role=Api`. 🔴 **Only tests in the xUnit collection `Owners` create staff with the Owner role or change Owners**: the tests share one database, and the Owner rules count every active Owner in it.
- **Cookies in tests.** `__Host-` cookies are `Secure`, and the client's cookie container sends them only over https: admin test clients use `BaseAddress = https://localhost` (helper `api.AdminClient()`).
- **Spec values (§6.2–§6.3, verbatim):** cookie `__Host-es-admin`, `HttpOnly`, `Secure`, `SameSite=Lax`, 8-hour sliding lifetime; header `X-CSRF-TOKEN`; S0 permissions `staff.manage`, `roles.manage`, `audit.read`, `jobs.manage`; system role `Owner` always has every permission; dashboard `/admin/jobs`.

## Review Focus

1. **Zero Owners.** Two Owners demote each other at the same moment, or the only Owner demotes themself. Expected: at least one active Owner remains; the loser gets 409 `LAST_OWNER` or 403. Pinned by Task 4 `Two_owners_demoting_each_other_at_once_leave_one_owner` and `The_only_owner_cannot_demote_themself` (advisory lock `staff-owners`, actor re-checked under the lock).
2. **Privilege escalation.** A staff member with `staff.manage` but not Owner gives themself or anyone the Owner role, or deactivates an Owner. Expected: 403. Pinned by Task 4 `Only_an_owner_can_grant_the_owner_role` and `Only_an_owner_can_change_an_owner`.
3. **A deactivated or demoted staff member keeps access** through a still-valid 8-hour cookie. Expected: the next request is 401 (deactivated) or loses the permission (demoted). Pinned by Task 3 `A_deactivated_staff_member_is_signed_out_at_the_next_request` and `A_role_change_applies_at_the_next_request`.
4. **An admin write without its audit row, or an audit row without its write.** Expected: the row and the change commit in one SaveChanges; a failed save leaves neither; a stale `version` leaves neither. Pinned by Task 2 `A_failed_save_writes_no_audit_row` and Task 4 `A_stale_version_gets_409_and_changes_nothing`.
5. **CSRF.** A write without the header, or with another staff member's token, must fail with 400 `CSRF_FAILED` before the handler runs. Pinned by Task 3 `A_write_without_the_csrf_header_is_rejected` and `A_csrf_token_of_another_staff_member_is_rejected`.
6. **Redirects and scheme bleed.** `/admin/api/*` without a cookie must be 401 JSON, never a 302. A customer JWT must not open admin routes, and the admin cookie must not open `/api/v1`. Pinned by Task 3 tests of the same names.
7. **Key ring.** Outside Development/Testing the app must refuse to start without `DataProtection:SsmPath`; with it, keys must go to SSM, never to the table. Pinned by Task 1.

## Decisions (approved by the owner 2026-10-13, three of them change the spec)

1. 🔴 **Key ring in SSM Parameter Store** (changes spec §5.1 / §6.2 "keys in PostgreSQL"). `Amazon.AspNetCore.DataProtection.SSM`, path `DataProtection:SsmPath` (`/es/<env>/data-protection/`), SecureString with the default `aws/ssm` KMS key, standard tier. Development and Testing keep the `data_protection_keys` table. Any other environment refuses to start without the path. The SSM client gets its own AWS options, because the SES setup turns off SDK retries on the shared defaults.
2. **OIDC library:** the built-in `Microsoft.AspNetCore.Authentication.OpenIdConnect` (changes spec §6.2, which named `Microsoft.Identity.Web`). Single tenant (`https://login.microsoftonline.com/<tenantId>/v2.0`), authorization code + PKCE, client secret, `MapInboundClaims = false`, no saved tokens, callback `/admin/api/auth/callback`.
3. **Callback lookup:** by `oid`; else by `preferred_username` (or `email`) lower-cased, and then the `oid` is saved. An email row already linked to another `oid` is refused. Unknown, inactive or refused → 403 `FORBIDDEN` at the callback, no cookie. An empty `display_name` is filled from `name`; `last_sign_in_at` is set.
4. **Bootstrap:** an address in `Admin:BootstrapEmails` with no staff row becomes an Owner at sign-in **only while no active Owner exists** (checked under the `staff-owners` lock).
5. **The cookie holds only the staff id.** `StaffAccess` reloads the staff member and role on every admin request (cookie `OnValidatePrincipal`): inactive or missing → cookie rejected → 401; permissions are rebuilt as `perm` claims. Owner = every catalogue permission; a stored permission that is no longer in the catalogue is ignored.
6. **No redirects on the API:** cookie challenge → 401, forbid → 403, both JSON problems (also `/admin/jobs`). The only redirect is `GET /admin/api/auth/login`, which always returns to `/admin` (no `returnUrl`).
7. **CSRF:** built-in antiforgery, header `X-CSRF-TOKEN`, cookie `__Host-es-csrf`; `AdminRequestFilter` validates every signed-in POST/PUT/PATCH/DELETE on the group. Failure → **400 `CSRF_FAILED`**. A route can opt out with `.DisableAntiforgery()` (none in S0). `SuppressXFrameOptionsHeader = true` (we send `DENY`).
8. **Entra settings missing:** Production refuses to start. Elsewhere the `Entra` scheme is not registered and `/auth/login` → **503 `ADMIN_SIGNIN_UNAVAILABLE`**.
9. **Dev sign-in:** `POST /admin/api/auth/dev-login { email }`, mapped only in Development, answers 404 unless the caller is loopback. It runs the same `StaffSignIn` (existing active staff, or bootstrap).
10. **Permission catalogue:** `services.AddPermissions(new Permission(name, description), …)` from `Features/Admin/Contracts`; one policy per name (cookie scheme + `perm` claim). Admin registers the four S0 permissions (`jobs.manage` too, because Platform cannot depend on a feature). Role writes with an unknown name → 400 `VALIDATION_FAILED`.
11. **Audit = endpoint filter + SaveChanges interceptor** (changes spec §6.3 "one endpoint filter"). The filter fills a scoped `AuditContext` (staff id, action `"<METHOD> <route template>"`, IP) for signed-in writes. `AuditInterceptor` adds one `audit_log` row per Added/Modified/Deleted `IAudited` entity, with `changes = { "<camelName>": { "from": …, "to": … } }` (Modified: only changed fields), skipping the key, timestamps, staff stamps, `Version` and `[NotAudited]` properties, in the same save. It also fills `created_by_staff_id` / `updated_by_staff_id` on `IHasStaffStamps` entities. Sign-ins and dashboard actions are log lines, not audit rows. `audit_log` has `occurred_at` and no `created_at` / `updated_at` (append-only; an exception to the timestamp rule).
12. **`xmin` concurrency:** `uint Version` mapped with `.IsRowVersion()` on `staff_user` and `role`. Responses carry `version`; PATCH bodies and `DELETE ?version=` must send it; a mismatch → 409 `CONFLICT` (already mapped). A PostgreSQL foreign-key violation also becomes 409 `CONFLICT` (new, generic: a race that assigns a role while it is deleted).
13. **Staff rules:** no self-deactivation (409 `CANNOT_DEACTIVATE_SELF`); never zero active Owners (409 `LAST_OWNER`; every write that changes role or active status takes `pg_advisory_xact_lock(hashtextextended('staff-owners', 0))` first). Staff rows are never deleted.
14. **Owner-only (added while writing the plan; security, not in the spec):** only an active Owner (re-checked under the lock) may grant the Owner role, or change the role or active status of an Owner → 403 `FORBIDDEN` otherwise. Without it, any `staff.manage` holder could make themself Owner.
15. **Roles:** Owner is seeded with the fixed id `0199dd00-0000-7000-8000-000000000001`; it cannot be renamed, edited or deleted (409 `SYSTEM_ROLE`). Deleting a role that staff hold → 409 `ROLE_IN_USE`. Names are trimmed and unique ignoring case (unique index on `lower(name)`). `GET /roles` needs only a signed-in staff member (the staff screen needs the list to assign roles); writes need `roles.manage`.
16. **Shapes:** listed in Task 3/Task 4 (`AdminDtos.cs`). `GET /staff` is not paged. `GET /audit` is offset-paged, newest first, `pageSize` 1–100 (default 50), `from`/`to` are instants with an offset; `GET /permissions` needs only a signed-in staff member.
17. **Hangfire dashboard:** `MapHangfireDashboard("/admin/jobs")` with `Authorization = []` (Hangfire's local-only default removed) + `.RequireAuthorization("jobs.manage")`; Hangfire uses the registered antiforgery service for its own POSTs.

---

### Task 1: 🔴 Key ring out of the database (SSM on AWS)

**Files:**
- Modify: `Directory.Packages.props`, `src/ExtraSpace.Api/ExtraSpace.Api.csproj`, `src/ExtraSpace.Api/Platform/Hosting/PlatformServices.cs`, `src/ExtraSpace.Api/Program.cs` (one line), `src/ExtraSpace.Api/appsettings.json`
- Create (tests): `tests/ExtraSpace.Api.Tests/Platform/DataProtectionTests.cs`

**Interfaces:**
- Changes: `AddPlatform(this IServiceCollection, IConfiguration, IHostEnvironment)` (was without the environment).
- Produces: config key `DataProtection:SsmPath`; the DbContext also picks up every `ISaveChangesInterceptor` registered in DI, after the platform ones (Task 2 registers the audit interceptor).

- [ ] **Step 1: Branch**

```bash
cd "/Users/waiyanmin/Projects/Extra Space/CMS"
git status --short          # must print nothing; stop and report if not
git log --oneline -1        # 9c678ce feat(identity): customer sign-in, jobs and email (S0-3)
git switch -c s0-4-admin-backend
```

- [ ] **Step 2: Packages.** In `Directory.Packages.props`, `Api` group, alphabetical:

```xml
    <PackageVersion Include="Amazon.AspNetCore.DataProtection.SSM" Version="4.0.3" />
    <PackageVersion Include="Microsoft.AspNetCore.Authentication.OpenIdConnect" Version="10.0.11" />
```

Add the `Amazon.AspNetCore.DataProtection.SSM` `PackageReference` to `ExtraSpace.Api.csproj` (OpenIdConnect comes in Task 3). If restore reports a downgrade or NU1605 because the package wants a newer `AWSSDK.Extensions.NETCore.Setup` than our pin, raise our pin to the version it asks for and report it.

- [ ] **Step 3: Write the failing tests.** `tests/ExtraSpace.Api.Tests/Platform/DataProtectionTests.cs`. They build the service collection only, so no host starts and no AWS call happens:

```csharp
using ExtraSpace.Api.Platform.Hosting;
using Microsoft.AspNetCore.DataProtection.KeyManagement;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Hosting.Internal;
using Microsoft.Extensions.Options;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class DataProtectionTests
{
    private static ServiceProvider Build(string environment, string? ssmPath)
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:Default"] = "Host=localhost;Database=test-not-used",
            ["DataProtection:SsmPath"] = ssmPath,
        }).Build();
        var services = new ServiceCollection().AddLogging();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddPlatform(configuration, new HostingEnvironment { EnvironmentName = environment });
        return services.BuildServiceProvider();
    }

    private static string RepositoryType(ServiceProvider provider) =>
        provider.GetRequiredService<IOptions<KeyManagementOptions>>().Value.XmlRepository!.GetType().Name;

    [Theory]
    [InlineData("Staging")]
    [InlineData("Production")]
    public void Outside_development_and_testing_the_app_needs_an_ssm_path(string environment)
    {
        var build = () => Build(environment, null);
        build.Should().Throw<InvalidOperationException>().WithMessage("*DataProtection:SsmPath*");
    }

    [Fact]
    public void With_an_ssm_path_the_keys_go_to_parameter_store()
    {
        using var provider = Build("Staging", "/es/test/data-protection/");
        RepositoryType(provider).Should().Contain("SSM");
    }

    [Theory]
    [InlineData("Development")]
    [InlineData("Testing")]
    public void In_development_and_testing_the_keys_stay_in_the_database(string environment)
    {
        using var provider = Build(environment, null);
        RepositoryType(provider).Should().StartWith("EntityFrameworkCoreXmlRepository");
    }
}
```

Confirm the real repository type name in the SSM package (look in `~/.nuget/packages/amazon.aspnetcore.dataprotection.ssm/4.0.3/`) and fix the assertion to it if it does not contain `SSM`. If resolving `KeyManagementOptions` makes an AWS call, stop and report.

- [ ] **Step 4: Run, expect a compile failure** (`AddPlatform` has no environment parameter):

```bash
dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*DataProtectionTests"
```

- [ ] **Step 5: Implement.** In `PlatformServices.AddPlatform`, add the `IHostEnvironment environment` parameter, and replace the line `services.AddDataProtection().SetApplicationName("ExtraSpace").PersistKeysToDbContext<AppDbContext>();` with:

```csharp
        // The key ring signs admin cookies and encrypts email jobs: on AWS it lives in SSM (SecureString, KMS), never in the database.
        var keyRing = services.AddDataProtection().SetApplicationName("ExtraSpace");
        if (configuration["DataProtection:SsmPath"] is { Length: > 0 } ssmPath)
        {
            // Own client: the SES setup turns off SDK retries on the shared default AWS options.
            services.TryAddSingleton(_ => configuration.GetAWSOptions().CreateServiceClient<IAmazonSimpleSystemsManagement>());
            keyRing.PersistKeysToAWSSystemsManager(ssmPath);
        }
        else if (environment.IsDevelopment() || environment.IsEnvironment("Testing"))
            keyRing.PersistKeysToDbContext<AppDbContext>();
        else
            throw new InvalidOperationException("DataProtection:SsmPath must be set outside Development and Testing.");
```

Read the SSM package's `PersistKeysToAWSSystemsManager` first: if it registers its client with `TryAdd`, ours wins; if it always creates its own client from the default `AWSOptions`, delete our `TryAddSingleton` line and report it (the default options then decide its retries). Keep the default `SecureString` + standard tier (no options), unless the extension needs them set explicitly.

In the same method, let feature interceptors run after the platform ones:

```csharp
            .AddInterceptors(sp.GetRequiredService<TimestampsInterceptor>(), sp.GetRequiredService<SlowQueryInterceptor>())
            .AddInterceptors(sp.GetServices<ISaveChangesInterceptor>()));   // feature interceptors (Admin audit), after the stamps
```

`Program.cs`: `builder.Services.AddPlatform(builder.Configuration, builder.Environment);`

`appsettings.json`: add `"DataProtection": { "SsmPath": "" },` after `"Cors"`.

- [ ] **Step 6: Run the new tests and the whole suite.**

```bash
dotnet build src/ExtraSpace.Api/ExtraSpace.Api.csproj        # 0 warnings, 0 errors
dotnet test tests/ExtraSpace.Api.Tests                        # 161 + 5 pass
```

- [ ] **Step 7: Hand-off.** Report the diff, the SSM package facts you checked (repository type name, client registration), and the test counts.

---

### Task 2: Admin data: tables, Owner seed, `xmin`, permission catalogue, audit interceptor

**Files:**
- Create: `src/ExtraSpace.Api/Platform/Data/IAudited.cs`
- Create: `src/ExtraSpace.Api/Features/Admin/StaffUser.cs`, `Role.cs`, `AuditLog.cs`, `AdminEntityConfigurations.cs`, `AdminPermissions.cs`, `PermissionCatalog.cs`, `AuditContext.cs`, `AuditInterceptor.cs`, `AdminSetup.cs`
- Create: `src/ExtraSpace.Api/Features/Admin/Contracts/Permissions.cs`
- Create: migration `AdminTables` (3 files, BOM stripped)
- Modify: `src/ExtraSpace.Api/Program.cs` (one line)
- Create (tests): `tests/ExtraSpace.Api.Tests/TestSupport/AdminTestData.cs`, `tests/ExtraSpace.Api.Tests/Features/Admin/AdminDataTests.cs`

**Interfaces:**
- Consumes: `IHasTimestamps`, `TimestampsInterceptor`, the interceptor pickup from Task 1.
- Produces:
  - `Platform.Data`: `public interface IAudited;` `public interface IHasStaffStamps { Guid? CreatedByStaffId; Guid? UpdatedByStaffId; }` `public sealed class NotAuditedAttribute : Attribute`.
  - `Features.Admin.Contracts`: `public sealed record Permission(string Name, string Description);` `PermissionRegistration.AddPermissions(this IServiceCollection, params Permission[])`.
  - `PermissionCatalog` (singleton: `All`, `Names`, `Contains(name)`), `AuditContext` (scoped: `Begin(staffId, action, ip)`), `AuditInterceptor` (scoped `ISaveChangesInterceptor`).
  - `Role.OwnerId`, `AdminSetup.AddAdminFeature(this IServiceCollection, IConfiguration, IHostEnvironment)` (Task 3 extends it).

- [ ] **Step 1: Markers.** `Platform/Data/IAudited.cs`:

```csharp
namespace ExtraSpace.Api.Platform.Data;

/// <summary>Changes made during an admin write get an audit_log row in the same save (S0 spec §6.3; written by Features/Admin).</summary>
public interface IAudited;

/// <summary><c>created_by_staff_id</c> / <c>updated_by_staff_id</c> (S0 spec §5), filled during admin writes.</summary>
public interface IHasStaffStamps
{
    Guid? CreatedByStaffId { get; set; }
    Guid? UpdatedByStaffId { get; set; }
}

/// <summary>Keeps a property's values out of audit_log (secrets, large blobs).</summary>
[AttributeUsage(AttributeTargets.Property)]
public sealed class NotAuditedAttribute : Attribute;
```

- [ ] **Step 2: Entities.**

```csharp
// Features/Admin/StaffUser.cs
using ExtraSpace.Api.Platform.Data;

namespace ExtraSpace.Api.Features.Admin;

/// <summary>A staff member (S0 spec §5.1). Must exist and be active to sign in; never deleted, only deactivated.</summary>
internal sealed class StaffUser : IHasTimestamps, IHasStaffStamps, IAudited
{
    public Guid Id { get; init; } = Guid.CreateVersion7();
    public required string Email { get; set; }
    public string? DisplayName { get; set; }
    public string? EntraObjectId { get; set; }
    public Guid RoleId { get; set; }
    public Role Role { get; set; } = null!;
    public bool Active { get; set; } = true;
    public DateTime? LastSignInAt { get; set; }
    public Guid? CreatedByStaffId { get; set; }
    public Guid? UpdatedByStaffId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public uint Version { get; set; }
}
```

```csharp
// Features/Admin/Role.cs
using ExtraSpace.Api.Platform.Data;

namespace ExtraSpace.Api.Features.Admin;

internal sealed class Role : IHasTimestamps, IHasStaffStamps, IAudited
{
    /// <summary>The system role Owner: every permission, cannot be changed or deleted (seeded by the AdminTables migration).</summary>
    public static readonly Guid OwnerId = Guid.Parse("0199dd00-0000-7000-8000-000000000001");

    public Guid Id { get; init; } = Guid.CreateVersion7();
    public required string Name { get; set; }
    public string[] Permissions { get; set; } = [];
    public bool IsSystem { get; set; }
    public Guid? CreatedByStaffId { get; set; }
    public Guid? UpdatedByStaffId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public uint Version { get; set; }
}
```

```csharp
// Features/Admin/AuditLog.cs
using System.Net;
using System.Text.Json;

namespace ExtraSpace.Api.Features.Admin;

/// <summary>Append-only (S0 spec §5.1): no update or delete path; written only by <see cref="AuditInterceptor"/>.</summary>
internal sealed class AuditLog
{
    public Guid Id { get; init; } = Guid.CreateVersion7();
    public Guid StaffUserId { get; init; }
    public required string Action { get; init; }
    public required string EntityType { get; init; }
    public Guid EntityId { get; init; }
    public required JsonDocument Changes { get; init; }
    public IPAddress? Ip { get; init; }
    public DateTime OccurredAt { get; init; }
}
```

- [ ] **Step 3: Configurations.** `AdminEntityConfigurations.cs`:

```csharp
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace ExtraSpace.Api.Features.Admin;

internal sealed class StaffUserConfiguration : IEntityTypeConfiguration<StaffUser>
{
    public void Configure(EntityTypeBuilder<StaffUser> builder)
    {
        builder.ToTable("staff_user");
        builder.Property(s => s.Id).ValueGeneratedNever();
        builder.Property(s => s.Email).HasMaxLength(254);
        builder.HasIndex(s => s.Email).IsUnique();
        builder.Property(s => s.DisplayName).HasMaxLength(200);
        builder.Property(s => s.EntraObjectId).HasMaxLength(64);
        builder.HasIndex(s => s.EntraObjectId).IsUnique();
        builder.HasOne(s => s.Role).WithMany().HasForeignKey(s => s.RoleId).OnDelete(DeleteBehavior.Restrict);
        builder.Property(s => s.Version).IsRowVersion();
    }
}

internal sealed class RoleConfiguration : IEntityTypeConfiguration<Role>
{
    private static readonly DateTime Seeded = new(2026, 10, 13, 0, 0, 0, DateTimeKind.Utc);

    public void Configure(EntityTypeBuilder<Role> builder)
    {
        builder.ToTable("role");
        builder.Property(r => r.Id).ValueGeneratedNever();
        builder.Property(r => r.Name).HasMaxLength(100);   // unique on lower(name): raw SQL in the AdminTables migration
        builder.Property(r => r.Version).IsRowVersion();
        builder.HasData(new Role { Id = Role.OwnerId, Name = "Owner", IsSystem = true, CreatedAt = Seeded, UpdatedAt = Seeded });
    }
}

internal sealed class AuditLogConfiguration : IEntityTypeConfiguration<AuditLog>
{
    public void Configure(EntityTypeBuilder<AuditLog> builder)
    {
        builder.ToTable("audit_log");
        builder.Property(a => a.Id).ValueGeneratedNever();
        builder.Property(a => a.Action).HasMaxLength(200);
        builder.Property(a => a.EntityType).HasMaxLength(100);
        builder.Property(a => a.Changes).HasColumnType("jsonb");
        builder.HasOne<StaffUser>().WithMany().HasForeignKey(a => a.StaffUserId).OnDelete(DeleteBehavior.Restrict);
        builder.HasIndex(a => a.StaffUserId);
        builder.HasIndex(a => new { a.EntityType, a.EntityId });
        builder.HasIndex(a => a.OccurredAt).IsDescending();
    }
}
```

- [ ] **Step 4: Permission catalogue.**

```csharp
// Features/Admin/Contracts/Permissions.cs
namespace ExtraSpace.Api.Features.Admin.Contracts;

public sealed record Permission(string Name, string Description);

public static class PermissionRegistration
{
    /// <summary>Each feature registers the permissions it checks; one authorization policy is made per name (S0 spec §6.3).</summary>
    public static IServiceCollection AddPermissions(this IServiceCollection services, params Permission[] permissions)
    {
        foreach (var permission in permissions) services.AddSingleton(permission);
        return services;
    }
}
```

```csharp
// Features/Admin/PermissionCatalog.cs
using ExtraSpace.Api.Features.Admin.Contracts;

namespace ExtraSpace.Api.Features.Admin;

internal sealed class PermissionCatalog
{
    public PermissionCatalog(IEnumerable<Permission> permissions)
    {
        All = permissions.OrderBy(p => p.Name, StringComparer.Ordinal).ToList();
        if (All.DistinctBy(p => p.Name).Count() != All.Count) throw new InvalidOperationException("A permission name is registered twice.");
        Names = All.Select(p => p.Name).ToList();
    }

    public IReadOnlyList<Permission> All { get; }
    public IReadOnlyList<string> Names { get; }
    public bool Contains(string name) => Names.Contains(name);
}
```

```csharp
// Features/Admin/AdminPermissions.cs
namespace ExtraSpace.Api.Features.Admin;

internal static class AdminPermissions
{
    public const string StaffManage = "staff.manage";
    public const string RolesManage = "roles.manage";
    public const string AuditRead = "audit.read";
    // The jobs dashboard belongs to Platform, which cannot depend on a feature, so Admin declares it.
    public const string JobsManage = "jobs.manage";
}
```

- [ ] **Step 5: Audit context and interceptor.**

```csharp
// Features/Admin/AuditContext.cs
using System.Net;

namespace ExtraSpace.Api.Features.Admin;

/// <summary>Per request: set by <see cref="AdminRequestFilter"/> for a signed-in admin write, read by <see cref="AuditInterceptor"/>.</summary>
internal sealed class AuditContext
{
    public Guid? StaffId { get; private set; }
    public string Action { get; private set; } = "";
    public IPAddress? Ip { get; private set; }

    public void Begin(Guid staffId, string action, IPAddress? ip) => (StaffId, Action, Ip) = (staffId, action, ip);
}
```

```csharp
// Features/Admin/AuditInterceptor.cs
using System.Reflection;
using System.Text.Json;
using ExtraSpace.Api.Platform.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace ExtraSpace.Api.Features.Admin;

/// <summary>Adds the audit_log rows inside the same SaveChanges as the change, so neither commits without the other.</summary>
internal sealed class AuditInterceptor(AuditContext audit, TimeProvider time) : SaveChangesInterceptor
{
    private static readonly HashSet<string> Skipped =
    [
        nameof(IHasTimestamps.CreatedAt), nameof(IHasTimestamps.UpdatedAt),
        nameof(IHasStaffStamps.CreatedByStaffId), nameof(IHasStaffStamps.UpdatedByStaffId), "Version",
    ];

    public override InterceptionResult<int> SavingChanges(DbContextEventData eventData, InterceptionResult<int> result)
    {
        Record(eventData.Context);
        return result;
    }

    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData, InterceptionResult<int> result, CancellationToken cancellationToken = default)
    {
        Record(eventData.Context);
        return ValueTask.FromResult(result);
    }

    private void Record(DbContext? context)
    {
        if (context is null || audit.StaffId is not { } staffId) return;
        context.ChangeTracker.DetectChanges();
        var now = time.GetUtcNow().UtcDateTime;
        var rows = new List<AuditLog>();
        foreach (var entry in context.ChangeTracker.Entries<IAudited>().ToList())
        {
            if (entry.State is not (EntityState.Added or EntityState.Modified or EntityState.Deleted)) continue;
            if (entry.Entity is IHasStaffStamps)
            {
                if (entry.State == EntityState.Added) entry.Property(nameof(IHasStaffStamps.CreatedByStaffId)).CurrentValue = staffId;
                if (entry.State != EntityState.Deleted) entry.Property(nameof(IHasStaffStamps.UpdatedByStaffId)).CurrentValue = staffId;
            }
            var changes = Changes(entry);
            if (changes.Count == 0) continue;
            rows.Add(new AuditLog
            {
                StaffUserId = staffId,
                Action = audit.Action,
                EntityType = entry.Metadata.GetTableName()!,
                EntityId = (Guid)entry.Property("Id").CurrentValue!,
                Changes = JsonSerializer.SerializeToDocument(changes, JsonSerializerOptions.Web),
                Ip = audit.Ip,
                OccurredAt = now,
            });
        }
        context.AddRange(rows);
    }

    private static Dictionary<string, AuditChange> Changes(EntityEntry entry)
    {
        var changes = new Dictionary<string, AuditChange>();
        foreach (var property in entry.Properties)
        {
            var metadata = property.Metadata;
            if (metadata.IsPrimaryKey() || Skipped.Contains(metadata.Name)
                || metadata.PropertyInfo?.IsDefined(typeof(NotAuditedAttribute)) == true) continue;
            var from = entry.State == EntityState.Added ? null : property.OriginalValue;
            var to = entry.State == EntityState.Deleted ? null : property.CurrentValue;
            if (entry.State == EntityState.Modified && (!property.IsModified || metadata.GetValueComparer().Equals(from, to))) continue;
            changes[JsonNamingPolicy.CamelCase.ConvertName(metadata.Name)] = new AuditChange(from, to);
        }
        return changes;
    }
}

internal sealed record AuditChange(object? From, object? To);
```

- [ ] **Step 6: Setup.** `Features/Admin/AdminSetup.cs`:

```csharp
using ExtraSpace.Api.Features.Admin.Contracts;
using Microsoft.EntityFrameworkCore.Diagnostics;

namespace ExtraSpace.Api.Features.Admin;

internal static class AdminSetup
{
    public static IServiceCollection AddAdminFeature(this IServiceCollection services, IConfiguration configuration, IHostEnvironment environment)
    {
        services.AddPermissions(
            new Permission(AdminPermissions.StaffManage, "Add staff, change their role, deactivate them"),
            new Permission(AdminPermissions.RolesManage, "Create, edit and delete roles"),
            new Permission(AdminPermissions.AuditRead, "Read the audit log"),
            new Permission(AdminPermissions.JobsManage, "Open the background jobs dashboard"));
        services.AddSingleton<PermissionCatalog>();
        services.AddScoped<AuditContext>();
        services.AddScoped<ISaveChangesInterceptor, AuditInterceptor>();
        return services;
    }
}
```

`Program.cs`: after `AddIdentityFeature`, add `builder.Services.AddAdminFeature(builder.Configuration, builder.Environment);`.

- [ ] **Step 7: Migration.**

```bash
dotnet ef migrations add AdminTables --project src/ExtraSpace.Api --output-dir Platform/Data/Migrations
```

Then edit the generated `Up` to add, after `role` is created: `migrationBuilder.Sql("CREATE UNIQUE INDEX ix_role_name_lower ON role (lower(name));");` and in `Down`, before `role` is dropped: `migrationBuilder.Sql("DROP INDEX ix_role_name_lower;");`. Check the migration: `xmin` appears as a mapped concurrency column but **no** `xmin` column is created and the Owner `InsertData` does not write `xmin`; `changes` is `jsonb`; `ip` is `inet`; `permissions` is `text[]`. Report anything else. Strip the BOM from the 3 files.

- [ ] **Step 8: Test helpers.** `tests/ExtraSpace.Api.Tests/TestSupport/AdminTestData.cs` (Task 3 adds the client helpers):

```csharp
using ExtraSpace.Api.Features.Admin;
using ExtraSpace.Api.Platform.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace ExtraSpace.Api.Tests.TestSupport;

internal static class AdminTestData
{
    public static async Task<Role> CreateRoleAsync(this ApiFactory api, params string[] permissions)
    {
        var role = new Role { Name = $"role-{Guid.NewGuid():N}", Permissions = permissions };
        await api.WithDbAsync(async db => { db.Add(role); await db.SaveChangesAsync(); });
        return role;
    }

    public static async Task<StaffUser> CreateStaffAsync(this ApiFactory api, Guid roleId, bool active = true, string? email = null)
    {
        var staff = new StaffUser { Email = email ?? IdentityTestData.NewEmail("s"), RoleId = roleId, Active = active };
        await api.WithDbAsync(async db => { db.Add(staff); await db.SaveChangesAsync(); });
        return staff;
    }

    /// <summary>Runs <paramref name="action"/> in a scope whose saves are audited as <paramref name="staffId"/>.</summary>
    public static async Task AsStaffAsync(this ApiFactory api, Guid staffId, Func<AppDbContext, Task> action)
    {
        await using var scope = api.Services.CreateAsyncScope();
        scope.ServiceProvider.GetRequiredService<AuditContext>().Begin(staffId, "TEST", null);
        await action(scope.ServiceProvider.GetRequiredService<AppDbContext>());
    }

    public static async Task<List<AuditLog>> AuditRowsForAsync(this ApiFactory api, Guid entityId)
    {
        List<AuditLog> rows = [];
        await api.WithDbAsync(async db => rows = await db.Set<AuditLog>().Where(a => a.EntityId == entityId).OrderBy(a => a.Id).ToListAsync());
        return rows;
    }

    /// <summary>Owners collection only: deactivates every Owner so the test starts from "no active Owner".</summary>
    public static Task ClearOwnersAsync(this ApiFactory api) =>
        api.WithDbAsync(db => db.Set<StaffUser>().Where(s => s.RoleId == Role.OwnerId).ExecuteUpdateAsync(u => u.SetProperty(s => s.Active, false)));
}

[CollectionDefinition("Owners", DisableParallelization = true)]
public sealed class OwnersCollection;
```

- [ ] **Step 9: Write the tests.** `tests/ExtraSpace.Api.Tests/Features/Admin/AdminDataTests.cs`. Each test below is required; write it in the style of `IdentityDataTests`:
  - `The_owner_role_is_seeded`: `role` row `OwnerId`, name `Owner`, `is_system` true.
  - `Staff_emails_are_unique`: second insert with the same email → `DbUpdateException` with a unique violation.
  - `Role_names_are_unique_ignoring_case`: `"Ops-<guid>"` then `"ops-<guid>"` → unique violation.
  - `A_stale_version_cannot_be_saved`: load one staff row in two scopes, save a change in the first, then in the second → `DbUpdateConcurrencyException`.
  - `An_audited_create_writes_one_row_with_the_new_values`: `AsStaffAsync(actor)` adds a role → one `audit_log` row: `staff_user_id` = actor, `action` = `TEST`, `entity_type` = `role`, `changes` has `name.to`, `permissions.to`, `isSystem.to` and no `id`, `createdAt`, `version`; the role's `created_by_staff_id` and `updated_by_staff_id` = actor.
  - `An_audited_update_records_only_changed_fields`: change only `Name` → `changes` has exactly `name` with `from`/`to`; `updated_by_staff_id` = actor, `created_by_staff_id` unchanged.
  - `An_audited_delete_records_the_old_values`: delete a role → `changes.name.to` is null, `changes.name.from` is the old name.
  - `Saves_outside_an_admin_write_are_not_audited`: `WithDbAsync` save → no row.
  - `A_failed_save_writes_no_audit_row`: `AsStaffAsync` add a role whose name collides (case-insensitive) → `DbUpdateException`, and no `audit_log` row for the new role id.
  - `The_catalogue_lists_the_s0_permissions`: `PermissionCatalog.Names` equals `audit.read, jobs.manage, roles.manage, staff.manage`.
  - `A_permission_registered_twice_fails`: `new PermissionCatalog([p, p])` throws.

- [ ] **Step 10: Run.**

```bash
dotnet build src/ExtraSpace.Api/ExtraSpace.Api.csproj
dotnet test tests/ExtraSpace.Api.Tests                 # all pass, architecture tests included
```

If the architecture test flags `AuditInterceptor` or anything in `Platform` depending on `Features`, stop and report; never weaken the rule.

- [ ] **Step 11: Hand-off.** Report the diff, the migration checks of Step 7, and the counts.

---

### Task 3: Staff sign-in, cookie, CSRF, policies and the `/admin/api` group

**Files:**
- Modify: `src/ExtraSpace.Api/ExtraSpace.Api.csproj` (OpenIdConnect reference), `src/ExtraSpace.Api/appsettings.json`, `src/ExtraSpace.Api/Program.cs`, `src/ExtraSpace.Api/Features/Admin/AdminSetup.cs`
- Create: `src/ExtraSpace.Api/Features/Admin/AdminOptions.cs`, `StaffAuth.cs`, `StaffSignIn.cs`, `StaffAccess.cs`, `StaffLocks.cs`, `AdminRequestFilter.cs`, `AdminErrors.cs`, `AdminDtos.cs`, `AdminEndpoints.cs`
- Modify (tests): `tests/ExtraSpace.Api.Tests/TestSupport/TestEndpoints.cs`, `TestSupport/AdminTestData.cs`
- Create (tests): `tests/ExtraSpace.Api.Tests/Features/Admin/StaffSignInTests.cs`, `AdminAuthTests.cs`, `AdminLoginTests.cs`, `DevLoginTests.cs`

**Interfaces:**
- Consumes: Task 2 entities, `PermissionCatalog`, `AuditContext`; `RequestLog.Add`, `ProblemWriter.WriteAsync`, `Pii.MaskEmail`, `AppException`.
- Produces:
  - `StaffAuth` constants (`CookieScheme = "Staff"`, `EntraScheme = "Entra"`, `Policy = "Staff"`, `PermissionClaim = "perm"`, cookie names, `CsrfHeader`), `StaffAuth.PrincipalFor(Guid, IEnumerable<string>?)`, `ClaimsPrincipal.StaffId()`, `HttpContext.StaffSession()`.
  - `StaffSession(Guid Id, string Email, string? DisplayName, Guid RoleId, string RoleName, bool IsOwner, IReadOnlyList<string> Permissions)`.
  - `StaffSignIn.ResolveAsync(string? objectId, string? email, string? name, CancellationToken) → Task<Guid?>`.
  - `StaffLocks.OwnersAsync(AppDbContext, CancellationToken)`.
  - `AdminEndpoints.RequireStaff(this RouteGroupBuilder)` and `MapAdminEndpoints(this RouteGroupBuilder, IHostEnvironment)`.
  - Routes: `GET /admin/api/auth/login`, `GET /admin/api/auth/csrf`, `POST /admin/api/auth/logout`, `POST /admin/api/auth/dev-login` (Development), `GET /admin/api/me`.
  - Test helpers: `/test/admin/sign-in/{staffId}`, `api.AdminClient()`, `api.SignedInAdminAsync(staff, withCsrf)`, `api.StaffClientAsync(params string[] permissions)`.

- [ ] **Step 1: Options and config.** `AdminOptions.cs`:

```csharp
namespace ExtraSpace.Api.Features.Admin;

internal sealed class AdminOptions
{
    public const string Section = "Admin";

    /// <summary>First staff emails (S0 spec §6.2); used only while no active Owner exists. Remove once one Owner exists.</summary>
    public string[] BootstrapEmails { get; set; } = [];

    public EntraOptions Entra { get; set; } = new();
}

internal sealed class EntraOptions
{
    public string TenantId { get; set; } = "";
    public string ClientId { get; set; } = "";
    public string ClientSecret { get; set; } = "";

    public bool IsConfigured => TenantId.Length > 0 && ClientId.Length > 0 && ClientSecret.Length > 0;
}
```

`appsettings.json`, after `"AWS"`: `"Admin": { "BootstrapEmails": [], "Entra": { "TenantId": "", "ClientId": "", "ClientSecret": "" } },`. Add the `Microsoft.AspNetCore.Authentication.OpenIdConnect` `PackageReference`.

- [ ] **Step 2: Errors and DTOs.**

```csharp
// Features/Admin/AdminErrors.cs
using ExtraSpace.Api.Platform.Errors;

namespace ExtraSpace.Api.Features.Admin;

internal static class AdminErrors
{
    public static AppException Unauthenticated() => new(401, ErrorCodes.Unauthenticated, "Sign in again.");
    public static AppException NoAccess() => new(403, ErrorCodes.Forbidden, "Your account has no access to the admin. Ask an administrator.");
    public static AppException OwnerOnly() => new(403, ErrorCodes.Forbidden, "Only an Owner can do this.");
    public static AppException NotFound(string what) => new(404, ErrorCodes.NotFound, $"{what} not found.");
    public static AppException Invalid(string title) => new(400, ErrorCodes.ValidationFailed, title);
    public static AppException CsrfFailed() => new(400, "CSRF_FAILED", "The security token is missing or out of date. Reload and try again.");
    public static AppException SignInUnavailable() => new(503, "ADMIN_SIGNIN_UNAVAILABLE", "Admin sign-in is not configured on this server.");
    public static AppException LastOwner() => new(409, "LAST_OWNER", "At least one active Owner must remain.");
    public static AppException CannotDeactivateSelf() => new(409, "CANNOT_DEACTIVATE_SELF", "You cannot deactivate yourself.");
    public static AppException SystemRole() => new(409, "SYSTEM_ROLE", "System roles cannot be changed or deleted.");
    public static AppException RoleInUse() => new(409, "ROLE_IN_USE", "Staff still hold this role. Move them to another role first.");
}
```

`AdminDtos.cs` (Task 4 adds its own records to this file):

```csharp
using System.ComponentModel.DataAnnotations;

namespace ExtraSpace.Api.Features.Admin;

internal sealed record StaffSession(Guid Id, string Email, string? DisplayName, Guid RoleId, string RoleName, bool IsOwner, IReadOnlyList<string> Permissions);

internal sealed record AdminMeResponse(Guid Id, string Email, string? DisplayName, Guid RoleId, string RoleName, IReadOnlyList<string> Permissions);

internal sealed record CsrfResponse(string Token);

// Request bodies are public: the .NET 10 validation generator skips non-public types.
public sealed class DevLoginBody
{
    [Required, EmailAddress, MaxLength(254)]
    public string? Email { get; init; }
}
```

- [ ] **Step 3: Lock helper.** `StaffLocks.cs`:

```csharp
using ExtraSpace.Api.Platform.Data;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Admin;

internal static class StaffLocks
{
    /// <summary>Serialises every write that can change who is an active Owner (bootstrap, role/active changes). Inside a transaction.</summary>
    public static Task OwnersAsync(AppDbContext db, CancellationToken cancellationToken) =>
        db.Database.ExecuteSqlAsync($"SELECT pg_advisory_xact_lock(hashtextextended('staff-owners', 0))", cancellationToken);
}
```

- [ ] **Step 4: `StaffSignIn`** (callback and dev sign-in):

```csharp
using ExtraSpace.Api.Platform.Data;
using ExtraSpace.Api.Platform.Logging;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace ExtraSpace.Api.Features.Admin;

internal sealed partial class StaffSignIn(AppDbContext db, IOptions<AdminOptions> options, TimeProvider time, ILogger<StaffSignIn> logger)
{
    /// <summary>The staff id to sign in, or null when this person may not (unknown, inactive, linked to another Entra user).</summary>
    public async Task<Guid?> ResolveAsync(string? objectId, string? email, string? name, CancellationToken cancellationToken)
    {
        email = email?.Trim().ToLowerInvariant();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        var staff = objectId is null ? null : await db.Set<StaffUser>().FirstOrDefaultAsync(s => s.EntraObjectId == objectId, cancellationToken);
        if (staff is null && email is not null)
        {
            staff = await db.Set<StaffUser>().FirstOrDefaultAsync(s => s.Email == email, cancellationToken);
            if (staff is { EntraObjectId: { } linked } && objectId is not null && linked != objectId)
                return Refuse(email, "linked to another Entra user");
            if (staff is null && options.Value.BootstrapEmails.Any(b => b.Trim().Equals(email, StringComparison.OrdinalIgnoreCase)))
            {
                await StaffLocks.OwnersAsync(db, cancellationToken);
                if (!await db.Set<StaffUser>().AnyAsync(s => s.Active && s.RoleId == Role.OwnerId, cancellationToken))
                {
                    staff = new StaffUser { Email = email, RoleId = Role.OwnerId };
                    db.Add(staff);
                    LogBootstrap(logger, staff.Id);
                }
            }
        }
        if (staff is null) return Refuse(email, "unknown");
        if (!staff.Active) return Refuse(email, "inactive");

        staff.EntraObjectId ??= objectId;
        if (string.IsNullOrWhiteSpace(staff.DisplayName)) staff.DisplayName = name;
        staff.LastSignInAt = time.GetUtcNow().UtcDateTime;
        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        LogSignedIn(logger, staff.Id);
        return staff.Id;
    }

    private Guid? Refuse(string? email, string reason)
    {
        LogRefused(logger, email is null ? "(none)" : Pii.MaskEmail(email), reason);
        return null;
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "Staff {staffId} signed in")]
    private static partial void LogSignedIn(ILogger logger, Guid staffId);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Staff sign-in refused for {email}: {reason}")]
    private static partial void LogRefused(ILogger logger, string email, string reason);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Bootstrap Owner {staffId} created")]
    private static partial void LogBootstrap(ILogger logger, Guid staffId);
}
```

- [ ] **Step 5: `StaffAccess`** (every request):

```csharp
using ExtraSpace.Api.Platform.Data;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Admin;

internal sealed class StaffAccess(AppDbContext db, PermissionCatalog catalog)
{
    public async Task<StaffSession?> LoadAsync(Guid staffId, CancellationToken cancellationToken)
    {
        var row = await db.Set<StaffUser>().Where(s => s.Id == staffId && s.Active)
            .Select(s => new { s.Id, s.Email, s.DisplayName, s.RoleId, RoleName = s.Role.Name, s.Role.Permissions })
            .FirstOrDefaultAsync(cancellationToken);
        if (row is null) return null;
        var isOwner = row.RoleId == Role.OwnerId;
        var permissions = isOwner ? catalog.Names : catalog.Names.Where(row.Permissions.Contains).ToList();
        return new StaffSession(row.Id, row.Email, row.DisplayName, row.RoleId, row.RoleName, isOwner, permissions);
    }

    /// <summary>Cookie OnValidatePrincipal: a deactivation or role change applies at the very next request (plan decision 5).</summary>
    public static async Task ValidateAsync(CookieValidatePrincipalContext context)
    {
        var http = context.HttpContext;
        var session = context.Principal?.StaffId() is { } staffId
            ? await http.RequestServices.GetRequiredService<StaffAccess>().LoadAsync(staffId, http.RequestAborted)
            : null;
        if (session is null)
        {
            context.RejectPrincipal();
            await http.SignOutAsync(StaffAuth.CookieScheme);
            return;
        }
        context.ReplacePrincipal(StaffAuth.PrincipalFor(session.Id, session.Permissions));
        http.Items[typeof(StaffSession)] = session;
    }
}
```

- [ ] **Step 6: `StaffAuth`** (schemes, cookie, OIDC, antiforgery, policies):

```csharp
using System.Security.Claims;
using ExtraSpace.Api.Features.Admin.Contracts;
using ExtraSpace.Api.Platform.Errors;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Authorization;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;

namespace ExtraSpace.Api.Features.Admin;

internal static class StaffAuth
{
    public const string CookieScheme = "Staff";
    public const string EntraScheme = "Entra";
    public const string Policy = "Staff";
    public const string PermissionClaim = "perm";
    public const string CookieName = "__Host-es-admin";
    public const string CsrfCookieName = "__Host-es-csrf";
    public const string CsrfHeader = "X-CSRF-TOKEN";
    public const string CallbackPath = "/admin/api/auth/callback";

    public static ClaimsPrincipal PrincipalFor(Guid staffId, IEnumerable<string>? permissions = null)
    {
        var identity = new ClaimsIdentity(CookieScheme);
        identity.AddClaim(new Claim(ClaimTypes.NameIdentifier, staffId.ToString()));
        foreach (var permission in permissions ?? []) identity.AddClaim(new Claim(PermissionClaim, permission));
        return new ClaimsPrincipal(identity);
    }

    public static Guid? StaffId(this ClaimsPrincipal user) =>
        user.Identity is { IsAuthenticated: true, AuthenticationType: CookieScheme }
        && Guid.TryParse(user.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : null;

    /// <summary>Loaded by <see cref="StaffAccess.ValidateAsync"/> for this request; null when the request is not signed in as staff.</summary>
    public static StaffSession? StaffSession(this HttpContext http) => http.Items[typeof(StaffSession)] as StaffSession;

    public static IServiceCollection AddStaffAuth(this IServiceCollection services, IConfiguration configuration, IHostEnvironment environment)
    {
        var entra = configuration.GetSection(AdminOptions.Section).Get<AdminOptions>()?.Entra ?? new EntraOptions();
        var authentication = services.AddAuthentication().AddCookie(CookieScheme, o =>
        {
            o.Cookie.Name = CookieName;
            o.Cookie.HttpOnly = true;
            o.Cookie.SecurePolicy = CookieSecurePolicy.Always;
            o.Cookie.SameSite = SameSiteMode.Lax;
            o.Cookie.Path = "/";
            o.ExpireTimeSpan = TimeSpan.FromHours(8);
            o.SlidingExpiration = true;
            o.Events = new CookieAuthenticationEvents
            {
                // An API answers with a status, never a redirect (plan decision 6); the status-code pages write the problem.
                OnRedirectToLogin = c => { c.Response.StatusCode = StatusCodes.Status401Unauthorized; return Task.CompletedTask; },
                OnRedirectToAccessDenied = c => { c.Response.StatusCode = StatusCodes.Status403Forbidden; return Task.CompletedTask; },
                OnValidatePrincipal = StaffAccess.ValidateAsync,
            };
        });

        if (entra.IsConfigured)
            authentication.AddOpenIdConnect(EntraScheme, o =>
            {
                o.Authority = $"https://login.microsoftonline.com/{entra.TenantId}/v2.0";
                o.ClientId = entra.ClientId;
                o.ClientSecret = entra.ClientSecret;
                o.ResponseType = OpenIdConnectResponseType.Code;
                o.UsePkce = true;
                o.CallbackPath = CallbackPath;
                o.SignInScheme = CookieScheme;
                o.MapInboundClaims = false;
                o.SaveTokens = false;
                o.Events = new OpenIdConnectEvents
                {
                    OnTokenValidated = OnTokenValidatedAsync,
                    OnRemoteFailure = async c =>
                    {
                        c.HandleResponse();
                        await ProblemWriter.WriteAsync(c.HttpContext, 401, ErrorCodes.Unauthenticated, "Sign-in did not complete. Try again.");
                    },
                };
            });
        else if (environment.IsProduction())
            throw new InvalidOperationException("Admin:Entra:TenantId, ClientId and ClientSecret must be set in Production.");

        services.AddAntiforgery(o =>
        {
            o.HeaderName = CsrfHeader;
            o.Cookie.Name = CsrfCookieName;
            o.Cookie.SecurePolicy = CookieSecurePolicy.Always;
            o.Cookie.SameSite = SameSiteMode.Strict;
            o.SuppressXFrameOptionsHeader = true;   // SecurityHeadersMiddleware sends DENY
        });

        services.AddAuthorizationBuilder()
            .AddPolicy(Policy, p => p.AddAuthenticationSchemes(CookieScheme).RequireAuthenticatedUser());
        services.AddOptions<AuthorizationOptions>().Configure<IEnumerable<Permission>>((o, permissions) =>
        {
            foreach (var permission in permissions)
                o.AddPolicy(permission.Name, p => p.AddAuthenticationSchemes(CookieScheme).RequireClaim(PermissionClaim, permission.Name));
        });
        return services;
    }

    private static async Task OnTokenValidatedAsync(TokenValidatedContext context)
    {
        var user = context.Principal!;
        var http = context.HttpContext;
        var staffId = await http.RequestServices.GetRequiredService<StaffSignIn>().ResolveAsync(
            user.FindFirstValue("oid"), user.FindFirstValue("preferred_username") ?? user.FindFirstValue("email"),
            user.FindFirstValue("name"), http.RequestAborted);
        if (staffId is null)
        {
            context.HandleResponse();
            var error = AdminErrors.NoAccess();
            await ProblemWriter.WriteAsync(http, error.Status, error.Code, error.Title);
            return;
        }
        context.Principal = PrincipalFor(staffId.Value);   // the cookie keeps only the id (plan decision 5)
        context.Properties!.RedirectUri = "/admin";
    }
}
```

Extend `AdminSetup.AddAdminFeature`: `services.Configure<AdminOptions>(configuration.GetSection(AdminOptions.Section)); services.AddScoped<StaffSignIn>(); services.AddScoped<StaffAccess>(); services.AddStaffAuth(configuration, environment);`.

- [ ] **Step 7: `AdminRequestFilter`** (top-level class, carry-over from S0-2b):

```csharp
using ExtraSpace.Api.Platform.Logging;
using Microsoft.AspNetCore.Antiforgery;

namespace ExtraSpace.Api.Features.Admin;

/// <summary>On the /admin/api group: staffId in the request log, CSRF check and audit context for every signed-in write.</summary>
internal sealed class AdminRequestFilter : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        var http = context.HttpContext;
        if (http.User.StaffId() is not { } staffId) return await next(context);   // anonymous routes: login, dev-login
        RequestLog.Add(http, "staffId", staffId);

        var method = http.Request.Method;
        if (HttpMethods.IsGet(method) || HttpMethods.IsHead(method) || HttpMethods.IsOptions(method)) return await next(context);

        var endpoint = http.GetEndpoint();
        if (endpoint?.Metadata.GetMetadata<IAntiforgeryMetadata>() is not { RequiresValidation: false })
        {
            try { await http.RequestServices.GetRequiredService<IAntiforgery>().ValidateRequestAsync(http); }
            catch (AntiforgeryValidationException) { throw AdminErrors.CsrfFailed(); }
        }
        http.RequestServices.GetRequiredService<AuditContext>()
            .Begin(staffId, $"{method} {(endpoint as RouteEndpoint)?.RoutePattern.RawText}", http.Connection.RemoteIpAddress);
        return await next(context);
    }
}
```

- [ ] **Step 8: Endpoints.** `AdminEndpoints.cs`:

```csharp
using System.Net;
using ExtraSpace.Api.Platform.Errors;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Http.HttpResults;

namespace ExtraSpace.Api.Features.Admin;

internal static class AdminEndpoints
{
    /// <summary>Every route of the group needs a signed-in staff member unless it says <c>.AllowAnonymous()</c>.</summary>
    public static RouteGroupBuilder RequireStaff(this RouteGroupBuilder group)
    {
        group.RequireAuthorization(StaffAuth.Policy);
        group.AddEndpointFilter<AdminRequestFilter>();
        return group;
    }

    public static RouteGroupBuilder MapAdminEndpoints(this RouteGroupBuilder admin, IHostEnvironment environment)
    {
        var auth = admin.MapGroup("/auth").WithTags("Admin auth");
        auth.MapGet("/login", Login).AllowAnonymous();
        auth.MapGet("/csrf", Csrf);
        auth.MapPost("/logout", Logout);
        if (environment.IsDevelopment()) auth.MapPost("/dev-login", DevLogin).AllowAnonymous();

        admin.MapGet("/me", GetMe).WithTags("Admin");
        return admin;
    }

    private static async Task<ChallengeHttpResult> Login(IAuthenticationSchemeProvider schemes)
    {
        if (await schemes.GetSchemeAsync(StaffAuth.EntraScheme) is null) throw AdminErrors.SignInUnavailable();
        return TypedResults.Challenge(new AuthenticationProperties { RedirectUri = "/admin" }, [StaffAuth.EntraScheme]);
    }

    private static Ok<CsrfResponse> Csrf(HttpContext http, IAntiforgery antiforgery) =>
        TypedResults.Ok(new CsrfResponse(antiforgery.GetAndStoreTokens(http).RequestToken!));

    private static async Task<NoContent> Logout(HttpContext http)
    {
        await http.SignOutAsync(StaffAuth.CookieScheme);
        return TypedResults.NoContent();
    }

    private static async Task<NoContent> DevLogin(DevLoginBody body, HttpContext http, StaffSignIn signIn, CancellationToken cancellationToken)
    {
        // Development only (mapped above) and loopback only, in case a shared host ever runs as Development.
        if (http.Connection.RemoteIpAddress is not { } ip || !IPAddress.IsLoopback(ip)) throw AdminErrors.NotFound("Route");
        var staffId = await signIn.ResolveAsync(null, body.Email!, null, cancellationToken) ?? throw AdminErrors.NoAccess();
        await http.SignInAsync(StaffAuth.CookieScheme, StaffAuth.PrincipalFor(staffId));
        return TypedResults.NoContent();
    }

    private static Ok<AdminMeResponse> GetMe(HttpContext http) =>
        http.StaffSession() is { } s
            ? TypedResults.Ok(new AdminMeResponse(s.Id, s.Email, s.DisplayName, s.RoleId, s.RoleName, s.Permissions))
            : throw AdminErrors.Unauthenticated();
}
```

`Program.cs` step 14, after the `/api/v1` lines:

```csharp
var admin = app.MapGroup("/admin/api").RequireStaff().WithEnumGuard();   // admin API; cookie + CSRF + audit
admin.MapAdminEndpoints(app.Environment);
```

- [ ] **Step 9: Test helpers.** In `TestEndpoints.Map` add:

```csharp
        test.MapPost("/admin/sign-in/{staffId:guid}", async (Guid staffId, HttpContext http) =>
        {
            await http.SignInAsync(StaffAuth.CookieScheme, StaffAuth.PrincipalFor(staffId));
            return TypedResults.NoContent();
        });
```

Append to `AdminTestData`:

```csharp
    /// <summary>__Host- cookies are Secure, and the cookie container sends them over https only.</summary>
    public static HttpClient AdminClient(this ApiFactory api) =>
        api.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost"), HandleCookies = true });

    public static async Task<HttpClient> SignedInAdminAsync(this ApiFactory api, StaffUser staff, bool withCsrf = true)
    {
        var client = api.AdminClient();
        (await client.PostAsync($"/test/admin/sign-in/{staff.Id}", null)).EnsureSuccessStatusCode();
        if (withCsrf)
        {
            var csrf = await client.GetFromJsonAsync<JsonElement>("/admin/api/auth/csrf");
            client.DefaultRequestHeaders.Add(StaffAuth.CsrfHeader, csrf.GetProperty("token").GetString());
        }
        return client;
    }

    public static async Task<(HttpClient Client, StaffUser Staff)> StaffClientAsync(this ApiFactory api, params string[] permissions)
    {
        var role = await api.CreateRoleAsync(permissions);
        var staff = await api.CreateStaffAsync(role.Id);
        return (await api.SignedInAdminAsync(staff), staff);
    }
```

- [ ] **Step 10: Write the tests.** Each test below is required.

`StaffSignInTests` (`[Collection("Owners")]`; each test calls `api.ClearOwnersAsync()` first; build `StaffSignIn` from a fresh scope, with `Options.Create(new AdminOptions { BootstrapEmails = [...] })` where a test needs bootstrap):
- `An_unknown_email_is_refused`, `An_inactive_staff_member_is_refused`.
- `The_first_sign_in_by_email_links_the_object_id`: then a second call with the same `oid` and a **different** email still resolves to the same staff.
- `An_email_linked_to_another_object_id_is_refused`.
- `The_display_name_and_last_sign_in_are_recorded`: empty name filled; existing name kept.
- `A_bootstrap_email_becomes_owner_while_no_owner_exists`.
- `Bootstrap_is_refused_once_an_active_owner_exists`.
- `The_refusal_line_masks_the_email`: the Warning line has the masked email, never the raw one.

`AdminAuthTests`:
- `Admin_routes_without_a_cookie_get_401_not_a_redirect`: `GET /admin/api/me` → `Problem.ReadAsync(…, 401, "UNAUTHENTICATED")`, no `Location` header.
- `Me_returns_the_staff_member_and_permissions`.
- `A_route_without_the_permission_gets_403`: the real permission routes come in Task 4, so add a test route to `TestEndpoints`: `test.MapGet("/admin/needs-audit", () => TypedResults.Ok()).RequireAuthorization(AdminPermissions.AuditRead);` → 403 `FORBIDDEN` for a role without `audit.read`, 200 with it.
- `A_deactivated_staff_member_is_signed_out_at_the_next_request`: signed in, then `active = false` in the DB → `/me` 401.
- `A_role_change_applies_at_the_next_request`: permission removed from the role in the DB → the needs-audit route goes from 200 to 403.
- `The_cookie_is_host_prefixed_http_only_secure_and_lax`: the `Set-Cookie` of the sign-in has `__Host-es-admin=`, `path=/`, `secure`, `httponly`, `samesite=lax`, and no `domain`.
- `A_write_without_the_csrf_header_is_rejected`: `POST /admin/api/auth/logout` without the header → 400 `CSRF_FAILED`; with it → 204, and `/me` is then 401.
- `A_csrf_token_of_another_staff_member_is_rejected`: token fetched by staff A, sent by staff B (with B's cookies) → 400 `CSRF_FAILED`.
- `Requests_log_the_staff_id`: the summary line of a `/me` call has `staffId`.
- `A_customer_token_does_not_open_admin_routes`: `Authorization: Bearer <customer access token>` on `/admin/api/me` → 401.
- `The_admin_cookie_does_not_open_customer_routes`: signed-in admin client on `/api/v1/me` → 401.
- `Admin_responses_never_allow_credentials_cross_origin` (carry-over): `GET /admin/api/me` and an `OPTIONS` preflight with `Origin: https://app.example.test` → no `Access-Control-Allow-Credentials` header.
- `Login_without_entra_settings_answers_503`: `GET /admin/api/auth/login` → 503 `ADMIN_SIGNIN_UNAVAILABLE`.
- `The_customer_bearer_lock_stays_off_admin_routes`: in `/openapi/v1.json`, `/admin/api/me` has no `security` entry.

`AdminLoginTests` (own host via `api.WithWebHostBuilder`: `App:Role=Api`, `Admin:Entra:TenantId=test-tenant`, `ClientId=test-client`, `ClientSecret=test-client-secret`, and `services.PostConfigure<OpenIdConnectOptions>("Entra", o => o.Configuration = new OpenIdConnectConfiguration { AuthorizationEndpoint = "https://login.example.test/authorize", Issuer = "https://login.example.test/test-tenant/v2.0" })` so no metadata is fetched):
- `Login_redirects_to_entra_with_pkce`: a client with `AllowAutoRedirect = false` and an https base address gets 302; `Location` starts with `https://login.example.test/authorize`, has `client_id=test-client`, `response_type=code`, `code_challenge_method=S256` and `redirect_uri=https%3A%2F%2Flocalhost%2Fadmin%2Fapi%2Fauth%2Fcallback`.
- `Production_refuses_to_start_without_entra_settings`: call `new ServiceCollection().AddLogging().AddStaffAuth(emptyConfig, new HostingEnvironment { EnvironmentName = "Production" })` → `InvalidOperationException` mentioning `Admin:Entra`.

`DevLoginTests`:
- `Dev_login_does_not_exist_outside_development`: default host → `POST /admin/api/auth/dev-login` → 404.
- `Dev_login_signs_in_a_staff_member_from_loopback`: own host with `UseEnvironment("Development")`, `App:Role=Api`, `Seq:Url=""`, `Email:Transport=Log`; client with `X-Forwarded-For: 127.0.0.1` → 204, then `/admin/api/me` 200.
- `Dev_login_refuses_a_remote_caller`: same host, `X-Forwarded-For: 10.9.9.9` → 404.
- `Dev_login_refuses_an_unknown_email`: loopback, unknown email → 403 `FORBIDDEN`.

- [ ] **Step 11: Run.**

```bash
dotnet build src/ExtraSpace.Api/ExtraSpace.Api.csproj
dotnet test tests/ExtraSpace.Api.Tests
```

The S0-3 customer tests must stay green: adding the cookie scheme removes the automatic default scheme, and the `Customer` policy already names its own scheme. If any customer test breaks, stop and report.

- [ ] **Step 12: Hand-off.** Report the diff, the counts, and anything in the framework that behaved differently from this plan (antiforgery claim binding, `ReplacePrincipal` and sliding renewal, OIDC events).

---

### Task 4: Staff, roles, permissions and audit endpoints

**Files:**
- Create: `src/ExtraSpace.Api/Features/Admin/StaffService.cs`, `RoleService.cs`, `AuditQuery.cs`
- Modify: `src/ExtraSpace.Api/Features/Admin/AdminDtos.cs`, `AdminEndpoints.cs`, `AdminSetup.cs`
- Modify: `src/ExtraSpace.Api/Platform/Errors/AppExceptionHandler.cs` (foreign-key violation → 409)
- Modify (tests): `tests/ExtraSpace.Api.Tests/Platform/ExceptionClassifyTests.cs`
- Create (tests): `tests/ExtraSpace.Api.Tests/Features/Admin/StaffEndpointsTests.cs`, `OwnerRulesTests.cs`, `RoleEndpointsTests.cs`, `PermissionsEndpointTests.cs`, `AuditEndpointTests.cs`

**Interfaces:**
- Routes:
  - `GET /admin/api/staff` (`staff.manage`) → `StaffResponse[]`
  - `POST /admin/api/staff` (`staff.manage`) `AddStaffBody` → 201 `StaffResponse`
  - `PATCH /admin/api/staff/{id}` (`staff.manage`) `UpdateStaffBody` → 200 `StaffResponse`
  - `GET /admin/api/roles` (signed in) → `RoleResponse[]`
  - `POST /admin/api/roles` (`roles.manage`) `CreateRoleBody` → 201 `RoleResponse`
  - `PATCH /admin/api/roles/{id}` (`roles.manage`) `UpdateRoleBody` → 200 `RoleResponse`
  - `DELETE /admin/api/roles/{id}?version=` (`roles.manage`) → 204
  - `GET /admin/api/permissions` (signed in) → `PermissionResponse[]`
  - `GET /admin/api/audit?staffId&entityType&entityId&from&to&page&pageSize` (`audit.read`) → `AuditPage`

- [ ] **Step 1: DTOs.** Append to `AdminDtos.cs`:

```csharp
internal sealed record StaffResponse(Guid Id, string Email, string? DisplayName, Guid RoleId, string RoleName, bool Active, DateTime? LastSignInAt, uint Version);

internal sealed record RoleResponse(Guid Id, string Name, IReadOnlyList<string> Permissions, bool IsSystem, int StaffCount, uint Version);

internal sealed record PermissionResponse(string Name, string Description);

internal sealed record AuditItem(Guid Id, DateTime OccurredAt, Guid StaffId, string StaffEmail, string Action, string EntityType, Guid EntityId, JsonElement Changes, string? Ip);

internal sealed record AuditPage(IReadOnlyList<AuditItem> Items, int Total, int Page, int PageSize);

public sealed class AddStaffBody
{
    [Required, EmailAddress, MaxLength(254)]
    public string? Email { get; init; }

    [Required]
    public Guid? RoleId { get; init; }
}

public sealed class UpdateStaffBody
{
    public Guid? RoleId { get; init; }
    public bool? Active { get; init; }

    [Required]
    public uint? Version { get; init; }
}

public sealed class CreateRoleBody
{
    [Required, MinLength(1), MaxLength(100)]
    public string? Name { get; init; }

    [Required]
    public string[]? Permissions { get; init; }
}

public sealed class UpdateRoleBody
{
    [MinLength(1), MaxLength(100)]
    public string? Name { get; init; }

    public string[]? Permissions { get; init; }

    [Required]
    public uint? Version { get; init; }
}
```

`OccurredAt` and `LastSignInAt` come from `timestamptz` and are Kind Utc. Check that the JSON shows `Z`.

- [ ] **Step 2: `StaffService`.** Exact code for the update path (concurrency and the Owner rules):

```csharp
using ExtraSpace.Api.Platform.Data;
using Microsoft.EntityFrameworkCore;

namespace ExtraSpace.Api.Features.Admin;

internal sealed class StaffService(AppDbContext db)
{
    public Task<List<StaffResponse>> ListAsync(CancellationToken cancellationToken) =>
        Responses(db.Set<StaffUser>()).OrderBy(s => s.Email).ToListAsync(cancellationToken);

    public async Task<StaffResponse> AddAsync(StaffSession actor, AddStaffBody body, CancellationToken cancellationToken)
    {
        var roleId = body.RoleId!.Value;
        if (roleId == Role.OwnerId && !actor.IsOwner) throw AdminErrors.OwnerOnly();
        if (!await db.Set<Role>().AnyAsync(r => r.Id == roleId, cancellationToken)) throw AdminErrors.Invalid("The role does not exist.");
        var staff = new StaffUser { Email = body.Email!.Trim().ToLowerInvariant(), RoleId = roleId };
        db.Add(staff);
        await db.SaveChangesAsync(cancellationToken);   // a second row with the same email → unique violation → 409 CONFLICT
        return await GetAsync(staff.Id, cancellationToken);
    }

    public async Task<StaffResponse> UpdateAsync(StaffSession actor, Guid id, UpdateStaffBody body, CancellationToken cancellationToken)
    {
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        if (body.RoleId is not null || body.Active is not null) await StaffLocks.OwnersAsync(db, cancellationToken);
        var staff = await db.Set<StaffUser>().FirstOrDefaultAsync(s => s.Id == id, cancellationToken) ?? throw AdminErrors.NotFound("Staff member");
        db.Entry(staff).Property(s => s.Version).OriginalValue = body.Version!.Value;   // stale → DbUpdateConcurrencyException → 409

        if (body.Active == false && id == actor.Id) throw AdminErrors.CannotDeactivateSelf();
        if (body.RoleId is { } roleId && roleId != staff.RoleId && !await db.Set<Role>().AnyAsync(r => r.Id == roleId, cancellationToken))
            throw AdminErrors.Invalid("The role does not exist.");

        var wasOwner = staff.Active && staff.RoleId == Role.OwnerId;
        staff.RoleId = body.RoleId ?? staff.RoleId;
        staff.Active = body.Active ?? staff.Active;
        var isOwner = staff.Active && staff.RoleId == Role.OwnerId;

        if (wasOwner != isOwner || (body.RoleId == Role.OwnerId && db.Entry(staff).Property(s => s.RoleId).IsModified))
        {
            // Re-checked under the lock: the session was loaded before another Owner may have demoted this actor.
            if (!await db.Set<StaffUser>().AnyAsync(s => s.Id == actor.Id && s.Active && s.RoleId == Role.OwnerId, cancellationToken))
                throw AdminErrors.OwnerOnly();
            if (wasOwner && !isOwner
                && !await db.Set<StaffUser>().AnyAsync(s => s.Id != id && s.Active && s.RoleId == Role.OwnerId, cancellationToken))
                throw AdminErrors.LastOwner();
        }

        await db.SaveChangesAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return await GetAsync(id, cancellationToken);
    }

    private Task<StaffResponse> GetAsync(Guid id, CancellationToken cancellationToken) =>
        Responses(db.Set<StaffUser>().Where(s => s.Id == id)).SingleAsync(cancellationToken);

    private static IQueryable<StaffResponse> Responses(IQueryable<StaffUser> staff) =>
        staff.Select(s => new StaffResponse(s.Id, s.Email, s.DisplayName, s.RoleId, s.Role.Name, s.Active, s.LastSignInAt, s.Version));
}
```

The condition `wasOwner != isOwner` covers both "demote/deactivate an Owner" and "grant Owner / reactivate an Owner". Changing an inactive Owner to another role leaves `wasOwner == isOwner == false` and is allowed for `staff.manage`; report it if you think it should be Owner-only.

- [ ] **Step 3: `RoleService`:**
  - `ListAsync`: every role, ordered system first then by name, with `StaffCount` (subquery count of staff with that role, active or not) and, for the Owner, `Permissions = catalog.Names`.
  - `CreateAsync(CreateRoleBody)`: name trimmed; permissions distinct and ordinal-sorted; each must be in `PermissionCatalog`, else `AdminErrors.Invalid($"Unknown permission '{name}'.")`. A duplicate name (ignoring case) is a unique violation → 409 `CONFLICT`.
  - `UpdateAsync(Guid id, UpdateRoleBody)`: not found → 404; `IsSystem` → `SystemRole()`; set `Version` original value; apply name/permissions with the same checks; save.
  - `DeleteAsync(Guid id, uint version)`: not found → 404; `IsSystem` → `SystemRole()`; any staff with the role → `RoleInUse()`; set `Version` original value; `db.Remove(role)`; save. A role assigned between the check and the delete raises a foreign-key violation → 409 `CONFLICT` (Step 5).

- [ ] **Step 4: `AuditQuery.SearchAsync(Guid? staffId, string? entityType, Guid? entityId, DateTimeOffset? from, DateTimeOffset? to, int page, int pageSize, CancellationToken)`:**
  - `page < 1`, `pageSize` outside 1–100, or `from > to` → `AdminErrors.Invalid(...)`.
  - Filters on `staff_user_id`, `entity_type`, `entity_id`, `occurred_at >= from.UtcDateTime`, `occurred_at < to.UtcDateTime`.
  - `Total = CountAsync`; items ordered by `OccurredAt` desc, then `Id` desc; `Skip((page - 1) * pageSize).Take(pageSize)`; joined to `staff_user` for `StaffEmail`.
  - Map `Changes.RootElement.Clone()` and `Ip?.ToString()` in memory after the query.

- [ ] **Step 5: Foreign-key violation → 409.** In `AppExceptionHandler.Classify`, next to the unique violation:

```csharp
        _ when HasSqlState(exception, PostgresErrorCodes.ForeignKeyViolation) => (409, ErrorCodes.Conflict, "The record is still in use, or refers to one that no longer exists."),
```

Rename `IsUniqueViolation` to `HasSqlState(Exception, string sqlState)` and use it for both. Add a `[Fact]` to `ExceptionClassifyTests` in the same style as the unique-violation one.

- [ ] **Step 6: Endpoints.** In `MapAdminEndpoints`, after `/me`:

```csharp
        var staff = admin.MapGroup("/staff").WithTags("Staff").RequireAuthorization(AdminPermissions.StaffManage);
        staff.MapGet("", ListStaff);
        staff.MapPost("", AddStaff);
        staff.MapPatch("/{id:guid}", UpdateStaff);

        var roles = admin.MapGroup("/roles").WithTags("Roles");
        roles.MapGet("", ListRoles);
        roles.MapPost("", CreateRole).RequireAuthorization(AdminPermissions.RolesManage);
        roles.MapPatch("/{id:guid}", UpdateRole).RequireAuthorization(AdminPermissions.RolesManage);
        roles.MapDelete("/{id:guid}", DeleteRole).RequireAuthorization(AdminPermissions.RolesManage);

        admin.MapGet("/permissions", ListPermissions).WithTags("Roles");
        admin.MapGet("/audit", SearchAudit).WithTags("Audit").RequireAuthorization(AdminPermissions.AuditRead);
```

Handlers follow the `IdentityEndpoints` style: thin, typed results, the actor from `http.StaffSession() ?? throw AdminErrors.Unauthenticated()`. `AddStaff` and `CreateRole` return `TypedResults.Created((string?)null, response)`. `DeleteRole` takes `[FromQuery] uint version` (a missing value is a binding failure → 400 `VALIDATION_FAILED`). `SearchAudit` takes `int page = 1, int pageSize = 50`. Register `StaffService`, `RoleService` and `AuditQuery` as scoped in `AdminSetup`.

- [ ] **Step 7: Write the tests.** Each test below is required. Use `api.StaffClientAsync(...)` for non-Owner actors.

`StaffEndpointsTests`:
- `Staff_routes_need_staff_manage`: without → 403 `FORBIDDEN` on GET, POST and PATCH.
- `Adding_staff_writes_an_audit_row`: 201; the body has `version`; one `audit_log` row: `action` = `POST /admin/api/staff`, `entity_type` = `staff_user`, `staff_user_id` = actor, `changes.email.to` = the lower-cased email; the row's `created_by_staff_id` = actor.
- `An_email_already_used_in_another_case_gets_409`.
- `An_unknown_role_gets_400`.
- `Changing_the_role_records_only_that_field`: 200, new `version` ≠ old; the audit row's `changes` has only `roleId` with `from`/`to`.
- `A_stale_version_gets_409_and_changes_nothing`: PATCH with the old version after another PATCH → 409 `CONFLICT`; role unchanged; no new audit row.
- `A_missing_version_gets_400`: 400 `VALIDATION_FAILED` with `errors.version`.
- `Nobody_can_deactivate_themself`: 409 `CANNOT_DEACTIVATE_SELF`.
- `Only_an_owner_can_grant_the_owner_role`: a `staff.manage` non-Owner → POST with `roleId = OwnerId` → 403; PATCH of themself to Owner → 403.
- `The_list_shows_role_name_and_last_sign_in`.

`OwnerRulesTests` (`[Collection("Owners")]`, `ClearOwnersAsync` first):
- `The_only_owner_cannot_demote_themself`: 409 `LAST_OWNER`; still Owner.
- `Only_an_owner_can_change_an_owner`: a `staff.manage` non-Owner deactivates or demotes an Owner → 403.
- `An_owner_can_demote_another_owner`: two Owners, A demotes B → 200.
- `Two_owners_demoting_each_other_at_once_leave_one_owner`: A and B PATCH each other to a plain role in parallel (`Task.WhenAll`) → exactly one 200; the other 403 or 409; exactly one active Owner afterwards.
- `An_owner_has_every_permission`: Owner's `/admin/api/me` lists all four.

`RoleEndpointsTests`:
- `Creating_a_role_writes_an_audit_row`: 201, permissions sorted; one audit row.
- `An_unknown_permission_gets_400`.
- `A_duplicate_name_ignoring_case_gets_409`.
- `The_owner_role_cannot_be_edited_or_deleted`: PATCH and DELETE → 409 `SYSTEM_ROLE`.
- `A_role_in_use_cannot_be_deleted`: 409 `ROLE_IN_USE`.
- `Deleting_with_a_stale_version_gets_409`.
- `Deleting_a_role_records_its_old_values`: 204; audit row with `changes.name.from` and `to` null.
- `Any_signed_in_staff_member_can_list_roles`: a role with no permissions → 200; the Owner row lists every permission.
- `Role_writes_need_roles_manage`: 403.

`PermissionsEndpointTests`:
- `The_catalogue_lists_names_and_descriptions`: four entries, any signed-in staff member.

`AuditEndpointTests`:
- `Audit_needs_audit_read`: 403 without.
- `Filters_by_staff_and_entity`: two actors write; the filter returns only the matching rows.
- `Pages_newest_first_with_a_total`: 3 rows, `pageSize=2` → page 1 has the 2 newest, `total` ≥ 3 for the entity filter; page 2 has the oldest.
- `Filters_by_time_range`: `from` after all rows → empty.
- `Rejects_a_page_size_over_100`: 400 `VALIDATION_FAILED`.
- `Changes_come_back_as_a_json_object`: `changes.roleId.from` / `.to` readable as strings.

- [ ] **Step 8: Run.**

```bash
dotnet build src/ExtraSpace.Api/ExtraSpace.Api.csproj
dotnet test tests/ExtraSpace.Api.Tests
```

- [ ] **Step 9: Hand-off.** Report the diff, the counts, and every reader you checked for the `AppExceptionHandler` change (checklist §1).

---

### Task 5: Hangfire dashboard behind `jobs.manage`, and the whole-flow tests

**Files:**
- Create: `src/ExtraSpace.Api/Features/Admin/JobsDashboard.cs`
- Modify: `src/ExtraSpace.Api/Program.cs` (one line)
- Create (tests): `tests/ExtraSpace.Api.Tests/Features/Admin/JobsDashboardTests.cs`, `AdminFlowTests.cs`

- [ ] **Step 1: Dashboard.**

```csharp
using Hangfire;
using Hangfire.Dashboard;

namespace ExtraSpace.Api.Features.Admin;

internal static class JobsDashboard
{
    /// <summary>S0 spec §7: /admin/jobs, behind admin sign-in + jobs.manage. Hangfire uses the app's antiforgery for its own POSTs.</summary>
    public static IEndpointConventionBuilder MapJobsDashboard(this IEndpointRouteBuilder app) =>
        app.MapHangfireDashboard("/admin/jobs", new DashboardOptions
        {
            Authorization = [],   // the policy decides; Hangfire's default allows local requests only
            AppPath = "/admin",
            DashboardTitle = "ExtraSpace jobs",
            DisplayStorageConnectionString = false,
        }).RequireAuthorization(AdminPermissions.JobsManage);
}
```

`Program.cs`, after `admin.MapAdminEndpoints(app.Environment);`: `app.MapJobsDashboard();`.

- [ ] **Step 2: Write the tests.** Each test below is required.

`JobsDashboardTests`:
- `The_dashboard_needs_a_signed_in_staff_member`: `GET /admin/jobs` without a cookie → 401 `UNAUTHENTICATED` problem, no redirect.
- `The_dashboard_needs_jobs_manage`: staff without it → 403 `FORBIDDEN`.
- `Staff_with_jobs_manage_open_the_dashboard`: 200, `text/html`.
- `Dashboard_actions_need_the_antiforgery_token`: staff with `jobs.manage`, a client **without** the CSRF header, `POST /admin/jobs/recurring/trigger` with form `jobs[]=IdentityHousekeeping` → not 2xx (Hangfire answers 403); with the token in the header → 204. If Hangfire behaves differently, report the real status and do not loosen the check.

`AdminFlowTests` (`[Collection("Owners")]`; spec §11 items 4–5 without Entra):
- `An_owner_adds_a_limited_staff_member_who_cannot_manage_staff`: Owner creates role `{audit.read}`, adds staff X with it; X signs in (test route) → `GET /admin/api/staff` 403, `GET /admin/jobs` 403, `GET /admin/api/audit` 200 and shows the Owner's two writes (`POST /admin/api/roles`, `POST /admin/api/staff`) with the Owner's `staffId`.
- `An_admin_flow_logs_no_cookie_or_csrf_token`: after a sign-in, a CSRF fetch and one write, no captured log line (`api.Logs.All()` raw text) contains the `__Host-es-admin` cookie value or the CSRF token.

- [ ] **Step 3: Run the whole suite and the architecture tests.**

```bash
dotnet build ExtraSpace.slnx            # 0 warnings, 0 errors
dotnet test tests/ExtraSpace.Api.Tests
dotnet test tests/ExtraSpace.Engines.Tests
dotnet test tests/ExtraSpace.Infra.Tests
```

- [ ] **Step 4: Hand-off.** Report the diff and the counts per project.

---

### Task 6: Review, local walk, migration script, docs (main session)

- [ ] **Step 1: Whole-branch review** by the `code-reviewer` agent against this plan, spec §6.2–§6.3 and the engineering checklist. Read the full diff of `AuditInterceptor`, `StaffService`, `StaffSignIn`, `StaffAccess`, `AdminRequestFilter`, `StaffAuth` and `PlatformServices` yourself. Send defects back to an implementer; scoped re-review.
- [ ] **Step 2: Local walk** (`dev-walker`, local Docker DB, one app, GET-first; memory `feedback-parallel-walkers`). Nobody inserts a staff row by hand (no SQL writes): start the app with `Admin__BootstrapEmails__0=<a test address>` and let `dev-login` create the first Owner. Cases: dev-login → `/me` (four permissions) → CSRF fetch → create role → add staff → stale PATCH 409 → self-deactivate 409 → audit list shows the writes → `/admin/jobs` 200 → logout → `/me` 401 → `dev-login` from a non-loopback `X-Forwarded-For` 404. Check `data_protection_keys` gets its key locally (Development) and the request summary lines carry `staffId`. Kill the app after.
- [ ] **Step 3: Migration script.** `dotnet ef migrations script AddCustomerIdentity AdminTables --idempotent` → `docs/migrations/2026-10-13-admin-tables.sql` (strip the BOM). Not run on staging (S0-6 runs the scripts in order).
- [ ] **Step 4: Docs.**
  - `docs/notes/cms/built-so-far.md`: add "Built so far (S0-4)": admin group, `RequireStaff`, `AdminRequestFilter`, permissions via `AddPermissions` + `.RequireAuthorization("<perm>")`, audit via `IAudited` / `IHasStaffStamps` / `[NotAudited]` and the ban on `ExecuteUpdate` in admin writes, `xmin` `Version` + `version` on the wire, `StaffSession()`, the Owners test collection, `AdminClient()` (https), key ring location.
  - Spec: §5.1 (`data_protection_keys` now Development/Testing only; `audit_log` has no `created_at`/`updated_at`), §6.2 and §6.3 "As built" (decisions 1–17).
  - Plan index: S0-4 status, and carry-overs below.
  - `.claude/rules/cross-repo.md` §4: the S0-4 decision line (already added 2026-10-13 with the plan); update it with the as-built facts.
  - Guide `docs/notes/cms/minimal-apis-vs-mvc.md`: typed endpoint filter class vs MVC action filter; cookie auth + antiforgery for a JSON API; policies per permission.
- [ ] **Step 5: Carry-overs to write into the plan index.**
  - **S0-5 (admin UI):**
    - On 401, navigate the whole page to `/admin/api/auth/login` (not a fetch). After sign-in, `GET /auth/csrf` and send `X-CSRF-TOKEN` on every write; on 400 `CSRF_FAILED`, fetch a new token and retry once.
    - Send `version` on every PATCH and `?version=` on DELETE; on 409 `CONFLICT`, reload the record.
    - Hide Owner-only actions for non-Owners (`me.roleName` / role id); the server still refuses them.
    - The Entra callback answers 403 JSON for an unknown person; S0-5 may turn it into a page.
    - `/admin/jobs` without a cookie answers 401 JSON; the menu link shows only with `jobs.manage`.
  - **S0-6 (delivery):**
    - Env vars on the `api` and `jobs` services: `DataProtection__SsmPath=/es/<env>/data-protection/`, `Admin__Entra__TenantId`, `Admin__Entra__ClientId`, `Admin__Entra__ClientSecret` (secret `es/<env>/entra-client-secret`), `Admin__BootstrapEmails__0` (remove after the first Owner signs in).
    - Task role: `ssm:GetParametersByPath` and `ssm:PutParameter` on `arn:aws:ssm:<region>:<account>:parameter/es/<env>/data-protection*`. The default `aws/ssm` key needs no explicit KMS grant (verify on the first staging deploy).
    - The first deploy race on an empty key ring still applies (S0-3 carry-over), now in SSM.
    - Client IT registers the Entra app: single tenant, web platform, redirect `https://<host>/admin/api/auth/callback` (plus `http://localhost:5080/admin/api/auth/callback` only if the owner wants live Entra locally), a client secret, ID token claims `oid`, `preferred_username`, `name`. Calendar the secret's expiry.
    - Staging walk: a real Entra sign-in, an unknown company user → 403, and one email job after the key ring moved to SSM.
- [ ] **Step 6: Hand-off to the owner:** verdict per task, test counts, walk result, the commit message (owner commits).

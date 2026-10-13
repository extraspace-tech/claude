# S0-5 Admin UI shell — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this workspace the implementer is the Opus `implementer` agent and the reviewer the Opus `code-reviewer` agent; Task 7 is run by the main session only. Agents never commit (memory `feedback-sdd-without-commits`).

**Goal:** A staff member opens `/admin`, signs in with their email and a one-time code, and gets the admin shell: sidebar, header, an empty dashboard, and working Staff, Roles and Audit screens, with menus and buttons hidden by permission. The monolith serves the built UI itself, and the UI's API types are generated from our OpenAPI document.

**Architecture:**
- **Server (`src/ExtraSpace.Api`).** Static files in pipeline slot 7 serve `wwwroot/admin/`. A fallback route (`Platform/Http/AdminSpa.cs`, slot 15) answers every other `/admin/...` page address with `index.html`, but never `/admin/api/*` or `/admin/jobs/*`. `SecurityHeadersMiddleware` adds a Content-Security-Policy to the admin pages. The OpenAPI document gets a `Problem` schema and a `default` error response on every operation, and integers stop accepting strings (`JsonNumberHandling.Strict`).
- **Contract file.** `admin-ui/openapi.json` is a committed copy of `/openapi/v1.json`. An xUnit test fails when it differs from the running app. `npm run gen:api` turns it into `admin-ui/src/api/schema.d.ts`. No running app is needed to generate types.
- **UI (`admin-ui/`).** React + Vite + TypeScript. One `openapi-fetch` client (`src/api/client.ts`) owns the three cross-cutting rules: the CSRF header on writes (with one retry on `CSRF_FAILED`), "401 means show the login screen", and turning every error body into one `ApiError` that carries `code` and `traceId`. TanStack Query holds server data; the signed-in staff member is the query `['me']`. Pages live in `src/features/<feature>/`; shared pieces in `src/components/`.

**Tech Stack** (every version below was installed and run together in a throwaway spike on 2026-10-13; the report with every working file is `docs/notes/cms/s0-5-toolchain-spike.md`, called "the spike note" below):
- Server: .NET 10, Minimal APIs, `Microsoft.AspNetCore.OpenApi` (no new package).
- UI runtime: `react` / `react-dom` 19.3.0, `react-router` 8.4.0, `@tanstack/react-query` 5.104.2, `@tanstack/react-table` 9.3.1, `react-hook-form` 7.90.0, `zod` 4.6.7, `@hookform/resolvers` 5.9.1, `openapi-fetch` 0.17.0, `lucide-react` 1.56.0, `sonner` 2.0.8, `radix-ui` 1.8.1, `class-variance-authority` 0.7.1, `clsx` 2.1.1, `tailwind-merge` 3.7.0, `tw-animate-css` 1.4.0, `@fontsource-variable/geist` 5.3.0, `shadcn` 4.21.4 (its CSS file is imported).
- UI tooling: `vite` 8.3.4, `@vitejs/plugin-react` 6.1.2, `tailwindcss` + `@tailwindcss/vite` 4.3.3, 🔴 **`typescript` 6.0.3** (not 7: the `openapi-typescript` CLI crashes on TypeScript 7, which has no JS compiler API), `openapi-typescript` 7.13.0, `vitest` 5.0.4, `jsdom` 30.1.2, `msw` 3.0.3, `@testing-library/react` 16.3.3, `@testing-library/user-event` 14.6.8, `@testing-library/jest-dom` 7.0.1, `@types/react` / `@types/react-dom` 19.3.0, `@types/node` 26.6.5.
- 🔴 These majors differ from what most examples online show. Before writing against a library, read the spike note's "Differs from the previous major" section: React Router 8 imports from `react-router` and `react-router/dom`; TanStack Table 9 uses `useTable` + `tableFeatures` + `<table.FlexRender>`; MSW 3 renamed `onUnhandledRequest` to `onUnhandledFrame`; Zod 4 has `z.email()`; TypeScript 6 rejects `baseUrl`.

**Spec:** `docs/superpowers/specs/2026-10-09-s0-foundation-design.md`: §4.1 errors, §4.2 pipeline (slots 5, 7, 15), §4.4 (`traceId` on every error toast), §4.5 API docs, §6.2 "As built in S0-4b" (sign-in), §6.3 "As built in S0-4" (staff, roles, audit rules), §8 Admin UI shell, §10 testing. Also read `docs/superpowers/plans/2026-10-12-s0-plan-index.md` (every "→ S0-5" carry-over), `docs/notes/cms/built-so-far.md` and `.claude/rules/cms.md`. Look reference (read only, never copied as files): `../Backend Demo/backend/admin-ui/src/components/layout/` and `src/pages/LoginPage.tsx`.

**Clients affected:**
- **Admin UI:** this plan builds it.
- **Flutter:** decision 1 changes how request bodies are read on **every** route: a number sent as a string (`"count": "5"`) is now 400 `VALIDATION_FAILED`. The app is not built yet, so nothing breaks; it goes into the contract notes.
- **S0-6 delivery:** the Docker build runs `npm ci && npm run build` in `admin-ui/` before `dotnet publish`; CI runs `npm run check:api`, `npm run typecheck`, `npm test`.
- **Cron, Stripe:** none.

## Global Constraints

- **Repo and branch.** Repo `../CMS` (`extraspace-tech/cms`, 🔴 PUBLIC). Work on branch `s0-5-admin-ui-shell`, cut from `main` at `583118a`. **Never `git commit`, `push`, `stash` or `reset`.** The owner commits.
- **No secrets in the repo.** No connection string, AWS account id, real email address or real staff name in any file, test fixtures included. Test addresses end in `@example.test`.
- **Agent limits.** Subagents never run `dotnet user-secrets`, `docker compose` or any AWS command, never dispatch subagents, and never start the API (`dotnet run`). UI tests use MSW, not a live API.
- **Files.** No new `.md` file inside `../CMS` (a hook blocks it; this also means no `admin-ui/README.md`). LF line endings. Match `.editorconfig` and the surrounding idiom: low comment density, one-line "why" comments.
- **C# rules (unchanged from S0-4):** package versions only in `Directory.Packages.props`; `internal sealed` unless a test or another layer needs the type; file-scoped namespaces; handlers call services, never `AppDbContext`; errors are thrown as `AppException`; `Program.cs` maps groups and calls `Map…` extension methods only, never a handler lambda.
- **Tests (C#).** Environment `Testing`. `ExtraSpace.Api.Tests` needs Docker. Filter form: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*AdminSpaTests"`. Every `WithWebHostBuilder` host sets `App:Role=Api`. Only tests in the xUnit collection `Owners` create or change Owners.
- **Node.** Node 24.18 at `~/.local/share/node-v24.18.0/bin` (put it on `PATH`). Node is a dev and CI tool only: nothing in production runs it.
- **UI rules (spec §8).**
  - TypeScript `strict`. No `any`, no `// @ts-ignore`, no `as` cast on an API response: API types come only from `src/api/schema.d.ts`.
  - `src/api/schema.d.ts` is generated. Never edit it by hand; run `npm run gen:api`.
  - Every HTTP call goes through `src/api/client.ts`. No `fetch` anywhere else, no second client.
  - **No business rule in the browser.** The UI hides what a staff member may not do, but the server decides. Never compute a permission, an Owner rule or a conflict in the UI beyond hiding a control.
  - **No generic CRUD engine.** Each screen names its own endpoints. Shared components (`PageShell`, `DataTable`, `ConfirmDialog`, `FormField`) are configured per page.
  - No inline `<script>` and no external URL (fonts, CDNs, analytics) in `index.html` or the code: the CSP is `script-src 'self'`.
  - Nothing sensitive in `localStorage` or `sessionStorage`. The sign-in lives in the HttpOnly cookie; the CSRF token lives in memory only. `localStorage` holds only the theme choice.
  - Every error the user sees shows the `traceId` with a copy button (spec §4.4).
- **Spec values (verbatim):** header `X-CSRF-TOKEN`; CSRF failure 400 `CSRF_FAILED`; sign-in routes `POST /admin/api/auth/code` (always 202) and `POST /admin/api/auth/code/verify` (204); codes are 6 digits, valid 10 minutes, 60 s between sends; permissions `staff.manage`, `roles.manage`, `audit.read`, `jobs.manage`; dashboard `/admin/jobs`; build output `src/ExtraSpace.Api/wwwroot/admin/` (git-ignored).

## Review Focus

1. **The fallback swallows an API miss.** `GET /admin/api/nope` or `POST /admin/staff` must be a 404 JSON problem, never `index.html` with 200; `/admin/jobs` without a cookie must stay 401 JSON. Pinned by Task 1 `Api_and_jobs_paths_never_get_the_page`.
2. **A missing asset returns the page.** `/admin/assets/old-hash.js` after a deploy must be 404, not HTML (the browser would try to run HTML as a script). Pinned by Task 1 `A_missing_asset_is_404_not_the_page`.
3. **The session ends mid-work.** A 401 on any call (cookie expired, staff deactivated) must show the login screen and, after sign-in, the same address. It must not loop, and the old CSRF token must not be reused. Pinned by Task 3 `a 401 drops the session and the csrf token` and Task 4 `shows the login screen when a later call gets 401`.
4. **A stale CSRF token.** The first write after a new sign-in (or after the key ring rotated) gets 400 `CSRF_FAILED`. Expected: one silent refetch and one retry; a second failure is shown. Pinned by Task 3 `retries a write once after CSRF_FAILED`.
5. **Two admins edit the same row.** A PATCH with an old `version` gets 409 `CONFLICT`. Expected: the list reloads, the dialog stays open with a message, nothing is silently overwritten. Pinned by Task 5 `reloads the list when the save is stale`.
6. **A control shown without the permission, or an Owner action offered to a non-Owner.** Pinned by Task 4 `hides menu items the staff member lacks` and Task 5 `does not offer the Owner role to a non-Owner`.
7. **The committed contract drifts.** A backend change without a regenerated `openapi.json` must fail the build. Pinned by Task 2 `The_committed_document_matches_the_app`.

## Decisions (to be approved by the owner; 1, 2 and 4 change the wire or the spec)

1. 🔴 **Integers are strict JSON numbers** (`JsonNumberHandling.Strict` on the one JSON option set). Today the web defaults also read `"5"` as 5, and the OpenAPI document therefore types every integer as `integer | string`, so the generated TypeScript says `number | string` for `version`, `page`, `total`. After the change the document says `integer`, and a number sent as a string is 400 `VALIDATION_FAILED`. It applies to `/api/v1` too (Flutter contract note).
2. **Every operation documents its error body.** A `Problem` schema (`type`, `title`, `status`, `detail`, `instance`, `code`, `traceId`, `errors`) and a `default` response `application/problem+json` on every operation, added by one OpenAPI transformer. This closes the S0-2 and S0-3 carry-overs (generated clients get the error type).
3. **`admin-ui/openapi.json` is committed and guarded by a test.** The test builds the document from a host without the test-only routes, drops `servers`, and compares it with the file; `UPDATE_OPENAPI=1` rewrites the file. Types are generated from the file. Reason: CI and agents never need a running API, and a contract change shows up as a reviewable diff.
4. **`GET /admin/api/me` also returns `isOwner`** (additive). The UI needs it to hide Owner-only actions and must not hard-code the Owner role id.
5. **Serving.** `UseStaticFiles` (slot 7) + fallback `/admin/{*path:nonfile}` (slot 15). The fallback answers only GET and HEAD of a page address; anything under `/admin/api` or `/admin/jobs`, any other method, and a missing `index.html` (UI not built) is a 404 JSON problem. The fallback is anonymous: the page is public, the data behind it is not.
6. **Content-Security-Policy on admin pages and assets** (every `/admin` path except `/admin/api` and `/admin/jobs`): `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'`. `style-src 'unsafe-inline'` is needed because the UI libraries set inline styles for positioning; scripts stay strict. The Hangfire dashboard keeps no CSP (it uses inline scripts).
7. **Caching.** `/admin/assets/*` (hashed file names): `public, max-age=31536000, immutable`. `index.html` and every other static file: `no-cache`.
8. **Sign-in screen.** Two steps on one screen: email → code. There is no `/login` route: when `GET /admin/api/me` answers 401 the shell shows the login screen at the current address, and after sign-in the same address renders. 429 shows the wait from `Retry-After`; `TOO_MANY_ATTEMPTS` returns to the email step; 403 shows the server's message. "Send a new code" is disabled for 60 s after a send.
9. **CSRF in the client.** The token is fetched on the first write after sign-in and kept in memory. On 400 `CSRF_FAILED` the client fetches a new token and retries the request once. The token is dropped on 401 and on sign-out.
10. **Screens.** Dashboard (empty), Staff (list, add, edit role and display name, deactivate / reactivate), Roles (list, create, rename, edit permissions, delete), Audit (filter by staff, entity type, time range; paged), and a "Jobs" link to `/admin/jobs`. Create, rename and delete of roles go beyond the spec's "list, edit permissions": the endpoints exist, and without them a second role could only be made with a tool.
11. **Times** are shown in the browser's time zone, and the zone name is shown next to them. Staff work in SG and MY (both UTC+8). The audit filter sends instants with `Z`.
12. **Look.** The demo's look through shadcn/ui tokens: brand blue `rgb(29 80 181)`, grey "ink" neutrals, 16 rem sidebar, 4 rem header, light / dark / system switch stored in `localStorage`. The font is Geist (the shadcn default), bundled with the UI; nothing is loaded from another host. Selects and checkboxes are the browser's own controls, styled (as in the demo).
13. **UI tests in S0-5.** Vitest + React Testing Library + MSW for the API client, the session, and each screen's main paths. (The spec asked only for type-check + build; Playwright still starts in S1.)
14. **`dotnet build` never runs npm.** The UI is built by `npm run build` (locally when wanted, in the Docker build in S0-6). A fresh clone without a UI build serves 404 on `/admin`.
15. **Local development.** `npm run dev` serves `http://localhost:5173/admin/` and forwards `/admin/api` and `/admin/jobs` to the API on 5080. Port 5173 is added to `.claude/dev-ports`.
16. **TypeScript 6.0.3, not 7**, until `openapi-typescript` supports TypeScript 7. `package.json` carries an `overrides` entry so a plain `npm ci` works.
17. **No ESLint in S0-5.** `tsc` strict with `noUnusedLocals` / `noUnusedParameters` is the gate. A working ESLint 10 + typescript-eslint 8 pair exists for TypeScript 6 if the owner wants it later.

---

### Task 1: Serve the admin UI (static files, fallback, CSP)

**Files:**
- Create: `src/ExtraSpace.Api/Platform/Http/AdminSpa.cs`
- Modify: `src/ExtraSpace.Api/Platform/Http/SecurityHeadersMiddleware.cs`
- Modify: `src/ExtraSpace.Api/Platform/Hosting/PlatformServices.cs` (one line in the "Pipeline" block)
- Modify: `src/ExtraSpace.Api/Program.cs` (slots 7 and 15)
- Test: `tests/ExtraSpace.Api.Tests/Platform/AdminSpaTests.cs`

**Interfaces:**
- Consumes: `ApiFactory`, `Problem.ReadAsync(response, status, code)`, `api.AdminClient()` (existing test helpers).
- Produces: `AdminSpa.Csp` (const string), `AdminSpa.IsPage(PathString)`, `AdminSpa.ConfigureStaticFiles(StaticFileOptions)`, `app.MapAdminSpa()`. The UI build writes to `src/ExtraSpace.Api/wwwroot/admin/` with `index.html` at its root and hashed files under `assets/`.

- [ ] **Step 1: Write the failing tests**

`tests/ExtraSpace.Api.Tests/Platform/AdminSpaTests.cs`:

```csharp
using System.Net;
using ExtraSpace.Api.Platform.Http;
using ExtraSpace.Api.Tests.TestSupport;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;

namespace ExtraSpace.Api.Tests.Platform;

public sealed class AdminSpaTests : IDisposable
{
    private const string Page = "<!doctype html><title>admin-ui-test</title>";
    private readonly ApiFactory _api;
    private readonly string _root = Directory.CreateTempSubdirectory("es-admin-ui-").FullName;
    private readonly PhysicalFileProvider _files;
    private readonly WebApplicationFactory<Program> _host;
    private readonly HttpClient _client;
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    public AdminSpaTests(ApiFactory api)
    {
        _api = api;
        Directory.CreateDirectory(Path.Combine(_root, "admin", "assets"));
        File.WriteAllText(Path.Combine(_root, "admin", "index.html"), Page);
        File.WriteAllText(Path.Combine(_root, "admin", "assets", "app-abc123.js"), "console.log('admin-ui-test')");
        _files = new PhysicalFileProvider(_root);
        // The real web root is git-ignored build output, so the tests bring their own.
        _host = api.WithWebHostBuilder(b => b.UseSetting("App:Role", "Api").ConfigureTestServices(services =>
            services.Configure<StaticFileOptions>(o => o.FileProvider = _files)));
        _client = _host.CreateClient();
    }

    public void Dispose()
    {
        _host.Dispose();
        _files.Dispose();
        Directory.Delete(_root, recursive: true);
    }

    [Theory]
    [InlineData("/admin")]
    [InlineData("/admin/")]
    [InlineData("/admin/staff")]
    [InlineData("/admin/roles/0199dd00-0000-7000-8000-000000000001")]
    [InlineData("/admin/index.html")]
    public async Task Page_addresses_get_the_page(string path)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        request.Headers.Add("Accept", "text/html");
        var response = await _client.SendAsync(request, Ct);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentType!.MediaType.Should().Be("text/html");
        (await response.Content.ReadAsStringAsync(Ct)).Should().Be(Page);
        response.Headers.CacheControl!.ToString().Should().Be("no-cache");
        response.Headers.GetValues("Content-Security-Policy").Should().Equal(AdminSpa.Csp);
        response.Headers.GetValues("X-Frame-Options").Should().Equal("DENY");
    }

    [Fact]
    public async Task Head_of_a_page_address_has_no_body()
    {
        var response = await _client.SendAsync(new HttpRequestMessage(HttpMethod.Head, "/admin/staff"), Ct);
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentLength.Should().Be(Page.Length);
        (await response.Content.ReadAsStringAsync(Ct)).Should().BeEmpty();
    }

    [Fact]
    public async Task Hashed_assets_are_cached_for_a_year()
    {
        var response = await _client.GetAsync("/admin/assets/app-abc123.js", Ct);
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentType!.MediaType.Should().Be("text/javascript");
        response.Headers.CacheControl!.ToString().Should().Be("public, max-age=31536000, immutable");
        response.Headers.GetValues("Content-Security-Policy").Should().Equal(AdminSpa.Csp);
    }

    [Fact]
    public async Task A_missing_asset_is_404_not_the_page()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/admin/assets/app-old999.js");
        request.Headers.Add("Accept", "*/*");
        await Problem.ReadAsync(await _client.SendAsync(request, Ct), 404, "NOT_FOUND");
    }

    [Theory]
    [InlineData("GET", "/admin/api/nope", 404, "NOT_FOUND")]
    [InlineData("GET", "/admin/api/staff/extra/segments", 404, "NOT_FOUND")]
    [InlineData("GET", "/admin/api/me", 401, "UNAUTHENTICATED")]
    [InlineData("GET", "/admin/jobs", 401, "UNAUTHENTICATED")]
    [InlineData("GET", "/admin/jobs/recurring", 401, "UNAUTHENTICATED")]
    [InlineData("POST", "/admin/staff", 404, "NOT_FOUND")]
    [InlineData("DELETE", "/admin", 404, "NOT_FOUND")]
    [InlineData("GET", "/administrator", 404, "NOT_FOUND")]
    public async Task Api_and_jobs_paths_never_get_the_page(string method, string path, int status, string code)
    {
        using var request = new HttpRequestMessage(new HttpMethod(method), path);
        request.Headers.Add("Accept", "text/html");
        await Problem.ReadAsync(await _host.AdminClient().SendAsync(request, Ct), status, code);
    }

    [Theory]
    [InlineData("/admin/api/me")]
    [InlineData("/admin/jobs")]
    [InlineData("/test/ok")]
    [InlineData("/health/live")]
    public async Task Only_admin_pages_get_the_csp(string path)
    {
        var response = await _client.GetAsync(path, Ct);
        response.Headers.Contains("Content-Security-Policy").Should().BeFalse();
    }

    [Fact]
    public async Task Without_a_built_ui_the_page_address_is_404()
    {
        // The shared host has no wwwroot/admin: a fresh clone before `npm run build`.
        using var request = new HttpRequestMessage(HttpMethod.Get, "/admin/staff");
        request.Headers.Add("Accept", "text/html");
        await Problem.ReadAsync(await _api.CreateClient().SendAsync(request, Ct), 404, "NOT_FOUND");
    }

    [Fact]
    public async Task Production_serves_the_page_too()
    {
        await using var production = _api.WithWebHostBuilder(b => b.UseEnvironment("Production").UseSetting("App:Role", "Api")
            .UseSetting("Email:Transport", "Ses").UseSetting("Email:From", "ExtraSpace <no-reply@example.test>").UseTestKeyRing()
            .ConfigureTestServices(services => services.Configure<StaticFileOptions>(o => o.FileProvider = _files)));
        var response = await production.CreateClient().GetAsync("/admin/staff", Ct);
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        (await response.Content.ReadAsStringAsync(Ct)).Should().Be(Page);
    }
}
```

If `src/ExtraSpace.Api/wwwroot/admin/index.html` exists on the machine (someone ran `npm run build`), `Without_a_built_ui_the_page_address_is_404` would see it. The test host's content root is the API project folder, so guard it: in `ApiFactory.ConfigureWebHost` add `services.Configure<StaticFileOptions>(o => o.FileProvider = new NullFileProvider());` inside the existing `ConfigureTestServices` block (the per-test hosts above override it, because their `Configure` runs later).

- [ ] **Step 2: Run the tests and see them fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*AdminSpaTests"`
Expected: compile error, `AdminSpa` does not exist.

- [ ] **Step 3: Write `AdminSpa.cs`**

```csharp
using Microsoft.Extensions.Options;

namespace ExtraSpace.Api.Platform.Http;

/// <summary>
/// The admin UI is a single-page app built into wwwroot/admin. Static files (step 7) serve its files; this fallback
/// (step 15) answers every other page address with index.html so a reload of /admin/staff works.
/// </summary>
internal static class AdminSpa
{
    // style-src needs 'unsafe-inline': the UI libraries position menus and toasts with inline styles. Scripts stay strict.
    public const string Csp =
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; " +
        "connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'";

    private const string AssetCache = "public, max-age=31536000, immutable";

    /// <summary>A page or file of the UI: under /admin, but not the admin API and not the jobs dashboard.</summary>
    public static bool IsPage(PathString path) =>
        path.StartsWithSegments("/admin") && !path.StartsWithSegments("/admin/api") && !path.StartsWithSegments("/admin/jobs");

    // Vite puts a content hash in every name under assets/, so those never change; index.html must be re-checked.
    public static void ConfigureStaticFiles(StaticFileOptions options) =>
        options.OnPrepareResponse = context => context.Context.Response.Headers.CacheControl =
            context.Context.Request.Path.StartsWithSegments("/admin/assets") ? AssetCache : "no-cache";

    // :nonfile keeps a missing /admin/assets/x.js a 404. MapFallback matches every method, so the handler checks it.
    public static IEndpointConventionBuilder MapAdminSpa(this IEndpointRouteBuilder app) =>
        app.MapFallback("/admin/{*path:nonfile}", ServeIndexAsync).AllowAnonymous().ExcludeFromDescription();

    private static async Task ServeIndexAsync(HttpContext http, IOptions<StaticFileOptions> staticFiles, IWebHostEnvironment environment)
    {
        var request = http.Request;
        var isRead = HttpMethods.IsGet(request.Method) || HttpMethods.IsHead(request.Method);
        var index = isRead && IsPage(request.Path)
            ? (staticFiles.Value.FileProvider ?? environment.WebRootFileProvider).GetFileInfo("admin/index.html")
            : null;
        if (index is not { Exists: true })
        {
            http.Response.StatusCode = StatusCodes.Status404NotFound;   // UseStatusCodePages writes the problem body
            return;
        }

        http.Response.ContentType = "text/html; charset=utf-8";
        http.Response.ContentLength = index.Length;
        http.Response.Headers.CacheControl = "no-cache";
        if (HttpMethods.IsGet(request.Method)) await http.Response.SendFileAsync(index, http.RequestAborted);
    }
}
```

- [ ] **Step 4: Add the CSP to `SecurityHeadersMiddleware`**

Inside the `OnStarting` callback, after the `Referrer-Policy` line:

```csharp
            if (AdminSpa.IsPage(http.Request.Path)) headers.ContentSecurityPolicy = AdminSpa.Csp;
```

- [ ] **Step 5: Register the cache rule and wire the pipeline**

`PlatformServices.cs`, in the "Pipeline (S0 spec §4.2)" block, after the `ForwardedHeadersOptions` block:

```csharp
        services.Configure<StaticFileOptions>(AdminSpa.ConfigureStaticFiles);
```

`Program.cs`, replace the slot 7 lines and the slot 15 comment:

```csharp
app.UseStaticFiles();                               // 7: the built admin UI (wwwroot/admin)
if (!app.Environment.IsProduction())                //    and Swagger UI outside production
    app.UseSwaggerUI(o =>
    {
        o.SwaggerEndpoint("/openapi/v1.json", "ExtraSpace API v1");
        o.RoutePrefix = "swagger";
    });
```

```csharp
if (!app.Environment.IsProduction()) app.MapOpenApi();
app.MapAdminSpa();                                  // 15: every other /admin page address gets index.html
app.Run();
```

Add `using Microsoft.Extensions.FileProviders;` and the `NullFileProvider` line to `ApiFactory.ConfigureWebHost` as described in Step 1.

- [ ] **Step 6: Run the tests**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*AdminSpaTests"`
Expected: all pass. If `Api_and_jobs_paths_never_get_the_page` fails for `/admin/api/me` with 200, the fallback was mapped before the groups or without the `IsPage` check.

Then the whole project, because the pipeline changed: `dotnet test tests/ExtraSpace.Api.Tests`
Expected: all pass (288 before this task plus the new ones), 0 warnings in the build.

- [ ] **Step 7: Hand-off**

Report the files changed, the test counts, and each reader you checked: `HttpPipelineTests` (security headers on `/test/ok` and `/test/boom` unchanged), `JobsDashboardTests` (dashboard still reachable, no CSP), `ApiDocsTests` (the fallback is not in the document). Do not commit.

---

### Task 2: The contract the UI is generated from

**Files:**
- Create: `src/ExtraSpace.Api/Platform/Errors/ProblemOpenApi.cs`
- Modify: `src/ExtraSpace.Api/Platform/Hosting/PlatformServices.cs` (`ConfigureHttpJsonOptions`, `AddOpenApi`)
- Modify: `src/ExtraSpace.Api/Features/Admin/AdminDtos.cs`, `AdminEndpoints.cs` (`isOwner`)
- Create: `admin-ui/openapi.json` (written by the test in update mode)
- Test: `tests/ExtraSpace.Api.Tests/Platform/ApiDocsTests.cs` (add), `tests/ExtraSpace.Api.Tests/Platform/OpenApiSnapshotTests.cs` (new), `tests/ExtraSpace.Api.Tests/Platform/ErrorTests.cs` (add), `tests/ExtraSpace.Api.Tests/Features/Admin/AdminAuthTests.cs` and `OwnerRulesTests.cs` (add)

**Interfaces:**
- Consumes: Task 1 (the fallback is excluded from the document).
- Produces:
  - `admin-ui/openapi.json`: OpenAPI 3.1, no `servers`, 2-space indent, LF, one trailing newline. Integers are `type: integer`. Every operation has `responses.default` → `#/components/schemas/Problem`.
  - `GET /admin/api/me` → `{ id, email, displayName, roleId, roleName, isOwner, permissions }`.
  - Update command: `UPDATE_OPENAPI=1 dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*OpenApiSnapshotTests"`.

- [ ] **Step 1: Write the failing tests**

Add to `ApiDocsTests.cs`:

```csharp
    private static IEnumerable<JsonElement> Walk(JsonElement element)
    {
        yield return element;
        var children = element.ValueKind switch
        {
            JsonValueKind.Object => element.EnumerateObject().Select(p => p.Value),
            JsonValueKind.Array => element.EnumerateArray(),
            _ => [],
        };
        foreach (var child in children)
            foreach (var nested in Walk(child))
                yield return nested;
    }

    [Fact]
    public async Task Numbers_are_never_documented_as_number_or_string()
    {
        var document = await api.CreateClient().GetFromJsonAsync<JsonElement>("/openapi/v1.json", Ct);
        var mixed = Walk(document)
            .Where(e => e.ValueKind == JsonValueKind.Object && e.TryGetProperty("type", out var type) && type.ValueKind == JsonValueKind.Array)
            .Select(e => e.GetProperty("type").EnumerateArray().Select(t => t.GetString()).ToList())
            .Where(types => types.Contains("string") && (types.Contains("integer") || types.Contains("number")));
        mixed.Should().BeEmpty("generated clients would type every number as number | string");
    }

    [Fact]
    public async Task Every_operation_documents_the_problem_body()
    {
        var document = await api.CreateClient().GetFromJsonAsync<JsonElement>("/openapi/v1.json", Ct);
        var problem = document.GetProperty("components").GetProperty("schemas").GetProperty("Problem");
        problem.GetProperty("properties").EnumerateObject().Select(p => p.Name)
            .Should().BeEquivalentTo(["type", "title", "status", "detail", "instance", "code", "traceId", "errors"]);
        problem.GetProperty("required").EnumerateArray().Select(r => r.GetString())
            .Should().BeEquivalentTo(["title", "status", "code", "traceId"]);

        string[] methods = ["get", "post", "put", "patch", "delete"];
        var operations = document.GetProperty("paths").EnumerateObject()
            .SelectMany(path => path.Value.EnumerateObject().Where(o => methods.Contains(o.Name)).Select(o => (Path: path.Name, Operation: o)))
            .ToList();
        operations.Should().NotBeEmpty();
        foreach (var (path, operation) in operations)
            operation.Value.GetProperty("responses").GetProperty("default").GetProperty("content")
                .GetProperty("application/problem+json").GetProperty("schema").GetProperty("$ref").GetString()
                .Should().Be("#/components/schemas/Problem", $"{operation.Name} {path}");
    }

    [Fact]
    public async Task The_admin_page_fallback_is_not_in_the_document()
    {
        var document = await api.CreateClient().GetFromJsonAsync<JsonElement>("/openapi/v1.json", Ct);
        document.GetProperty("paths").EnumerateObject().Select(p => p.Name).Should().NotContain(p => p.Contains("{path}") || p.Contains("{*path"));
    }
```

Add to `ErrorTests.cs` (next to the existing `"count":"abc"` test; use that test's own client field and `Ct`):

```csharp
    [Fact]
    public async Task A_number_sent_as_a_string_is_a_binding_error()
    {
        using var content = new StringContent("""{"count":"5"}""", System.Text.Encoding.UTF8, "application/json");
        var body = await Problem.ReadAsync(await _client.PostAsync("/test/validate", content, Ct), 400, "VALIDATION_FAILED");
        body.TryGetProperty("errors", out _).Should().BeFalse("the body cannot be read, so no field was validated");
    }
```

Add to `AdminAuthTests.cs`, inside the existing `Me_returns_the_staff_member_and_permissions`, one assertion on the body it already reads:

```csharp
        me.GetProperty("isOwner").GetBoolean().Should().BeFalse();
```

(name the variable as that test names it). Add to `OwnerRulesTests.cs` (it is in the `Owners` collection; use the file's own field names):

```csharp
    [Fact]
    public async Task Me_marks_an_owner()
    {
        await api.ClearOwnersAsync();
        var owner = await api.CreateStaffAsync(Role.OwnerId);
        var client = await api.SignedInAdminAsync(owner);
        var me = await client.GetFromJsonAsync<JsonElement>("/admin/api/me", Ct);
        me.GetProperty("isOwner").GetBoolean().Should().BeTrue();
    }
```

Create `OpenApiSnapshotTests.cs`:

```csharp
using System.Text.Json;
using System.Text.Json.Nodes;
using ExtraSpace.Api.Platform.Hosting;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace ExtraSpace.Api.Tests.Platform;

/// <summary>
/// admin-ui/openapi.json is the committed copy of the API contract; the UI's TypeScript types are generated from it.
/// Update it with: UPDATE_OPENAPI=1 dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*OpenApiSnapshotTests"
/// then run `npm run gen:api` in admin-ui.
/// </summary>
public sealed class OpenApiSnapshotTests(ApiFactory api)
{
    private static readonly JsonSerializerOptions Indented = new() { WriteIndented = true };

    [Fact]
    public async Task The_committed_document_matches_the_app()
    {
        var ct = TestContext.Current.CancellationToken;
        // Without the /test/* routes, which exist only in this test project.
        await using var host = api.WithWebHostBuilder(b => b.UseSetting("App:Role", "Api")
            .ConfigureTestServices(services => services.RemoveAll<IEndpointMapper>()));
        var document = JsonNode.Parse(await host.CreateClient().GetStringAsync("/openapi/v1.json", ct))!.AsObject();
        document.Remove("servers");   // the host name of whoever asked
        var current = document.ToJsonString(Indented).ReplaceLineEndings("\n") + "\n";

        var path = Path.Combine(RepoRoot(), "admin-ui", "openapi.json");
        if (Environment.GetEnvironmentVariable("UPDATE_OPENAPI") == "1")
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            await File.WriteAllTextAsync(path, current, ct);
            return;
        }

        File.Exists(path).Should().BeTrue("admin-ui/openapi.json is committed; see the comment on this class");
        var committed = (await File.ReadAllTextAsync(path, ct)).ReplaceLineEndings("\n");
        (committed == current).Should().BeTrue(
            "the API contract changed: rerun this test with UPDATE_OPENAPI=1, then `npm run gen:api` in admin-ui, and review both diffs");
    }

    private static string RepoRoot()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
            if (File.Exists(Path.Combine(dir.FullName, "ExtraSpace.slnx"))) return dir.FullName;
        throw new InvalidOperationException("ExtraSpace.slnx not found above the test output folder.");
    }
}
```

The comparison is a plain `==` on purpose: a `Should().Be` on two 2,000-line strings prints both.

- [ ] **Step 2: Run the tests and see them fail**

Run: `dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*ApiDocsTests" --filter-class "*OpenApiSnapshotTests" --filter-class "*ErrorTests"`
Expected: `Numbers_are_never_documented_as_number_or_string`, `Every_operation_documents_the_problem_body`, `A_number_sent_as_a_string_is_a_binding_error` and `The_committed_document_matches_the_app` fail; the `isOwner` assertions fail in their classes.

- [ ] **Step 3: Strict numbers**

`PlatformServices.cs`, replace the `ConfigureHttpJsonOptions` line:

```csharp
        services.ConfigureHttpJsonOptions(o =>
        {
            o.SerializerOptions.Converters.Add(new JsonStringEnumConverter(allowIntegerValues: false));
            // The web default also reads "5" as 5, and the OpenAPI document then types every integer as integer | string.
            o.SerializerOptions.NumberHandling = JsonNumberHandling.Strict;
        });
```

- [ ] **Step 4: The problem schema and the default response**

`src/ExtraSpace.Api/Platform/Errors/ProblemOpenApi.cs`:

```csharp
using Microsoft.AspNetCore.OpenApi;
using Microsoft.OpenApi;

namespace ExtraSpace.Api.Platform.Errors;

/// <summary>S0 spec §4.1 in the OpenAPI document: one Problem schema, and every operation says its errors use it.</summary>
internal static class ProblemOpenApi
{
    private const string SchemaName = "Problem";

    public static OpenApiOptions AddProblemResponses(this OpenApiOptions options) => options
        .AddDocumentTransformer((document, _, _) =>
        {
            document.Components ??= new OpenApiComponents();
            document.Components.Schemas ??= new Dictionary<string, IOpenApiSchema>();
            document.Components.Schemas[SchemaName] = new OpenApiSchema
            {
                Type = JsonSchemaType.Object,
                Required = new HashSet<string> { "title", "status", "code", "traceId" },
                Properties = new Dictionary<string, IOpenApiSchema>
                {
                    ["type"] = Text(),
                    ["title"] = Text(),
                    ["status"] = new OpenApiSchema { Type = JsonSchemaType.Integer, Format = "int32" },
                    ["detail"] = Text(),
                    ["instance"] = Text(),
                    ["code"] = Text(),
                    ["traceId"] = Text(),
                    // Present for field validation only; keys are camelCase field names.
                    ["errors"] = new OpenApiSchema
                    {
                        Type = JsonSchemaType.Object,
                        AdditionalProperties = new OpenApiSchema { Type = JsonSchemaType.Array, Items = Text() },
                    },
                },
            };
            return Task.CompletedTask;
        })
        .AddOperationTransformer((operation, context, _) =>
        {
            operation.Responses ??= new OpenApiResponses();
            operation.Responses["default"] = new OpenApiResponse
            {
                Description = "Error",
                Content = new Dictionary<string, OpenApiMediaType>
                {
                    ["application/problem+json"] = new() { Schema = new OpenApiSchemaReference(SchemaName, context.Document) },
                },
            };
            return Task.CompletedTask;
        });

    private static OpenApiSchema Text() => new() { Type = JsonSchemaType.String };
}
```

`PlatformServices.cs`: chain it onto the existing schema transformer. The call becomes `services.AddOpenApi(o => o.AddSchemaTransformer((schema, context, _) => { … }).AddProblemResponses());` (the lambda body is unchanged).

The Microsoft.OpenApi 2.x type names above follow `Features/Identity/CustomerAuth.cs` (`OpenApiSecuritySchemeReference("Bearer", context.Document)`). If a member differs in the installed version (for example `Required` being `ISet<string>`), follow the installed type; the test in Step 1 fixes the JSON that must come out.

- [ ] **Step 5: `isOwner` on `/me`**

`AdminDtos.cs`:

```csharp
internal sealed record AdminMeResponse(Guid Id, string Email, string? DisplayName, Guid RoleId, string RoleName, bool IsOwner, IReadOnlyList<string> Permissions);
```

`AdminEndpoints.GetMe`:

```csharp
            ? TypedResults.Ok(new AdminMeResponse(s.Id, s.Email, s.DisplayName, s.RoleId, s.RoleName, s.IsOwner, s.Permissions))
```

Readers of `AdminMeResponse` to check with grep: only `GetMe` builds it; tests read the JSON by property name.

- [ ] **Step 6: Write the snapshot, then run everything**

```bash
UPDATE_OPENAPI=1 dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*OpenApiSnapshotTests"
dotnet test tests/ExtraSpace.Api.Tests
```

Expected: `admin-ui/openapi.json` exists; the full run passes with 0 build warnings. Open the file and check by eye: no `servers`; `/admin/api/staff` is there; no path starts with `/test/`; `StaffResponse.version` is `"type": "integer"`; `AdminMeResponse` has `isOwner`.

If an existing test fails because it posted a number as a string, that test documented the old lax behaviour: report it, do not change it without the main session's ruling.

- [ ] **Step 7: Hand-off**

Report the files changed, the test counts, the size of `openapi.json`, and the readers checked for the JSON option change: every request DTO with a numeric field (`UpdateStaffBody.Version`, `UpdateRoleBody.Version`, the audit `page` / `pageSize` query values, which are not JSON and are unaffected). Do not commit.

---

### Task 3: UI project and the API client

**Files (all under `admin-ui/`):**
- Create: `package.json`, `package-lock.json`, `vite.config.ts`, `tsconfig.json`, `tsconfig.app.json`, `tsconfig.node.json`, `index.html`, `components.json`
- Create: `src/main.tsx`, `src/index.css`, `src/lib/utils.ts`, `src/lib/query.ts`, `src/lib/theme.ts`
- Create (generated by the shadcn CLI, then kept in git): `src/components/ui/{button,input,label,dialog,table,badge,sonner}.tsx`
- Create (generated): `src/api/schema.d.ts`
- Create: `src/api/errors.ts`, `src/api/client.ts`
- Create: `src/test/setup.ts`, `src/test/server.ts`, `src/test/relative-fetch.ts`, `src/test/problems.ts`
- Test: `src/api/client.test.ts`, `src/lib/theme.test.ts`

**Interfaces:**
- Consumes: `admin-ui/openapi.json` (Task 2).
- Produces:
  - Scripts: `npm run dev | build | typecheck | test | gen:api | check:api`.
  - `api` (the one `openapi-fetch` client) and `call(() => api.GET(...))`: resolves to the success body (`undefined` for 204) or throws `ApiError`.
  - `class ApiError extends Error { status: number; code: string; traceId?: string; fieldErrors: Record<string, string[]>; retryAfterSeconds?: number }`; `message` is the server's `title`.
  - `onUnauthorized(listener): () => void` (returns the unsubscribe function), `resetCsrf(): void`.
  - `makeQueryClient(): QueryClient`.
  - `getTheme(): ThemePref`, `setTheme(pref: ThemePref): void`, `applyTheme(): void`, `type ThemePref = 'light' | 'dark' | 'system'`.
  - Test helpers: `server` (MSW), `problem(status, code, title, extra?)` → an MSW `HttpResponse`.

- [ ] **Step 1: Create the project files**

Copy these files from the spike note, unchanged except where listed: `tsconfig.json`, `tsconfig.app.json`, `tsconfig.node.json`, `index.html`, `src/test/server.ts`, `src/test/relative-fetch.ts`, `src/test/setup.ts`, `src/lib/query.ts`.

`package.json` (exact versions, no carets; the lock file is committed):

```json
{
  "name": "extraspace-admin-ui",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "typecheck": "tsc -b",
    "test": "vitest run",
    "gen:api": "openapi-typescript openapi.json -o src/api/schema.d.ts",
    "check:api": "npm run gen:api && git diff --exit-code -- src/api/schema.d.ts"
  },
  "dependencies": {
    "@fontsource-variable/geist": "5.3.0",
    "@hookform/resolvers": "5.9.1",
    "@tanstack/react-query": "5.104.2",
    "@tanstack/react-table": "9.3.1",
    "class-variance-authority": "0.7.1",
    "clsx": "2.1.1",
    "lucide-react": "1.56.0",
    "openapi-fetch": "0.17.0",
    "radix-ui": "1.8.1",
    "react": "19.3.0",
    "react-dom": "19.3.0",
    "react-hook-form": "7.90.0",
    "react-router": "8.4.0",
    "shadcn": "4.21.4",
    "sonner": "2.0.8",
    "tailwind-merge": "3.7.0",
    "tw-animate-css": "1.4.0",
    "zod": "4.6.7"
  },
  "devDependencies": {
    "@tailwindcss/vite": "4.3.3",
    "@testing-library/jest-dom": "7.0.1",
    "@testing-library/react": "16.3.3",
    "@testing-library/user-event": "14.6.8",
    "@types/node": "26.6.5",
    "@types/react": "19.3.0",
    "@types/react-dom": "19.3.0",
    "@vitejs/plugin-react": "6.1.2",
    "jsdom": "30.1.2",
    "msw": "3.0.3",
    "openapi-typescript": "7.13.0",
    "tailwindcss": "4.3.3",
    "typescript": "6.0.3",
    "vite": "8.3.4",
    "vitest": "5.0.4"
  },
  "overrides": {
    "openapi-typescript": { "typescript": "$typescript" }
  }
}
```

`vite.config.ts`: the spike note's file with one change, the real output folder:

```ts
  build: {
    outDir: '../src/ExtraSpace.Api/wwwroot/admin',
    emptyOutDir: true,
  },
```

Run `npm install` in `admin-ui/`. Expected: no peer-dependency error (the `overrides` entry is what makes that true).

- [ ] **Step 2: shadcn components**

```bash
npx shadcn@4.21.4 init -t vite -b radix -p nova -y --no-reinstall --no-monorepo --no-rtl --no-pointer
npx shadcn@4.21.4 add button input label dialog table badge sonner -y -o
```

Both need network (the shadcn registry and npm). The CLI finds the `@/*` alias only in the **root** `tsconfig.json`; if a literal `@` folder appears, the alias is missing there. Then make three corrections to what the CLI wrote:

1. The preset adds the packages `cn` and `next-themes`. We do not take them: `npm uninstall cn next-themes`, make sure `package.json` still has exact versions (the CLI writes carets: remove them), and write `src/lib/utils.ts`:

```ts
import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
```

2. In `src/components/ui/sonner.tsx` remove the `"use client"` line and the `next-themes` import, and replace the `useTheme()` line with our own theme (Step 4):

```tsx
import { useSyncExternalStore } from 'react'
import { getTheme, subscribeTheme } from '@/lib/theme'
// inside Toaster:
  const theme = useSyncExternalStore(subscribeTheme, getTheme)
```

3. In `src/index.css`, set the brand colour on the tokens the CLI generated. Change only these values; keep every other line:

```css
:root {
  --primary: oklch(0.45 0.16 262);            /* brand blue, rgb(29 80 181) */
  --primary-foreground: oklch(0.985 0 0);
  --ring: oklch(0.45 0.16 262);
  --sidebar-primary: oklch(0.45 0.16 262);
  --sidebar-primary-foreground: oklch(0.985 0 0);
}
.dark {
  --primary: oklch(0.62 0.16 262);
  --primary-foreground: oklch(0.985 0 0);
  --ring: oklch(0.62 0.16 262);
  --sidebar-primary: oklch(0.62 0.16 262);
  --sidebar-primary-foreground: oklch(0.985 0 0);
}
```

- [ ] **Step 3: Generate the types**

Run: `npm run gen:api`
Expected: `src/api/schema.d.ts` exists and contains `"/admin/api/staff"`, `AdminMeResponse` with `isOwner: boolean`, `StaffResponse` with `version: number` (not `number | string`), and `Problem`.

- [ ] **Step 4: Theme (test first)**

`src/lib/theme.test.ts`:

```ts
import { applyTheme, getTheme, setTheme } from './theme'

describe('theme', () => {
  beforeEach(() => {
    localStorage.clear()
    document.documentElement.classList.remove('dark')
  })

  it('defaults to system and follows the system setting', () => {
    expect(getTheme()).toBe('system')
    applyTheme()
    expect(document.documentElement.classList.contains('dark')).toBe(false)   // the matchMedia stub says light
  })

  it('remembers the choice and puts the dark class on <html>', () => {
    setTheme('dark')
    expect(localStorage.getItem('es-admin-theme')).toBe('dark')
    expect(document.documentElement.classList.contains('dark')).toBe(true)
    setTheme('light')
    expect(document.documentElement.classList.contains('dark')).toBe(false)
  })

  it('ignores a stored value it does not know', () => {
    localStorage.setItem('es-admin-theme', 'purple')
    expect(getTheme()).toBe('system')
  })
})
```

`src/lib/theme.ts`:

```ts
export type ThemePref = 'light' | 'dark' | 'system'

const KEY = 'es-admin-theme'
const listeners = new Set<() => void>()

export function getTheme(): ThemePref {
  const stored = localStorage.getItem(KEY)
  return stored === 'light' || stored === 'dark' ? stored : 'system'
}

export function applyTheme(): void {
  const pref = getTheme()
  const dark = pref === 'dark' || (pref === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches)
  document.documentElement.classList.toggle('dark', dark)
}

export function setTheme(pref: ThemePref): void {
  if (pref === 'system') localStorage.removeItem(KEY)
  else localStorage.setItem(KEY, pref)
  applyTheme()
  for (const listener of listeners) listener()
}

export function subscribeTheme(listener: () => void): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}
```

`src/main.tsx` for now (Task 4 replaces the placeholder element with `<App />`). `applyTheme()` runs before the first render because the CSP forbids the usual inline script in `index.html`:

```tsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { applyTheme } from '@/lib/theme'
import './index.css'

applyTheme()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <p className="p-6 text-sm text-muted-foreground">ExtraSpace Admin</p>
  </StrictMode>,
)
```

- [ ] **Step 5: Write the failing client tests**

`src/test/problems.ts`:

```ts
import { HttpResponse } from 'msw'

export const TRACE = '4bf92f3577b34da6a3ce929d0e0e4736'

/** An error response in the server's shape (S0 spec §4.1). */
export function problem(status: number, code: string, title: string, extra: { errors?: Record<string, string[]>; headers?: Record<string, string> } = {}) {
  return HttpResponse.json(
    { type: 'about:blank', title, status, code, traceId: TRACE, ...(extra.errors ? { errors: extra.errors } : {}) },
    { status, headers: { 'Content-Type': 'application/problem+json', 'X-Trace-Id': TRACE, ...extra.headers } },
  )
}
```

`src/api/client.test.ts`:

```ts
import { http, HttpResponse } from 'msw'
import { problem, TRACE } from '@/test/problems'
import { server } from '@/test/server'
import { api, call, onUnauthorized, resetCsrf } from './client'
import { ApiError } from './errors'
import type { components } from './schema'

const role = { id: '0199dd00-0000-7000-8000-0000000000aa', name: 'Front desk', permissions: [], isSystem: false, staffCount: 0, version: 7 }

/** Serves /auth/csrf with token-1, token-2, … and counts the calls. */
function csrfHandler() {
  const state = { calls: 0 }
  server.use(http.get('*/admin/api/auth/csrf', () => HttpResponse.json({ token: `token-${++state.calls}` })))
  return state
}

async function failure(send: () => Promise<unknown>): Promise<ApiError> {
  try {
    await send()
  } catch (error) {
    if (error instanceof ApiError) return error
    throw error
  }
  throw new Error('expected the call to fail')
}

describe('api client', () => {
  beforeEach(() => resetCsrf())

  it('returns the typed body of a successful call', async () => {
    server.use(http.get('*/admin/api/roles', () => HttpResponse.json([role])))
    const roles: components['schemas']['RoleResponse'][] = await call(() => api.GET('/admin/api/roles'))
    expect(roles[0]?.version).toBe(7)
  })

  it('returns undefined for 204', async () => {
    csrfHandler()
    server.use(http.post('*/admin/api/auth/logout', () => new HttpResponse(null, { status: 204 })))
    expect(await call(() => api.POST('/admin/api/auth/logout'))).toBeUndefined()
  })

  it('sends the csrf header on writes and fetches the token once', async () => {
    const csrf = csrfHandler()
    const seen: (string | null)[] = []
    server.use(http.post('*/admin/api/roles', ({ request }) => {
      seen.push(request.headers.get('X-CSRF-TOKEN'))
      return HttpResponse.json(role, { status: 201 })
    }))
    await call(() => api.POST('/admin/api/roles', { body: { name: 'A', permissions: [] } }))
    await call(() => api.POST('/admin/api/roles', { body: { name: 'B', permissions: [] } }))
    expect(seen).toEqual(['token-1', 'token-1'])
    expect(csrf.calls).toBe(1)
  })

  it('needs no csrf token for reads or for the sign-in calls', async () => {
    const csrf = csrfHandler()
    server.use(
      http.get('*/admin/api/roles', () => HttpResponse.json([])),
      http.post('*/admin/api/auth/code', () => new HttpResponse(null, { status: 202 })),
      http.post('*/admin/api/auth/code/verify', () => new HttpResponse(null, { status: 204 })),
    )
    await call(() => api.GET('/admin/api/roles'))
    await call(() => api.POST('/admin/api/auth/code', { body: { email: 'ada@example.test' } }))
    await call(() => api.POST('/admin/api/auth/code/verify', { body: { email: 'ada@example.test', code: '123456' } }))
    expect(csrf.calls).toBe(0)
  })

  it('retries a write once after CSRF_FAILED', async () => {
    const csrf = csrfHandler()
    const bodies: unknown[] = []
    server.use(http.post('*/admin/api/roles', async ({ request }) => {
      bodies.push(await request.json())
      return request.headers.get('X-CSRF-TOKEN') === 'token-1'
        ? problem(400, 'CSRF_FAILED', 'The security token is missing or out of date. Reload and try again.')
        : HttpResponse.json(role, { status: 201 })
    }))
    const created = await call(() => api.POST('/admin/api/roles', { body: { name: 'A', permissions: [] } }))
    expect(created.id).toBe(role.id)
    expect(csrf.calls).toBe(2)
    expect(bodies).toEqual([{ name: 'A', permissions: [] }, { name: 'A', permissions: [] }])
  })

  it('gives up after the second CSRF_FAILED', async () => {
    csrfHandler()
    let posts = 0
    server.use(http.post('*/admin/api/roles', () => {
      posts++
      return problem(400, 'CSRF_FAILED', 'The security token is missing or out of date. Reload and try again.')
    }))
    const error = await failure(() => call(() => api.POST('/admin/api/roles', { body: { name: 'A', permissions: [] } })))
    expect(error.code).toBe('CSRF_FAILED')
    expect(posts).toBe(2)
  })

  it('a 401 drops the session and the csrf token', async () => {
    const csrf = csrfHandler()
    const listener = vi.fn()
    const unsubscribe = onUnauthorized(listener)
    server.use(http.post('*/admin/api/roles', () => HttpResponse.json(role, { status: 201 })))
    await call(() => api.POST('/admin/api/roles', { body: { name: 'A', permissions: [] } }))

    server.use(http.get('*/admin/api/staff', () => problem(401, 'UNAUTHENTICATED', 'Sign in again.')))
    const error = await failure(() => call(() => api.GET('/admin/api/staff')))
    expect(error.status).toBe(401)
    expect(listener).toHaveBeenCalledTimes(1)

    await call(() => api.POST('/admin/api/roles', { body: { name: 'B', permissions: [] } }))
    expect(csrf.calls).toBe(2)   // the token of the old sign-in was not reused

    unsubscribe()
    await failure(() => call(() => api.GET('/admin/api/staff')))
    expect(listener).toHaveBeenCalledTimes(1)
  })

  it('turns a problem body into an ApiError', async () => {
    server.use(http.get('*/admin/api/staff', () =>
      problem(429, 'RATE_LIMITED', 'Too many requests.', { headers: { 'Retry-After': '42' }, errors: { email: ['Not allowed.'] } })))
    const error = await failure(() => call(() => api.GET('/admin/api/staff')))
    expect(error).toMatchObject({ status: 429, code: 'RATE_LIMITED', message: 'Too many requests.', traceId: TRACE, retryAfterSeconds: 42 })
    expect(error.fieldErrors).toEqual({ email: ['Not allowed.'] })
  })

  it('copes with an error that is not a problem body', async () => {
    server.use(http.get('*/admin/api/staff', () =>
      new HttpResponse('<html>Bad Gateway</html>', { status: 502, headers: { 'Content-Type': 'text/html', 'X-Trace-Id': TRACE } })))
    const error = await failure(() => call(() => api.GET('/admin/api/staff')))
    expect(error).toMatchObject({ status: 502, code: 'HTTP_502', traceId: TRACE })
    expect(error.fieldErrors).toEqual({})
  })

  it('reports a network failure as NETWORK', async () => {
    server.use(http.get('*/admin/api/staff', () => HttpResponse.error()))
    const error = await failure(() => call(() => api.GET('/admin/api/staff')))
    expect(error).toMatchObject({ status: 0, code: 'NETWORK' })
  })
})
```

Run: `npm test`
Expected: FAIL, `./client` and `./errors` do not exist. (`theme.test.ts` passes.)

- [ ] **Step 6: Write `errors.ts` and `client.ts`**

`src/api/errors.ts`:

```ts
import type { components } from './schema'

export type Problem = components['schemas']['Problem']

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}

/** Every failed call becomes one of these. `message` is the server's title, written for people. */
export class ApiError extends Error {
  readonly status: number
  readonly code: string
  readonly traceId: string | undefined
  readonly fieldErrors: Record<string, string[]>
  readonly retryAfterSeconds: number | undefined

  private constructor(status: number, code: string, title: string, traceId?: string, fieldErrors: Record<string, string[]> = {}, retryAfterSeconds?: number) {
    super(title)
    this.name = 'ApiError'
    this.status = status
    this.code = code
    this.traceId = traceId
    this.fieldErrors = fieldErrors
    this.retryAfterSeconds = retryAfterSeconds
  }

  static network(): ApiError {
    return new ApiError(0, 'NETWORK', 'Cannot reach the server. Check your connection and try again.')
  }

  /** `body` is what openapi-fetch parsed: the problem object, or text when a proxy answered instead of the app. */
  static from(response: Response, body: unknown): ApiError {
    const problem = isRecord(body) ? body : {}
    const retryAfter = Number(response.headers.get('Retry-After'))
    const fieldErrors: Record<string, string[]> = {}
    if (isRecord(problem.errors))
      for (const [field, messages] of Object.entries(problem.errors))
        if (Array.isArray(messages)) fieldErrors[field] = messages.filter((m): m is string => typeof m === 'string')
    return new ApiError(
      response.status,
      typeof problem.code === 'string' ? problem.code : `HTTP_${response.status}`,
      typeof problem.title === 'string' ? problem.title : 'Something went wrong. Please try again.',
      typeof problem.traceId === 'string' ? problem.traceId : (response.headers.get('X-Trace-Id') ?? undefined),
      fieldErrors,
      Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter : undefined,
    )
  }
}
```

`src/api/client.ts`:

```ts
import createClient, { type Middleware } from 'openapi-fetch'
import { ApiError } from './errors'
import type { paths } from './schema'

const CSRF_HEADER = 'X-CSRF-TOKEN'
const WRITES = new Set(['POST', 'PUT', 'PATCH', 'DELETE'])
// The emailed code is the credential on these two; the server makes no CSRF check there.
const NO_CSRF = new Set(['/admin/api/auth/code', '/admin/api/auth/code/verify'])

let csrf: Promise<string | undefined> | undefined
const unauthorizedListeners = new Set<() => void>()

/** Called on every 401: the cookie expired or the staff member was deactivated. */
export function onUnauthorized(listener: () => void): () => void {
  unauthorizedListeners.add(listener)
  return () => unauthorizedListeners.delete(listener)
}

/** The token belongs to one sign-in: drop it on sign-in, sign-out and 401. */
export function resetCsrf(): void {
  csrf = undefined
}

function csrfToken(): Promise<string | undefined> {
  csrf ??= api.GET('/admin/api/auth/csrf').then(
    ({ data }) => data?.token,
    () => undefined,
  )
  const pending = csrf
  void pending.then((token) => {
    if (token === undefined && csrf === pending) csrf = undefined   // a failed fetch is not remembered
  })
  return pending
}

const csrfMiddleware: Middleware = {
  async onRequest({ request }) {
    if (!WRITES.has(request.method) || NO_CSRF.has(new URL(request.url).pathname)) return request
    const token = await csrfToken()
    if (token !== undefined) request.headers.set(CSRF_HEADER, token)
    return request
  },
}

export const api = createClient<paths>({
  baseUrl: '/',
  // Looked up per call: openapi-fetch otherwise keeps the fetch that existed at import, which MSW replaces later.
  fetch: (request) => globalThis.fetch(request),
})
api.use(csrfMiddleware)

type Result<T> = { data?: T; error?: unknown; response: Response }

async function once<T>(send: () => Promise<Result<T>>): Promise<T> {
  let result: Result<T>
  try {
    result = await send()
  } catch {
    throw ApiError.network()
  }
  if (result.response.ok) return result.data as T   // undefined for 204; the one cast in the UI, on the client's own typed result
  if (result.response.status === 401) {
    resetCsrf()
    for (const listener of unauthorizedListeners) listener()
  }
  throw ApiError.from(result.response, result.error)
}

/**
 * Runs one API call: `await call(() => api.GET('/admin/api/staff'))`. It takes a function so that a write refused
 * with CSRF_FAILED (the token is from an older sign-in) can be sent once more with a new token.
 */
export async function call<T>(send: () => Promise<Result<T>>): Promise<T> {
  try {
    return await once(send)
  } catch (error) {
    if (!(error instanceof ApiError) || error.code !== 'CSRF_FAILED') throw error
    resetCsrf()
    return once(send)
  }
}
```

The type inference of `call` (`T` = the operation's success body) was checked against `openapi-fetch` 0.17.0 in the spike. Requests are same-origin, so the browser sends the cookie without any `credentials` option.

- [ ] **Step 7: Run everything**

```bash
npm run typecheck && npm test && npm run build && npm run check:api
```

Expected: 0 type errors; every test passes; the build writes `../src/ExtraSpace.Api/wwwroot/admin/index.html` and `assets/` (git-ignored: `git -C .. status --short` must not list `wwwroot`); `check:api` leaves no diff. Confirm the built `index.html` has no inline `<script>` body and no `http://` / `https://` URL.

- [ ] **Step 8: Hand-off**

Report: the files created, test counts, the output of `npm ls --depth=0`, every file the shadcn CLI wrote, and any place where an installed API differed from this plan. Do not commit.

---

### Task 4: Session, sign-in screen and the shell

**Files (under `admin-ui/src/`):**
- Create: `features/auth/session.tsx`, `features/auth/LoginScreen.tsx`
- Create: `app/App.tsx`, `app/routes.tsx`, `app/Shell.tsx`, `app/nav.ts`, `app/ThemeSwitch.tsx`
- Create: `components/ErrorNote.tsx`, `components/PageShell.tsx`, `lib/time.ts`
- Create: `features/dashboard/DashboardPage.tsx`, `features/staff/StaffPage.tsx`, `features/roles/RolesPage.tsx`, `features/audit/AuditPage.tsx` (the last three are one-line placeholders here; Tasks 5 and 6 fill them)
- Create: `test/render.tsx`, `test/data.ts`
- Modify: `main.tsx`
- Test: `app/App.test.tsx`, `features/auth/LoginScreen.test.tsx`

**Interfaces:**
- Consumes: `api`, `call`, `onUnauthorized`, `resetCsrf`, `ApiError`, `makeQueryClient`, theme functions, `problem`, `server` (Task 3).
- Produces:
  - `type Me = components['schemas']['AdminMeResponse']`; `useSession(): { me: Me; can(permission: string): boolean }` (throws outside the signed-in shell).
  - `<ErrorNote error={unknown} />` (inline message + trace id + Copy) and `toastError(error: unknown): void`.
  - `<PageShell title actions?>children</PageShell>`.
  - `formatInstant(iso: string): string`, `zoneName(): string`, `localInputToInstant(value: string): string | undefined`.
  - `renderApp(path: string, options?: { me?: Me | null | 'down' })` → `{ user }` and `staffMe`, `ownerMe` test data.
  - Routes: `/` dashboard, `/staff`, `/roles`, `/audit`; each page file exports a component named as its file.

- [ ] **Step 1: Test helpers**

`src/test/data.ts`:

```ts
import type { components } from '@/api/schema'

type Me = components['schemas']['AdminMeResponse']

export const OWNER_ROLE_ID = '0199dd00-0000-7000-8000-000000000001'
export const DESK_ROLE_ID = '0199dd00-0000-7000-8000-0000000000aa'

export const ownerMe: Me = {
  id: '0199dd00-0000-7000-8000-000000000101', email: 'owner@example.test', displayName: 'Olive Owner',
  roleId: OWNER_ROLE_ID, roleName: 'Owner', isOwner: true,
  permissions: ['staff.manage', 'roles.manage', 'audit.read', 'jobs.manage'],
}

export const staffMe: Me = {
  id: '0199dd00-0000-7000-8000-000000000102', email: 'desk@example.test', displayName: null,
  roleId: DESK_ROLE_ID, roleName: 'Front desk', isOwner: false, permissions: ['staff.manage'],
}
```

`src/test/render.tsx`:

```tsx
import { render } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { http, HttpResponse } from 'msw'
import { createMemoryRouter } from 'react-router'
import type { components } from '@/api/schema'
import { resetCsrf } from '@/api/client'
import { App } from '@/app/App'
import { routes } from '@/app/routes'
import { makeQueryClient } from '@/lib/query'
import { ownerMe } from './data'
import { problem } from './problems'
import { server } from './server'

type Me = components['schemas']['AdminMeResponse']

/** Renders the whole app at an address. `me: null` = not signed in; `'down'` = the session check fails with 500. */
export function renderApp(path: string, options: { me?: Me | null | 'down' } = {}) {
  const me = options.me === undefined ? ownerMe : options.me
  resetCsrf()
  server.use(
    http.get('*/admin/api/me', () =>
      me === 'down' ? problem(500, 'INTERNAL_ERROR', 'Something went wrong on our side.')
      : me ? HttpResponse.json(me) : problem(401, 'UNAUTHENTICATED', 'Sign in again.')),
    http.get('*/admin/api/auth/csrf', () => HttpResponse.json({ token: 'csrf-test' })),
  )
  const router = createMemoryRouter(routes, { basename: '/admin', initialEntries: [path] })
  const user = userEvent.setup()
  return { user, router, ...render(<App router={router} queryClient={makeQueryClient()} />) }
}
```

Handlers added later with `server.use` in a test win over these (MSW takes the newest first).

- [ ] **Step 2: Write the failing tests**

`src/features/auth/LoginScreen.test.tsx`:

```tsx
import { screen, waitFor } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { ownerMe } from '@/test/data'
import { problem, TRACE } from '@/test/problems'
import { renderApp } from '@/test/render'
import { server } from '@/test/server'

function codeRoutes() {
  const sent: unknown[] = []
  server.use(http.post('*/admin/api/auth/code', async ({ request }) => {
    sent.push(await request.json())
    return new HttpResponse(null, { status: 202 })
  }))
  return sent
}

describe('sign-in', () => {
  it('signs in with an email and a code, and lands on the address that was asked for', async () => {
    const sent = codeRoutes()
    const { user } = renderApp('/admin/staff', { me: null })
    await user.type(await screen.findByLabelText('Email'), 'Owner@Example.test')
    await user.click(screen.getByRole('button', { name: 'Send code' }))
    expect(sent).toEqual([{ email: 'owner@example.test' }])

    let verified: unknown
    server.use(
      http.post('*/admin/api/auth/code/verify', async ({ request }) => {
        verified = await request.json()
        server.use(http.get('*/admin/api/me', () => HttpResponse.json(ownerMe)))   // the cookie is set from here on
        return new HttpResponse(null, { status: 204 })
      }),
      http.get('*/admin/api/staff', () => HttpResponse.json([])),
      http.get('*/admin/api/roles', () => HttpResponse.json([])),
    )
    await user.type(await screen.findByLabelText('Code'), '123456')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    expect(await screen.findByRole('heading', { name: 'Staff' })).toBeInTheDocument()
    expect(verified).toEqual({ email: 'owner@example.test', code: '123456' })
    expect(screen.getByText('Olive Owner')).toBeInTheDocument()
  })

  it('says the same thing whether or not the address is known', async () => {
    codeRoutes()
    const { user } = renderApp('/admin/', { me: null })
    await user.type(await screen.findByLabelText('Email'), 'nobody@example.test')
    await user.click(screen.getByRole('button', { name: 'Send code' }))
    expect(await screen.findByText(/If nobody@example.test belongs to a staff member/)).toBeInTheDocument()
  })

  it('shows a wrong code with its trace id and lets the user try again', async () => {
    codeRoutes()
    server.use(http.post('*/admin/api/auth/code/verify', () => problem(400, 'INVALID_CODE', 'The code is wrong or has expired')))
    const { user } = renderApp('/admin/', { me: null })
    await user.type(await screen.findByLabelText('Email'), 'owner@example.test')
    await user.click(screen.getByRole('button', { name: 'Send code' }))
    await user.type(await screen.findByLabelText('Code'), '000000')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByText('The code is wrong or has expired')).toBeInTheDocument()
    expect(screen.getByText(new RegExp(TRACE))).toBeInTheDocument()
    expect(screen.getByLabelText('Code')).toBeInTheDocument()
  })

  it('goes back to the email step after too many attempts', async () => {
    codeRoutes()
    server.use(http.post('*/admin/api/auth/code/verify', () => problem(400, 'TOO_MANY_ATTEMPTS', 'Too many wrong codes. Request a new one.')))
    const { user } = renderApp('/admin/', { me: null })
    await user.type(await screen.findByLabelText('Email'), 'owner@example.test')
    await user.click(screen.getByRole('button', { name: 'Send code' }))
    await user.type(await screen.findByLabelText('Code'), '000000')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByText('Too many wrong codes. Request a new one.')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Send code' })).toBeInTheDocument()
    expect(screen.queryByLabelText('Code')).not.toBeInTheDocument()
  })

  it('shows how long to wait on 429', async () => {
    server.use(http.post('*/admin/api/auth/code', () => problem(429, 'RATE_LIMITED', 'Too many requests.', { headers: { 'Retry-After': '95' } })))
    const { user } = renderApp('/admin/', { me: null })
    await user.type(await screen.findByLabelText('Email'), 'owner@example.test')
    await user.click(screen.getByRole('button', { name: 'Send code' }))
    expect(await screen.findByText(/Try again in 2 minutes/)).toBeInTheDocument()
  })

  it('does not allow a new code for 60 seconds', async () => {
    codeRoutes()
    const { user } = renderApp('/admin/', { me: null })
    await user.type(await screen.findByLabelText('Email'), 'owner@example.test')
    await user.click(screen.getByRole('button', { name: 'Send code' }))
    const resend = await screen.findByRole('button', { name: /Send a new code/ })
    expect(resend).toBeDisabled()
    await waitFor(() => expect(resend).toHaveTextContent(/in \d+ s/))
  })
})
```

`src/app/App.test.tsx`:

```tsx
import { screen, within } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { ownerMe, staffMe } from '@/test/data'
import { problem, TRACE } from '@/test/problems'
import { renderApp } from '@/test/render'
import { server } from '@/test/server'

describe('shell', () => {
  it('shows every menu item to an Owner', async () => {
    renderApp('/admin/')
    const nav = within(await screen.findByRole('navigation'))
    for (const name of ['Dashboard', 'Staff', 'Roles', 'Audit log', 'Jobs'])
      expect(nav.getByRole('link', { name })).toBeInTheDocument()
    expect(nav.getByRole('link', { name: 'Jobs' })).toHaveAttribute('href', '/admin/jobs')
    expect(screen.getByText('Olive Owner')).toBeInTheDocument()
    expect(screen.getByText('Owner')).toBeInTheDocument()
  })

  it('hides menu items the staff member lacks', async () => {
    server.use(http.get('*/admin/api/staff', () => HttpResponse.json([])), http.get('*/admin/api/roles', () => HttpResponse.json([])))
    renderApp('/admin/', { me: staffMe })
    const nav = within(await screen.findByRole('navigation'))
    expect(nav.getByRole('link', { name: 'Staff' })).toBeInTheDocument()
    for (const name of ['Roles', 'Audit log', 'Jobs'])
      expect(nav.queryByRole('link', { name })).not.toBeInTheDocument()
    expect(screen.getByText('desk@example.test')).toBeInTheDocument()   // no display name: the email stands in
  })

  it('refuses a page address the staff member has no permission for', async () => {
    renderApp('/admin/audit', { me: staffMe })
    expect(await screen.findByText('You do not have access to this page.')).toBeInTheDocument()
  })

  it('shows a not-found page for an unknown address', async () => {
    renderApp('/admin/nope')
    expect(await screen.findByText('This page does not exist.')).toBeInTheDocument()
  })

  it('shows the login screen when a later call gets 401, and returns to the same address', async () => {
    server.use(http.get('*/admin/api/roles', () => HttpResponse.json([])))
    let signedIn = true
    server.use(http.get('*/admin/api/staff', () => (signedIn ? HttpResponse.json([]) : problem(401, 'UNAUTHENTICATED', 'Sign in again.'))))
    const { user, router } = renderApp('/admin/staff')
    expect(await screen.findByRole('heading', { name: 'Staff' })).toBeInTheDocument()

    signedIn = false
    server.use(http.get('*/admin/api/me', () => problem(401, 'UNAUTHENTICATED', 'Sign in again.')))
    await user.click(screen.getByRole('button', { name: 'Reload' }))
    expect(await screen.findByLabelText('Email')).toBeInTheDocument()
    expect(screen.queryByRole('navigation')).not.toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/staff')
  })

  it('signs out', async () => {
    let csrf: string | null = null
    server.use(http.post('*/admin/api/auth/logout', ({ request }) => {
      csrf = request.headers.get('X-CSRF-TOKEN')
      return new HttpResponse(null, { status: 204 })
    }))
    const { user } = renderApp('/admin/')
    await user.click(await screen.findByRole('button', { name: 'Sign out' }))
    expect(await screen.findByLabelText('Email')).toBeInTheDocument()
    expect(csrf).toBe('csrf-test')
  })

  it('shows a retry and the trace id when the session check itself fails', async () => {
    const { user } = renderApp('/admin/', { me: 'down' })
    expect(await screen.findByText('Something went wrong on our side.')).toBeInTheDocument()
    expect(screen.getByText(new RegExp(TRACE))).toBeInTheDocument()
    server.use(http.get('*/admin/api/me', () => HttpResponse.json(ownerMe)))
    await user.click(screen.getByRole('button', { name: 'Try again' }))
    expect(await screen.findByRole('navigation')).toBeInTheDocument()
  })

  it('switches the theme', async () => {
    const { user } = renderApp('/admin/')
    await user.click(await screen.findByRole('button', { name: 'Dark' }))
    expect(document.documentElement.classList.contains('dark')).toBe(true)
    await user.click(screen.getByRole('button', { name: 'Light' }))
    expect(document.documentElement.classList.contains('dark')).toBe(false)
  })
})
```

The "Reload" button in the 401 test is the Staff page's own reload control. Until Task 5 builds that page, give the placeholder `StaffPage` a heading "Staff", a `useQuery` on `GET /admin/api/staff` and a "Reload" button that refetches it, so this test is real now and stays valid after Task 5.

Run: `npm test`
Expected: FAIL, `@/app/App` does not exist.

- [ ] **Step 3: Session**

`src/features/auth/session.tsx`:

```tsx
import { createContext, useContext, useEffect, type ReactNode } from 'react'
import { useQuery, useQueryClient, type QueryClient } from '@tanstack/react-query'
import { api, call, onUnauthorized, resetCsrf } from '@/api/client'
import { ApiError } from '@/api/errors'
import type { components } from '@/api/schema'

export type Me = components['schemas']['AdminMeResponse']

const meKey = ['me'] as const

// null = not signed in. For this one call a 401 is an answer, not an error.
async function fetchMe(): Promise<Me | null> {
  try {
    return await call(() => api.GET('/admin/api/me'))
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) return null
    throw error
  }
}

export function useMe() {
  return useQuery({ queryKey: meKey, queryFn: fetchMe, staleTime: Infinity })
}

/** Forgets the staff member and everything loaded for them. */
function forget(queryClient: QueryClient) {
  resetCsrf()
  queryClient.setQueryData(meKey, null)
  queryClient.removeQueries({ predicate: (query) => query.queryKey[0] !== meKey[0] })
}

/** Any 401, from any call, means the sign-in ended: show the login screen. */
export function useSessionWatch() {
  const queryClient = useQueryClient()
  useEffect(() => onUnauthorized(() => forget(queryClient)), [queryClient])
}

export function useSignedIn() {
  const queryClient = useQueryClient()
  return async () => {
    resetCsrf()   // a token fetched before sign-in belongs to nobody
    await queryClient.invalidateQueries({ queryKey: meKey })
  }
}

export function useSignOut() {
  const queryClient = useQueryClient()
  return async () => {
    try {
      await call(() => api.POST('/admin/api/auth/logout'))
    } finally {
      forget(queryClient)
    }
  }
}

type Session = { me: Me; can: (permission: string) => boolean }

const SessionContext = createContext<Session | null>(null)

export function SessionProvider({ me, children }: { me: Me; children: ReactNode }) {
  // Hiding only: the server checks every call (S0 spec §6.3).
  const session: Session = { me, can: (permission) => me.permissions.includes(permission) }
  return <SessionContext value={session}>{children}</SessionContext>
}

export function useSession(): Session {
  const session = useContext(SessionContext)
  if (!session) throw new Error('useSession is only available inside the signed-in shell.')
  return session
}
```

- [ ] **Step 4: Errors, time and the page frame**

`src/components/ErrorNote.tsx`:

```tsx
import { toast } from 'sonner'
import { ApiError } from '@/api/errors'

function describe(error: unknown): { message: string; traceId?: string } {
  if (error instanceof ApiError) return { message: error.message, traceId: error.traceId }
  return { message: 'Something went wrong. Please try again.' }
}

function copy(traceId: string) {
  void navigator.clipboard?.writeText(traceId)
}

/** An error where it happened, with the trace id support needs to find the request (S0 spec §4.4). */
export function ErrorNote({ error }: { error: unknown }) {
  const { message, traceId } = describe(error)
  return (
    <div role="alert" className="rounded-md border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
      <p>{message}</p>
      {traceId ? (
        <p className="mt-1 flex items-center gap-2 text-xs opacity-80">
          <span>Trace {traceId}</span>
          <button type="button" className="underline" onClick={() => copy(traceId)}>Copy</button>
        </p>
      ) : null}
    </div>
  )
}

export function toastError(error: unknown): void {
  const { message, traceId } = describe(error)
  toast.error(message, traceId
    ? { description: `Trace ${traceId}`, action: { label: 'Copy', onClick: () => copy(traceId) } }
    : undefined)
}
```

`src/lib/time.ts`:

```ts
const format = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' })

/** A server instant in the browser's time zone. */
export function formatInstant(iso: string): string {
  return format.format(new Date(iso))
}

export function zoneName(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone
}

/** A `datetime-local` value (browser time, no zone) as an instant with Z; the audit filter needs an offset. */
export function localInputToInstant(value: string): string | undefined {
  if (!value) return undefined
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? undefined : date.toISOString()
}
```

`src/components/PageShell.tsx`:

```tsx
import type { ReactNode } from 'react'

export function PageShell({ title, actions, children }: { title: string; actions?: ReactNode; children: ReactNode }) {
  return (
    <section className="space-y-4">
      <div className="flex items-center justify-between gap-4">
        <h1 className="text-lg font-semibold">{title}</h1>
        <div className="flex items-center gap-2">{actions}</div>
      </div>
      {children}
    </section>
  )
}
```

- [ ] **Step 5: Sign-in screen**

`src/features/auth/LoginScreen.tsx`:

```tsx
import { useEffect, useState, type FormEvent } from 'react'
import { api, call } from '@/api/client'
import { ApiError } from '@/api/errors'
import { ErrorNote } from '@/components/ErrorNote'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { useSignedIn } from './session'

const RESEND_SECONDS = 60   // the server refuses a second send sooner (S0 spec §6.1)

function wait(seconds: number): string {
  return seconds < 60 ? `${seconds} seconds` : `${Math.ceil(seconds / 60)} minutes`
}

export function LoginScreen() {
  const signedIn = useSignedIn()
  const [step, setStep] = useState<'email' | 'code'>('email')
  const [email, setEmail] = useState('')
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<unknown>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [resendIn, setResendIn] = useState(0)

  useEffect(() => {
    if (resendIn <= 0) return
    const timer = setTimeout(() => setResendIn((s) => s - 1), 1000)
    return () => clearTimeout(timer)
  }, [resendIn])

  async function run(action: () => Promise<void>) {
    setBusy(true)
    setError(null)
    setNotice(null)
    try {
      await action()
    } catch (caught) {
      setError(caught)
      if (caught instanceof ApiError && caught.retryAfterSeconds) setNotice(`Try again in ${wait(caught.retryAfterSeconds)}.`)
      if (caught instanceof ApiError && caught.code === 'TOO_MANY_ATTEMPTS') {
        setStep('email')
        setCode('')
      }
    } finally {
      setBusy(false)
    }
  }

  const address = email.trim().toLowerCase()

  const sendCode = () => run(async () => {
    await call(() => api.POST('/admin/api/auth/code', { body: { email: address } }))
    setStep('code')
    setResendIn(RESEND_SECONDS)
  })

  const verify = () => run(async () => {
    await call(() => api.POST('/admin/api/auth/code/verify', { body: { email: address, code: code.trim() } }))
    await signedIn()
  })

  function onSubmit(event: FormEvent) {
    event.preventDefault()
    void (step === 'email' ? sendCode() : verify())
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/40 px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 flex flex-col items-center gap-3 text-center">
          <div className="flex size-11 items-center justify-center rounded-xl bg-primary text-lg font-bold text-primary-foreground">e</div>
          <div>
            <h1 className="text-lg font-bold">ExtraSpace Admin</h1>
            <p className="text-sm text-muted-foreground">Sign in with your work email</p>
          </div>
        </div>

        <form onSubmit={onSubmit} className="space-y-4 rounded-xl border bg-card p-6 shadow-sm">
          {step === 'email' ? (
            <div className="space-y-1.5">
              <Label htmlFor="email">Email</Label>
              <Input id="email" type="email" autoComplete="username" required autoFocus value={email} onChange={(e) => setEmail(e.target.value)} />
            </div>
          ) : (
            <>
              <p className="text-sm text-muted-foreground">
                If {address} belongs to a staff member, a 6-digit code is on its way. It is valid for 10 minutes.
              </p>
              <div className="space-y-1.5">
                <Label htmlFor="code">Code</Label>
                <Input id="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required autoFocus
                  value={code} onChange={(e) => setCode(e.target.value)} />
              </div>
            </>
          )}

          {error ? <ErrorNote error={error} /> : null}
          {notice ? <p className="text-sm text-muted-foreground">{notice}</p> : null}

          <Button type="submit" className="w-full" disabled={busy}>
            {step === 'email' ? 'Send code' : 'Sign in'}
          </Button>

          {step === 'code' ? (
            <div className="flex justify-between text-sm">
              <button type="button" className="underline" onClick={() => { setStep('email'); setCode(''); setError(null) }}>
                Use another email
              </button>
              <button type="button" className="underline disabled:no-underline disabled:opacity-60" disabled={busy || resendIn > 0} onClick={() => void sendCode()}>
                {resendIn > 0 ? `Send a new code in ${resendIn} s` : 'Send a new code'}
              </button>
            </div>
          ) : null}
        </form>
      </div>
    </div>
  )
}
```

The sentence starting "If … belongs to a staff member" is deliberate: the server answers 202 for every address, and the screen must not say more than the server does.

- [ ] **Step 6: Shell, routes and the app root**

`src/app/nav.ts`:

```ts
import { LayoutDashboard, ScrollText, ShieldCheck, Timer, Users, type LucideIcon } from 'lucide-react'

export type NavItem = {
  label: string
  to: string
  icon: LucideIcon
  /** Hidden without it. */
  permission?: string
  /** A page outside this app (a full page load, not a route). */
  external?: boolean
}

export const navItems: NavItem[] = [
  { label: 'Dashboard', to: '/', icon: LayoutDashboard },
  { label: 'Staff', to: '/staff', icon: Users, permission: 'staff.manage' },
  { label: 'Roles', to: '/roles', icon: ShieldCheck, permission: 'roles.manage' },
  { label: 'Audit log', to: '/audit', icon: ScrollText, permission: 'audit.read' },
  { label: 'Jobs', to: '/admin/jobs', icon: Timer, permission: 'jobs.manage', external: true },
]
```

`src/app/ThemeSwitch.tsx`:

```tsx
import { useSyncExternalStore } from 'react'
import { Monitor, Moon, Sun } from 'lucide-react'
import { getTheme, setTheme, subscribeTheme, type ThemePref } from '@/lib/theme'
import { cn } from '@/lib/utils'

const options: [ThemePref, string, typeof Sun][] = [
  ['light', 'Light', Sun],
  ['dark', 'Dark', Moon],
  ['system', 'Match system', Monitor],
]

export function ThemeSwitch() {
  const pref = useSyncExternalStore(subscribeTheme, getTheme)
  return (
    <div role="group" aria-label="Theme" className="flex items-center rounded-lg border bg-muted p-0.5">
      {options.map(([value, label, Icon]) => (
        <button key={value} type="button" title={label} aria-label={label} aria-pressed={pref === value} onClick={() => setTheme(value)}
          className={cn('flex size-7 items-center justify-center rounded-md text-muted-foreground', pref === value && 'bg-background text-foreground shadow-sm')}>
          <Icon className="size-3.5" />
        </button>
      ))}
    </div>
  )
}
```

`src/app/Shell.tsx`:

```tsx
import { LogOut } from 'lucide-react'
import { NavLink, Outlet } from 'react-router'
import { toastError } from '@/components/ErrorNote'
import { Button } from '@/components/ui/button'
import { Toaster } from '@/components/ui/sonner'
import { useSession, useSignOut } from '@/features/auth/session'
import { cn } from '@/lib/utils'
import { navItems } from './nav'
import { ThemeSwitch } from './ThemeSwitch'

const itemClass = 'flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm font-medium text-muted-foreground hover:bg-muted hover:text-foreground'

export function Shell() {
  const { me, can } = useSession()
  const signOut = useSignOut()
  const items = navItems.filter((item) => !item.permission || can(item.permission))

  return (
    <div className="flex h-screen bg-muted/40">
      <aside className="hidden w-64 shrink-0 flex-col border-r bg-background md:flex">
        <div className="flex h-16 items-center gap-2 border-b px-4">
          <div className="flex size-8 items-center justify-center rounded-lg bg-primary text-sm font-bold text-primary-foreground">e</div>
          <div className="leading-tight">
            <p className="text-sm font-bold">ExtraSpace</p>
            <p className="text-[11px] text-muted-foreground">Admin</p>
          </div>
        </div>
        <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4">
          {items.map(({ label, to, icon: Icon, external }) =>
            external ? (
              <a key={to} href={to} className={itemClass}><Icon className="size-4" />{label}</a>
            ) : (
              <NavLink key={to} to={to} end={to === '/'} className={({ isActive }) => cn(itemClass, isActive && 'bg-primary/10 text-primary')}>
                <Icon className="size-4" />{label}
              </NavLink>
            ))}
        </nav>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-16 shrink-0 items-center justify-end gap-3 border-b bg-background px-6">
          <ThemeSwitch />
          <div className="text-right leading-tight">
            <p className="text-sm font-medium">{me.displayName ?? me.email}</p>
            <p className="text-xs text-muted-foreground">{me.roleName}</p>
          </div>
          <Button variant="outline" size="sm" onClick={() => void signOut().catch(toastError)}>
            <LogOut className="size-4" />Sign out
          </Button>
        </header>
        <main className="flex-1 overflow-y-auto p-6"><Outlet /></main>
      </div>
      <Toaster />
    </div>
  )
}
```

The external "Jobs" link is a plain `<a>`: `/admin/jobs` is the Hangfire dashboard, served by the API, not a route of this app.

`src/app/routes.tsx`:

```tsx
import type { ComponentType } from 'react'
import type { RouteObject } from 'react-router'
import { useSession } from '@/features/auth/session'
import { AuditPage } from '@/features/audit/AuditPage'
import { DashboardPage } from '@/features/dashboard/DashboardPage'
import { RolesPage } from '@/features/roles/RolesPage'
import { StaffPage } from '@/features/staff/StaffPage'
import { Shell } from './Shell'

function Message({ text }: { text: string }) {
  return <p className="py-16 text-center text-sm text-muted-foreground">{text}</p>
}

/** Hiding only: a page the staff member may not use shows a message; its API calls would get 403 anyway. */
function guarded(permission: string, Page: ComponentType): ComponentType {
  return function Guarded() {
    return useSession().can(permission) ? <Page /> : <Message text="You do not have access to this page." />
  }
}

export const routes: RouteObject[] = [
  {
    path: '/',
    Component: Shell,
    children: [
      { index: true, Component: DashboardPage },
      { path: 'staff', Component: guarded('staff.manage', StaffPage) },
      { path: 'roles', Component: guarded('roles.manage', RolesPage) },
      { path: 'audit', Component: guarded('audit.read', AuditPage) },
      { path: '*', Component: () => <Message text="This page does not exist." /> },
    ],
  },
]
```

`src/app/App.tsx`:

```tsx
import { QueryClientProvider, type QueryClient } from '@tanstack/react-query'
import type { createBrowserRouter } from 'react-router'
import { RouterProvider } from 'react-router/dom'
import { ErrorNote } from '@/components/ErrorNote'
import { Button } from '@/components/ui/button'
import { LoginScreen } from '@/features/auth/LoginScreen'
import { SessionProvider, useMe, useSessionWatch } from '@/features/auth/session'

type Router = ReturnType<typeof createBrowserRouter>

function Gate({ router }: { router: Router }) {
  useSessionWatch()
  const me = useMe()

  if (me.isPending) return <p className="p-6 text-sm text-muted-foreground">Loading…</p>
  if (me.isError)
    return (
      <div className="mx-auto max-w-sm space-y-3 p-6">
        <ErrorNote error={me.error} />
        <Button onClick={() => void me.refetch()}>Try again</Button>
      </div>
    )
  // No /login route: the router keeps its address while the login screen shows, so sign-in returns to the same page.
  if (me.data === null) return <LoginScreen />
  return (
    <SessionProvider me={me.data}>
      <RouterProvider router={router} />
    </SessionProvider>
  )
}

export function App({ router, queryClient }: { router: Router; queryClient: QueryClient }) {
  return (
    <QueryClientProvider client={queryClient}>
      <Gate router={router} />
    </QueryClientProvider>
  )
}
```

`src/main.tsx`:

```tsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { createBrowserRouter } from 'react-router'
import { App } from '@/app/App'
import { routes } from '@/app/routes'
import { makeQueryClient } from '@/lib/query'
import { applyTheme } from '@/lib/theme'
import './index.css'

applyTheme()
const router = createBrowserRouter(routes, { basename: '/admin' })
const queryClient = makeQueryClient()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App router={router} queryClient={queryClient} />
  </StrictMode>,
)
```

`src/features/dashboard/DashboardPage.tsx`:

```tsx
import { PageShell } from '@/components/PageShell'
import { useSession } from '@/features/auth/session'

export function DashboardPage() {
  const { me } = useSession()
  return (
    <PageShell title="Dashboard">
      <p className="text-sm text-muted-foreground">Welcome, {me.displayName ?? me.email}. Reports arrive with the self-storage release.</p>
    </PageShell>
  )
}
```

Placeholders for now: `features/roles/RolesPage.tsx` and `features/audit/AuditPage.tsx` each export a component that renders `<PageShell title="Roles">` / `<PageShell title="Audit log">` with no content. `features/staff/StaffPage.tsx`:

```tsx
import { useQuery } from '@tanstack/react-query'
import { api, call } from '@/api/client'
import { PageShell } from '@/components/PageShell'
import { Button } from '@/components/ui/button'

export function StaffPage() {
  const staff = useQuery({ queryKey: ['staff'], queryFn: () => call(() => api.GET('/admin/api/staff')) })
  return (
    <PageShell title="Staff" actions={<Button variant="outline" onClick={() => void staff.refetch()}>Reload</Button>}>
      {null}
    </PageShell>
  )
}
```

- [ ] **Step 7: Run everything**

```bash
npm run typecheck && npm test && npm run build
```

Expected: all pass. Known jsdom points: `navigator.clipboard` may be missing (the code guards it); React Router's `createBrowserRouter` type is used for the memory router too (both return the same router type; if the installed types disagree, import the router type the library exports).

- [ ] **Step 8: Hand-off**

Report the files, test counts, and anything that differed from the plan. Do not commit.

---

### Task 5: Shared list and form pieces, and the Staff screen

**Files (under `admin-ui/src/`):**
- Create: `components/DataTable.tsx`, `components/ConfirmDialog.tsx`, `components/FormField.tsx`, `components/NativeSelect.tsx`, `lib/forms.ts`
- Create: `features/roles/api.ts` (the roles list query only; Task 6 adds the writes)
- Create: `features/staff/api.ts`, `features/staff/StaffDialog.tsx`
- Modify: `features/staff/StaffPage.tsx` (replace the placeholder)
- Test: `features/staff/StaffPage.test.tsx`

**Interfaces:**
- Consumes: Task 3 and Task 4 exports.
- Produces:
  - `features` (the shared TanStack Table feature set), `columnsFor<T>()` (a column helper bound to it), `<DataTable columns data empty />`.
  - `<ConfirmDialog open title description confirmLabel pending error onConfirm onCancel />`.
  - `<FormField label htmlFor error?>children</FormField>`, `<NativeSelect>` (a styled `<select>`, same props as `select`).
  - `applyServerErrors(error, form.setError, fields): boolean` in `lib/forms.ts`: copies `ApiError.fieldErrors` onto the named form fields and says whether it placed any.
  - `conflictMessage` (the text shown on 409 `CONFLICT`).
  - `useRoles()`, `rolesKey`, `type Role = components['schemas']['RoleResponse']`.

- [ ] **Step 1: Write the failing tests**

`src/features/staff/StaffPage.test.tsx`:

```tsx
import { screen, within } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import type { components } from '@/api/schema'
import { DESK_ROLE_ID, OWNER_ROLE_ID, ownerMe, staffMe } from '@/test/data'
import { problem } from '@/test/problems'
import { renderApp } from '@/test/render'
import { server } from '@/test/server'

type Staff = components['schemas']['StaffResponse']

const roles = [
  { id: OWNER_ROLE_ID, name: 'Owner', permissions: [], isSystem: true, staffCount: 1, version: 1 },
  { id: DESK_ROLE_ID, name: 'Front desk', permissions: ['staff.manage'], isSystem: false, staffCount: 1, version: 3 },
]
const olive: Staff = { id: ownerMe.id, email: ownerMe.email, displayName: 'Olive Owner', roleId: OWNER_ROLE_ID, roleName: 'Owner', active: true, lastSignInAt: '2026-10-13T02:30:00Z', version: 11 }
const dan: Staff = { id: staffMe.id, email: staffMe.email, displayName: null, roleId: DESK_ROLE_ID, roleName: 'Front desk', active: true, lastSignInAt: null, version: 5 }

function serve(staff: Staff[]) {
  const state = { staff, lists: 0 }
  server.use(
    http.get('*/admin/api/roles', () => HttpResponse.json(roles)),
    http.get('*/admin/api/staff', () => {
      state.lists++
      return HttpResponse.json(state.staff)
    }),
  )
  return state
}

const rowOf = (email: string) => within(screen.getByText(email).closest('tr')!)

describe('Staff', () => {
  it('lists staff with role, status and last sign-in', async () => {
    serve([olive, dan])
    renderApp('/admin/staff')
    expect(await screen.findByText('desk@example.test')).toBeInTheDocument()
    expect(rowOf('owner@example.test').getByText('Olive Owner')).toBeInTheDocument()
    expect(rowOf('owner@example.test').getByText('Active')).toBeInTheDocument()
    expect(rowOf('desk@example.test').getByText('Front desk')).toBeInTheDocument()
    expect(rowOf('desk@example.test').getByText('Never')).toBeInTheDocument()
  })

  it('adds a staff member', async () => {
    const state = serve([olive])
    let body: unknown
    server.use(http.post('*/admin/api/staff', async ({ request }) => {
      body = await request.json()
      state.staff = [olive, dan]
      return HttpResponse.json(dan, { status: 201 })
    }))
    const { user } = renderApp('/admin/staff')
    await user.click(await screen.findByRole('button', { name: 'Add staff' }))
    const dialog = within(await screen.findByRole('dialog'))
    await user.type(dialog.getByLabelText('Email'), 'desk@example.test')
    await user.type(dialog.getByLabelText('Display name'), 'Dan Desk')
    await user.selectOptions(dialog.getByLabelText('Role'), DESK_ROLE_ID)
    await user.click(dialog.getByRole('button', { name: 'Add' }))

    expect(await screen.findByText('desk@example.test')).toBeInTheDocument()
    expect(body).toEqual({ email: 'desk@example.test', displayName: 'Dan Desk', roleId: DESK_ROLE_ID })
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('shows a field error from the server on its field', async () => {
    serve([olive])
    server.use(http.post('*/admin/api/staff', () =>
      problem(400, 'VALIDATION_FAILED', 'One or more fields are not valid.', { errors: { email: ['The Email field is not a valid e-mail address.'] } })))
    const { user } = renderApp('/admin/staff')
    await user.click(await screen.findByRole('button', { name: 'Add staff' }))
    const dialog = within(await screen.findByRole('dialog'))
    await user.type(dialog.getByLabelText('Email'), 'a@b')
    await user.selectOptions(dialog.getByLabelText('Role'), DESK_ROLE_ID)
    await user.click(dialog.getByRole('button', { name: 'Add' }))
    expect(await dialog.findByText('The Email field is not a valid e-mail address.')).toBeInTheDocument()
  })

  it('edits the role and the display name with the row version', async () => {
    const state = serve([olive, dan])
    let body: unknown
    server.use(http.patch(`*/admin/api/staff/${dan.id}`, async ({ request }) => {
      body = await request.json()
      state.staff = [olive, { ...dan, displayName: 'Dan Desk', version: 6 }]
      return HttpResponse.json(state.staff[1])
    }))
    const { user } = renderApp('/admin/staff')
    await screen.findByText('desk@example.test')
    await user.click(rowOf('desk@example.test').getByRole('button', { name: 'Edit' }))
    const dialog = within(await screen.findByRole('dialog'))
    await user.type(dialog.getByLabelText('Display name'), 'Dan Desk')
    await user.click(dialog.getByRole('button', { name: 'Save' }))
    expect(await screen.findByText('Dan Desk')).toBeInTheDocument()
    expect(body).toEqual({ displayName: 'Dan Desk', roleId: DESK_ROLE_ID, version: 5 })
  })

  it('reloads the list when the save is stale', async () => {
    const state = serve([olive, dan])
    const versions: unknown[] = []
    server.use(http.patch(`*/admin/api/staff/${dan.id}`, async ({ request }) => {
      const sent = (await request.json()) as { version: number }
      versions.push(sent.version)
      if (sent.version === 5) {
        state.staff = [olive, { ...dan, version: 9 }]   // someone else saved in between
        return problem(409, 'CONFLICT', 'The record was changed by someone else.')
      }
      return HttpResponse.json({ ...dan, version: 10 })
    }))
    const { user } = renderApp('/admin/staff')
    await screen.findByText('desk@example.test')
    await user.click(rowOf('desk@example.test').getByRole('button', { name: 'Edit' }))
    const dialog = within(await screen.findByRole('dialog'))
    await user.type(dialog.getByLabelText('Display name'), 'Dan')
    await user.click(dialog.getByRole('button', { name: 'Save' }))

    expect(await dialog.findByText(/Someone else changed this record/)).toBeInTheDocument()
    expect(screen.getByRole('dialog')).toBeInTheDocument()   // nothing was lost or silently overwritten
    await user.click(dialog.getByRole('button', { name: 'Save' }))
    await screen.findByText('desk@example.test')
    expect(versions).toEqual([5, 9])
  })

  it('deactivates after a confirmation and shows a business refusal', async () => {
    serve([olive, dan])
    const bodies: unknown[] = []
    server.use(http.patch(`*/admin/api/staff/${dan.id}`, async ({ request }) => {
      bodies.push(await request.json())
      return problem(409, 'LAST_OWNER', 'At least one active Owner must remain.')
    }))
    const { user } = renderApp('/admin/staff')
    await screen.findByText('desk@example.test')
    await user.click(rowOf('desk@example.test').getByRole('button', { name: 'Deactivate' }))
    const dialog = within(await screen.findByRole('dialog'))
    expect(dialog.getByText(/desk@example.test will be signed out/)).toBeInTheDocument()
    await user.click(dialog.getByRole('button', { name: 'Deactivate' }))
    expect(await dialog.findByText('At least one active Owner must remain.')).toBeInTheDocument()
    expect(bodies).toEqual([{ active: false, version: 5 }])
  })

  it('offers no way to deactivate yourself', async () => {
    serve([olive, dan])
    renderApp('/admin/staff')
    await screen.findByText('desk@example.test')
    expect(rowOf('owner@example.test').queryByRole('button', { name: 'Deactivate' })).not.toBeInTheDocument()
    expect(rowOf('owner@example.test').getByRole('button', { name: 'Edit' })).toBeInTheDocument()
  })

  it('does not offer the Owner role to a non-Owner', async () => {
    serve([olive, dan])
    const { user } = renderApp('/admin/staff', { me: staffMe })
    await screen.findByText('owner@example.test')
    expect(rowOf('owner@example.test').queryByRole('button')).not.toBeInTheDocument()   // an Owner's row is Owner-only
    await user.click(screen.getByRole('button', { name: 'Add staff' }))
    const dialog = within(await screen.findByRole('dialog'))
    const options = within(dialog.getByLabelText('Role')).getAllByRole('option').map((o) => o.textContent)
    expect(options).toEqual(['Choose a role', 'Front desk'])
  })

  it('reactivates an inactive staff member', async () => {
    serve([olive, { ...dan, active: false }])
    let body: unknown
    server.use(http.patch(`*/admin/api/staff/${dan.id}`, async ({ request }) => {
      body = await request.json()
      return HttpResponse.json({ ...dan, version: 6 })
    }))
    const { user } = renderApp('/admin/staff')
    await screen.findByText('desk@example.test')
    expect(rowOf('desk@example.test').getByText('Inactive')).toBeInTheDocument()
    await user.click(rowOf('desk@example.test').getByRole('button', { name: 'Reactivate' }))
    await user.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Reactivate' }))
    await screen.findByText('desk@example.test')
    expect(body).toEqual({ active: true, version: 5 })
  })
})
```

Run: `npm test -- StaffPage`
Expected: FAIL (no "Add staff" button, no rows).

- [ ] **Step 2: Shared pieces**

`src/components/DataTable.tsx` (TanStack Table 9; the working reference is `DashboardPage.tsx` in the spike note):

```tsx
import type { ReactNode } from 'react'
import { createColumnHelper, tableFeatures, useTable } from '@tanstack/react-table'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'

/** One feature set for every list. Sorting, filtering and paging are done by the server (or not at all) in S0. */
export const features = tableFeatures({})

export function columnsFor<T>() {
  return createColumnHelper<typeof features, T>()
}

type Columns<T> = ReturnType<ReturnType<typeof columnsFor<T>>['columns']>

export function DataTable<T>({ columns, data, empty }: { columns: Columns<T>; data: T[]; empty: ReactNode }) {
  const table = useTable({ features, columns, data })
  const rows = table.getRowModel().rows
  return (
    <div className="rounded-xl border bg-card">
      <Table>
        <TableHeader>
          {table.getHeaderGroups().map((group) => (
            <TableRow key={group.id}>
              {group.headers.map((header) => (
                <TableHead key={header.id}>{header.isPlaceholder ? null : <table.FlexRender header={header} />}</TableHead>
              ))}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {rows.length === 0 ? (
            <TableRow>
              <TableCell colSpan={table.getAllColumns().length} className="py-10 text-center text-sm text-muted-foreground">{empty}</TableCell>
            </TableRow>
          ) : (
            rows.map((row) => (
              <TableRow key={row.id}>
                {row.getAllCells().map((cell) => (
                  <TableCell key={cell.id}><table.FlexRender cell={cell} /></TableCell>
                ))}
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
    </div>
  )
}
```

`Columns<T>` is the one type here the spike did not compile. If the instantiation expression does not resolve in the installed version, type the prop with the column-definition type the package exports for `(typeof features, T)` (see `node_modules/@tanstack/react-table/skills/`); do not fall back to `any`.

`src/components/FormField.tsx`:

```tsx
import type { ReactNode } from 'react'
import { Label } from '@/components/ui/label'

export function FormField({ label, htmlFor, error, children }: { label: string; htmlFor: string; error?: string; children: ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={htmlFor}>{label}</Label>
      {children}
      {error ? <p role="alert" className="text-xs text-destructive">{error}</p> : null}
    </div>
  )
}
```

`src/components/NativeSelect.tsx`:

```tsx
import type { ComponentProps } from 'react'
import { cn } from '@/lib/utils'

export function NativeSelect({ className, ...props }: ComponentProps<'select'>) {
  return (
    <select
      className={cn('h-9 w-full rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-60', className)}
      {...props}
    />
  )
}
```

`src/components/ConfirmDialog.tsx`:

```tsx
import type { ReactNode } from 'react'
import { ErrorNote } from '@/components/ErrorNote'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'

type Props = {
  open: boolean
  title: string
  description: ReactNode
  confirmLabel: string
  destructive?: boolean
  pending: boolean
  error: unknown
  onConfirm: () => void
  onCancel: () => void
}

export function ConfirmDialog({ open, title, description, confirmLabel, destructive, pending, error, onConfirm, onCancel }: Props) {
  return (
    <Dialog open={open} onOpenChange={(next) => { if (!next) onCancel() }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>
        {error ? <ErrorNote error={error} /> : null}
        <DialogFooter>
          <Button variant="outline" onClick={onCancel}>Cancel</Button>
          <Button variant={destructive ? 'destructive' : 'default'} disabled={pending} onClick={onConfirm}>{confirmLabel}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
```

`src/lib/forms.ts`:

```ts
import type { FieldValues, Path, UseFormSetError } from 'react-hook-form'
import { ApiError } from '@/api/errors'

export const conflictMessage = 'Someone else changed this record. The list was reloaded; check it and save again.'

/** Puts the server's field errors (keys are camelCase field names) on the form. False = nothing placed, show the error as a whole. */
export function applyServerErrors<T extends FieldValues>(error: unknown, setError: UseFormSetError<T>, fields: readonly Path<T>[]): boolean {
  if (!(error instanceof ApiError)) return false
  let placed = false
  for (const field of fields) {
    const message = error.fieldErrors[field]?.[0]
    if (message) {
      setError(field, { message })
      placed = true
    }
  }
  return placed
}
```

- [ ] **Step 3: Data hooks**

`src/features/roles/api.ts`:

```ts
import { useQuery } from '@tanstack/react-query'
import { api, call } from '@/api/client'
import type { components } from '@/api/schema'

export type Role = components['schemas']['RoleResponse']

export const rolesKey = ['roles'] as const

export function useRoles() {
  return useQuery({ queryKey: rolesKey, queryFn: () => call(() => api.GET('/admin/api/roles')) })
}
```

`src/features/staff/api.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api, call } from '@/api/client'
import { ApiError } from '@/api/errors'
import type { components } from '@/api/schema'

export type Staff = components['schemas']['StaffResponse']
type AddStaff = components['schemas']['AddStaffBody']
type UpdateStaff = components['schemas']['UpdateStaffBody']

export const staffKey = ['staff'] as const

export function useStaff() {
  return useQuery({ queryKey: staffKey, queryFn: () => call(() => api.GET('/admin/api/staff')) })
}

/** After any staff write, and after a 409: the list (and the versions in it) must be fresh before the next try. */
function useReload() {
  const queryClient = useQueryClient()
  return () => queryClient.invalidateQueries({ queryKey: staffKey })
}

export function useAddStaff() {
  const reload = useReload()
  return useMutation({
    mutationFn: (body: AddStaff) => call(() => api.POST('/admin/api/staff', { body })),
    onSuccess: reload,
  })
}

export function useUpdateStaff() {
  const reload = useReload()
  return useMutation({
    mutationFn: ({ id, body }: { id: string; body: UpdateStaff }) =>
      call(() => api.PATCH('/admin/api/staff/{id}', { params: { path: { id } }, body })),
    onSuccess: reload,
    onError: (error) => (error instanceof ApiError && error.status === 409 ? reload() : undefined),
  })
}
```

Returning the `invalidateQueries` promise from `onSuccess` / `onError` keeps the mutation pending until the list is fresh; the tests rely on that.

- [ ] **Step 4: The dialog**

`src/features/staff/StaffDialog.tsx`:

```tsx
import { useState } from 'react'
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm } from 'react-hook-form'
import { z } from 'zod'
import { ApiError } from '@/api/errors'
import { ErrorNote } from '@/components/ErrorNote'
import { FormField } from '@/components/FormField'
import { NativeSelect } from '@/components/NativeSelect'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { useSession } from '@/features/auth/session'
import type { Role } from '@/features/roles/api'
import { applyServerErrors, conflictMessage } from '@/lib/forms'
import { useAddStaff, useUpdateStaff, type Staff } from './api'

// The server validates again and is the authority; this only saves a round trip.
const schema = z.object({
  email: z.email('Enter a valid email address.').max(254),
  displayName: z.string().max(200, 'At most 200 characters.'),
  roleId: z.string().min(1, 'Choose a role.'),
})
type Values = z.infer<typeof schema>

/** `staff` set = edit that member (always the current row of the list, so `version` is fresh); unset = add. */
export function StaffDialog({ staff, roles, onClose }: { staff?: Staff; roles: Role[]; onClose: () => void }) {
  const { me } = useSession()
  const add = useAddStaff()
  const update = useUpdateStaff()
  const [failure, setFailure] = useState<unknown>(null)
  const form = useForm<Values>({
    resolver: zodResolver(schema),
    defaultValues: { email: staff?.email ?? '', displayName: staff?.displayName ?? '', roleId: staff?.roleId ?? '' },
  })
  const { errors } = form.formState
  // Hiding only: the server refuses a non-Owner who grants the Owner role (403).
  const options = roles.filter((role) => me.isOwner || !role.isSystem)

  async function onSubmit(values: Values) {
    setFailure(null)
    try {
      if (staff)
        await update.mutateAsync({ id: staff.id, body: { displayName: values.displayName, roleId: values.roleId, version: staff.version } })
      else
        await add.mutateAsync({ email: values.email, displayName: values.displayName, roleId: values.roleId })
      onClose()
    } catch (error) {
      if (!applyServerErrors(error, form.setError, ['email', 'displayName', 'roleId'])) setFailure(error)
    }
  }

  const stale = failure instanceof ApiError && failure.code === 'CONFLICT'

  return (
    <Dialog open onOpenChange={(next) => { if (!next) onClose() }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{staff ? `Edit ${staff.email}` : 'Add staff'}</DialogTitle>
        </DialogHeader>
        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4" noValidate>
          {staff ? null : (
            <FormField label="Email" htmlFor="staff-email" error={errors.email?.message}>
              <Input id="staff-email" type="email" autoComplete="off" {...form.register('email')} />
            </FormField>
          )}
          <FormField label="Display name" htmlFor="staff-name" error={errors.displayName?.message}>
            <Input id="staff-name" autoComplete="off" {...form.register('displayName')} />
          </FormField>
          <FormField label="Role" htmlFor="staff-role" error={errors.roleId?.message}>
            <NativeSelect id="staff-role" {...form.register('roleId')}>
              <option value="">Choose a role</option>
              {options.map((role) => <option key={role.id} value={role.id}>{role.name}</option>)}
            </NativeSelect>
          </FormField>
          {stale ? <p role="alert" className="text-sm text-destructive">{conflictMessage}</p> : failure ? <ErrorNote error={failure} /> : null}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
            <Button type="submit" disabled={add.isPending || update.isPending}>{staff ? 'Save' : 'Add'}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
```

In edit mode the `email` field is not shown but is still in the schema: its default value is the member's own address, so it always passes. An empty display name is sent as `""`, which the server reads as "clear it".

- [ ] **Step 5: The page**

`src/features/staff/StaffPage.tsx`:

```tsx
import { useState } from 'react'
import { ErrorNote } from '@/components/ErrorNote'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import { columnsFor, DataTable } from '@/components/DataTable'
import { PageShell } from '@/components/PageShell'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useSession } from '@/features/auth/session'
import { useRoles } from '@/features/roles/api'
import { formatInstant, zoneName } from '@/lib/time'
import { useStaff, useUpdateStaff, type Staff } from './api'
import { StaffDialog } from './StaffDialog'

type Open = { kind: 'add' } | { kind: 'edit' | 'toggle'; id: string } | null

export function StaffPage() {
  const { me } = useSession()
  const staff = useStaff()
  const roles = useRoles()
  const update = useUpdateStaff()
  const [open, setOpen] = useState<Open>(null)

  const systemRoles = new Set((roles.data ?? []).filter((role) => role.isSystem).map((role) => role.id))
  // The dialogs read the row from the list, never a copy: after a 409 the reloaded row carries the new version.
  const selected = open && open.kind !== 'add' ? staff.data?.find((member) => member.id === open.id) : undefined

  function close() {
    update.reset()
    setOpen(null)
  }

  const helper = columnsFor<Staff>()
  const columns = helper.columns([
    helper.accessor('email', { header: 'Email' }),
    helper.accessor('displayName', { header: 'Name', cell: (c) => c.getValue() ?? '—' }),
    helper.accessor('roleName', { header: 'Role' }),
    helper.accessor('active', { header: 'Status', cell: (c) => <Badge variant={c.getValue() ? 'default' : 'secondary'}>{c.getValue() ? 'Active' : 'Inactive'}</Badge> }),
    helper.accessor('lastSignInAt', { header: `Last sign-in (${zoneName()})`, cell: (c) => { const at = c.getValue(); return at ? formatInstant(at) : 'Never' } }),
    helper.display({
      id: 'actions',
      header: '',
      cell: ({ row }) => {
        const member = row.original
        // Hiding only: only an Owner may change an Owner, and nobody deactivates themself (the server refuses both).
        if (systemRoles.has(member.roleId) && !me.isOwner) return null
        return (
          <div className="flex justify-end gap-2">
            <Button size="sm" variant="outline" onClick={() => setOpen({ kind: 'edit', id: member.id })}>Edit</Button>
            {member.id === me.id ? null : (
              <Button size="sm" variant="outline" onClick={() => setOpen({ kind: 'toggle', id: member.id })}>
                {member.active ? 'Deactivate' : 'Reactivate'}
              </Button>
            )}
          </div>
        )
      },
    }),
  ])

  return (
    <PageShell
      title="Staff"
      actions={
        <>
          <Button variant="outline" onClick={() => void staff.refetch()}>Reload</Button>
          <Button onClick={() => setOpen({ kind: 'add' })} disabled={!roles.data}>Add staff</Button>
        </>
      }
    >
      {staff.isError ? <ErrorNote error={staff.error} /> : null}
      {roles.isError ? <ErrorNote error={roles.error} /> : null}
      <DataTable columns={columns} data={staff.data ?? []} empty={staff.isPending ? 'Loading…' : 'No staff yet.'} />

      {open?.kind === 'add' && roles.data ? <StaffDialog roles={roles.data} onClose={close} /> : null}
      {open?.kind === 'edit' && selected && roles.data ? <StaffDialog key={selected.id} staff={selected} roles={roles.data} onClose={close} /> : null}
      {open?.kind === 'toggle' && selected ? (
        <ConfirmDialog
          open
          title={selected.active ? 'Deactivate staff member' : 'Reactivate staff member'}
          description={selected.active
            ? `${selected.email} will be signed out at their next click and cannot sign in again.`
            : `${selected.email} will be able to sign in again.`}
          confirmLabel={selected.active ? 'Deactivate' : 'Reactivate'}
          destructive={selected.active}
          pending={update.isPending}
          error={update.error}
          onConfirm={() => update.mutate({ id: selected.id, body: { active: !selected.active, version: selected.version } }, { onSuccess: close })}
          onCancel={close}
        />
      ) : null}
    </PageShell>
  )
}
```

`helper.display` is TanStack Table's column type without an accessor; confirm the name in the installed version. The column list is built inside the component because the action cell reads `me` and the roles.

- [ ] **Step 6: Run everything**

```bash
npm run typecheck && npm test && npm run build
```

Expected: all pass, including Task 4's `shows the login screen when a later call gets 401` (it uses this page's "Reload" button). If a dialog test fails inside Radix with `hasPointerCapture` or `scrollIntoView is not a function`, add those two no-op stubs to `src/test/setup.ts` (jsdom lacks them) and say so in the report.

- [ ] **Step 7: Hand-off**

Report the files, test counts, the final type of `Columns<T>`, and any jsdom stub added. Do not commit.

---

### Task 6: Roles and Audit screens

**Files (under `admin-ui/src/`):**
- Modify: `features/roles/api.ts` (add the writes and the permission catalogue)
- Create: `features/roles/RoleDialog.tsx`; modify `features/roles/RolesPage.tsx` (replace the placeholder)
- Create: `features/audit/api.ts`, `features/audit/Changes.tsx`; modify `features/audit/AuditPage.tsx` (replace the placeholder)
- Test: `features/roles/RolesPage.test.tsx`, `features/audit/AuditPage.test.tsx`

**Interfaces:**
- Consumes: Task 5's `DataTable`, `columnsFor`, `ConfirmDialog`, `FormField`, `NativeSelect`, `applyServerErrors`, `conflictMessage`, `useRoles`, `rolesKey`, `useStaff`; Task 4's `useSession`, `PageShell`, `ErrorNote`, `formatInstant`, `zoneName`, `localInputToInstant`.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the failing tests**

`src/features/roles/RolesPage.test.tsx`:

```tsx
import { screen, within } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import type { components } from '@/api/schema'
import { DESK_ROLE_ID, OWNER_ROLE_ID } from '@/test/data'
import { problem } from '@/test/problems'
import { renderApp } from '@/test/render'
import { server } from '@/test/server'

type Role = components['schemas']['RoleResponse']

const owner: Role = { id: OWNER_ROLE_ID, name: 'Owner', permissions: ['staff.manage', 'roles.manage', 'audit.read', 'jobs.manage'], isSystem: true, staffCount: 1, version: 1 }
const desk: Role = { id: DESK_ROLE_ID, name: 'Front desk', permissions: ['staff.manage'], isSystem: false, staffCount: 2, version: 3 }
const catalogue = [
  { name: 'staff.manage', description: 'Add and change staff' },
  { name: 'roles.manage', description: 'Create and change roles' },
  { name: 'audit.read', description: 'Read the audit log' },
  { name: 'jobs.manage', description: 'Open the jobs dashboard' },
]

function serve(roles: Role[]) {
  const state = { roles }
  server.use(
    http.get('*/admin/api/roles', () => HttpResponse.json(state.roles)),
    http.get('*/admin/api/permissions', () => HttpResponse.json(catalogue)),
  )
  return state
}

const rowOf = (name: string) => within(screen.getAllByText(name)[0]!.closest('tr')!)

describe('Roles', () => {
  it('lists roles; the system role has no actions', async () => {
    serve([owner, desk])
    renderApp('/admin/roles')
    expect(await screen.findByText('Front desk')).toBeInTheDocument()
    expect(rowOf('Front desk').getByText('2')).toBeInTheDocument()
    expect(rowOf('Front desk').getByText('staff.manage')).toBeInTheDocument()
    expect(rowOf('Owner').getByText('Every permission')).toBeInTheDocument()
    expect(rowOf('Owner').queryByRole('button')).not.toBeInTheDocument()
  })

  it('creates a role with the ticked permissions', async () => {
    const state = serve([owner])
    let body: unknown
    server.use(http.post('*/admin/api/roles', async ({ request }) => {
      body = await request.json()
      state.roles = [owner, desk]
      return HttpResponse.json(desk, { status: 201 })
    }))
    const { user } = renderApp('/admin/roles')
    await user.click(await screen.findByRole('button', { name: 'Add role' }))
    const dialog = within(await screen.findByRole('dialog'))
    await user.type(dialog.getByLabelText('Name'), 'Front desk')
    await user.click(await dialog.findByLabelText(/staff.manage/))
    await user.click(dialog.getByLabelText(/audit.read/))
    await user.click(dialog.getByRole('button', { name: 'Add' }))
    expect(await screen.findByText('Front desk')).toBeInTheDocument()
    expect(body).toEqual({ name: 'Front desk', permissions: ['staff.manage', 'audit.read'] })
  })

  it('edits name and permissions with the row version, and survives a stale save', async () => {
    const state = serve([owner, desk])
    const bodies: { version: number }[] = []
    server.use(http.patch(`*/admin/api/roles/${desk.id}`, async ({ request }) => {
      const sent = (await request.json()) as { version: number }
      bodies.push(sent)
      if (sent.version === 3) {
        state.roles = [owner, { ...desk, version: 4 }]
        return problem(409, 'CONFLICT', 'The record was changed by someone else.')
      }
      return HttpResponse.json({ ...desk, version: 5 })
    }))
    const { user } = renderApp('/admin/roles')
    await screen.findByText('Front desk')
    await user.click(rowOf('Front desk').getByRole('button', { name: 'Edit' }))
    const dialog = within(await screen.findByRole('dialog'))
    expect(await dialog.findByLabelText(/staff.manage/)).toBeChecked()
    await user.click(dialog.getByLabelText(/staff.manage/))
    await user.click(dialog.getByLabelText(/roles.manage/))
    await user.click(dialog.getByRole('button', { name: 'Save' }))
    expect(await dialog.findByText(/Someone else changed this record/)).toBeInTheDocument()
    await user.click(dialog.getByRole('button', { name: 'Save' }))
    await screen.findByText('Front desk')
    expect(bodies).toEqual([
      { name: 'Front desk', permissions: ['roles.manage'], version: 3 },
      { name: 'Front desk', permissions: ['roles.manage'], version: 4 },
    ])
  })

  it('deletes with the version in the query, and shows why a role in use cannot go', async () => {
    serve([owner, desk])
    let query = ''
    server.use(http.delete(`*/admin/api/roles/${desk.id}`, ({ request }) => {
      query = new URL(request.url).search
      return problem(409, 'ROLE_IN_USE', 'Staff still hold this role. Move them to another role first.')
    }))
    const { user } = renderApp('/admin/roles')
    await screen.findByText('Front desk')
    await user.click(rowOf('Front desk').getByRole('button', { name: 'Delete' }))
    const dialog = within(await screen.findByRole('dialog'))
    await user.click(dialog.getByRole('button', { name: 'Delete' }))
    expect(await dialog.findByText('Staff still hold this role. Move them to another role first.')).toBeInTheDocument()
    expect(query).toBe('?version=3')
  })
})
```

`src/features/audit/AuditPage.test.tsx`:

```tsx
import { screen } from '@testing-library/react'
import { http, HttpResponse } from 'msw'
import { DESK_ROLE_ID, ownerMe, staffMe } from '@/test/data'
import { localInputToInstant } from '@/lib/time'
import { renderApp } from '@/test/render'
import { server } from '@/test/server'

const item = {
  id: '0199dd00-0000-7000-8000-000000000901', occurredAt: '2026-10-13T02:30:00Z', staffId: ownerMe.id, staffEmail: ownerMe.email,
  action: 'PATCH /admin/api/staff/{id:guid}', entityType: 'staff_user', entityId: staffMe.id,
  changes: { active: { from: true, to: false }, roleId: { from: null, to: DESK_ROLE_ID } }, ip: '203.0.113.9',
}

function serve(total: number) {
  const queries: URLSearchParams[] = []
  server.use(
    http.get('*/admin/api/staff', () => HttpResponse.json([
      { id: ownerMe.id, email: ownerMe.email, displayName: null, roleId: ownerMe.roleId, roleName: 'Owner', active: true, lastSignInAt: null, version: 1 },
    ])),
    http.get('*/admin/api/audit', ({ request }) => {
      const query = new URL(request.url).searchParams
      queries.push(query)
      return HttpResponse.json({ items: [item], total, page: Number(query.get('page') ?? 1), pageSize: 50 })
    }),
  )
  return queries
}

describe('Audit log', () => {
  it('shows who changed what, with each field before and after', async () => {
    serve(1)
    renderApp('/admin/audit')
    expect(await screen.findByText('PATCH /admin/api/staff/{id:guid}')).toBeInTheDocument()
    expect(screen.getByText('owner@example.test')).toBeInTheDocument()
    expect(screen.getByText('staff_user')).toBeInTheDocument()
    expect(screen.getByText('active')).toBeInTheDocument()
    expect(screen.getByText('true → false')).toBeInTheDocument()
    expect(screen.getByText(`— → ${DESK_ROLE_ID}`)).toBeInTheDocument()
    expect(screen.getByText('1 entry')).toBeInTheDocument()
  })

  it('sends the filters; times go out as instants with Z', async () => {
    const queries = serve(1)
    const { user } = renderApp('/admin/audit')
    await screen.findByText('PATCH /admin/api/staff/{id:guid}')
    await user.selectOptions(screen.getByLabelText('Staff'), ownerMe.id)
    await user.selectOptions(screen.getByLabelText('Record type'), 'staff_user')
    await user.type(screen.getByLabelText('From'), '2026-10-13T08:00')
    await user.type(screen.getByLabelText('To'), '2026-10-14T08:00')
    await user.click(screen.getByRole('button', { name: 'Apply' }))
    await screen.findByText('PATCH /admin/api/staff/{id:guid}')

    const last = queries.at(-1)!
    expect(last.get('staffId')).toBe(ownerMe.id)
    expect(last.get('entityType')).toBe('staff_user')
    expect(last.get('from')).toBe(localInputToInstant('2026-10-13T08:00'))
    expect(last.get('from')).toMatch(/Z$/)
    expect(last.get('to')).toMatch(/Z$/)
    expect(last.get('page')).toBe('1')
  })

  it('pages through the results and goes back to page 1 when the filter changes', async () => {
    const queries = serve(120)
    const { user } = renderApp('/admin/audit')
    expect(await screen.findByText('Page 1 of 3')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Previous' })).toBeDisabled()
    await user.click(screen.getByRole('button', { name: 'Next' }))
    expect(await screen.findByText('Page 2 of 3')).toBeInTheDocument()
    expect(queries.at(-1)!.get('page')).toBe('2')

    await user.selectOptions(screen.getByLabelText('Record type'), 'role')
    await user.click(screen.getByRole('button', { name: 'Apply' }))
    expect(await screen.findByText('Page 1 of 3')).toBeInTheDocument()
    expect(queries.at(-1)!.get('page')).toBe('1')
    expect(queries.at(-1)!.get('entityType')).toBe('role')
  })

  it('has no staff filter without staff.manage (that list would be refused)', async () => {
    serve(1)
    renderApp('/admin/audit', { me: { ...staffMe, permissions: ['audit.read'] } })
    await screen.findByText('PATCH /admin/api/staff/{id:guid}')
    expect(screen.queryByLabelText('Staff')).not.toBeInTheDocument()
  })
})
```

Run: `npm test -- RolesPage AuditPage`
Expected: FAIL.

- [ ] **Step 2: Roles data**

Append to `src/features/roles/api.ts` (add `useMutation`, `useQueryClient` and `ApiError` to the imports):

```ts
type CreateRole = components['schemas']['CreateRoleBody']
type UpdateRole = components['schemas']['UpdateRoleBody']

export function usePermissions() {
  return useQuery({ queryKey: ['permissions'], queryFn: () => call(() => api.GET('/admin/api/permissions')), staleTime: Infinity })
}

function useReload() {
  const queryClient = useQueryClient()
  // Staff rows show role names, so they go stale with the roles.
  return () => Promise.all([queryClient.invalidateQueries({ queryKey: rolesKey }), queryClient.invalidateQueries({ queryKey: ['staff'] })])
}

const reloadOn409 = (reload: () => Promise<unknown>) => (error: unknown) =>
  error instanceof ApiError && error.status === 409 ? reload() : undefined

export function useCreateRole() {
  const reload = useReload()
  return useMutation({ mutationFn: (body: CreateRole) => call(() => api.POST('/admin/api/roles', { body })), onSuccess: reload })
}

export function useUpdateRole() {
  const reload = useReload()
  return useMutation({
    mutationFn: ({ id, body }: { id: string; body: UpdateRole }) =>
      call(() => api.PATCH('/admin/api/roles/{id}', { params: { path: { id } }, body })),
    onSuccess: reload,
    onError: reloadOn409(reload),
  })
}

export function useDeleteRole() {
  const reload = useReload()
  return useMutation({
    mutationFn: ({ id, version }: { id: string; version: number }) =>
      call(() => api.DELETE('/admin/api/roles/{id}', { params: { path: { id }, query: { version } } })),
    onSuccess: reload,
    onError: reloadOn409(reload),
  })
}
```

- [ ] **Step 3: Role dialog and page**

`src/features/roles/RoleDialog.tsx`:

```tsx
import { useState } from 'react'
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm } from 'react-hook-form'
import { z } from 'zod'
import { ApiError } from '@/api/errors'
import { ErrorNote } from '@/components/ErrorNote'
import { FormField } from '@/components/FormField'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { applyServerErrors, conflictMessage } from '@/lib/forms'
import { useCreateRole, usePermissions, useUpdateRole, type Role } from './api'

const schema = z.object({
  name: z.string().trim().min(1, 'Enter a name.').max(100, 'At most 100 characters.'),
  permissions: z.array(z.string()),
})
type Values = z.infer<typeof schema>

/** `role` set = edit it (always the current row of the list, so `version` is fresh); unset = add. */
export function RoleDialog({ role, onClose }: { role?: Role; onClose: () => void }) {
  const catalogue = usePermissions()
  const create = useCreateRole()
  const update = useUpdateRole()
  const [failure, setFailure] = useState<unknown>(null)
  const form = useForm<Values>({
    resolver: zodResolver(schema),
    defaultValues: { name: role?.name ?? '', permissions: role?.permissions ?? [] },
  })

  async function onSubmit(values: Values) {
    setFailure(null)
    // In the catalogue's order, so the same choice always sends the same list.
    const permissions = (catalogue.data ?? []).map((p) => p.name).filter((name) => values.permissions.includes(name))
    try {
      if (role) await update.mutateAsync({ id: role.id, body: { name: values.name, permissions, version: role.version } })
      else await create.mutateAsync({ name: values.name, permissions })
      onClose()
    } catch (error) {
      if (!applyServerErrors(error, form.setError, ['name'])) setFailure(error)
    }
  }

  const stale = failure instanceof ApiError && failure.code === 'CONFLICT'

  return (
    <Dialog open onOpenChange={(next) => { if (!next) onClose() }}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{role ? `Edit ${role.name}` : 'Add role'}</DialogTitle>
        </DialogHeader>
        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4" noValidate>
          <FormField label="Name" htmlFor="role-name" error={form.formState.errors.name?.message}>
            <Input id="role-name" autoComplete="off" {...form.register('name')} />
          </FormField>
          <fieldset className="space-y-2">
            <legend className="text-sm font-medium">Permissions</legend>
            {catalogue.isError ? <ErrorNote error={catalogue.error} /> : null}
            {(catalogue.data ?? []).map((permission) => (
              <label key={permission.name} className="flex items-start gap-2 text-sm">
                <input type="checkbox" className="mt-1" value={permission.name} {...form.register('permissions')} />
                <span>
                  <span className="font-mono text-xs">{permission.name}</span>
                  <span className="block text-muted-foreground">{permission.description}</span>
                </span>
              </label>
            ))}
          </fieldset>
          {stale ? <p role="alert" className="text-sm text-destructive">{conflictMessage}</p> : failure ? <ErrorNote error={failure} /> : null}
          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
            <Button type="submit" disabled={!catalogue.data || create.isPending || update.isPending}>{role ? 'Save' : 'Add'}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
```

A checkbox group registered under one name gives React Hook Form an array of the ticked values. The boxes render only after the catalogue loads; if the ticked state of an edited role does not show (the default value was set before the boxes existed), render the form only once `catalogue.data` is there.

`src/features/roles/RolesPage.tsx`:

```tsx
import { useState } from 'react'
import { ConfirmDialog } from '@/components/ConfirmDialog'
import { columnsFor, DataTable } from '@/components/DataTable'
import { ErrorNote } from '@/components/ErrorNote'
import { PageShell } from '@/components/PageShell'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useDeleteRole, useRoles, type Role } from './api'
import { RoleDialog } from './RoleDialog'

type Open = { kind: 'add' } | { kind: 'edit' | 'delete'; id: string } | null

export function RolesPage() {
  const roles = useRoles()
  const remove = useDeleteRole()
  const [open, setOpen] = useState<Open>(null)
  const selected = open && open.kind !== 'add' ? roles.data?.find((role) => role.id === open.id) : undefined

  function close() {
    remove.reset()
    setOpen(null)
  }

  const helper = columnsFor<Role>()
  const columns = helper.columns([
    helper.accessor('name', { header: 'Role' }),
    helper.accessor('permissions', {
      header: 'Permissions',
      cell: ({ row }) =>
        row.original.isSystem ? 'Every permission' : (
          <div className="flex flex-wrap gap-1">
            {row.original.permissions.length === 0 ? '—' : row.original.permissions.map((name) => <Badge key={name} variant="secondary">{name}</Badge>)}
          </div>
        ),
    }),
    helper.accessor('staffCount', { header: 'Staff' }),
    helper.display({
      id: 'actions',
      header: '',
      // System roles cannot be changed or deleted (the server answers 409 SYSTEM_ROLE).
      cell: ({ row }) => row.original.isSystem ? null : (
        <div className="flex justify-end gap-2">
          <Button size="sm" variant="outline" onClick={() => setOpen({ kind: 'edit', id: row.original.id })}>Edit</Button>
          <Button size="sm" variant="outline" onClick={() => setOpen({ kind: 'delete', id: row.original.id })}>Delete</Button>
        </div>
      ),
    }),
  ])

  return (
    <PageShell title="Roles" actions={<Button onClick={() => setOpen({ kind: 'add' })}>Add role</Button>}>
      {roles.isError ? <ErrorNote error={roles.error} /> : null}
      <DataTable columns={columns} data={roles.data ?? []} empty={roles.isPending ? 'Loading…' : 'No roles yet.'} />

      {open?.kind === 'add' ? <RoleDialog onClose={close} /> : null}
      {open?.kind === 'edit' && selected ? <RoleDialog key={selected.id} role={selected} onClose={close} /> : null}
      {open?.kind === 'delete' && selected ? (
        <ConfirmDialog
          open
          title="Delete role"
          description={`Delete the role "${selected.name}"? This cannot be undone.`}
          confirmLabel="Delete"
          destructive
          pending={remove.isPending}
          error={remove.error}
          onConfirm={() => remove.mutate({ id: selected.id, version: selected.version }, { onSuccess: close })}
          onCancel={close}
        />
      ) : null}
    </PageShell>
  )
}
```

- [ ] **Step 4: Audit**

`src/features/audit/api.ts`:

```ts
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { api, call } from '@/api/client'
import type { components } from '@/api/schema'

export type AuditItem = components['schemas']['AuditItem']

export type AuditFilter = { staffId?: string; entityType?: string; from?: string; to?: string }

export const PAGE_SIZE = 50

export function useAudit(filter: AuditFilter, page: number) {
  return useQuery({
    queryKey: ['audit', filter, page],
    // openapi-fetch URL-encodes the query, so an offset's "+" would survive too; we send Z anyway.
    queryFn: () => call(() => api.GET('/admin/api/audit', { params: { query: { ...filter, page, pageSize: PAGE_SIZE } } })),
    placeholderData: keepPreviousData,
  })
}
```

`src/features/audit/Changes.tsx`:

```tsx
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function show(value: unknown): string {
  if (value === null || value === undefined) return '—'
  return typeof value === 'string' ? value : JSON.stringify(value)
}

/** `changes` is `{ field: { from, to } }`, written by the server's audit interceptor. Anything else is shown as raw JSON. */
export function Changes({ changes }: { changes: unknown }) {
  if (!isRecord(changes)) return <code className="text-xs">{JSON.stringify(changes)}</code>
  return (
    <dl className="space-y-0.5 text-xs">
      {Object.entries(changes).map(([field, change]) => (
        <div key={field} className="flex gap-2">
          <dt className="font-mono text-muted-foreground">{field}</dt>
          <dd>{isRecord(change) ? `${show(change.from)} → ${show(change.to)}` : show(change)}</dd>
        </div>
      ))}
    </dl>
  )
}
```

`src/features/audit/AuditPage.tsx`:

```tsx
import { useState, type FormEvent } from 'react'
import { columnsFor, DataTable } from '@/components/DataTable'
import { ErrorNote } from '@/components/ErrorNote'
import { FormField } from '@/components/FormField'
import { NativeSelect } from '@/components/NativeSelect'
import { PageShell } from '@/components/PageShell'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useSession } from '@/features/auth/session'
import { useStaff } from '@/features/staff/api'
import { formatInstant, localInputToInstant, zoneName } from '@/lib/time'
import { PAGE_SIZE, useAudit, type AuditFilter, type AuditItem } from './api'
import { Changes } from './Changes'

// The audit log names a record by its table. Add a line here when a later feature audits a new table.
const recordTypes = [
  { value: 'staff_user', label: 'Staff member' },
  { value: 'role', label: 'Role' },
]

const helper = columnsFor<AuditItem>()
const columns = helper.columns([
  helper.accessor('occurredAt', { header: `When (${zoneName()})`, cell: (c) => formatInstant(c.getValue()) }),
  helper.accessor('staffEmail', { header: 'Who' }),
  helper.accessor('action', { header: 'Action', cell: (c) => <span className="font-mono text-xs">{c.getValue()}</span> }),
  helper.accessor('entityType', { header: 'Record', cell: ({ row }) => (
    <div className="text-xs">
      <div>{row.original.entityType}</div>
      <div className="font-mono text-muted-foreground">{row.original.entityId}</div>
    </div>
  ) }),
  helper.accessor('changes', { header: 'Changes', cell: (c) => <Changes changes={c.getValue()} /> }),
])

function StaffFilter() {
  const staff = useStaff()
  return (
    <FormField label="Staff" htmlFor="audit-staff">
      <NativeSelect id="audit-staff" name="staffId" defaultValue="">
        <option value="">Anyone</option>
        {(staff.data ?? []).map((member) => <option key={member.id} value={member.id}>{member.email}</option>)}
      </NativeSelect>
    </FormField>
  )
}

export function AuditPage() {
  const { can } = useSession()
  const [filter, setFilter] = useState<AuditFilter>({})
  const [page, setPage] = useState(1)
  const audit = useAudit(filter, page)
  const total = audit.data?.total ?? 0
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    const text = (name: string) => { const value = form.get(name); return typeof value === 'string' && value ? value : undefined }
    setFilter({ staffId: text('staffId'), entityType: text('entityType'), from: localInputToInstant(text('from') ?? ''), to: localInputToInstant(text('to') ?? '') })
    setPage(1)
  }

  return (
    <PageShell title="Audit log">
      <form onSubmit={onSubmit} className="flex flex-wrap items-end gap-3 rounded-xl border bg-card p-4">
        {can('staff.manage') ? <StaffFilter /> : null}
        <FormField label="Record type" htmlFor="audit-type">
          <NativeSelect id="audit-type" name="entityType" defaultValue="">
            <option value="">Any</option>
            {recordTypes.map((type) => <option key={type.value} value={type.value}>{type.label}</option>)}
          </NativeSelect>
        </FormField>
        <FormField label="From" htmlFor="audit-from"><Input id="audit-from" name="from" type="datetime-local" /></FormField>
        <FormField label="To" htmlFor="audit-to"><Input id="audit-to" name="to" type="datetime-local" /></FormField>
        <Button type="submit">Apply</Button>
      </form>

      {audit.isError ? <ErrorNote error={audit.error} /> : null}
      <DataTable columns={columns} data={audit.data?.items ?? []} empty={audit.isPending ? 'Loading…' : 'No entries match.'} />

      <div className="flex items-center justify-between text-sm text-muted-foreground">
        <span>{total === 1 ? '1 entry' : `${total} entries`}</span>
        <div className="flex items-center gap-2">
          <Button size="sm" variant="outline" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Button>
          <span>Page {page} of {pages}</span>
          <Button size="sm" variant="outline" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</Button>
        </div>
      </div>
    </PageShell>
  )
}
```

The filter form is uncontrolled (read with `FormData` on Apply): the list changes only when the user asks. Times are typed in the browser's zone and sent as instants; the column header names the zone. In the generated types `AuditItem.changes` has no fixed shape (the server sends free JSON), which is why `Changes` takes `unknown` and checks at run time.

- [ ] **Step 5: Run everything**

```bash
npm run typecheck && npm test && npm run build && npm run check:api
```

Expected: all pass, no diff from `check:api`. jsdom's `datetime-local` input accepts typed text in the `YYYY-MM-DDTHH:mm` form; if `user.type` does not set it, use `fireEvent.change` for those two fields only.

- [ ] **Step 6: Hand-off**

Report the files, test counts, and anything that differed from the plan. Do not commit.

---

### Task 7: Fit, documents and the local walk (main session only)

No product code. The main session does this after Tasks 1–6 are reviewed.

- [ ] **Step 1: Read the real diff.** `git -C ../CMS status --short`, `git -C ../CMS diff --stat`; full hunks for `Program.cs`, `PlatformServices.cs`, `AdminSpa.cs`, `SecurityHeadersMiddleware.cs`, `src/api/client.ts`, `features/auth/session.tsx`. Check: `wwwroot/` and `node_modules/` are not listed; `package.json` has exact versions; `src/api/schema.d.ts` was generated, not typed by hand; no `any`, `@ts-ignore` or `fetch(` outside `src/api/client.ts` (`grep -rn "fetch(\|: any\|as any\|@ts-ignore" admin-ui/src`).

- [ ] **Step 2: Whole build, once more.**

```bash
dotnet build ../CMS/ExtraSpace.slnx          # 0 errors, 0 warnings
dotnet test ../CMS/tests/ExtraSpace.Api.Tests
dotnet test ../CMS/tests/ExtraSpace.Engines.Tests
dotnet test ../CMS/tests/ExtraSpace.Infra.Tests
cd ../CMS/admin-ui && npm ci && npm run typecheck && npm test && npm run build && npm run check:api
```

- [ ] **Step 3: Whole-branch review.** One `code-reviewer` run over the branch with this plan, the spec sections named in the header and the Review Focus list. Send defects back to an implementer; re-review only what changed.

- [ ] **Step 4: Local walk** (local Docker database; `docker compose up -d` and the migrations as in `.claude/rules/cms.md`; `Admin:BootstrapEmails:0` set to a test address through user-secrets if no Owner exists). One `dev-walker`, GET cases first:
  1. Built UI served by the API on 5080: `GET /admin`, `/admin/staff` → 200 HTML with the CSP header and `Cache-Control: no-cache`; a file under `/admin/assets/` → 200 with `immutable`; `/admin/assets/nope.js` → 404 problem; `/admin/api/nope` → 404 problem; `/admin/jobs` without a cookie → 401 problem and no CSP.
  2. Sign-in through the API as the page does it: `POST /auth/code`, read the code from the console (`Development email`), `POST /auth/code/verify`, `GET /me` (has `isOwner`), `GET /auth/csrf`, one staff add, one PATCH with a stale `version` → 409.
  3. `"version": "5"` (a string) on a PATCH → 400 `VALIDATION_FAILED`.
  Then, in a browser (the owner, or the main session if a browser tool is available): open `http://localhost:5080/admin`, sign in, add and deactivate a staff member, create and delete a role, filter the audit log, open Jobs, switch the theme, sign out. Watch the browser console for CSP violations: there must be none. Also run `npm run dev` once and repeat the sign-in on `http://localhost:5173/admin/` (the proxy path). Kill the API and Vite afterwards; remove the test staff and role rows.

- [ ] **Step 5: Documents** (context repo):
  - `docs/notes/cms/built-so-far.md`: a section "Built so far (S0-5)": the serving rules, the CSP, strict numbers, the `Problem` schema, the snapshot test and its update command, the `admin-ui/` layout, `call()`, the session rules, the versions and the TypeScript 6 pin.
  - `.claude/rules/cms.md`: "Running locally" gets the admin UI commands (`npm ci`, `npm run dev`, `npm run build`, the contract update); the stack line gets the pinned majors.
  - `.claude/dev-ports`: add `5173`.
  - `docs/superpowers/plans/2026-10-12-s0-plan-index.md`: S0-5 status; strike the S0-5 carry-overs that are done; new "Carry-overs from S0-5" (S0-6: Docker stage with Node 24 that runs `npm ci && npm run build` before `dotnet publish`; CI runs `check:api`, `typecheck`, `test`; the ALB or WAF must not cache `/admin` HTML; Flutter note on strict numbers; S1: Playwright smoke, and every new audited table adds a line to the audit screen's record types).
  - Spec §4.5, §6.3 and §8: "As built in S0-5" notes for decisions 1–4, 10 and 16.
  - `.claude/rules/cross-repo.md` §4: one decision-log row.
  - Memory `project_setup_owed.md`: S0-5 state and the next step (S0-6).

- [ ] **Step 6: Report** per task: ACCEPT / FIX NEEDED / BLOCKED, with what was verified and what was not, the test counts, and the commit message for the owner. Do not commit.

## Self-review notes (written with the plan)

- **Spec §8 coverage:** base and look (Task 3), server data and forms (Tasks 4–6), lists with TanStack Table (Task 5 `DataTable`), generated API types with a staleness check (Tasks 2–3), no generic CRUD and no business maths (constraints, hiding-only comments), every S0 screen (Tasks 4–6), menus hidden by permission (Task 4), build output and dev proxy (Task 3). Recharts is "from S1" and is not installed.
- **Carry-overs covered:** CSP and static files (Task 1); OpenAPI error schema and the `/api/v1/auth/*` error responses (Task 2, decision 2); SPA fallback before 404 and not over `/admin/api` or `/admin/jobs` (Task 1); `NumberHandling` (decision 1); 401 → login screen, CSRF fetch and retry (Task 3–4); `version` on PATCH and DELETE, reload on 409 (Tasks 5–6); Owner-only actions hidden (Task 5); audit `from` / `to` with an offset (Task 6); `Retry-After` shown (Task 4); `displayName` on the staff forms (Task 5); the Jobs link only with `jobs.manage` (Task 4).
- **Not verified while planning** (each has a test that will show it): the `Columns<T>` type of `DataTable`; `helper.display`; Radix Dialog under jsdom; typing into `datetime-local` under jsdom; the exact Microsoft.OpenApi member types in `ProblemOpenApi.cs`; whether an existing C# test posts a number as a string.

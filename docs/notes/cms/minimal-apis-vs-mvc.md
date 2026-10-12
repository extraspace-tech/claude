# Minimal APIs vs MVC in our monolith

Written 2026-10-12 for the switch in S0-2b (branch `s0-2b-minimal-apis`). It explains every piece the switch added or removed, why, and what the MVC version was. Extend it when a new concept lands (route groups with auth in S0-3, endpoint filters and permission policies in S0-4).

## 1. What changed and what did not

The request pipeline in `Program.cs` is the same: forwarded headers → trace → request summary → exception handler → … → authentication → authorization → **step 14** → health → OpenAPI. Only step 14 changed. MVC called `app.MapControllers()`, which found every `ControllerBase` class by reflection. Now each feature maps its own routes with `MapGet` / `MapPost` / ….

Both styles sit on the same ASP.NET Core **routing** and **endpoint** system. An MVC action is also an "endpoint" under the hood. Minimal APIs remove the controller layer on top: no controller classes, no `ModelState`, no action filters, no MVC options. What we lose is MVC's ready-made conventions. What we gain is that each route is one visible line, and one JSON option set.

The wire contract did not change: same URLs, same `ProblemDetails` + `code` + `traceId`, same 400 `VALIDATION_FAILED` with camelCase `errors` keys, same enum strings. All 130 tests stayed green, and the review added 4 more (134).

## 2. Piece by piece

| What we have now | Why it is there | What MVC used instead |
|---|---|---|
| `services.AddValidation()` (`PlatformServices.cs`) | .NET 10's built-in validation for Minimal APIs. A source generator reads the DataAnnotations (`[Required]`, `[EmailAddress]`, `[Range]`) on handler parameters and returns a 400 when they fail. | `[ApiController]` did this automatically through `ModelState`. |
| `ProblemDetailsSetup.Customize`: the `HttpValidationProblemDetails` branch | The validation 400 is written through `IProblemDetailsService`, so our one `Customize` hook sees it. We set `code = VALIDATION_FAILED` and our title there. | A separate `InvalidModelStateResponseFactory` (`ProblemDetailsSetup.ValidationResponse`, now deleted) built the 400 by hand. |
| `CamelCaseKeys` in the same file | .NET 10 validation names errors by the **C# property** (`Email`, `Address.PostCode`). The Flutter app and admin UI read the **JSON name** (`email`, `address.postCode`), so we convert each segment to camelCase. The framework has no setting for this. | `SystemTextJsonValidationMetadataProvider` made MVC use the JSON names. |
| `RouteHandlerOptions.ThrowOnBadRequest = true` | A body that is not valid JSON, or a missing required parameter, throws `BadHttpRequestException`. The default is `true` only in Development; outside it the framework writes a bare 400 itself. With `true` everywhere, every environment takes the same path: `AppExceptionHandler` → 400 `VALIDATION_FAILED`, with no Error log line. | MVC put JSON errors into `ModelState`, and the same factory returned the 400. |
| `ConfigureHttpJsonOptions(...)`: the **only** JSON settings | Minimal API responses and the OpenAPI document read these same options. | MVC had its own set (`AddControllers().AddJsonOptions`), and OpenAPI read the other one. That is why S0-2 shipped enums as integers in the docs until we added the converter twice. That class of bug is gone. |
| `IEndpointMapper` (`Platform/Hosting/IEndpointMapper.cs`) and the `foreach` in `Program.cs` step 14 | Lets a host add endpoints after the features. Only the test host uses it (`/test/*`); production registers none. Features do **not** use it: they are mapped by name in `Program.cs`, so you can read every route group in one place. | `AddControllers().AddApplicationPart(testAssembly)` made MVC scan the test assembly for controllers. |
| `TestEndpoints.cs` (was `TestController.cs`) | The same 15 test routes, written as Minimal API handlers. | An `[ApiController]` class with `[HttpGet("...")]` methods. |
| `services.AddValidation()` again, in `ApiFactory` | The validation source generator only sees types in the project that calls `AddValidation()`. `TestBody` lives in the test project, so the test host calls it too. Without it, the validation test got 200 instead of 400. | Not needed: MVC validated by reflection at run time. |
| `JsonProblemWriter` (`Platform/Errors/JsonProblemWriter.cs`) | The framework's own problem writer refuses a request whose `Accept` header is not JSON (`text/html`, `text/plain`). It then writes a bare fallback body, and our `Customize` never runs: no `code`, no `traceId`, PascalCase keys. Our writer accepts every request and always writes the JSON problem. It is registered before `AddProblemDetails`, because the first writer that accepts wins. | MVC forced `application/problem+json` on its `BadRequestObjectResult`, so it did not have this gap. |
| `JsonStringEnumConverter(allowIntegerValues: false)` | A JSON body with `"status": 5` is rejected; only the names (`"Archived"`) are valid. | Same converter, but with integers allowed (a gap in S0-2 too). |
| `.WithEnumGuard()` (`Platform/Http/EnumArgumentsFilter.cs`) | Minimal API route and query binding uses `Enum.TryParse`, which accepts any number: `?filter=5` would reach the handler. This **endpoint filter** checks every enum parameter and returns a 400 validation problem for an undefined value. It is an *endpoint filter factory*: it looks at the handler once at startup and attaches only to handlers that have an enum parameter. Put it on each route group. | MVC's enum model binder rejected undefined values itself. |
| Architecture rule `EndpointDataAccess` | "Endpoint classes call a service; they never touch the `DbContext`." An endpoint class is one whose name ends with `Endpoints`, or one that maps routes (it calls `EndpointRouteBuilderExtensions`). Proven by fixtures that must fail, including an async lambda and a class not named `*Endpoints`. | `ControllerDataAccess`: any `ControllerBase` subclass. |

## 3. The same endpoint both ways

A sketch of S0-3's `GET /api/v1/me` (illustration only, not final code).

MVC:

```csharp
[ApiController]
[Route("api/v1/me")]
[Authorize]
public sealed class MeController(ICustomerService customers) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<MeResponse>> Get(CancellationToken ct) =>
        await customers.GetMeAsync(User.CustomerId(), ct);
}
```

Minimal APIs (`Features/Customers/CustomerEndpoints.cs`):

```csharp
public static class CustomerEndpoints
{
    public static RouteGroupBuilder MapCustomerEndpoints(this RouteGroupBuilder api)
    {
        api.MapGet("/me", GetMe);
        return api;
    }

    private static async Task<Ok<MeResponse>> GetMe(ClaimsPrincipal user, ICustomerService customers, CancellationToken ct) =>
        TypedResults.Ok(await customers.GetMeAsync(user.CustomerId(), ct));
}
```

`Program.cs` (step 14):

```csharp
var api = app.MapGroup("/api/v1").RequireAuthorization().WithEnumGuard();   // once, for every customer route
api.MapCustomerEndpoints();
```

What moved where:

- **Route:** `[Route]` + `[HttpGet]` → the group prefix plus `MapGet("/me", ...)`.
- **Auth:** `[Authorize]` on each controller → `.RequireAuthorization()` once on the group. A public route inside opts out with `.AllowAnonymous()`, the same as MVC.
- **Dependencies:** constructor injection → handler parameters. The framework decides where each parameter comes from:
  - registered services come from DI;
  - `ClaimsPrincipal`, `HttpContext` and `CancellationToken` are special types the framework fills in;
  - a name that matches the route template (`{id}`) comes from the route;
  - other simple types come from the query string;
  - a class on a POST/PUT comes from the JSON body.
  Use `[FromQuery]`, `[FromRoute]`, `[FromBody]` or `[FromServices]` when you want to be explicit.
- **Return type:** `ActionResult<T>` → `TypedResults.Ok(...)` with a typed return (`Ok<MeResponse>`, or `Results<Ok<MeResponse>, NotFound>` when there are two outcomes). OpenAPI reads the return type, so the document lists exactly these responses.
- **Errors:** unchanged. Throw `AppException(status, code, title)`; never return a hand-made error body.

## 4. Dictionary

| Minimal API | MVC equivalent | Notes |
|---|---|---|
| `app.MapGet/MapPost/MapPut/MapPatch/MapDelete` | `[HttpGet]` … on an action | One line per route |
| `MapGroup("/api/v1")` (route group) | `[Route]` on a base controller, or conventions | Prefix plus shared settings (auth, filters, tags, rate limit) applied once |
| `TypedResults.Ok(x)`, `TypedResults.NotFound()` | `Ok(x)`, `NotFound()` | `TypedResults` keeps the type, so OpenAPI knows it. `Results.StatusCode(n)` is the untyped form |
| `.RequireAuthorization("staff.manage")` | `[Authorize(Policy = "staff.manage")]` | S0-4 permissions |
| `.AllowAnonymous()` | `[AllowAnonymous]` | |
| `.RequireRateLimiting("policy")` | `[EnableRateLimiting("policy")]` | |
| `.AddEndpointFilter<T>()` (`IEndpointFilter`) | Action filter (`IActionFilter`) | S0-4's admin audit filter goes on the `/admin/api` group |
| `.WithTags("Auth")`, `.WithName(...)`, `.WithSummary(...)` | ApiExplorer settings, XML comments | OpenAPI grouping and names |
| `AddValidation()` + DataAnnotations | `[ApiController]` + `ModelState` | .NET 10+ |
| Handler parameters | Constructor injection + `[From*]` binding | See §3 |

## 5. Things we learned in the switch (gotchas)

- **Write routes with a leading slash:** `MapGroup("/api/v1")`, `MapGet("/me")`. The logged `route` field is the template text, so it then reads like the URL (`/api/v1/me`, `/health/live`). MVC logged `api/v1/me` without the slash.
- **Validation runs only for types in the project that calls `AddValidation()`.** All feature DTOs live in `ExtraSpace.Api`, so this matters only for test-only types.
- **Validation messages use the C# name** ("The Email field is required."). MVC used the JSON name. If the app ever shows these texts, add `[Display(Name = "email")]` on the property.
- **`[FromQuery]` and friends still live in the `Microsoft.AspNetCore.Mvc` namespace**, as do `ProblemDetails` and `HttpValidationProblemDetails`. A `using Microsoft.AspNetCore.Mvc` does not mean MVC is in use.
- **No `ModelState`.** For a business rule that is not a simple attribute, throw `AppException(400, ErrorCodes.ValidationFailed, "...")`, or return `TypedResults.ValidationProblem(errors)` for field errors (it goes through the same `Customize` hook).
- **`errors` is optional.** Field validation fills it. A binding failure (bad JSON, `"count": "abc"`, `?page=abc`, empty body) is 400 `VALIDATION_FAILED` without `errors`. MVC gave a per-field entry here.
- **Never use `[JsonPropertyName]` on a request DTO.** Error keys are the camelCased C# names, so a renamed JSON field would get the wrong key.
- **`Program.cs` maps groups only, never handlers.** The architecture rule cannot see the top-level `Program` class, so a `MapGet` lambda there using the `DbContext` would go unchecked.
- **An endpoint filter is a small class.** `IEndpointFilter.InvokeAsync(context, next)` sees the handler's arguments (`context.Arguments`) and either returns its own result or calls `next`. It is MVC's `IActionFilter` without `ActionExecutingContext`. The S0-4 audit filter must be its own top-level class.

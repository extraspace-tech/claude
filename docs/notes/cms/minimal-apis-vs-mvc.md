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

A sketch of S0-3's `GET /api/v1/me`, written before S0-3. The real code is in §6.

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

## 6. S0-3: sign-in, groups with auth, endpoint filters, rate limits

Added 2026-10-13 with S0-3 (branch `s0-3-customer-identity`). The real code is `Program.cs` step 14, `Features/Identity/IdentityEndpoints.cs` and `Features/Identity/CustomerAuth.cs`.

### 6.1 The `/api/v1` group: sign-in required by default

```csharp
// Program.cs, step 14
var api = app.MapGroup("/api/v1").RequireCustomer().WithEnumGuard();
api.MapIdentityEndpoints();

// IdentityEndpoints.cs
public static RouteGroupBuilder RequireCustomer(this RouteGroupBuilder group)
{
    group.RequireAuthorization(CustomerAuth.Policy);
    group.AddEndpointFilter(static (context, next) => { /* adds customerId to the request log, see 6.3 */ return next(context); });
    return group;
}

public static RouteGroupBuilder MapIdentityEndpoints(this RouteGroupBuilder api)
{
    var auth = api.MapGroup("/auth").AllowAnonymous().WithTags("Auth");   // a group inside the group
    auth.MapPost("/code", RequestCode).RequireRateLimiting(CustomerAuth.CodeRateLimit);
    auth.MapPost("/code/verify", VerifyCode).RequireRateLimiting(CustomerAuth.VerifyRateLimit);
    auth.MapPost("/refresh", Refresh);
    auth.MapPost("/logout", Logout);

    api.MapGet("/me", GetMe).WithTags("Me");   // inherits RequireAuthorization from /api/v1
    return api;
}
```

The MVC version of the same rules:

```csharp
[ApiController, Route("api/v1/auth"), AllowAnonymous]
public sealed class AuthController : ControllerBase
{
    [HttpPost("code"), EnableRateLimiting("auth-code")] public Task<IActionResult> RequestCode(...) { ... }
}

[ApiController, Route("api/v1/me"), Authorize(Policy = "Customer")]
public sealed class MeController : ControllerBase { ... }
```

What to notice:

- **Secure by default.** In MVC, each controller needed its own `[Authorize]`. If you forgot it, the controller was public. (A global `AuthorizeFilter` could fix that, but then every public controller needed `[AllowAnonymous]`.) Here the rule sits once on `/api/v1`. A new route under it is signed-in only, unless it says `.AllowAnonymous()`.
- **Groups nest.** `api.MapGroup("/auth")` makes `/api/v1/auth`. The inner group inherits the outer group's settings (policy, filters, enum guard) and adds its own. `.AllowAnonymous()` on the inner group cancels the outer `RequireAuthorization` for those routes only. This is the same rule as MVC: `[AllowAnonymous]` beats `[Authorize]`.
- **Why logout is anonymous.** The refresh token in the body is the credential. An app whose access token has already expired must still be able to sign out.

### 6.2 The JWT scheme and the `Customer` policy

```csharp
services.AddAuthentication().AddJwtBearer("Customer");                     // the scheme: HOW to read a token
services.AddOptions<JwtBearerOptions>("Customer").Configure<IOptions<CustomerAuthOptions>>((jwt, auth) => { ... });
services.AddAuthorizationBuilder()
    .AddPolicy("Customer", p => p.AddAuthenticationSchemes("Customer").RequireAuthenticatedUser());   // the policy: WHO may enter
```

- **Scheme versus policy.** A *scheme* is how a request proves who it is: here, a `Bearer` JWT checked with HS256, our issuer and audience, and 30 s clock skew. A *policy* is the rule a route demands: here, "signed in through the `Customer` scheme". Routes name only the policy (`RequireAuthorization("Customer")`).
- **MVC did the same with attributes:** `[Authorize(AuthenticationSchemes = "Customer")]`, or `[Authorize(Policy = "Customer")]` with the same policy. The scheme and policy setup in `Program.cs` / DI is identical in both styles. Only the place where a route asks for it changed: an attribute became a method call.
- **Why the policy names its scheme.** S0-4 adds a second scheme, the admin cookie. When there is more than one scheme, ASP.NET Core no longer picks a default. A policy that names its scheme keeps working, and an admin cookie can never open a customer route.
- **`MapInboundClaims = false`.** Without it, the JWT handler renames `sub` to a long `http://schemas.xmlsoap.org/...` claim type. We keep the short names, and `CustomerPrincipal.CustomerId()` reads `sub`.
- **Getting the user in a handler.** Add a `ClaimsPrincipal user` parameter, and the framework fills it in. MVC used the controller's `User` property.
- **401 bodies.** The JWT handler writes an empty 401. `UseStatusCodePages()` turns it into our problem with `code: UNAUTHENTICATED`, in both styles.

### 6.3 Endpoint filter: `customerId` on every log line

```csharp
group.AddEndpointFilter(static (context, next) =>
{
    if (context.HttpContext.User.CustomerId() is { } customerId) RequestLog.Add(context.HttpContext, "customerId", customerId);
    return next(context);
});
```

- **The MVC equivalent** is an action filter (`IActionFilter.OnActionExecuting`) registered globally or as `[ServiceFilter]` on controllers. The endpoint filter is the same idea: code that runs around the handler. It gets `context` (the `HttpContext` and the handler's arguments) and `next` (the rest of the chain).
- **Placed once on the group**, it runs for every route in it, and only for those routes. `/health/*` and `/test/*` are outside the group, so they do not get it.
- **Limit.** A filter runs only when the request reaches the handler stage. If binding fails first (bad JSON), the request's summary line has no `customerId`. MVC's action filters had the same limit. S1 checks this with its first signed-in POST route.
- This one is a lambda, because it is two lines. A filter with dependencies is a class that implements `IEndpointFilter`, added with `.AddEndpointFilter<T>()` (S0-4's audit filter).

### 6.4 Rate-limit policies on routes

```csharp
// CustomerAuth.cs: register named policies
services.Configure<RateLimiterOptions>(o =>
{
    o.AddPolicy("auth-code", http => PerIpPerHour(http, 20));
    o.AddPolicy("auth-verify", http => PerIpPerHour(http, 30));
});

// IdentityEndpoints.cs: attach them
auth.MapPost("/code", RequestCode).RequireRateLimiting("auth-code");
```

- **MVC:** the same policies, attached with `[EnableRateLimiting("auth-code")]` on an action or a controller. `.RequireRateLimiting(...)` can also sit on a group, like `RequireAuthorization`.
- `app.UseRateLimiter()` (pipeline step 10) does the counting. A refused request gets 429 with `Retry-After`, written by `RateLimitSetup`.
- These per-IP counters live **in memory**, so each API task counts on its own (plan decision 3). The exact per-email limits (one code per 60 s, 5 per hour) are not rate-limit policies. They live in the database, under a per-email lock, and throw `AppException(429, …) { RetryAfter = … }`.

### 6.5 `TypedResults.Accepted` and `NoContent`

| Route | Returns | Why | MVC |
|---|---|---|---|
| `POST /auth/code` | `Task<Accepted>`, `TypedResults.Accepted((string?)null)` → 202, no body | The email is queued as a job, not sent yet. 202 means "accepted for processing". The same answer is given whether or not the email is a customer, so the route tells nobody which emails exist. | `return Accepted();` |
| `POST /auth/logout` | `Task<NoContent>`, `TypedResults.NoContent()` → 204 | Nothing to return. It is always 204, even for an unknown token. | `return NoContent();` |
| `POST /auth/code/verify`, `/auth/refresh` | `Task<Ok<TokenResponse>>` → 200 | The token pair | `ActionResult<TokenResponse>` |

The typed return (`Accepted`, `NoContent`, `Ok<T>`) is what OpenAPI reads, so the document shows exactly 202, 204 or 200 with the body schema. `Accepted(...)` takes a location URI, and we have none. That is why it is called with `(string?)null`.

### 6.6 Swagger "Authorize" with a JWT

`CustomerAuth` adds a `Bearer` security scheme to the OpenAPI document. An **operation transformer** puts the lock icon only on routes that need the `Customer` policy, so `/auth/*` and `/health/*` stay open. To try `/me` in Swagger UI:

1. Run `POST /api/v1/auth/code`.
2. Read the code from the "Development email" console line.
3. Run `POST /api/v1/auth/code/verify`.
4. Click **Authorize** and paste the `accessToken`.

MVC used Swashbuckle's `AddSecurityDefinition` and an `IOperationFilter` for the same result.

### 6.7 Gotchas found in S0-3

- **Request bodies must be `public`.** The .NET 10 validation source generator skips `internal` types: with `internal` bodies, bad input was not validated and the handler ran anyway (the tests got `INVALID_CODE` instead of 400 `VALIDATION_FAILED`). Response records and services can stay `internal`. MVC validated by reflection, so it did not care.
- **A second test host shares Hangfire's static state.** `WithWebHostBuilder` hosts set `App:Role=Api`, so they do not start a second job server. This is not a Minimal API rule, but you will hit it in endpoint tests.

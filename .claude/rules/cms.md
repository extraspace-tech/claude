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
3. Never handle card data. Cards are collected only by Stripe's SDK in the app (`flutter_stripe` `CardField`, 3DS via `handleNextAction`); our server creates and confirms PaymentIntents (Stripe Connect direct charges, SG and MY platforms); saved cards are stored as Stripe ids + brand / last4 / expiry / fingerprint only. Card data never reaches our servers or logs. Webhooks: platform + connect route per platform, each signature-verified. A new payment flow needs explicit business approval. (Changed from "hosted Checkout + one webhook" by the owner, 2026-10-14, S1 spec §3.)
4. Never call a SiteLink card-carrying operation (list: `docs/notes/sitelink/ccws-3.5-operations.md:5`). Only exception: `MoveInReservation_v6` / `MoveInWithDiscount_v7` with every card element blank and `iPayMethod 2` (Cash), guarded by a test. Record payments with `PaymentSimpleCashWithSource`. Never `bTestMode` (it still records). Outside production, SiteLink writes only to `SiteLink:WriteAllowList` (`LSETUP`). SiteLink is called on demand only (call budget, S1 spec §6.6). SiteLink request field names exactly as in the WSDL (`docs/notes/sitelink/`).
5. Every BizPlus credit change goes through the wallet service (single writer).
6. Mobile routes live under `/api/v1/*`. They change freely until the first store release of our app. After that, changes are additive only (freeze policy OPEN, `.claude/rules/cross-repo.md` §4).
7. Every endpoint that reads or changes a customer's data checks ownership. Never trust a client-reported amount; the server prices everything.
8. Configuration values come from the environment or a secret store, never from a committed file.
9. Write tests with the code (xUnit). Where a spec feature doc has an acceptance table we keep, port it as `[Theory]` data.
10. A feature uses another feature only through its `Features/<Feature>/Contracts/` folder (service interfaces + DTOs), never its entities or tables. The architecture test in `tests/ExtraSpace.Api.Tests/Architecture/` enforces it; never weaken that test to make a build pass.
11. Outside calls (SiteLink, Stripe, SES) have a timeout, a circuit breaker and retries for safe reads only. Side effects after a payment run as idempotent jobs whose trigger is saved in the payment's own transaction (outbox row, S1-1 `Platform/Outbox`: `IOutbox.Enqueue` inside the payment's transaction).

## Conventions to decide in the design spec (write the answer here)

- Error envelope: ProblemDetails + `code` + `traceId`, real status codes; validation 400 `VALIDATION_FAILED` + `errors` (S0 spec §4.1).
- Delete: hard by default; `archived_at` only where a feature spec asks (S0 spec §5).
- Audit stamps: `created_at` / `updated_at` (UTC) by one `SaveChanges` interceptor; `created_by_staff_id` / `updated_by_staff_id` on admin-edited tables; admin writes also go to `audit_log` via one action filter.
- Logging (S0 spec §4.4): Serilog compact JSON to stdout; every line has `traceId` + `correlationId` (carried into Hangfire jobs), `role`, `version`; `X-Trace-Id` on every response; one summary line per request, one line per outside call, slow-query Warning > 500 ms; `ILogger<T>` message templates only (CA2254 = error); ids not entities; emails only via `Pii.MaskEmail`; never tokens, codes, cookies, secrets or bodies. Local: Seq at `http://localhost:5341`. CloudWatch saved query **Trace** finds a whole chain by id.
- Plain `DbContext` in services, no repository layer (decided).
- Jobs: Hangfire on PostgreSQL (schema `hangfire`), registered in code at start-up, `Jobs:<Name>:Enabled` switch, idempotent (decided).

## Built so far

The conventions and helpers of S0-1, S0-2 and S0-3 (test commands, CDK rules, `Platform/` layout, Minimal API, error, logging, enum and JSON rules, jobs, email, identity, test helpers) live in `docs/notes/cms/built-so-far.md`. 🔴 Read it before you design, build, review or walk CMS code; every implementer and reviewer brief names it.

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

SiteLink (S1-1): with no `SiteLink:*` login in user-secrets every SiteLink call answers 503 and the unit refresh records "SiteLink could not be reached."; to call LSETUP, the owner sets `SiteLink:CorpCode`, `SiteLink:CorpUserName` (`user:::key`), `SiteLink:CorpPassword` with a no-print command (never echo them). Writes go only to `SiteLink:WriteAllowList` (`LSETUP`).

Development sends email through the `Log` transport: the sign-in code is printed in the console (`Development email`). Health `/health/live`, `/health/ready`; OpenAPI `/openapi/v1.json`; Swagger UI `/swagger` (both outside production). In Seq, find a request with `@TraceId = '<id>'` (Seq keeps the trace id as its built-in field, not as `traceId`). Shared environments: migration scripts go to `docs/migrations/` via `dotnet ef migrations script --idempotent`; strip the BOM before running them with `psql`. Kill the app after testing (ports 5080 and 5173 are in `.claude/dev-ports`).

Admin UI (S0-5), from `../CMS/admin-ui` with Node 24 on PATH (`~/.local/share/node-v24.18.0/bin`):

```bash
npm ci
npm run dev      # http://localhost:5173/admin/ , forwards /admin/api and /admin/jobs to the API on 5080
npm run build    # writes src/ExtraSpace.Api/wwwroot/admin (git-ignored); then the API serves http://localhost:5080/admin
npm run typecheck && npm test
```

After a change to an admin or mobile endpoint or DTO: `UPDATE_OPENAPI=1 dotnet test tests/ExtraSpace.Api.Tests -- --filter-class "*OpenApiSnapshotTests"`, then `npm run gen:api`, and review both diffs. 🔴 TypeScript stays 6.0.3 (the type generator crashes on 7).

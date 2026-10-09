# `../CMS` — the new C# monolith

Always loaded. Applies to every file under `../CMS/`. Rewritten 2026-10-09 after the owner decided on a brand-new system (`.claude/rules/cross-repo.md` §4). The S0 design spec (`docs/superpowers/specs/2026-10-09-s0-foundation-design.md`) fixes the layout and conventions below; fill in the remaining **TBD** at phase 1, and keep this file as the house-rules sheet for the repo.

## Facts

- Remote `extraspace-tech/cms`, branch `main`. 🔴 PUBLIC repository: no secrets, no connection strings, no real customer data, not even in a test fixture. The whole monolith lives here (owner, 2026-10-09): mobile API, admin API, React admin UI, jobs. `../API` is not used. Making this repo private is recommended and OPEN (org admin).
- Architecture: **one monolith** (owner, 2026-10-09): mobile API, admin back office and background jobs in one deployable, hosted on AWS.
- Written **from scratch**. The demo (`../Backend Demo/backend`) and the old Codigo system are read-only references, never integrated (`.claude/rules/backend-demo.md`, `.claude/rules/old-backend.md`).
- Database: **PostgreSQL on AWS RDS, our own schema**, EF Core migrations owned by this repo.
- Stack (recommended, confirm in the design spec): .NET 10 (installed locally: `dotnet 10.0.400`), EF Core + Npgsql (+ EFCore.NamingConventions snake_case), MVC controllers, Hangfire on PostgreSQL, Stripe.net, AWS SES v2, Serilog, .NET `TimeProvider`, xUnit + FluentAssertions + Testcontainers. No Redis in S0 (S1 decides whether the SiteLink cache needs ElastiCache); no NodaTime. Admin UI: React + Vite + TypeScript (owner, 2026-10-09), built to static files in the API's `wwwroot` and served same-origin; Node is needed only on dev machines and CI, never in production. Layout (S0 spec §3): `src/ExtraSpace.Api` (`Platform/`, `Features/<Feature>/` with `Admin/` sub-folder, `Integrations/`), `src/ExtraSpace.Engines` (pure maths), `admin-ui/`, `infra/ExtraSpace.Infra` (CDK), `tests/ExtraSpace.Engines.Tests`, `tests/ExtraSpace.Api.Tests`. UI libs: React 19, Tailwind + shadcn/ui, TanStack Query/Table, React Hook Form + Zod, Recharts, `openapi-typescript` + `openapi-fetch`. Paths: OpenAPI `/openapi/v1.json` (Swagger UI outside production), health `/health/live` + `/health/ready`, Hangfire `/admin/jobs`. **TBD:** local port.

## House rules (design defaults; only the owner changes them)

1. Money is exact: `numeric` in PostgreSQL, `decimal` in C#. Never `double` or `float` for money. One rounding helper; the rule is set in the design spec.
2. Business dates are Asia/Singapore wall clock; storage is UTC. Never `DateTime.Now`.
3. Never handle card data. Stripe only via hosted Checkout + one signature-verified webhook. A new payment flow needs explicit business approval.
4. Never call a SiteLink card-carrying operation; record payments with `PaymentSimpleCashWithSource`. SiteLink request field names exactly as in the WSDL (`docs/notes/sitelink/`).
5. Every BizPlus credit change goes through the wallet service (single writer).
6. Mobile routes live under `/api/v1/*`. They change freely until the first store release of our app. After that, changes are additive only (freeze policy OPEN, `.claude/rules/cross-repo.md` §4).
7. Every endpoint that reads or changes a customer's data checks ownership. Never trust a client-reported amount; the server prices everything.
8. Configuration values come from the environment or a secret store, never from a committed file.
9. Write tests with the code (xUnit). Where a spec feature doc has an acceptance table we keep, port it as `[Theory]` data.

## Conventions to decide in the design spec (write the answer here)

- Error envelope: ProblemDetails + `code` + `traceId`, real status codes; validation 400 `VALIDATION_FAILED` + `errors` (S0 spec §4.1).
- Delete: hard by default; `archived_at` only where a feature spec asks (S0 spec §5).
- Audit stamps: `created_at` / `updated_at` (UTC) by one `SaveChanges` interceptor; `created_by_staff_id` / `updated_by_staff_id` on admin-edited tables; admin writes also go to `audit_log` via one action filter.
- Logging: Serilog JSON with a request id; never log PII, tokens or full entity dumps.
- Plain `DbContext` in services, no repository layer (decided).
- Jobs: Hangfire on PostgreSQL (schema `hangfire`), registered in code at start-up, `Jobs:<Name>:Enabled` switch, idempotent (decided).

## Running locally

**TBD** at phase 1: build command, run command, port, OpenAPI URL, health URL, required env (user-secrets or a local `.env`, never committed). Add every local port to `.claude/dev-ports` so the Stop hook can reap orphaned apps.

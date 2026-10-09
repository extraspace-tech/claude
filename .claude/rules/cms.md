# `../CMS` — the new C# repo (CMS + API)

Always loaded. Applies to every file under `../CMS/`. Started 2026-10-09 before the solution existed; fill in the facts marked **TBD** at port-plan phase 1 and keep this file as the house-rules sheet for the repo.

## Facts

- Remote `extraspace-tech/cms`, branch `main`. 🔴 PUBLIC repository: no secrets, no connection strings, no real customer data, not even in a test fixture.
- Solution layout (recommended by `13-csharp-port-plan.md` §1, confirm when created): `src/<Api>`, `src/<Domain>` (pure engines, no IO), `src/<Application>` (services, DTOs, validators), `src/<Infrastructure>` (EF DbContext + entities, Redis, SiteLink client, Stripe client, jobs), `tests/…`. **TBD:** project names, csproj paths, local port, Swagger path (`/api/docs` in the reference), health path.
- Stack (recommended, confirm): .NET 10 (installed locally: `dotnet 10.0.400`), EF Core + Npgsql database-first against `reference/schema.sql`, StackExchange.Redis, FluentValidation, BCrypt.Net-Next, Stripe.net, NodaTime, Serilog, Swashbuckle, xUnit + FluentAssertions.

## House rules (from the spec; do not violate)

1. Keep the existing PostgreSQL schema. No breaking renames. Quoted PascalCase/camelCase identifiers; PG enums; cuid ids; app-maintained `updatedAt`.
2. Money columns are `double precision` — compute with `double`, JS half-up rounding (`Math.Floor(x + 0.5)`), never bare `Math.Round`.
3. Business dates are Asia/Singapore; store UTC.
4. Never handle card data. Stripe only via hosted Checkout + the one signature-verified webhook, for the five authorised `metadata.kind` flows (spec 05). A new payment flow needs explicit business approval.
5. Never call a SiteLink card-carrying operation; move-ins use `iPayMethod = 2`. SiteLink request field names come from spec 02 exactly.
6. Every BizPlus credit change goes through the wallet service (single writer).
7. Admin-manageable resources are declared once in the resource registry; the admin UI is generated from `GET /admin/api/meta/resources`.
8. Mobile routes stay under `/api/v1/*`, REST verbs, response shapes unchanged. Same error `code`s and status codes as the spec's error envelope.
9. Configuration uses the env var names in `reference/env-vars.md`.
10. Port each feature doc's acceptance tests as xUnit `[Theory]` data with the implementation (the spec asks for it; the Porsche "no tests" rule does NOT apply here).

## Conventions to decide at phase 1 (write the answer here)

- Error envelope implementation and the `VALIDATION_ERROR` shape (spec 00).
- Soft delete: the reference has no global soft-delete convention; check per table in `schema.sql` before assuming one.
- Audit stamps: `createdAt` / `updatedAt` UTC; who writes them.
- Logging: Serilog JSON with `requestId`; never log PII, tokens or full entity dumps.
- Repository / unit-of-work pattern or plain DbContext — **TBD**.

## Running locally

**TBD** at phase 1: build command, run command, port, Swagger URL, health URL, required env (`.env` or user-secrets, never committed). Until then the reference runs with `npm run dev` on 4000 (`../Backend Demo/backend/CLAUDE.md` "Commands"). Add every local port to `.claude/dev-ports` so the Stop hook can reap orphaned apps.

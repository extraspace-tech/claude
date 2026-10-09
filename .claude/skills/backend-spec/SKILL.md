---
name: backend-spec
description: >-
  ExtraSpace platform backend specification for re-implementing (or changing) the backend in
  C# / ASP.NET Core. Use when building, porting, or reviewing any backend feature or API endpoint:
  auth, SiteLink units/reservations/leases, Stripe payments and webhook, leads/viewings, facility
  booking, BizPlus credits, Cowork Manager (units, licences, invoices, payments, outbox), rewards,
  CMS, admin console/RBAC/generic CRUD, cron jobs, database tables, or env configuration.
---

# ExtraSpace backend spec

The spec lives in the client's reference repo:
`/Users/waiyanmin/Projects/Extra Space/Backend Demo/backend/.claude/backend-spec/` (call it `SPEC` below).
It is the contract for the C# repo (`../CMS`): the existing Flutter app and React admin UI must keep
working unchanged. The reference repo is read-only; corrections go to `docs/notes/` in the workspace root.

## Procedure

1. Read `SPEC/00-architecture-and-conventions.md` once per session (pipeline, error envelope, auth,
   DB conventions, rounding and time-zone parity traps).
2. Find the feature: `SPEC/reference/endpoints.md` maps every route to its doc (`features/01…12`).
   Read that feature doc fully before writing code — especially *Business rules & algorithms*,
   *Edge cases* and *C# implementation notes*. Then open the TS files it cites.
3. For tables, use the feature doc's *Data model* section; exact DDL is `SPEC/reference/schema.sql`,
   relations are easiest to read in `SPEC/reference/schema.prisma`.
4. For `/api/v1/*` JSON shapes, cross-check `SPEC/reference/openapi.json`.
5. Implement the feature doc's *Acceptance tests* as xUnit tests alongside the code.
6. Follow the build order and parity checks in `SPEC/13-csharp-port-plan.md`.

## Non-negotiables

- Same routes, same JSON field names/casing, same error `code`s and status codes.
- Keep the existing PostgreSQL schema; money is `double precision`; JS half-up rounding.
- Asia/Singapore business dates; UTC storage.
- No card data; Stripe only via hosted Checkout + verified webhook for the authorised flows.
- Never commit secrets — env var names only (`SPEC/reference/env-vars.md`); `extraspace-tech/cms` is public.

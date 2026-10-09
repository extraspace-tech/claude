---
name: backend-spec
description: >-
  ExtraSpace demo handover spec, used as the feature reference for the brand-new C# / ASP.NET Core
  monolith. Use when designing, building, or reviewing any feature or API endpoint: auth, SiteLink
  units/reservations/leases, Stripe payments and webhook, leads/viewings, facility booking, BizPlus
  credits, Cowork Manager (units, licences, invoices, payments, outbox), rewards, CMS, admin
  console/RBAC, cron jobs, database tables, or configuration.
---

# ExtraSpace demo spec (feature reference)

The spec lives in the demo repo:
`/Users/waiyanmin/Projects/Extra Space/Backend Demo/backend/.claude/backend-spec/` (call it `SPEC` below).
It describes the PM's demo. The new monolith is written from scratch and owes the demo nothing
(owner, 2026-10-09): the spec is a reference for **what a feature does**, not a contract for how
we build it. For rules the demo lacks (points, tiers, autopay, bills from SiteLink), read
`docs/notes/old-backend/`. The client's own Claude prototypes are a third reference: read
`docs/notes/client-artifacts/` (Cowork Manager, ES App, Admin) for the same feature. Each note has a
rule-by-rule comparison with this spec. Where they disagree, do not pick one: list the conflict for
the PM (`.claude/rules/cross-repo.md` §4, open decision 8). The demo repo is read-only; corrections
go to `docs/notes/` here.

## Procedure

1. Read `SPEC/00-architecture-and-conventions.md` once per session, for the demo's conventions and
   the traps it found (time zones, rounding, SiteLink quirks).
2. Find the feature: `SPEC/reference/endpoints.md` maps every demo route to its doc
   (`features/01…12`). Read that feature doc fully, especially *Business rules & algorithms*,
   *Edge cases* and *Acceptance tests*. Open the TS files it cites when a rule is unclear.
3. Use the *Data model* section and `SPEC/reference/schema.prisma` to understand the entities. Our
   own schema is designed in the design spec and may differ.
4. For SiteLink calls, spec 02 + the live WSDL (`docs/notes/sitelink/`) give the exact operation
   and field names. Those ARE binding, because SiteLink is external.
5. Port the acceptance tables we keep as xUnit `[Theory]` data.
6. In the design or plan, list which spec rules we keep and which we change.

## Not binding

Routes, JSON shapes, error codes, the schema, env var names, `double` money with JS half-up
rounding, the port plan's phases and its parity checks.

## Never copy

The demo's defects:
- email-only login
- missing ownership checks
- client-reported payment amounts
- the hard-coded anon key
- billing maths in the admin browser code

See `.claude/rules/backend-demo.md`.

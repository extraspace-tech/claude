---
name: clarification-checklist
description: Questions to ask before starting any non-trivial implementation in the Extra Space C# repo (spec doc, scope, clients, data model, money and time, payments and SiteLink, auth, jobs). Use before building any feature, endpoint, or entity change; skip questions that clearly do not apply.
---

# Clarification Checklist

Ask these questions before starting any non-trivial implementation. Not every question applies to every task — skip ones clearly irrelevant — but when in doubt, ask. First check the design spec, the demo spec, `docs/notes/client-artifacts/` and `docs/notes/old-backend/`; many answers are already there. Where the demo and the client's artifacts disagree, ask the PM which one wins (cross-repo §4, open decision 8) (memory `feedback-reference-first`).

### Spec and reference
- Which `features/NN-*.md` doc covers this? Which TS files does it cite? Have both been read?
- Which demo spec rules does this keep, and which does it change? Is each change written in the plan?
- Which implementation-plan phase does this belong to, and are its dependencies built?

### Clients
- Which client reads this (Flutter `/api/v1/*`, admin UI `/admin/api/*`, cron, Stripe webhook)? Does the route, JSON field name, casing, status code or error `code` change? (Additive only unless the owner decides otherwise.)
- For admin resources: is editing the resource registry enough, or does the screen need custom UI?

### Scope
- Full-stack (entity → service → controller → tests) or one layer only?
- Which existing feature in the C# repo is the closest reference implementation to follow?

### Data model
- Which tables? Exact DDL in `reference/schema.sql` (constraints, enums, EXCLUDE ranges). Any additive migration needed? (`docs/migrations/`, run by hand.)
- Soft delete or hard delete for this table? (Decided per table in the design spec.)
- For any computed or display field: what is the exact source column or formula?

### Money and time
- Which values are money? Rounding point (which helper, after which operation)? GST per site?
- Which dates are business dates (the site's time zone) and which are instants (UTC)?
- Idempotency key for a webhook, cron or retry path?

### Payments and SiteLink
- Does this touch Stripe? Which of the five authorised `metadata.kind` flows? New flow = business approval needed.
- Does this call SiteLink? Which operation (spec 02), test mode, per-location credentials?

### Auth and access
- Anonymous key, customer JWT or admin session? Which permission string for admin actions? Audit log row?

### Jobs
- Cron or in-process `BackgroundService`? How does it run only once across app instances, and what makes it idempotent?

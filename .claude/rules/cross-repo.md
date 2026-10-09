# Cross-repo impact map (Extra Space)

Always loaded (no `paths:` filter). Before designing any change, check whether it touches a route, JSON shape, table, enum, env var or Redis key listed here; if it does, name every affected client in the plan's "Clients affected" section. Started 2026-10-09 from the handover spec (`../Backend Demo/backend/.claude/backend-spec/`); verify a specific line in the spec before relying on it. Grow this file as the C# repo grows.

## 1. Repos and clients

| Thing | Where | Contract it owns |
|---|---|---|
| New C# repo (CMS + API) | `../CMS` | All of the below, re-implemented |
| Node reference | `../Backend Demo/backend` (read-only) | The behaviour to match; every spec doc cites its TS files |
| Flutter mobile / web app | not in this workspace | Calls `/api/v1/*` with an anonymous API key or a customer JWT. Response shapes match its models. Not changing. |
| React admin UI | `../Backend Demo/backend/admin-ui/` (reuse as-is, built into `wwwroot/admin`) | Calls `/admin/api/*` with a session cookie (`extraspace.admin.sid`); nav, tables and forms are generated from `GET /admin/api/meta/resources` (the resource registry) |
| web-app prototype | `../Backend Demo/backend/web-app/` | Presentation prototype; calls `/api/v1/*` |
| Cron triggers | infra (Vercel cron today) | `GET /api/cron/*` with `Authorization: Bearer $CRON_SECRET` |
| Stripe | external | Hosted Checkout + ONE signature-verified webhook (`/api/v1/payments/webhook`); five authorised `metadata.kind` flows (spec 05) |
| SiteLink | external SOAP (CCWs 3.5) | Field names verified against the live WSDL; keep the names in spec 02 exactly; never a card-carrying operation |

## 2. Shared database (PostgreSQL)

One database, 69 models, DDL frozen in `reference/schema.sql`. During parity testing and cutover the Node service and the C# service may run against copies of the same schema, so:

- No renames, no drops, no type changes. Additive migrations only, written to `docs/migrations/` and run by hand.
- Table and column names are quoted PascalCase / camelCase identifiers; enums are PostgreSQL enums; ids are cuid strings; `updatedAt` is maintained by the app.
- Money is `double precision`; compute with `double` and JS half-up rounding (`Math.Floor(x + 0.5)`), never bare `Math.Round`.
- Business dates are Asia/Singapore; storage is UTC.
- Single-writer rules from the spec: every BizPlus credit change goes through the wallet service; admin-manageable resources are declared once in the resource registry.
- Redis lock keys are listed per feature doc; two schedulers (Node + C#) sharing Redis are safe only if the keys match exactly. Disable the Node schedulers before enabling the C# ones.

## 3. Env vars

Keep the exact names in `reference/env-vars.md` so deployment secrets carry over (`DATABASE_URL`, `REDIS_URL`, `SITELINK_*`, `MOBILE_API_KEY`, `MOBILE_SESSION_JWT_SECRET`, `SESSION_SECRET`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `CRON_SECRET`, cron settings). Values never enter any repo; `extraspace-tech/cms` is public.

## 4. Enum and contract drift

The spec was written from the Node code at 2026-10-08. When the C# code and the Node reference disagree, the Node source is the authority until the owner decides otherwise; record every decided deviation here with the date and the affected clients.

| Date | Deviation | Affected clients | Decided by |
|---|---|---|---|
| — | none yet | — | — |

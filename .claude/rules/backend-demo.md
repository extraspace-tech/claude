# `../Backend Demo/backend` — the PM's demo (READ ONLY, feature reference)

Always loaded. This is the demo the PM built with the client (`extraspace-tech/backend`, private). Stack: Node 20 / Express 5 / Prisma 6 / PostgreSQL / Redis, plus the `admin-ui/` and `web-app/` Vite + React apps. It never reached customers or the product owner.

**Owner, 2026-10-09:** the new C# monolith is a brand-new project written from scratch. The demo is **never touched** and owes nothing: no shared database, no data carried over, no API or schema compatibility, no parity tests against it. It is a **feature and screen reference** only. Full inventory: `docs/notes/demo-backend/01-demo-inventory.md`.

**Goal (owner, 2026-10-09): our monolith is a functional copy of the demo**, meaning the same features and screens, with our own code. The demo keeps changing. Check it for new commits with `fetch` + `log <last-synced>..origin/main` (read-only, never pull), and log each sync in `docs/notes/demo-backend/sync-log.md` (baseline `6be4474`).

- The client's own Claude artifacts (`docs/notes/client-artifacts/`) describe several of the same features differently: late fees, auto-billing, refunds, booking length and hours, packages, reward tiers, insurance, lease status. The demo is not automatically right. Ask the PM which wins (`.claude/rules/cross-repo.md` §4, open decision 8). Spec 09 says the demo's Cowork part was ported from the Cowork Manager artifact.
- 🔴 A PreToolUse hook blocks every Edit/Write under this folder. Do not work around it. If a spec doc is wrong, write the correction into `docs/notes/` here.
- The spec: `.claude/backend-spec/` inside it (README, `00-architecture-and-conventions.md`, `features/01…12`, `13-csharp-port-plan.md`, `reference/{endpoints.md, schema.sql, schema.prisma, openapi.json, env-vars.md}`). Prepared 2026-10-08 from the demo code; every doc cites the TS files it came from. Use it for business rules, algorithms, edge cases and acceptance tables. Its routes, shapes, schema, env names, `double` money and port plan do not bind us.
- Its own `CLAUDE.md` and `README.md` describe its layout. `README.md:340-377` maps the 36 Lucy paths the Flutter app calls today; our API must cover those flows.
- Never copy these demo defects:
  - Email-only login: anyone with the public anon key can log in as any email.
  - `/me/spaces?userId=` and reservation cancel have no ownership check.
  - Storage payments are taken on the client's word.
  - The anon API key is hard-coded in `web-app/src/lib/api.ts`.
  - The admin-ui Cowork pages import the backend's TS engine (`@engine`) and do the billing maths in the browser.
- Maturity, for judging how far to trust a rule:
  - Built in about 3 weeks, mostly with Claude Code.
  - Only the pure maths has tests: 9 jest files. There is no CI.
  - Storage, leads, facility booking and credits were stable at 2026-10-08. Cowork (spec 09/10) was still changing daily.
- Running it needs real SiteLink / Stripe / DB values from the client's secret store. Only run it when the owner asks, for example to see a screen, and kill it after.

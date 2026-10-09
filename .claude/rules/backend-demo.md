# `../Backend Demo/backend` — the client's Node reference (READ ONLY)

Always loaded. The client's existing backend (`extraspace-tech/backend`, private, Node 20 / Express 5 / Prisma 6 / PostgreSQL / Redis, plus `admin-ui/` and `web-app/` Vite apps). It is the behaviour the C# repo must match and the home of the handover spec.

- 🔴 A PreToolUse hook blocks every Edit/Write under this folder. Do not work around it. If a spec doc is wrong, write the correction into `docs/notes/` here and tell the owner.
- The spec: `.claude/backend-spec/` inside it (README, `00-architecture-and-conventions.md`, `features/01…12`, `13-csharp-port-plan.md`, `reference/{endpoints.md, schema.sql, schema.prisma, openapi.json, env-vars.md}`). Prepared 2026-10-08 from the code at that date; every doc cites the TS files it came from, and the TS source is the final authority.
- Its own `CLAUDE.md` and `README.md` describe its layout and rules (card data, Stripe flows, SiteLink, resource registry). Read them once per feature.
- Running it (`npm install`, `npm run prisma:migrate && npm run seed`, `npm run dev` on 4000) needs a `.env` from `.env.sample` with real SiteLink / Stripe / DB values; those come from the client's secret store, never from this workspace. Only run it for parity checks the owner asked for, and kill it after.
- Golden-response parity (port plan §3): record the Node GET responses, assert the C# ones are JSON-equal (ignore `requestId` and uncontrollable timestamps). Mutations: same request on two DB copies, diff the rows.

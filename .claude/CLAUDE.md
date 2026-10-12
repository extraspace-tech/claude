# Extra Space workspace

## 1. What this is

This folder (`Claude/`) is the **private context repo** and the **workspace root** for the new Extra
Space system. It carries all AI tooling (`.claude/`, `.cursor/`), the cross-repo knowledge, the
shared docs, and the auto-memory. The code repositories are its **siblings** under
`/Users/waiyanmin/Projects/Extra Space/`; they are their own git repos and are never tracked here.

**Always start Claude Code and Cursor here, in `Claude/` — never inside a code repo.** Settings,
rules, MCP servers, hooks and auto-memory are all keyed to this folder. Starting in a code repo
loses every one of them.

### What we are building (owner decisions, 2026-10-09)

The client is ExtraSpace Asia (self-storage, Singapore and Malaysia). The first release covers
**Singapore AND Malaysia** (PM, 2026-10-09) on **one platform**; currency, time zone and tax live
per site, never hard-coded. We build a **brand-new C# /
ASP.NET Core monolith, from scratch**: one deployable that holds the mobile API, the admin back
office and the background jobs.

- It **replaces Lucy/Iviva**, which is retired. The Flutter app moves fully onto the new API.
  **Our team also builds the Flutter app.**
- **Self-storage runs on SiteLink** (CCWs 3.5 SOAP).
- **The whole BizPlus line is built in-house**: Cowork inventory, licences and billing; facility
  booking; credits.
- The **database is PostgreSQL on AWS RDS**, with **our own schema**. Hosting is AWS.

There are two read-only references. We **never touch** them: no edits, no calls, no shared
database, no data copied from them, no compatibility owed.

1. **The demo** (`../Backend Demo/backend`): the PM's Node/PostgreSQL prototype and its handover
   spec. It is our **feature and screen reference**. It never reached customers or the product
   owner, so nothing depends on it. Rules: `.claude/rules/backend-demo.md`.
2. **The old production system** (`../../Extra Space old/extraspace-backend`): Codigo's .NET Core
   3.1 + MySQL code, in use since 2020, for the YES app and the ES Express back office. It keeps
   running on its own. It is a **reference for how today's business rules work**. 🔴 Live secrets
   are committed in it. Rules: `.claude/rules/old-backend.md`.

**The goal is a functional copy of the demo** (same features and screens), written from scratch.
The demo keeps changing; we diff it regularly and add the changes
(`docs/notes/demo-backend/sync-log.md`). The admin frontend is **React + Vite + TypeScript**,
served by the monolith.

Still OPEN (see `.claude/rules/cross-repo.md` §4):

- whether `extraspace-tech/cms` becomes private (it is PUBLIC today)
- the API freeze policy after the first store release

Scan notes from 2026-10-09: `docs/notes/demo-backend/`, `docs/notes/old-backend/`, `docs/notes/sitelink/`,
`docs/notes/client-artifacts/` (the client's own Claude prototypes: Cowork Manager, ES App, Admin —
a third rule reference; where they disagree with the demo is an OPEN question for the PM, see
`.claude/rules/cross-repo.md` §4 item 8).

## 2. Repo map

| Folder (relative to `Claude/`) | Purpose | Runtime shape | Build file | Local port | Remote (branch) |
|---|---|---|---|---|---|
| `../CMS/` | **The new C# monolith**: mobile API, admin API, React admin UI and jobs in one repo and one deployable (owner, 2026-10-09) | ASP.NET Core monolith (MVC controllers), .NET 10, EF Core + Npgsql, PostgreSQL, Hangfire; admin UI React + Vite + TS | `ExtraSpace.slnx` (S0-1, branch `s0-1-network-database`, uncommitted); CDK app `infra/ExtraSpace.Infra` | not chosen yet | `extraspace-tech/cms` (main) 🔴 PUBLIC repo |
| `../API/` | **Not used** (owner, 2026-10-09: everything goes in `../CMS`). README only | — | — | — | `extraspace-tech/es-api` (main) |
| `../Backend Demo/backend/` | **Feature reference, read only, never integrated**: the PM's demo + the handover spec in its `.claude/backend-spec/` | Node 20, Express 5, Prisma, PostgreSQL, Redis; React admin-ui + web-app | `package.json` | 4000 (admin-ui 5173, web-app 5174) | `extraspace-tech/backend` (main), private |
| `../../Extra Space old/extraspace-backend/` | **Business-rule reference, read only, never touched**: the old production system. Never run it. | .NET Core 3.1 Web API + Razor MVC CMS, MySQL, Redis, Hangfire | `ExtraSpaceAPI/ExtraSpaceAPI.sln`, `ExtraSpaceCMS/ExtraSpaceCMS.sln` | — | `sgcodigo/extraspace-backend` (`yes-production` = SG, `mys-yes-production` = MY) 🔴 live secrets committed |
| `../../Extra Space old/ExtraSpaceAPI`, `…/ExtraSpaceCMS` | Non-git snapshot of the old code; holds newer EarnPoints notes | — | — | — | not a git repo |

Clients and external systems of the **new** system (details: `.claude/rules/cross-repo.md`): our
Flutter app (`/api/v1/*`), the admin back office (React SPA), SiteLink CCWs 3.5, Stripe, and AWS
(ECS Fargate + ALB + WAF, RDS PostgreSQL + RDS Proxy, SES, Secrets Manager; ElastiCache Valkey from S1; S3 from S2; sizing = cost estimate v4). The email, SMS and
push providers are decided in the design spec. The old system's integrations (Noke, UniqGift, WOGI,
SMSGlobal, Firebase) are not in scope unless the owner adds them.

## 3. The spec is a feature reference

The handover spec lives at `../Backend Demo/backend/.claude/backend-spec/` (27k lines, prepared
2026-10-08 from the demo). Read in this order: `README.md` → `00-architecture-and-conventions.md` →
the `features/NN-*.md` doc for the feature. `reference/endpoints.md` maps the demo's 178 routes to
their doc. The skill `backend-spec` repeats the reading procedure.

Use the spec for what a feature does: its business rules, algorithms, edge cases and acceptance
tables. Most of these will carry over.

**The spec does not bind us** on routes, JSON shapes, error codes, the schema, env var names, money
as `double` with JS rounding, or the port plan's phases and parity checks. Each design or plan says
which spec rules it keeps and which it changes.

Never copy a demo defect. Known defects:
- email-only login
- missing ownership checks on `/me/spaces` and reservation cancel
- storage payments trusted on the client's word
- an API key hard-coded in the web-app

**API freeze policy (recommended, owner to confirm):** our `/api/v1` changes freely until the first
store release of the app. After that, changes are additive only, and a breaking change goes to
`/api/v2`.

## 4. Working model

- The user names the task. New code goes to `../CMS`. Build the
  csproj before reporting done.
- Before designing any change:
  - read `.claude/rules/cross-repo.md` (always loaded)
  - read the spec feature doc as a reference
  - if the old system has the feature, read `docs/notes/old-backend/`
  - name every client (Flutter, admin UI, cron, Stripe) a contract change affects
- `../Backend Demo/backend` is **read-only**: a hook blocks every Edit/Write under it. Read it for
  behaviour; copy what you need into `docs/` here.
- `../../Extra Space old/` is **read-only** too (hook), and it holds 🔴 live production secrets
  committed in git. Rules: `.claude/rules/old-backend.md`.
- Cross-repo edits are allowed only in the monolith repo. Each task gets its own branch and commit
  there; report which files changed and which csproj was built.
- The schema is ours: EF Core migrations in the monolith repo. On shared environments they run by
  hand, from a script kept in `docs/migrations/`. The design spec fixes the details.
- The build order comes from the design spec and the implementation plan in
  `docs/superpowers/`, not from the demo's port plan.

## 5. Git rule

`git` at the root reports the **context repo**. Code commits use `git -C ../CMS`. Never commit or
push unless the user asks in that turn, and then hand over the message and stop (memory
`feedback-user-commits-and-tests`). The user runs several sessions on the same trees; check
`git -C ../CMS status` before describing a diff. 🔴 `extraspace-tech/cms` is public: never commit a
secret, a connection string or a real customer row.

## 6. Context rule

Per-repo conventions live in `.claude/rules/cms.md` (the monolith), `.claude/rules/backend-demo.md`
(the demo) and `.claude/rules/old-backend.md` (old production).

Design defaults. They come from the spec, and we keep them because they are sound; only the owner
changes them:

- No card data, ever. Stripe only through hosted Checkout + one signature-verified webhook. A new
  payment flow needs business approval.
- SiteLink: never a card-carrying operation. Record payments with `PaymentSimpleCashWithSource`.
  Request field names exactly as in the WSDL (`docs/notes/sitelink/`).
- Business dates use the site's time zone (`site.time_zone`, default `Asia/Singapore`; MY sites `Asia/Kuala_Lumpur`); storage is UTC.
- Money is exact: `numeric` in PostgreSQL and `decimal` in C#. The rounding rule is set in the
  design spec.
- Every BizPlus credit change goes through one wallet service (single writer).
- Migrations run by hand on shared environments.

`.mcp.json` has two read-only MySQL servers pointing at the **old system's PRODUCTION** databases:
`mysql-dev` = SG production (misleading name), `mysql-prod-my` = MY production. Aggregate reads only,
when the owner asks (`.claude/rules/old-backend.md`). A read-only `postgres-dev` for our own staging
is still owed.

🔴 **Production DB hard rule (carried over from Porsche, owner 2026-10-06).** A production database
MCP, if one is ever added, is for debugging reads only. Never write to production. Never run a walk
on it: no local API booted against production data or secrets, no production endpoint that writes.
Walks run on staging. When production needs a change, write the script and stop; the owner runs it
by hand. This applies to the main session and to every subagent, and no earlier approval overrides it.

## 7. Docs rule

Project documents live under `docs/` at the root: `docs/plans/` (plans and briefs, templates
`docs/plans/TEMPLATE.md` and `TEMPLATE-engineer.md`), `docs/Handover/`, `docs/migrations/`,
`docs/postman/`, `docs/superpowers/` (specs and plans from the superpowers skills), `docs/notes/`,
`docs/meetings/`.

## 8. Clean-root rule

AI tooling lives only in `.claude/` and `.cursor/` (plus the gitignored `.mcp.json`). Never create
`.agents/`, `AGENTS.md`, a root `CLAUDE.md`, or any tool folder inside `../CMS` or `../API`. Never
write a new `.md` inside a code repo: notes, plans, handovers, and migration scripts go under `docs/`
here (a PreToolUse hook blocks this). Auto-memory lives in `.claude/memory/` (linked from
`~/.claude/projects/<encoded path>/memory`); commit it together with context changes.

Exception, by the client's own choice: `../Backend Demo/backend` already holds a `CLAUDE.md`,
`.claude/backend-spec/` and `.agents/`. Leave them as they are. Nothing under `../../Extra Space old/`
is ever edited.

There is no root `AGENTS.md`. Cursor reads this same file through `.cursor/rules/workspace.mdc`.

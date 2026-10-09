# Extra Space workspace

## 1. What this is

This folder (`Claude/`) is the **private context repo** and the **workspace root** for the Extra Space
re-implementation. It carries all AI tooling (`.claude/`, `.cursor/`), the cross-repo knowledge, the
shared docs, and the auto-memory. The code repositories are its **siblings** under
`/Users/waiyanmin/Projects/Extra Space/`; they are their own git repos and are never tracked here.

**Always start Claude Code and Cursor here, in `Claude/` — never inside a code repo.** Settings,
rules, MCP servers, hooks and auto-memory are all keyed to this folder. Starting in a code repo
loses every one of them.

Background: the client (ExtraSpace Asia, self-storage) has an existing Node/TypeScript backend. They
want it rebuilt **from scratch in C# / ASP.NET Core with new logic**. The existing Node repo stays as
the reference and carries a feature-by-feature handover spec.

## 2. Repo map

| Folder (relative to `Claude/`) | Purpose | Runtime shape | Build file | Local port | Remote (branch) |
|---|---|---|---|---|---|
| `../CMS/` | **The new C# repo: CMS + API** (target of all new work) | ASP.NET Core Web API (planned: .NET 10, EF Core + Npgsql, Redis) | not created yet — fill in at port-plan phase 1 | not chosen yet | `extraspace-tech/cms` (main) 🔴 PUBLIC repo |
| `../Backend Demo/backend/` | **Reference only**: the client's existing Node/Express/Prisma backend + the handover spec in its `.claude/backend-spec/` | Node 20, Express 5, Prisma, PostgreSQL, Redis | `package.json` (`npm run dev`) | 4000 (admin-ui 5173, web-app 5174) | `extraspace-tech/backend` (main), private |
| `../API/` | Empty folder, purpose not decided yet (2026-10-09) | — | — | — | not a git repo |

Clients that must keep working unchanged: the Flutter mobile/web app (`/api/v1/*`), the React
admin UI (`/admin`, `/admin/api/*`), cron triggers (`/api/cron/*`) and the Stripe webhook.
External systems: SiteLink (SOAP), Stripe, PostgreSQL, Redis. Details: `.claude/rules/cross-repo.md`.

## 3. The spec is the contract

The handover spec lives at `../Backend Demo/backend/.claude/backend-spec/` (committed in the
client's repo, 27k lines, prepared 2026-10-08). Read in this order: `README.md` →
`00-architecture-and-conventions.md` → `13-csharp-port-plan.md` → the `features/NN-*.md` doc for
the feature. `reference/endpoints.md` maps all 178 routes to their doc; `reference/schema.sql` is
the frozen PostgreSQL DDL; `reference/openapi.json` is the mobile surface. The skill
`backend-spec` (`.claude/skills/backend-spec/`) repeats the reading procedure.

"New logic" (owner, 2026-10-09) means the C# code is written fresh, not ported line by line. The
routes, JSON shapes, status codes, error codes and the database schema still stay as the spec says,
because the clients are not changing. When the owner decides to change a contract, write the
decision into the plan and into `.claude/rules/cross-repo.md`.

## 4. Working model

- The user names the task. New code goes to `../CMS`. Build the csproj before reporting done.
- Before designing any change, read `.claude/rules/cross-repo.md` (always loaded) and the feature
  doc in the spec. Name every client (Flutter, admin UI, cron, Stripe) a contract change affects.
- `../Backend Demo/backend` is **read-only**: a hook blocks every Edit/Write under it. Read it for
  behaviour; copy what you need into `docs/` here.
- Cross-repo edits are allowed only in `../CMS`. Each task gets its own branch and commit there;
  report which files changed and which csproj was built.
- One migration script per schema change in `docs/migrations/`. The schema is frozen by the spec:
  additive changes only, and the header says which client reads the table.
- Port plan phases (`13-csharp-port-plan.md` §2) are the default build order; each phase ends with
  the parity check in §3.

## 5. Git rule

`git` at the root reports the **context repo**. Code commits use `git -C ../CMS`. Never commit or
push unless the user asks in that turn, and then hand over the message and stop (memory
`feedback-user-commits-and-tests`). The user runs several sessions on the same trees; check
`git -C ../CMS status` before describing a diff. 🔴 `extraspace-tech/cms` is public: never commit a
secret, a connection string or a real customer row.

## 6. Context rule

Per-repo conventions live in `.claude/rules/cms.md` (the C# repo) and `.claude/rules/backend-demo.md`
(the reference). Cross-cutting facts from the spec: PostgreSQL schema frozen (`reference/schema.sql`);
money columns are `double precision` with JS half-up rounding; business dates Asia/Singapore, stored
UTC; no card data ever; Stripe only through hosted Checkout + the one verified webhook; every BizPlus
credit change goes through the wallet service. Migrations run by hand. The `postgres-dev` MCP (once
installed) is read-only.

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
`.claude/backend-spec/` and `.agents/`. Leave them as they are.

There is no root `AGENTS.md`. Cursor reads this same file through `.cursor/rules/workspace.mdc`.

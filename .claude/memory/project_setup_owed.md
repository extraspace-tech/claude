---
name: project-setup-owed
description: ⭐ RESUME — S0-1 done + pushed; S0-2 merged (PR #1); S0-2b on main; S0-3 on main (9c678ce); S0-4 built on branch s0-4-admin-backend (uncommitted), next S0-5 plan; plus open owner/IT items.
metadata:
  type: project
---

Open after the 2026-10-09 setup (copied from Porsche-AI). Tick off and delete lines as they close.

**RESUME (2026-10-12, end of day):**
- **S0 spec APPROVED** 2026-10-12. Plans: `docs/superpowers/plans/2026-10-12-s0-plan-index.md` (S0-1…S0-6) with a "Carry-overs from S0-2" section that S0-3…S1 must read first.
- **S0-1 DONE** (plan `2026-10-12-s0-1-network-database.md`): skeleton + CDK network/database; **staging network + database LIVE** in the client account since 2026-10-12 (≈ US$128/mo running); DB users `es_app` / `es_readonly` + schema `hangfire` created (guide B5). On `main` (`84b8475`). Production stacks written and tested, not deployed.
- **S0-2 DONE** (plan `2026-10-12-s0-2-api-platform.md`): API platform, 130 tests (Api 80, Engines 18, Infra 32). Merged to `main` via **PR #1** (`9b0f86b`). Local run verified (Swagger at `/swagger` is nearly empty until S0-3 adds endpoints). Migration script `docs/migrations/2026-10-12-initial-platform.sql` NOT yet run on staging (S0-6 runs it before the first deploy).
- **S0-2b DONE (uncommitted, owner pushes)** 2026-10-12: owner switched endpoints from MVC to **Minimal APIs** to learn them. Branch `s0-2b-minimal-apis` in `../CMS`, 134 tests (Api 84). Adds `AddValidation()`, one JSON option set, `IEndpointMapper` (test host only), `JsonProblemWriter` (JSON problem for any Accept), `.WithEnumGuard()`, enums reject numbers, `EndpointDataAccess` architecture rule. Learning guide for the owner: `docs/notes/cms/minimal-apis-vs-mvc.md` (extend it per new concept).
- Client progress page (2026-10-13, private until the owner shares it): https://claude.ai/artifact/F3Td9wxGtbotcjPpoPoWzf — republish from a copy of its HTML when the status changes.
- **S0-3 DONE, committed on `main` as `9c678ce`** (tree identical to the reviewed tree) 2026-10-13. Local walk: 11/11 PASS (local Docker DB). Postgres MCP: `postgres-local` works; `postgres-staging` waits for the owner to fill the `es_readonly` password and open the tunnel. Tests: Api 161, Engines 18, Infra 32; 0 warnings. It ran subagent-driven: 5 Opus tasks, each reviewed, then a whole-branch review and one fix wave. Ledger with every ruling: `.superpowers/sdd/2026-10-13-s0-3-customer-identity/progress.md` (gitignored). Migration script: `docs/migrations/2026-10-13-customer-identity.sql`, not run on staging (S0-6). Carry-overs are in the plan index under "Carry-overs from S0-3". Docs updated: `cms.md` "Built so far (S0-3)", spec §4.4/§5.1/§6.1 "As built", guide §6. 
- **S0-4 BUILT** 2026-10-13 committed + pushed by the owner on `main` as `6a8a16e`: plan `docs/superpowers/plans/2026-10-13-s0-4-admin-backend.md`, 5 tasks each reviewed + whole-branch review ACCEPT + one fix wave; Api 278 / Engines 18 / Infra 32 tests; local walk 14/14 PASS. Ledger: `.superpowers/sdd/2026-10-13-s0-4-admin-backend/progress.md`. Migration script `docs/migrations/2026-10-13-admin-tables.sql` (not run on staging). Carry-overs in the plan index ("Carry-overs from S0-4"). Open owner question: Entra B2B guests / company-domain limit. **NEXT:** S0-5 plan (admin UI shell), then S0-6.
- **PM UPDATE 2026-10-13:** (1) self-storage only for now, BizPlus (S2, S3) deferred, S4 Extras stays in; (2) no Microsoft Entra: staff sign in with an emailed one-time code; (3) Stripe Connect for payments, model OPEN (cross-repo §4 open decision 10).
- **S0-4b BUILT** 2026-10-13 on branch `s0-4b-staff-email-code` in `../CMS` (uncommitted; owner commits): plan `docs/superpowers/plans/2026-10-13-s0-4b-staff-email-code.md`. One code engine with a purpose (`login_code`, `ILoginCodes`), staff routes `/admin/api/auth/code` + `/code/verify`, Entra + dev-login removed, `Admin:AllowedEmailDomains`, `displayName`. Api 288 tests, local walk 12/12 PASS, review ACCEPT. Migrations `StaffEmailCode` (hand-written rename) + `DropEntraObjectId`; script `docs/migrations/2026-10-13-staff-email-code.sql` (not run on staging). 🔴 Open owner decision 12: harden staff codes before production (guess budget, lock-out). **NEXT:** S0-5 plan (admin UI shell with a login screen), then S0-6.
- **S0-4b is on `main` as `583118a`.** **S0-5 BUILT 2026-10-13** on branch `s0-5-admin-ui-shell` in `../CMS` (uncommitted; owner commits): plan `docs/superpowers/plans/2026-10-13-s0-5-admin-ui-shell.md` (17 decisions approved), 6 tasks each reviewed + whole-branch review + one fix wave; Api 332 tests, admin UI 96 tests (Vitest), local walk 20/20 PASS at API level. 🔴 Owed by the owner: the BROWSER walk (`npm run build` in `admin-ui/`, run the API, open `http://localhost:5080/admin`, sign in, check the console shows no CSP report; also `npm run dev` on 5173). Ledger with every ruling: `.superpowers/sdd/2026-10-13-s0-5-admin-ui-shell/progress.md`. Contract changes: strict JSON numbers on every route, `Problem` schema on every operation, `isOwner` on `/me`, 409 `ROLE_NAME_TAKEN`, committed `admin-ui/openapi.json` (update with `UPDATE_OPENAPI=1` + `npm run gen:api`). TypeScript pinned 6.0.3. Carry-overs in the plan index ("Carry-overs from S0-5"). **NEXT:** S0-6 plan (Docker with a Node 24 stage, CI, EsEdge/EsApp stacks, staging deploy + walk).
- (old) **NEXT: write the S0-3 plan** (after S0-2b is merged; read the S0-2b carry-overs: groups `.WithEnumGuard()`, `Program.cs` maps groups only) (customer sign-in: email code, JWT + refresh rotation, `/api/v1/me`, rate limits, Hangfire + job tracing, SES login-code email, IdentityHousekeeping). Then S0-4 (needs Entra registration for live sign-in), S0-5, S0-6 (CI/CD on GitHub Actions + staging app deploy).
- How S0-2 ran (repeat it): subagent-driven development, Opus implementer per task + Opus code-reviewer per task + scoped re-reviews + one final whole-branch review; agents never commit, so per-task diffs come from snapshot trees ([[feedback-sdd-without-commits]]).
- **AWS account facts and rules:** [[reference-aws-account]]. Never the `default` profile (Porsche); always `--profile extraspace --region ap-southeast-1`.
- Cost estimate **v4**: $1,019/month, budget ≈ $1,170 ([[reference-aws-cost-estimate]]). SG + MY at release. One client account holds staging and production (Vercel staging dropped).
- Client artifacts: `docs/notes/client-artifacts/` ([[reference-client-artifacts]]). S1–S3 specs read the demo spec, the client-artifact notes and the old-backend notes; conflicts go to the PM (cross-repo §4, open decision 8).
- Not checked: client-artifact rules vs the live Flutter app (repo not in the workspace). Do it before the S1 spec.
- The context repo has many uncommitted changes. The owner commits.

**Open owner / client-IT items (spec §12):**
- make `extraspace-tech/cms` private (PUBLIC today)
- Entra ID app registration; confirm M365
- SES sender + SPF/DKIM
- host name
- API freeze policy
- in-app account deletion (S1)
- confirm with the business that MY customer data may be hosted in Singapore (PDPA)
- ask the PM which source wins where the demo and the client's artifacts disagree (cross-repo §4 open decision 8: late fees, auto-billing, refunds incl. GST, booking length/hours, packages, rewards tiers, insurance, lease status)
- SiteLink IP allowlisting (S1)
- SiteLink PDFs: password-protected, so ask for unprotected copies or the password

**To verify at the first `claude` start in `Claude/`:**
- `~/.claude/projects/` gets a folder named `-Users-waiyanmin-Projects-Extra-Space-Claude` (the symlink was created in advance; if the real name differs, re-link per README).
- `permissions.additionalDirectories` with relative paths (`../CMS`, `../API`, `../Backend Demo`) lets Claude edit `../CMS` without a prompt. If not, switch to absolute paths in `settings.local.json`.
- The PreToolUse hook blocks a Write under `../Backend Demo` and a new `.md` under `../CMS` (test with a scratch file).
- `/code-review`, `clarification-checklist`, `backend-spec`, `api-debug-and-run` show in the skill list; `code-reviewer` and `dev-walker` show in the agent list.

**Owner installs (said 2026-10-09 "I will install necessary skills and MCP"):** MCP servers into `.mcp.json` (postgres read-only on staging, figma-console, serena), plugins already listed in `settings.json` `enabledPlugins`.

**Owner decisions needed (grew on 2026-10-09 after the old-system scan; list in `.claude/rules/cross-repo.md` §4):**
- ~~What the monolith replaces first~~ DECIDED 2026-10-09: demo features; old system untouched (no migration from it). Malaysia in scope? still open.
- ~~DB engine~~ DECIDED 2026-10-09: PostgreSQL on RDS with OUR OWN schema (brand-new project; the demo schema is only a reference, no data carried over). DONE 2026-10-13: `postgres-local` + `postgres-staging` MCP (Postgres MCP Pro, restricted) in `.mcp.json` / `.cursor/mcp.json`; the staging entry needs the owner to fill the `es_readonly` password (placeholder `REPLACE_WITH_ES_READONLY_PASSWORD`).
- ~~Which `/api/v1/*` contracts are frozen~~ SETTLED 2026-10-09: nothing is frozen to the demo. Open: confirm our own freeze policy after the first store release (additive-only + `/api/v2` + min-app-version check).
- Which repo holds the monolith: `../CMS` (public) or `../API` (es-api).
- SiteLink PDFs the owner attached were password-protected; ask for unprotected copies or the password.
- Frontend framework for the admin UI (user: "you can choose").
- Money `double` (spec) vs `decimal` (old DB).
- Relation of Lucy/Iviva + MongoDB "Core" to the old Codigo system; who owns customer identity (old: passwords live in SiteLink).
- 🔴 Old repo secrets: committed live keys (Stripe live, AWS, DB, SiteLink, JWT, AES, SendGrid, Firebase) in `sgcodigo/extraspace-backend` and the API image build logs (`RUN cat appsettings.json`). Told the owner 2026-10-09 to rotate; owner decides. One scan subagent's transcript (session scratchpad, 2026-10-09) contains a few connection strings it printed by mistake; none went into `docs/`.
- `Codigo.Crypto.dll` (closed) holds the admin password hash + AES algorithm needed to read old encrypted columns.
- What `../API` (`extraspace-tech/es-api`) is for next to a monolith.
- C# solution layout, project names, local port, Swagger / health paths → fill the TBD lines in `.claude/rules/cms.md`, `.claude/skills/api-debug-and-run/SKILL.md`, `.vscode/launch.json`, `.vscode/tasks.json`, `.claude/dev-ports`.
- Which spec contracts the "new logic" may change (routes / shapes are frozen by default) → `.claude/rules/cross-repo.md` §4.
- Whether the spec's "port acceptance tests as xUnit" rule stands (it differs from the Porsche "no tests" rule; the setup assumes it stands).

**Later:** rewrite `.claude/skills/code-review/reviewer-agent.md` and `codigo-reviewer.md` with this repo's own conventions (they carry a Porsche note at the top); add Extra Space defects to `.claude/rules/engineering-checklist.md` as they are found.

**Second account (asked 2026-10-09):** run Extra Space under `CLAUDE_CONFIG_DIR=~/.claude-extraspace` (docs: authentication.md "Log in with multiple accounts"). Seed the dir with `~/.claude/CLAUDE.md`, `settings.json`, `agents/`; `/login` with account B; then re-link memory under `~/.claude-extraspace/projects/<name>/memory` (the link under `~/.claude/projects/` only serves account A). VS Code: launch with the env var set; one account per VS Code process (inferred). Not done yet.
- 2026-10-09: `~/.claude-extraspace` seeded (CLAUDE.md, settings.json, agents/). Wrapper `~/.local/bin/claude-by-project` sets `CLAUDE_CONFIG_DIR` when started under `Extra Space/`; VS Code uses it through the user setting `claudeCode.claudeProcessWrapper`. 🔴 Assumes the extension starts Claude with cwd = the workspace folder; confirm at first start (`/status` shows the config dir). Documented side effects of a wrapper: the extension skips the "conversation open elsewhere" check and does not restore plan mode. `/login` with account B still owed.
- 2026-10-09 skills + MCP copied: `.mcp.json` and `.cursor/mcp.json` written (gitignored). `mysql-dev` has EMPTY host / user / password / database: the owner fills them once the database exists ("I will add them once the db is set up"); it fails to connect until then. `figma-console` and `serena` are ready. `mysql-prod` was NOT copied (Porsche bastion tunnel). Account B (`~/.claude-extraspace`) now has all 8 plugins. `.cursor/skills/` (7 generic skills) and `.serena/project.yml` copied.
- RESOLVED 2026-10-09 (owner chose PostgreSQL; the PostgreSQL-based rules stand, no rewrite needed): the owner said "mysql mcp", but the handover spec and the rules written on 2026-10-09 (`cross-repo.md`, `cms.md`, `engineering-checklist.md`, both agents, the reviewer prompts) assume the frozen **PostgreSQL** schema and name the MCP `postgres-dev`. Ask which database the new C# backend uses; if MySQL, rewrite those files (schema no longer frozen by `reference/schema.sql`, enum and id conventions change).

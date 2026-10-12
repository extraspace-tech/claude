---
name: project-setup-owed
description: ⭐ RESUME — S0-1 DONE 2026-10-12 (staging network + DB live, ≈ US$128/mo running; DB users created); code on branch s0-1-network-database uncommitted; NEXT = owner commits S0-1, then the S0-2 plan; plus open owner/IT items.
metadata:
  type: project
---

Open after the 2026-10-09 setup (copied from Porsche-AI). Tick off and delete lines as they close.

**RESUME (2026-10-12):**
- **S0 spec APPROVED** 2026-10-12. Plans: `docs/superpowers/plans/2026-10-12-s0-plan-index.md` (6 plans S0-1…S0-6). Only S0-1 is written so far.
- **S0-1** (`docs/superpowers/plans/2026-10-12-s0-1-network-database.md`), branch `s0-1-network-database` in `../CMS`, NOTHING committed:
  - Tasks 1–3 (skeleton, CDK app, network + data stacks): done by an implementer, verdict **ACCEPT**. Build 0 errors / 0 warnings; tests 32/32. The 5 deviations are in the plan's "Implementation notes".
  - Task 4 (`cdk diff` staging, read-only): done.
  - Task 5: **staging deployed 2026-10-12** (PM approved the ≈ US$128/mo; the owner ran `cdk deploy` in their own terminal because Claude Code blocks `--require-approval never`). Cost is running from 2026-10-12.
  - Task 6: DB users `es_app` / `es_readonly` + schema `hangfire` created on staging, TLS forced (checked). RDS needs `GRANT es_app TO postgres` … `REVOKE` around `CREATE SCHEMA … AUTHORIZATION es_app` (guide B5).
  - **NEXT: the owner commits S0-1 in `../CMS` and pushes the branch (owner approved pushing while the repo is still PUBLIC, 2026-10-12, so the PM can see progress; still never an account id, endpoint or secret in the repo), then write the S0-2 plan.**
  - Production stacks are written and tested but not deployed (deploy before go-live). Before the first production deploy, verify the RDS Proxy target-group tags (CloudFormation schema allows them; checked 2026-10-12).
- **After S0-1:** write the S0-2 plan (API platform). S0-6 infra can run in parallel.
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
- ~~DB engine~~ DECIDED 2026-10-09: PostgreSQL on RDS with OUR OWN schema (brand-new project; the demo schema is only a reference, no data carried over). Owed: swap `mysql-dev` in `.mcp.json` / `.cursor/mcp.json` for a read-only `postgres-dev` pointed at staging (owner fills credentials).
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

---
name: project-setup-owed
description: ⭐ RESUME — things the 2026-10-09 workspace copy could not finish or verify: first start check (hooks, additionalDirectories, memory folder name), MCP install, C# solution facts (TBD lines), reviewer prompt rewrite, decisions the owner must make.
metadata:
  type: project
---

Open after the 2026-10-09 setup (copied from Porsche-AI). Tick off and delete lines as they close.

**RESUME (2026-10-09 evening):**
- The brainstorm finished for S0. The spec is `docs/superpowers/specs/2026-10-09-s0-foundation-design.md` (316 lines).
- It is WAITING for owner review. The next step after approval is the `superpowers:writing-plans` skill: the S0 implementation plan, split into parallel implementer pieces with their own file sets.
- All decisions are in `.claude/rules/cross-repo.md` §4.
- AWS cost estimate is at **v3** for SG + MY on one platform: launch $437/month, budget ceiling ≈ $500, about $270–330 after tuning. Page version 3. See [[reference-aws-cost-estimate]].
- The PM confirmed **SG + MY at release** (it replaced "Singapore only").
- The client's own Claude artifacts were extracted to `docs/notes/client-artifacts/`. See [[reference-client-artifacts]].
- Next sub-project specs (S1–S3) must read three references: the demo spec, the client-artifact notes and the old-backend notes. Where they disagree, ask the PM (cross-repo §4, open decision 8).
- Saved 2026-10-09 wrap-up: redacted artifact sources in `docs/notes/client-artifacts/source/`, cost page source in `docs/notes/aws-cost/`.
- Not checked: client-artifact rules vs the live Flutter app (repo not in the workspace). Do it before the S1 spec.
- Nothing is committed; the context repo has uncommitted changes.

**Open owner / client-IT items (spec §12):**
- make `extraspace-tech/cms` private (PUBLIC today)
- AWS account(s) and who owns them
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

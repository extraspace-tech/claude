---
name: project-setup-owed
description: ⭐ RESUME — things the 2026-10-09 workspace copy could not finish or verify: first start check (hooks, additionalDirectories, memory folder name), MCP install, C# solution facts (TBD lines), reviewer prompt rewrite, decisions the owner must make.
metadata:
  type: project
---

Open after the 2026-10-09 setup (copied from Porsche-AI). Tick off and delete lines as they close.

**To verify at the first `claude` start in `Claude/`:**
- `~/.claude/projects/` gets a folder named `-Users-waiyanmin-Projects-Extra-Space-Claude` (the symlink was created in advance; if the real name differs, re-link per README).
- `permissions.additionalDirectories` with relative paths (`../CMS`, `../API`, `../Backend Demo`) lets Claude edit `../CMS` without a prompt. If not, switch to absolute paths in `settings.local.json`.
- The PreToolUse hook blocks a Write under `../Backend Demo` and a new `.md` under `../CMS` (test with a scratch file).
- `/code-review`, `clarification-checklist`, `backend-spec`, `api-debug-and-run` show in the skill list; `code-reviewer` and `dev-walker` show in the agent list.

**Owner installs (said 2026-10-09 "I will install necessary skills and MCP"):** MCP servers into `.mcp.json` (postgres read-only on staging, figma-console, serena), plugins already listed in `settings.json` `enabledPlugins`.

**Owner decisions needed:**
- What `../API` is for (empty folder).
- C# solution layout, project names, local port, Swagger / health paths → fill the TBD lines in `.claude/rules/cms.md`, `.claude/skills/api-debug-and-run/SKILL.md`, `.vscode/launch.json`, `.vscode/tasks.json`, `.claude/dev-ports`.
- Which spec contracts the "new logic" may change (routes / shapes are frozen by default) → `.claude/rules/cross-repo.md` §4.
- Whether the spec's "port acceptance tests as xUnit" rule stands (it differs from the Porsche "no tests" rule; the setup assumes it stands).

**Later:** rewrite `.claude/skills/code-review/reviewer-agent.md` and `codigo-reviewer.md` with this repo's own conventions (they carry a Porsche note at the top); add Extra Space defects to `.claude/rules/engineering-checklist.md` as they are found.

**Second account (asked 2026-10-09):** run Extra Space under `CLAUDE_CONFIG_DIR=~/.claude-extraspace` (docs: authentication.md "Log in with multiple accounts"). Seed the dir with `~/.claude/CLAUDE.md`, `settings.json`, `agents/`; `/login` with account B; then re-link memory under `~/.claude-extraspace/projects/<name>/memory` (the link under `~/.claude/projects/` only serves account A). VS Code: launch with the env var set; one account per VS Code process (inferred). Not done yet.
- 2026-10-09: `~/.claude-extraspace` seeded (CLAUDE.md, settings.json, agents/). Wrapper `~/.local/bin/claude-by-project` sets `CLAUDE_CONFIG_DIR` when started under `Extra Space/`; VS Code uses it through the user setting `claudeCode.claudeProcessWrapper`. 🔴 Assumes the extension starts Claude with cwd = the workspace folder; confirm at first start (`/status` shows the config dir). Documented side effects of a wrapper: the extension skips the "conversation open elsewhere" check and does not restore plan mode. `/login` with account B still owed.
- 2026-10-09 skills + MCP copied: `.mcp.json` and `.cursor/mcp.json` written (gitignored). `mysql-dev` has EMPTY host / user / password / database: the owner fills them once the database exists ("I will add them once the db is set up"); it fails to connect until then. `figma-console` and `serena` are ready. `mysql-prod` was NOT copied (Porsche bastion tunnel). Account B (`~/.claude-extraspace`) now has all 8 plugins. `.cursor/skills/` (7 generic skills) and `.serena/project.yml` copied.
- 🔴 OPEN: the owner said "mysql mcp", but the handover spec and the rules written on 2026-10-09 (`cross-repo.md`, `cms.md`, `engineering-checklist.md`, both agents, the reviewer prompts) assume the frozen **PostgreSQL** schema and name the MCP `postgres-dev`. Ask which database the new C# backend uses; if MySQL, rewrite those files (schema no longer frozen by `reference/schema.sql`, enum and id conventions change).

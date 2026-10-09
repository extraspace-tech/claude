# Extra Space / Claude — private context repo and workspace root

This folder is the **workspace root** for the Extra Space re-implementation and the **private
context repo** that carries everything Claude Code and Cursor need but the code repos deliberately
do not: AI rules, agents, skills, hooks, cross-repo knowledge, shared docs, and auto-memory. One
copy serves both laptops. The layout and workflow are copied from the Porsche-AI workspace
(2026-10-09).

**This must never be pushed to a client remote.** `extraspace-tech/cms` is a public repository.

## Target tree

```
Extra Space/
  Claude/                                git repo = this private context repo (START HERE)
    .git/  .gitignore  .gitattributes  README.md
    .claude/                             all Claude tooling
      CLAUDE.md                          workspace map + operating rules
      settings.json  settings.local.json hooks, plugins, permissions (sibling dirs allowed)
      dev-ports                          one local port per line; the Stop hook reaps orphaned apps on them
      agents/                            code-reviewer, dev-walker (implementer is global: ~/.claude/agents)
      rules/                             model-routing, cross-repo, engineering-checklist, cms, backend-demo
      skills/                            clarification-checklist, code-review, backend-spec, api-debug-and-run
      scripts/                           plan gate scripts (Cursor hybrid workflow, not the default)
      memory/                            auto-memory (linked from ~/.claude/projects/…/memory)
    .cursor/                             all Cursor tooling: rules/*.mdc, mcp.json (gitignored) + mcp.example.json
    .mcp.json                            Claude MCP servers (gitignored) + .mcp.example.json
    .vscode/                             launch.json + tasks.json for the C# API (placeholders until phase 1)
    docs/                                plans, Handover, migrations, postman, superpowers, notes, meetings
  CMS/                                   extraspace-tech/cms (main) — the NEW C# repo: CMS + API. PUBLIC.
  Backend Demo/backend/                  extraspace-tech/backend (main) — Node reference + handover spec. READ ONLY.
  API/                                   empty, purpose not decided (2026-10-09)
```

Unlike Porsche-AI, the code repos are **siblings** of the context repo, not children. Claude reaches
them through `permissions.additionalDirectories` in `.claude/settings.json` and by `../CMS` paths.
They are not submodules and are never tracked here.

## Two rules that matter

**Start at the root.** Always open Claude Code and Cursor in `Claude/`, never in a code repo.
Settings, rules, hooks, MCP servers, and auto-memory are all keyed to this folder.

**Clean root.** AI tooling lives only in `.claude/` and `.cursor/` (plus the gitignored `.mcp.json`).
Never create `.agents/`, `AGENTS.md`, a `CLAUDE.md`, or any tool folder inside `../CMS` or `../API`,
and never add a new `.md` inside a code repo — notes, plans, handovers, and migration scripts go
under `docs/`. A PreToolUse hook enforces this and also blocks every edit under `../Backend Demo`.
The client's own `CLAUDE.md` / `.claude/backend-spec/` / `.agents/` inside `Backend Demo/backend`
stay as they are.

## The auto-memory folder name changes per machine

Claude Code names the project folder after the workspace's absolute path, with every character
that is not a letter or digit turned into a dash:

| Workspace path | Folder name |
|---|---|
| `/Users/you/Projects/Extra Space/Claude` | `-Users-you-Projects-Extra-Space-Claude` |
| `d:\Projects\Extra Space\Claude` | `d--Projects-Extra-Space-Claude` |

Do not guess it. Start Claude at the root once and run `ls ~/.claude/projects/` to see the name
that machine created, then link that folder's `memory` here.

## Setting up a new machine

### 1. Clone this context repo and the code repos side by side

```bash
mkdir -p ~/Projects/"Extra Space" && cd ~/Projects/"Extra Space"
git clone <this-repo-url> Claude
git clone https://github.com/extraspace-tech/cms.git CMS
mkdir -p "Backend Demo" && git clone https://github.com/extraspace-tech/backend.git "Backend Demo/backend"
```

The folder names are what `.claude/CLAUDE.md`, the hooks and `.vscode/` expect. Do not rename them.

### 2. Fill the two secret MCP files

```bash
cd Claude
cp .mcp.example.json .mcp.json
cp .cursor/mcp.example.json .cursor/mcp.json
# edit both: set the database URL, the Figma token and any <fill> tokens
```

### 3. Run Claude once at the root, then link auto-memory

```bash
claude          # start it once so it creates ~/.claude/projects/<name>/
```

**macOS / Linux**

```bash
ls ~/.claude/projects/                     # find the encoded name for Extra Space/Claude
rm -rf ~/.claude/projects/<name>/memory
ln -s ~/Projects/"Extra Space"/Claude/.claude/memory ~/.claude/projects/<name>/memory
```

**Windows (PowerShell)**

```powershell
Get-ChildItem "$env:USERPROFILE\.claude\projects"
Remove-Item -Recurse -Force "$env:USERPROFILE\.claude\projects\<name>\memory"
New-Item -ItemType Junction `
  -Path "$env:USERPROFILE\.claude\projects\<name>\memory" `
  -Target "$env:USERPROFILE\Projects\Extra Space\Claude\.claude\memory"
```

### 4. Global files this workspace relies on (not in this repo)

- `~/.claude/CLAUDE.md` — "Restate my request", "Roles and models" (Fable main, Opus subagents).
- `~/.claude/agents/implementer.md` — the Opus implementer agent.
- `~/.claude/settings.json` — `effortLevel: high`, `modelSettings` for Opus 5.5.

## Secrets this repo does not carry

- `.mcp.json` and `.cursor/mcp.json` (database URL / password, Figma token; use the `.example` twins)
- `docs/postman/*.postman_environment.json`
- any `.env`, `appsettings.Development.json`, `*.pem`

Move those between machines through a password manager, never through this repo.

## Daily use

```bash
git pull          # start of a session on either laptop
git add -A && git commit -m "context: <what changed>" && git push
```

Memory files change on their own as Claude writes them. **Pull before you start.**

Commit code changes with `git -C ../CMS …`; those go to the client remote, not here.

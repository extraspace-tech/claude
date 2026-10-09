---
name: project-workspace-layout
description: Extra Space workspace = Claude/ (context repo, start here) with sibling code repos CMS/ (new C#, public), Backend Demo/backend (Node reference + spec, read-only), API/ (empty). Set up 2026-10-09 by copying the Porsche-AI flow.
metadata:
  type: project
---

Set up 2026-10-09 at the user's request: "do the same claude set up for another project … the client wants to start from scratch with new logics … `/Users/waiyanmin/Projects/Extra Space/Claude` is where you'll live and manage the multiple projects."

- `Claude/` = context repo and workspace root (`.claude/`, `.cursor/`, `docs/`, memory). Not a client repo; never push it to the client org.
- `../CMS` = `extraspace-tech/cms` (public, "CMS + API in C#"), the new repo. Empty except README on 2026-10-09 (one commit).
- `../Backend Demo/backend` = `extraspace-tech/backend` (private), the Node reference; handover spec at `.claude/backend-spec/` (commit `6be4474`, 2026-10-08, "for a C# re-implementation"). A PreToolUse hook blocks every edit there.
- `../API` = empty folder, purpose not decided.
- Code repos are siblings of the context repo (unlike Porsche where they were children); `.claude/settings.json` lists them in `permissions.additionalDirectories` (🔴 not verified at first start yet, see [[project-setup-owed]]).
- Memory link: `~/.claude/projects/-Users-waiyanmin-Projects-Extra-Space-Claude/memory` → `Claude/.claude/memory` (created 2026-10-09; confirm the encoded name after the first start).
- Local tools on this machine: `dotnet 10.0.400`, `node v24.18.0`.
- VS Code: open `Claude/extra-space.code-workspace` (Claude/ is the first root) or the `Claude/` folder itself. Never the parent `Extra Space/` folder: settings, hooks and memory would not load. 🔴 Multi-root + Claude Code extension picking the first root is not verified yet; confirm at first start (`.claude/CLAUDE.md` content visible in the first reply).

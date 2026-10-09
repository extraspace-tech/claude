---
name: code-review
description: Use when the user asks for a code review, PR review, or to check code quality on any file or set of changes. Dispatches a dedicated reviewer subagent (separate agent = less bias) across 5 priority categories in order — Security, Error Handling, Performance, Code Quality, Testing. Includes ASP.NET Core / EF Core / PostgreSQL edge cases; the reviewer prompts were copied from the Porsche workspace and still name some Porsche-only conventions (see the note at the top of each). Pass `codigo` (or `company`/`omni`) to run the company-mandated Omni-Architect 360° reviewer instead.
---

# Code Review Skill

## When This Skill Activates

Trigger when the user says any of:
- "review my code / changes / PR"
- "check this before I raise a PR"
- "do a code review on X"
- "review the diff / staged changes"

## Choosing the reviewer

Two reviewer prompts live in this skill folder. Pick based on the skill argument:

| Invocation | Reviewer file | Output | Use when |
|---|---|---|---|
| `/code-review` (default) | `reviewer-agent.md` | strict JSON (5 categories, verdict) | normal pre-PR gate; structured pass/fail |
| `/code-review codigo` (also `company` / `omni`) | `codigo-reviewer.md` | Markdown "Omni-Architect 360°" report | company-mandated deep 360° review |

If the argument contains `codigo`, `company`, or `omni` → use **`codigo-reviewer.md`**. Otherwise → use **`reviewer-agent.md`**. Steps 3–5 below branch on this choice; scope and input-gathering are identical either way.

## Workflow

### Step 1 — Determine scope

> Run every git command below as `git -C <code repo>`. Bare `git` at the workspace root reports the **context repo**, not the code under review.

Ask if not obvious:
- **Staged changes only** → `git diff --cached --name-only`
- **Current branch vs develop** → `git diff develop...HEAD --name-only`
- **Specific file(s)** → user provides paths
- **Recent commit** → `git diff HEAD~1 HEAD --name-only`

Run the appropriate git command to get the file list.

### Step 2 — Gather inputs

Run `git status --short` (staged vs unstaged), then gather the diff **matching the scope chosen in Step 1** — do not default to `git diff HEAD` blindly:

| Scope | Diff command |
|---|---|
| Working tree (uncommitted work) | `git diff HEAD` |
| Staged only | `git diff --cached` |
| Branch vs develop | `git diff develop...HEAD` |
| Last commit (post-commit review) | `git diff HEAD~1 HEAD` |

`git diff HEAD` is empty right after a commit — if the user just committed and asks for a review, use the commit-range form.

Read each changed file in full (not just the diff) so the reviewer sees complete context.

### Step 3 — Dispatch the reviewer subagent

Call `Agent` with:
- `subagent_type: "code-reviewer"` (pinned to Opus in `.claude/agents/code-reviewer.md`; do not pass a `model` override). If the call fails with "Agent type 'code-reviewer' not found" (the session started before the agent file existed), use `subagent_type: "general-purpose"` with `model: "opus"` instead.
- `description: "Code review subagent"`
- `prompt`: paste the full contents of the **chosen reviewer file** (`reviewer-agent.md` by default, or `codigo-reviewer.md` when the argument selects it — see "Choosing the reviewer"), then append:

```
## Inputs

Workspace root: /Users/waiyanmin/Projects/Extra Space/Claude
Code repo under review: /Users/waiyanmin/Projects/Extra Space/CMS
Conventions: <workspace root>/.claude/CLAUDE.md, <workspace root>/.claude/rules/cross-repo.md, <workspace root>/.claude/rules/cms.md, <workspace root>/.claude/rules/engineering-checklist.md; spec feature doc: /Users/waiyanmin/Projects/Extra Space/Backend Demo/backend/.claude/backend-spec/features/<NN>-*.md

Changed files:
<file list from Step 1>

Git status:
<git status --short output>

Full diff:
<git diff HEAD output>

## Task

1. Read CLAUDE.md for project conventions.
2. Read each changed file in full.
3. Produce your report exactly in the format your instructions specify.
```

**Output format differs by reviewer:**
- `reviewer-agent.md` → strict JSON (parsed in Step 4).
- `codigo-reviewer.md` → a finished Markdown "Omni-Architect 360°" report. Do NOT ask it for JSON — its output structure is already the report. Relay it per Step 4 (codigo branch).

### Step 4 — Parse and present results

**If the codigo reviewer was used:** it returns a finished Markdown report. Relay it to the user largely verbatim (preserve the risk matrix, granular analysis, and engineered solutions). Convert any bare file references to clickable `[file](path)` links. Then skip to Step 5's codigo branch. Do NOT attempt JSON parsing.

**Otherwise (default JSON reviewer)**, parse the subagent JSON response and format for the user:

**If `critical` is non-empty:**
- State each finding prominently with file:line
- Do NOT claim the review passed
- Ask whether to fix now or note for later

**If `warning` is non-empty and `critical` is empty:**
- List warnings with file:line
- State overall assessment
- Author decides whether to address before PR

**If both empty:**
- State the review passed cleanly
- Note what was checked

**If subagent returns malformed JSON:**
- Report the failure
- Ask whether to re-run or proceed without structured output

### Step 5 — Summary

**Default JSON reviewer** — end with:
1. Counts: `X critical, Y warnings, Z suggestions across N files`
2. Verdict: **Approve** / **Request Changes** / **Needs Discussion**
3. One sentence on what was done well

**Codigo reviewer branch** — the report already carries its own Critical Risk & Threat Matrix and priority (P0/P1/P2) verdict, so don't invent a second one. End with a 1–2 line takeaway: the highest-priority item (or "no P0/P1 found") and the file count reviewed.

## Notes

- The subagent reads files fresh — it is not primed by this conversation, reducing anchoring bias
- If the user says "skip review" or "I know, just proceed" — respect that and note the override
- Do not re-run on the same commit unless new edits occurred since the last run
- Reviewer selection is per-run via the argument (`codigo`/`company`/`omni` → Omni-Architect; otherwise default JSON reviewer). Both prompt files live beside this SKILL.md.
- **Project policy — tests.** The spec asks for xUnit acceptance tests per feature; a missing test for a ported acceptance table is a Warning, not Critical. Verification is build + tests + Swagger + the staging DB (read-only MCP when installed).
- `docs/` (plans, migrations, handovers) lives at the **workspace root** in the context repo, not inside the code repos, so it never appears in a code-repo diff. If a change references a migration, remind the reviewer it lives at `docs/migrations/` and is applied manually by the user.

---
name: project-model-routing-v2
description: Routing v2 in effect since 2026-10-13 - main Opus 5.5 high; implementer/reviewer Opus, dev-walker Sonnet medium, Explore Haiku low; compact-nudge hook; Sonnet walker first-walk rule.
metadata:
  type: project
---

Model routing v2 (ported from Porsche-AI) is in effect in this workspace since 2026-10-13. Main session = Opus 5.5 high (Fable not used here; do not report it).

Files: `.claude/rules/model-routing.md` (the rule), `.claude/agents/code-reviewer.md` (Opus high), `.claude/agents/dev-walker.md` (Sonnet medium), `.claude/agents/explore.md` (Haiku low, overrides built-in Explore), `~/.claude-extraspace/agents/implementer.md` (Opus high, unchanged), `.claude/hooks/compact-nudge.py` (UserPromptSubmit, 150k then every 50k), `.claude/settings.json` (`"model": "opus"`, deliberately not `opus[1m]`, user 2026-10-13; use `/model opus[1m]` per session only when a task needs a huge context). Effort high comes from `~/.claude-extraspace/settings.json`.

**Why:** on Porsche-AI 43% of spend was subagents and 98% of that was input (cache write + read); context size, cold-start size and spawn count matter more than model choice.

**How to apply:** first Sonnet walks run GET-only cases first; revert dev-walker to `opus` if a walk leaves rows behind or misreads a PASS. Path-scoped rules (`paths:`) cannot match `../CMS` files (tested 2026-10-13: relative and absolute globs did not load, an in-root glob did), so `cms.md` and the engineering checklist stay unconditional. Context trim (same day): `cms.md` "Built so far" moved to `docs/notes/cms/built-so-far.md` (briefs name it; add new pieces there); superseded cost rows to `docs/notes/aws-cost/superseded-estimates.md`; project settings turn off plugins figma, fullstack-dev-skills, andrej-karpathy-skills, caveman (user, 2026-10-13: terse style hurts plain English; output is a small share of cost), the MCPs figma-console, serena, mysql-dev, mysql-prod-my, and exclude the ancestor `~/.claude/CLAUDE.md` (`claudeMdExcludes`). See [[feedback_subagents_opus_fable_reviews]], [[feedback_parallel_walkers]].

---
name: feedback-codigo-review-global-changes
description: Review a cross-module ("global") change, or any money / permission code, with /code-review codigo (Omni-Architect 360°), still inside the Opus code-reviewer agent.
metadata:
  type: feedback
---

When a change spans several modules, or touches money, payments or permissions, review it with the company `/code-review codigo` format (`.claude/skills/code-review/codigo-reviewer.md`), not only the plan identity check.

**Why:** user request 2026-09-11 and again 2026-09-24 (Porsche).

**How to apply:** dispatch the Opus `code-reviewer` agent and tell it to read `codigo-reviewer.md` as its system prompt, plus a saved diff file path. Relay the report largely verbatim. Small single-module plans can keep the plain review. 🔴 The reviewer prompts were copied from Porsche on 2026-10-09 and carry a header note about Porsche-only items; rewrite them once the C# solution has its own conventions.

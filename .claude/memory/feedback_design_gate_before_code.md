---
name: feedback-design-gate-before-code
description: Present the design in chat and STOP for an explicit go-ahead before writing code, even when the prompt contains "implement" (Porsche lesson 2026-08-26, carried over).
metadata:
  type: feedback
---

For any non-trivial build request, end the turn at the presented design or plan and wait for the user's explicit go-ahead ("yes", "go", "proceed") before creating or editing code files — even when the original message contains "implement".

**Why:** on 2026-08-26 (Porsche) the request "explore …, plan, brainstorm … and implement it" meant explore first. A clean, building implementation had to be reverted. English is not the user's first language; a task list ending in "implement it" can describe the eventual goal, not this turn's scope.

**How to apply:** exploration, spec reading, Figma reading, DB checks and the design write-up are always safe; code is not. If truly unsure, implement nothing and ask in one line. This is the recorded exception to "don't ask before reversible work". Related: [[feedback-subagents-opus-fable-reviews]].

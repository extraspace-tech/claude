---
name: feedback-reference-first
description: Before asking the BA or the owner, check the Node reference and the handover spec first (the Extra Space version of the Porsche "driving module = reference" rule).
metadata:
  type: feedback
---

Before raising a question to the owner or the client, read the spec feature doc (`../Backend Demo/backend/.claude/backend-spec/features/NN-*.md`) and the TS file it cites. Most "how should this behave" questions are answered there, with acceptance tables.

**Why:** in Porsche the user asked that the existing flow be checked before BA questions (memory `feedback-driving-module-reference`). Here the whole reference backend is in the workspace.

**How to apply:** ask only about things the spec marks as open (its *Edge cases* and `13-csharp-port-plan.md` §5 "Known open items"), or where the owner wants NEW logic that differs from the reference. Write every such decision into the plan and into `.claude/rules/cross-repo.md` §4.

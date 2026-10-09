---
name: feedback-subagents-opus-fable-reviews
description: Role split since 2026-10-05 - Fable high = architect / software engineer in the main session; Opus 5.5 high subagents = implementer, reviewer, walker; parallel subagents allowed; Fable reviews and reports a verdict.
metadata:
  type: feedback
---

The main session (Fable, high effort) is the architect and software engineer: it designs, plans, briefs, reviews and reports. It does not write or patch product code itself, not even a two-line fix. Every subagent (implementer, reviewer, walker, exploration) runs on Opus 5.5 at high effort. Fable may run several Opus subagents in parallel when the pieces are independent, must make sure they share what they depend on, and after they finish it reviews their work and reports a verdict (ACCEPT / FIX NEEDED / BLOCKED).

**Why:** user, 2026-10-04 and 2026-10-05 (Porsche): "when you are deploying the subagents always use opus 5.5 high. And your only job Fable, is to review their work" … "Fable can deploy multiple opus 5.5 high sub agents in parallel … make sure the multiple sub agents communicate each other." Copied to Extra Space 2026-10-09 at the user's request ("the same claude set up").

**How to apply:** global rule `~/.claude/CLAUDE.md` "Roles and models"; workspace details `.claude/rules/model-routing.md`. Implementer = `~/.claude/agents/implementer.md`; reviewer and walker = project agents `code-reviewer` and `dev-walker`; all three carry `model: opus` + `effort: high`. Subagents cannot reliably talk to each other, so communication runs through Fable: shared contracts in each brief, one shared notes file in the scratchpad, SendMessage to pass changes on. Config and doc files (rules, memory, plans, specs) are still Fable's own to write.

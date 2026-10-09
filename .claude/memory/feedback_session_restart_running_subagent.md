---
name: feedback-session-restart-running-subagent
description: After a session restart an Agent call can show "interrupted, outcome unknown" while the subagent is still running in the old process - check before re-running, and never print process command lines.
metadata:
  type: feedback
---

When an Agent call comes back as "interrupted: the session ended before this call's result was recorded", do not dispatch it again. First check whether it is still running.

**Why:** 2026-10-05 (Porsche) a walker that writes to staging was interrupted this way; the old Claude process kept it alive with no window. A second dispatch would have run the write cases twice.

**How to apply:**
- Check, in this order: listening ports of the apps the subagent boots; the newest files in its scratch folder; the subagent transcript's last write (`~/.claude/projects/<project>/<session>/subagents/agent-*.jsonl`); staging rows of the write cases.
- Ask every walker brief to save each response to a file in its scratch folder, so results can be rebuilt without the report.
- 🔴 Never list process command lines (`pgrep -fl`, `ps -o command`) while a walk runs: a curl command line carries the bearer token. Use `ps -o pid,ppid,etime,comm`.
- 🔴 The main session may be denied `kill` on app pids by the auto-mode classifier. Give the owner the one-line command instead.
- Until the owner says which window is the live one, only read.

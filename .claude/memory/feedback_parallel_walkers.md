---
name: feedback-parallel-walkers
description: Split live walks across several dev-walker agents in parallel, sharing ONE local app started by the main session, launched in the FOREGROUND so the Stop hook does not kill their app.
metadata:
  type: feedback
---

When a walk has independent case groups, split it across several `dev-walker` agents that run at the same time (user, 2026-09-30: "spread out the agents in parallel to do the testing … so that it gets done faster").

**How to apply:**
- Give each walker its own fixtures so they never write the same rows.
- Start ONE local app in the main session, set up auth once, and tell every walker the app is already running (do not start or stop it).
- Launch the walkers in ONE message, in the FOREGROUND (`run_in_background: false`). The Stop hook reaps orphaned apps on the ports in `.claude/dev-ports` whenever a main-session turn ends; ending the turn while background walkers run would kill their app.
- Walk rules still apply to every walker (staging only, Stripe test mode, cleanup through the API). Related: [[feedback-session-restart-running-subagent]].

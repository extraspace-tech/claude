---
name: feedback-kill-app-after-testing
description: Shut down any locally started app as soon as the checks finish; a leftover instance blocks the user's own run with "address already in use".
metadata:
  type: feedback
---

When I start the API (or any long-lived process: watchers, tunnels) to verify something, I kill it in the same turn the checks finish, then confirm the port is free before reporting done.

**Why:** 2026-07-29 (Porsche) a leftover instance made the user's own `dotnet run` fail with `Failed to bind to address … address already in use`. They asked for this as a standing instruction.

**How to apply:** `lsof -ti tcp:<port> | xargs kill`. Never hand the user a running instance "as a convenience". If a port is busy when I try to START, check `lsof -i :<port>` first: it may be the user's instance; ask before killing something I did not start. The Stop hook in `.claude/settings.json` reaps orphaned apps on the ports listed in `.claude/dev-ports`; keep that file current. Related: [[feedback-user-commits-and-tests]].

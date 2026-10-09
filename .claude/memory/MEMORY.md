# Memory Index

- [Setup owed (RESUME)](project_setup_owed.md) — ⭐ first-start checks (memory folder name, additionalDirectories, hooks), MCP install, C# solution TBD lines, owner decisions (API/ folder, new-logic contracts, tests).
- [Workspace layout](project_workspace_layout.md) — Claude/ = context repo (start here); siblings CMS/ (new C#, PUBLIC), Backend Demo/backend (Node reference + spec, READ ONLY), API/ (empty).
- [Reference first](feedback_reference_first.md) — ⭐ read the spec feature doc + cited TS before asking the owner or BA.
- [Design gate before code](feedback_design_gate_before_code.md) — ⭐ present the design, STOP for go-ahead before code, even when the prompt says "implement".
- [Roles: Fable architect, Opus subagents](feedback_subagents_opus_fable_reviews.md) — ⭐ Fable designs / briefs / reviews, never edits product code; Opus implementer / reviewer / walker; verdict per piece.
- [User commits & tests](feedback-user-commits-and-tests.md) — 🔴 NEVER commit / push, also on "let's push": give the message and stop.
- [Plain English](feedback_plain_english.md) — simple English everywhere; detail stays full.
- [Comment style](feedback_comment_style.md) — minimal comments; never narrate updates; short commit messages.
- [Kill the app after testing](feedback_kill_app_after_testing.md) — kill what you start; Stop hook reaps ports in `.claude/dev-ports`.
- [Parallel walkers](feedback_parallel_walkers.md) — split walks across foreground dev-walkers sharing ONE app.
- [Session restart with a running subagent](feedback_session_restart_running_subagent.md) — "interrupted" Agent call can still be running; check ports / files before re-running; never print command lines.
- [Data-fix SQL: check every writer](feedback_datafix_check_all_writers.md) — test the predicate against every writer; keep a restore read.
- [Codigo review for global / money changes](feedback_codigo_review_global_changes.md) — `/code-review codigo` 360° report; reviewer prompts still carry a Porsche note.

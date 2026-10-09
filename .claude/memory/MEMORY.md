# Memory Index

- [Setup owed (RESUME)](project_setup_owed.md) — ⭐ RESUME HERE: S0 spec awaits owner review → then writing-plans; open owner/IT items (repo private, AWS account, Entra, SES, host, freeze policy, account deletion).
- [System landscape](project_system_landscape.md) — ⭐ brand-new C# monolith in CMS/ = functional copy of the Node demo (read-only reference); old Codigo system + Lucy untouched/retired; all owner decisions of 2026-10-09.
- [AWS cost estimate](reference_aws_cost_estimate.md) — v3 SG+MY one platform: launch $437/mo, budget ceiling ≈ $500, after tuning ≈ $270–330; sized on real old-prod usage; client page URL, unit prices, measured volumes.
- [Client artifacts](reference_client_artifacts.md) — client's own Claude prototypes (Cowork Manager, ES App, Admin): links, extracted rules in docs/notes/client-artifacts/, conflicts vs demo OPEN.
- [Backend owner](user_backend_owner.md) — user is the ONLY backend dev; prefers MVC controllers; keep layout simple.
- [Workspace layout](project_workspace_layout.md) — Claude/ = context repo (start here); siblings CMS/ (the monolith, PUBLIC), Backend Demo/backend (demo + spec, READ ONLY), API/ (es-api, unused); Extra Space old/ (READ ONLY, secrets).
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

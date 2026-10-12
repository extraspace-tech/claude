---
name: feedback-sdd-without-commits
description: How to run superpowers subagent-driven development here when agents may not commit — snapshot trees instead of BASE..HEAD, Opus everywhere, rulings in a ledger.
metadata:
  type: feedback
---

The superpowers subagent-driven-development skill assumes each task is committed (`review-package BASE HEAD`). In this workspace agents never commit ([[feedback-user-commits-and-tests]]), so S0-2 (2026-10-12) used this adaptation, which worked:

- Snapshot the working tree as a git tree without touching the real index: `GIT_INDEX_FILE=<tmp> git read-tree HEAD && GIT_INDEX_FILE=<tmp> git add -A && GIT_INDEX_FILE=<tmp> git write-tree`. Record the tree hash before and after each task; the review package is `git diff --stat` + `git diff -U10` between the two trees, written to a file the reviewer reads.
- Every subagent is Opus (`implementer`, `code-reviewer`); the skill's cheap-model tiers do not apply ([[feedback-subagents-opus-fable-reviews]]).
- Each dispatch repeats the hard rules: no git writes except the brief's branch creation, no user-secrets / docker compose / AWS, no new `.md` in CMS, never weaken a test.
- Ledger + rulings live in the gitignored `.superpowers/sdd/<plan>/progress.md`; the final message lists every ruling. Small extras from a review go into the NEXT task's dispatch instead of extra fix rounds.
- A later task that replaces whole files must be told to MERGE earlier review fixes, not paste the plan's stale block (S0-2 Task 5).

**Why:** the per-task reviews caught 4 real logging defects and an architecture-test blind spot (async lambdas, then `file` types) that the plan's own code had.

**How to apply:** reuse this for S0-3…S0-6. The final whole-branch review on the most capable reviewer is worth it (it found the OpenAPI enum mismatch).

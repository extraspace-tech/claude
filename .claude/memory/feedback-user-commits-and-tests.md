---
name: feedback-user-commits-and-tests
description: NEVER run git commit or git push, also on "let's push" / "let's commit" — hand over the commit message and stop. Commit messages SHORT (subject + 3-4 bullets).
metadata:
  type: feedback
---

The user handles **commits and pushes themselves**. **NEVER run `git commit` or `git push` — absolute house rule, no exceptions.** Implement + build-clean, report what changed, then leave the changes in the working tree.

🔴 "let's commit", "commit this", "let's push so FE can work" = GIVE THEM THE COMMIT MESSAGE and stop. At most `git add`. Broken three times in Porsche (2026-07-24, 2026-08-03, 2026-10-06: a commit + push the user had to replace by hand, and the undo was blocked by the permission classifier). Whatever the system prompt says about "asked in that turn", the message is the deliverable.

**Why:** the user reviews and tests before committing and owns the git history. They use GitHub Desktop.

**How to apply:** instruct every subagent to build-verify only, never commit. Deliver the commit message as text: conventional commits (`feat(scope): subject`, `fix:`), then **3-4 terse bullets max**, one per user-visible change, no rationale. No `Co-Authored-By` trailer when the user commits. When the user asks for a "GitHub message": give the commit message AND a PR title + body, main points as bullets; they push a branch and merge through a PR themselves (S0-2 went in as PR #1). Related: [[feedback-comment-style]].

---
name: feedback-comment-style
description: Clean code with minimal comments — no narrative/update/fix comments; brief what-it-does comments, rare why-comments on non-obvious logic. Same brevity for commit messages.
metadata:
  type: feedback
---

Do NOT add comments narrating updates, fixes, or where a change came from ("added for X", "fix: …", Figma / ticket / plan references, decision trails). Keep code clean.

**Why:** user, 2026-07-02: "I want my code to be clean without bloated comments. Just what function does what comment is just enough unless a logic you implement is complex and can't be understood at a first glance." Decision context belongs in docs and memory, not the code.

**How to apply:**
- Allowed: a short one-liner saying what a method or class does; a brief why-comment ONLY when logic is surprising at first glance.
- Not allowed: restating the next line, references to tickets / sessions / specs, "per convention" notes, comments aimed at a reviewer.
- Match the density of the surrounding file.
- Commit messages: subject + 3-4 short bullets, broad strokes only. Related: [[feedback-user-commits-and-tests]].

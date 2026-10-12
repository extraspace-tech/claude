---
name: user-backend-owner
description: The user is the ONLY person handling the Extra Space C# backend and is more familiar with ASP.NET Core MVC controllers than Minimal APIs (said 2026-10-09).
metadata:
  type: user
---

The user is the sole backend developer for the new Extra Space monolith. They are more familiar with **MVC controllers** than with Minimal APIs. Their team also builds the Flutter app. The user is a Codigo developer (git user `waiyanmin-codigo`) and worked on the old Codigo .NET system.

**Why:** with one person owning the backend, familiarity and simplicity beat newer patterns. Every extra project, layer or abstraction is upkeep that one person carries.

**How to apply:**
- Use `[ApiController]` controllers in feature folders.
- Keep the project count small.
- When there is a choice, prefer the well-known ASP.NET Core pattern, and explain new concepts briefly in plain English. See [[feedback-plain-english]].
- **First time setting up AWS** (said 2026-10-10). On 2026-10-12 they asked Claude to do the AWS setup for them. So run the AWS steps yourself through the `extraspace` profile; explain each in plain words; show the command and the monthly cost and wait for an explicit OK before anything that creates, changes or deletes. See [[reference-aws-account]].

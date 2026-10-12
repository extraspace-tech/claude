---
name: user-backend-owner
description: The user is the ONLY Extra Space C# backend dev; knows MVC best but chose Minimal APIs on 2026-10-12 to learn them — explain new concepts against MVC.
metadata:
  type: user
---

The user is the sole backend developer for the new Extra Space monolith. They know **MVC controllers** best (2026-10-09). On 2026-10-12 they chose to switch the project to **Minimal APIs** to learn something new ("I don't mind maintaining this alone, I want to learn new thing"), and asked for every addition to be explained and compared with MVC. Their team also builds the Flutter app. The user is a Codigo developer (git user `waiyanmin-codigo`) and worked on the old Codigo .NET system.

**Why:** with one person owning the backend, familiarity and simplicity beat newer patterns. Every extra project, layer or abstraction is upkeep that one person carries.

**How to apply:**
- Endpoints are Minimal APIs in feature folders (`Features/<X>/<X>Endpoints.cs`), not controllers.
- When a plan or review adds an ASP.NET Core piece, say why it is there and what the MVC equivalent was. The guide is `docs/notes/cms/minimal-apis-vs-mvc.md`; extend it when a new concept lands (route groups, endpoint filters, auth policies in S0-3/S0-4).
- Keep the project count small.
- When there is a choice, prefer the well-known ASP.NET Core pattern, and explain new concepts briefly in plain English. See [[feedback-plain-english]].
- **First time setting up AWS** (said 2026-10-10). On 2026-10-12 they asked Claude to do the AWS setup for them. So run the AWS steps yourself through the `extraspace` profile; explain each in plain words; show the command and the monthly cost and wait for an explicit OK before anything that creates, changes or deletes. See [[reference-aws-account]].

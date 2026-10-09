---
name: project-system-landscape
description: ⭐ Extra Space has THREE backend lines - old Codigo .NET Core 3.1 + MySQL production (YES app + ES Express admin, SG/MY forks), Lucy/Iviva + MongoDB (what prod Flutter calls for storage), and the PM's Node demo (prototype, not production). Scanned 2026-10-09.
metadata:
  type: project
---

The user corrected the setup on 2026-10-09. The setup had called `Backend Demo/backend` "the client's existing backend". In fact it is the PM's prototype, and the old system at `/Users/waiyanmin/Projects/Extra Space old/extraspace-backend` is what runs. A full scan the same day (4 Opus agents) wrote `docs/notes/old-backend/01..03` and `docs/notes/demo-backend/01`.

- **Old production** (`sgcodigo/extraspace-backend`, Codigo, 2020+, .NET Core 3.1, MySQL, Redis, Hangfire, AWS ECS ap-southeast-1):
  - `mobile_api` = the YES customer API, 81 routes.
  - `admin_cms` = Razor back office, 398 actions, for YES and for **ES Express**.
  - ES Express is unmanned storage with Noke locks and its own MySQL DB. Its customer backend is not in the repo.
  - SG (`yes-production`) and MY (`mys-yes-production`) are separate forks since 2024-06-26, each with its own DB, Stripe and S3.
  - 🔴 Live secrets are committed. Rules for working there are in `.claude/rules/old-backend.md`.
- **Lucy/Iviva gateway + 8 MongoDB services**: the production Flutter app calls these for storage today (`Backend Demo/backend/README.md:13`). They are not in the workspace. **Retired** (owner, 2026-10-09); the new C# API replaces them.
- **Demo** (`Backend Demo/backend`, Node + PostgreSQL on Vercel/Neon): built in about 3 weeks, mostly with Claude Code. It holds real Cowork data since 2026-10-05. Its 12 features + spec are the feature reference for the new C# monolith (never integrated). It has insecure gaps that must not be copied (email-only login, no ownership checks).
- Owner decisions on 2026-10-09:
  - One **monolith** in C#.
  - The user lets Claude choose the frontend framework.
  - First release = **the demo's features** (option B of the brainstorm).
  - "You won't need to touch the old system": no calls, no DB reads, no migration and no changes to the old Codigo system. It keeps running on its own.
  - The PM said "as we like" on the DB. The owner chose **PostgreSQL on RDS** after asking about scalability and PostgreSQL vs MySQL. The "demo's schema" part was later dropped: we use our own schema.
  - "We won't be using Lucy anymore": Lucy/Iviva is retired, and Flutter moves fully onto the C# API.
  - Self-storage stays on **SiteLink CCWs 3.5**.
  - **BizPlus is built in-house, the whole line**: Cowork 09/10, facility booking 07 and credits 08. So spec C1 is settled: we own Cowork billing.
  - **Our team builds the Flutter app too.** The API and the app change together.
  - **Brand-new project, written from scratch. The demo is never touched.** It never reached customers or the PO: no shared DB, no data carried over, no API or schema compatibility, no parity tests. The demo and the old system are read-only references only. This replaced the earlier "take over the demo schema" plan.
  - **Goal = a functional copy of the demo**: same features and screens, our own code. The demo will keep changing. We diff it and add the changes, logged in `docs/notes/demo-backend/sync-log.md` (baseline `6be4474`).
  - ~~Singapore only~~. Later the same day the PM confirmed **Singapore AND Malaysia at release**, on **one platform**. Currency, time zone and tax are per site. S1 designs the per-country pieces: Stripe account (SGD/MYR), GST vs SST, SiteLink sites, SES sender. Hosting MY data in SG must be confirmed against the PDPA.
  - **Shape 1: one backend, one repo, everything in `../CMS`** (`extraspace-tech/cms`): mobile API, admin API, React admin UI and jobs. `es-api` is unused. 🔴 Both repos are PUBLIC. Making `cms` private is recommended and still open.
  - **Admin frontend = React + Vite + TypeScript**, served by the monolith (option A). The customer side is Flutter.
  - **Sub-projects approved**: S0 Foundation → S1 Self-storage → S2 BizPlus booking + credits → S3 Cowork → S4 Extras. The Flutter track runs in parallel. Brainstorming for S0 started 2026-10-09. S0 design sections approved: 1 (layout + MVC controllers), 2 (auth: customer email code + JWT 15 min / refresh 60 days rotated; admin Entra SSO with pre-added staff only, cookie, per-action policies, audit; ProblemDetails + `code`; `X-App-Version` → 426), and 3 (data: EF code-first, snake_case, UUID v7, `numeric(12,2)`, GST copied onto each line, timestamptz/DateOnly + TimeProvider, statuses as text, xmin concurrency, no repository layer). 4 approved (Hangfire on PG, no Redis in S0, SES via a job, Secrets Manager, CloudWatch). 5 approved (React 19 + Vite + TS, Tailwind + shadcn/ui, TanStack Query/Table, RHF + Zod, Recharts, OpenAPI-generated types; BFF cookie sign-in; NO generic CRUD engine: explicit admin endpoints per feature + shared UI components; no billing maths in the browser). 6 approved (ECS Fargate + ALB, NAT fixed IP, RDS Multi-AZ in prod, CDK, GitHub Actions: PR checks, main → staging auto, prod by approval with the same image, OIDC to AWS; Testcontainers). **S0 spec written 2026-10-09: `docs/superpowers/specs/2026-10-09-s0-foundation-design.md`, awaiting owner review.** Next after approval: the writing-plans skill → S0 implementation plan.
  - S0 decision: **customers sign in with email + a one-time code**, then get an access token and a refresh token. There are no customer passwords. SiteLink tenants are linked by email only after the email is verified.
  - S0 decision: **admin staff sign in with Microsoft Entra ID SSO**. The client is on M365, inferred from MX records. Roles stay in our admin.
  - S0 decision: **ECS Fargate + ALB**, with AWS CDK in C# (assumed). Which AWS account to use is open.
  - The client's own Claude artifacts (Cowork Manager, ES App UI Test, ExtraSpace Admin) are a **third rule reference**, next to the demo and the old system. They disagree with the demo in places, and the source of truth is OPEN (ask the PM). See [[reference-client-artifacts]].
  - The two MySQL MCPs are the old system's **production** databases: `mysql-dev` = SG, `mysql-prod-my` = MY. Aggregate reads only, when the owner asks.
  - The owner attached SiteLink PDFs on 2026-10-09. They were password-protected and did not load.

**Why:** the demo and the old system look like systems to port or stay compatible with, but they are not. Each plan designs fresh, and only cites them for business rules.

**How to apply:**
- Read `.claude/rules/cross-repo.md` §4 for the open decisions before designing.
- For behaviour the demo lacks (points, autopay, Noke, Express, notifications), cite the old-backend notes.
- Never treat old code as a design to copy: it has many security defects.

Related: [[project-setup-owed]], [[project-workspace-layout]].

2026-10-09: monolith reviewed and kept. Guards added: feature `Contracts/` folders + architecture test (S0), outside-call limits + payment side effects as idempotent jobs (S1), time zone per site. Details: `.claude/rules/cross-repo.md` §4.

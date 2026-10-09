# Plan: <task name>

**Mode: verbatim**

> **Instructions for the implementing agent:**
> Read `.claude/CLAUDE.md` and `.cursor/rules/implementer.mdc` section B first and follow them exactly.
> Implement ONLY what this plan says. Do not refactor, rename, or "improve" code outside the listed files.
> If something in this plan conflicts with what you find in the code, STOP and report the conflict instead of guessing.
> If the compiler forces any deviation (e.g. a variable rename), make the smallest one possible and list EVERY deviation at the end of your final message.
> Verification is `dotnet build <csproj>` with 0 errors plus the tests this plan names.
> Do NOT commit. Leave all changes uncommitted for review.

## Task
<one-paragraph statement of what to build and why>

## Spec
- Feature doc: `../Backend Demo/backend/.claude/backend-spec/features/<NN>-*.md`, sections <…>
- Reference TS files: <paths cited by the doc>
- Port-plan phase: <n>

## House rules that apply to THIS task
<!-- Inline the specific traps for this task. The implementer has no access to project memory.
     Always check whether these apply and copy the relevant ones in:
     - Money = double, JS half-up rounding (Math.Floor(x + 0.5)) at the point the reference rounds.
     - Business dates Asia/Singapore; storage UTC; audit stamps DateTime.UtcNow. Never DateTime.Now.
     - Routes, JSON names/casing, status codes, error codes exactly as the spec; additive only.
     - No card data; Stripe only via hosted Checkout + verified webhook; SiteLink field names from spec 02.
     - Credit changes only through the wallet service; admin resources only through the registry.
     - PostgreSQL enums compared as strings; cuid ids; updatedAt maintained by the app.
     - Public repo: no secrets, no real data.
-->
- <rule 1>
- <rule 2>

## Clients affected
<!-- Check `.claude/rules/cross-repo.md` first. Name every client that reads this route, shape, table or env var. If none, write "none" with the reason. -->
| Client | What changes | Additive? |
|---|---|---|
| Flutter `/api/v1/*` | <what> | yes / no (owner decision recorded) |

## Files to touch
| File | Change |
|---|---|
| `../CMS/src/...` | <what> |

## Steps
1. <ordered, concrete steps — entity → DbContext → DTOs / validators → service → DI → controller → tests>
2. ...

## SQL migration (if any)
<!-- Migrations are run manually by the developer. Write the script into docs/migrations/ and name it here; do NOT run it. Additive only. -->
None.

## Out of scope
- <things the implementer must NOT do, deferred items, known TODOs to leave alone>

## Verification
1. `dotnet build <csproj>` → 0 errors.
2. `dotnet test <test csproj>` → the acceptance cases listed: <…>
3. <manual Swagger / curl check for the risky logic>

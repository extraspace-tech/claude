---
name: api-debug-and-run
description: Build, run and triage the Extra Space C# API locally — dotnet build/run commands, Swagger and health paths, and the steps for debugging an unexpected error envelope or exception. Use when booting the API or chasing an unexpected response. Fill in the TBD lines at port-plan phase 1.
---

# `../CMS`: run locally and debug an error

Paths are relative to the workspace root (`Claude/`).

## Running locally

```bash
dotnet build ../CMS/<Api project>.csproj        # TBD: real path
dotnet run --project ../CMS/<Api project>        # TBD
```

- Port: **TBD** (add it to `.claude/dev-ports`). Swagger: **TBD** (`/api/docs` in the reference). Health: **TBD** (`/api/v1/health` family in the reference, spec 11).
- Config comes from env vars named in the spec (`reference/env-vars.md`); keep a local `.env` or user-secrets outside git.
- Kill the app when done; a Stop hook also reaps orphaned apps on the ports listed in `.claude/dev-ports`.

## Debugging an error

1. Find the error `code` in the response envelope (spec 00 §error envelope) and the `requestId`; grep the Serilog output for that id.
2. Compare the failing route with `reference/endpoints.md` → feature doc → cited TS handler: the reference shows the expected status and body.
3. Validation 400s: the `VALIDATION_ERROR` shape must match spec 00; check the FluentValidation rule against the zod schema in the TS file.
4. Rounding or amount mismatches: check the rounding point (JS half-up on `double`) and the per-site GST.
5. Time mismatches: a business date computed in UTC instead of Asia/Singapore shifts by 8 hours.
6. Npgsql enum errors: the PG enum must be mapped on the data source / model builder; compare as strings in SQL.

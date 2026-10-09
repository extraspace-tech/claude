---
name: api-debug-and-run
description: Build, run and triage the Extra Space C# API locally — dotnet build/run commands, Swagger and health paths, and the steps for debugging an unexpected error envelope or exception. Use when booting the API or chasing an unexpected response. Fill in the TBD lines at phase 1.
---

# `../CMS`: run locally and debug an error

Paths are relative to the workspace root (`Claude/`).

## Running locally

```bash
dotnet build ../CMS/src/ExtraSpace.Api/ExtraSpace.Api.csproj
dotnet run --project ../CMS/src/ExtraSpace.Api        # needs `docker compose up` (PostgreSQL) in ../CMS first
```

- Port: **TBD** (add it to `.claude/dev-ports`). OpenAPI: `/openapi/v1.json` (Swagger UI outside production). Health: `/health/live`, `/health/ready`. Jobs: `/admin/jobs`.
- Config comes from the environment or user-secrets (names set in the design spec); never from a committed file.
- Kill the app when done; a Stop hook also reaps orphaned apps on the ports listed in `.claude/dev-ports`.

## Debugging an error

1. Find the error `code` in the response envelope (spec 00 §error envelope) and the `requestId`; grep the Serilog output for that id.
2. Compare the failing route with the design spec and our OpenAPI document: they define the expected status and body. The demo spec's feature doc shows the intended business rule.
3. Validation 400s: the `VALIDATION_ERROR` shape must match spec 00; check the FluentValidation rule against the zod schema in the TS file.
4. Rounding or amount mismatches: check the rounding helper and the per-site GST.
5. Time mismatches: a business date computed in UTC instead of Asia/Singapore shifts by 8 hours.
6. Npgsql enum errors: the PG enum must be mapped on the data source / model builder; compare as strings in SQL.

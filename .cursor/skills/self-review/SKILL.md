---
name: self-review
description: Review the uncommitted diff of the C# repo (`../CMS`) as a senior reviewer who did not write it, against its plan or brief and the workspace engineering checklist. Use after implementing a docs/plans task, or in a fresh chat for a second pass before hand-back.
---

# Self-review

Best run in a **new chat**, so you read the code without the author's assumptions.

1. Find the work: `git -C <repo> status --short` and `git -C <repo> diff` for each repo the plan
   names. Bare `git` at the workspace root reports the context repo, not the code.
2. Read the plan or brief in `docs/plans/` and the spec it names. Read each changed file in full
   around every hunk, not only the diff.
3. Check, in this order, and quote `file:line` for every claim:
   - each fixed decision, contract field, error message, guard and invariant is built as written;
   - each verification case can pass — trace the risky ones through the code;
   - every section of `.claude/rules/engineering-checklist.md`;
   - callers and readers of every changed symbol across the C# repo and the Node reference (`../Backend Demo/backend`);
   - the house rules for the repo (`.claude/rules/<repo>.md`) and the domain rule file.
4. Verify schema or data doubts with the read-only `mysql-dev` MCP (it is the staging database).
   Never call POST, PUT or DELETE on a running API.
5. Fix what you find, in the smallest way. Rebuild every touched csproj to 0 errors. Read the new
   diff once more.
6. Report: findings ranked P0 / P1 / P2 with `file:line` and a concrete failure scenario, what you
   fixed, what you left and why, and what you could not verify.

Not findings here: no automated tests (owner decision); migrations are hand-run from
`docs/migrations/`; `AddAsync` (cms) and `AddAysnc` (customer-api) are both correct; soft delete only;
audit stamps are UTC.

# Brief: <task name>

**Mode: engineer**
**Repos you may edit:** `../CMS` (csproj `<path>`). No other repo. `../Backend Demo/backend` is read-only reference.
**Spec:** `../Backend Demo/backend/.claude/backend-spec/features/<NN>-*.md` (+ the TS files it cites) and
`docs/superpowers/specs/<file>.md` if one exists — read them fully first. They hold the sources, the
owner's decisions and the reasons. This brief does not repeat them.

> You own the code for this task (`.cursor/rules/implementer.mdc`, section A). The decisions below are
> fixed. How to build them is yours: read the code and the reference, find what this brief missed, fix
> what the task needs, review your own diff, and report. No commits. No POST/PUT/PATCH/DELETE calls
> against a running API (the database behind it is staging).

## Goal
<two or three sentences: what changes for the user, and why>

## Fixed decisions
<!-- Business rules and contract choices the owner already made, including every place the new C#
     logic deliberately differs from the Node reference. Number them. The implementer must not reopen
     these; if one cannot be built as written, that is a stop-and-ask. -->
1. <decision>

## Contract
<!-- Routes, request and response fields, error codes and messages, exactly as the clients see them.
     Say which parts are additive and which existing fields must not change. Cite openapi.json. -->

## Invariants and guards
<!-- What must always hold after this change, in words. Include the ones that are easy to break from
     the far side: other callers, the webhook, the cron job, the Node service during cutover. -->
- <invariant>

## Known traps
<!-- Facts already found in the code, the spec's Edge cases, or memory that would cost time to
     rediscover. File and line where possible. Not instructions on how to write the code. -->
- <trap>

## Do not touch
- <files, methods, behaviours and tables that stay as they are>

## Clients affected
<!-- From `.claude/rules/cross-repo.md`. "none" is a valid row, with the reason. -->
| Client | What changes | Additive? |
|---|---|---|

## SQL migration (if any)
None.

## Verification cases
<!-- The spec's acceptance table rows this task covers, plus the cases the live walk will run later.
     Build the code so that each one passes; say in your report which ones you proved by test, by
     reading or by GET-only smoke, and which you could not. -->
| # | Case | Expect | Proof |
|---|---|---|---|

## Report back
Use the report format in `.cursor/rules/implementer.mdc` section A, item 8.

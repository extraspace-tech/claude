---
name: feedback-datafix-check-all-writers
description: Before handing over a data-fix SQL, test its WHERE clause against rows written by EVERY writer of that table (here: the Node service, the C# service, the Stripe webhook, cron jobs, seeds), and keep a restore read.
metadata:
  type: feedback
---

A data-fix or cleanup SQL must be checked against the rows every writer creates before the user runs it.

**Why:** 2026-09-11 (Porsche) a cleanup matched rows a second writer had created legitimately and wiped 8 real ids on dev; a restore had to be written.

**How to apply:** for each table the SQL touches, run a read-only `SELECT … GROUP BY` of the rows the predicate matches, split by the columns that tell the writers apart (source, kind, created-by, time window), and grep each writer's insert site before calling the SQL safe. Put the exclusion guards in the SQL itself and list the writers in the header. Keep a pre-change read of the values when the SQL clears data. During cutover the Node service and the C# service can both write the same tables: `.claude/rules/cross-repo.md` §2.

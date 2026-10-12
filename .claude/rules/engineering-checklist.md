# Engineering checklist (shared by Claude and Cursor)

Always loaded. Every item below was a real defect in the Porsche workspace, found in review or on a live walk, and applies to any ASP.NET Core / EF Core service. Run this list against your own diff before you say "done". The per-repo house rules (`.claude/rules/cms.md`) still apply; this list does not repeat them. Add Extra Space defects here as they are found.

## 1. Look outside the lines you edited

- For every method signature, column, enum value, DTO field or "mode" flag you change or start writing: grep the C# repo for its callers and readers (and the Flutter app when an API shape changes). The regression hides in the door you did not touch. In your report, list each reader you checked and why it needed no change.
- When you add a branch to a **shared add/update method**, say what the update path does. A branch that ignores the update flag is the default failure.
- When a path deliberately **skips guards**, list what each skipped guard protected and re-provide the ones that matter.
- A request that accepts "either A or B" must still accept the payload its own GET returns.
- Extract business rules from a prototype's **code**, not its rendered page. A rendered read of the client's ES App artifact got 4 rules wrong (2026-10-09).
- Before you say the demo or the old system does or lacks something: read the spec doc AND the cited TS file (demo), or `docs/notes/old-backend/` AND the cited C# file (old system). The spec is a snapshot of 2026-10-08.

## 1b. AWS and CDK

- 🔴 Every AWS CLI or CDK command names the profile (`--profile extraspace`). The laptop's `default` profile is another client's account. Claude sessions here cannot see it (`AWS_SHARED_CREDENTIALS_FILE=/dev/null`), but a subagent must not work around that. Real incident, 2026-10-12: a `cdk synth` without a profile reached the Porsche account.
- The CDK app must never do context lookups (`Vpc.FromLookup`, AZ lookups, `HostedZone.FromLookup`). A lookup calls AWS at synth time and writes the account id into `cdk.context.json`, which must never reach the public repo. Pass known values in.
- A CDK test that fails because CDK renders a value differently (a token instead of a literal, inline vs separate rules) means: read the synthesized JSON and fix the construct. Never loosen a Review Focus assertion.

## 2. EF Core and transactions

- Every `BeginTransactionAsync` needs a `CommitAsync` on every success path. A missing commit rolls back silently at dispose: green build, no exception.
- Never `Update()` a row you added with `AddAsync` in the same unit of work (Added → Modified fails the save).
- Never full-row `Update()` a row that another process also writes (a background job, the Stripe webhook). Set only your columns on the tracked row.
- After a lost race, clear any stale id left on a tracked entity before a later save writes it back.
- An unbounded `.ToListAsync()` followed by `.Contains` becomes a giant IN list. Compose an `IQueryable` subquery unless a filter caps the list. On .NET 10, `.Contains` on an **enum array** inside an EF expression tree fails to translate.
- An anonymous `.Select(x => new { … })` only carries the columns it names.
- Reads that feed a write, uniqueness or conflict decision run inside the same transaction as the write, with the row lock the spec names (Postgres `FOR UPDATE` where the Node code used it).

## 3. Money, time and idempotency

- Validate the value **as it will be stored** (after rounding), never the raw request value. Money is `decimal`; round only through the one rounding helper (rule set in the design spec).
- When money moves between records, list every lifecycle state of that money and say what happens to each.
- When money goes into a frozen snapshot, state the invariant between the snapshot field and the live field, and keep both sides of a shared formula in one helper.
- An aggregate that answers "does one already exist?" must exclude the caller's own row.
- Every webhook and cron handler is idempotent: a duplicate delivery changes nothing the second time. Say which column or key proves it.
- Business dates use the site's time zone (`site.time_zone`, default `Asia/Singapore`; MY sites `Asia/Kuala_Lumpur`); storage is UTC. Never `DateTime.Now`. A `DateTime` gets a `Z` in JSON only when its Kind is Utc; a value read from the database is Kind Unspecified unless you set it.

## 4. Schema and contracts

- A migration that NULLs or changes a column: check the table's UNIQUE indexes, CHECK and EXCLUDE constraints in `reference/schema.sql` first.
- Routes and JSON field names / casing already used by the Flutter app or the admin UI change additively only. New fields must read as null on old rows.
- Interface placement varies per module. Grep `interface IX` and cite the real file before you edit.
- "X updates lazily through a sync": trace which **column** the consumer reads and confirm the sync writes that column.

## 5. Finish

- Match the idiom of the surrounding file over any outside suggestion, including a reviewer's code.
- Write files with LF line endings.
- Report the real build result (`0 errors`) and the real test result (counts).
- If the change masks a value in logs, grep the live log for that value after a run; other loggers print the same request.
- State what you could **not** verify. An honest gap is worth more than a confident guess.

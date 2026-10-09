# Plan hand-off gate (Cursor hybrid workflow, not the default)

Copied from Porsche-AI. Run from the workspace root (`Claude/`) before handing a verbatim-mode
`docs/plans/*.md` file to Cursor. Both scripts assume the code repo root is `../CMS` (edit `root`
in each script if the C# solution puts sources deeper) and that every file mention in the plan is a
backticked path relative to that root.

1. `python3 .claude/scripts/plan_anchor_check.py docs/plans/<plan>.md`
   Every ```csharp block whose heading line contains `Replace:`, `Delete this` or `Find this exact line`
   must occur exactly once in the file named above it. Exit 1 on any failure.
2. `python3 .claude/scripts/plan_apply.py docs/plans/<plan>.md` (working tree must be clean), then
   build the csproj, then `git -C ../CMS checkout -- .` to revert so the implementer still implements it.
   A `with:` block replaces the preceding anchor; `insert the following block immediately before it` inserts.

Heading spelling matters: a lower-case `replace:` is NOT picked up.

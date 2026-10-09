# Demo sync log

The new monolith is a functional copy of the demo, written from scratch (owner, 2026-10-09). The demo keeps changing, so we track which demo commit our design and code have caught up to. The demo is read only, and we never change it.

## How to check for demo updates

1. `git -C "../Backend Demo/backend" fetch` (read-only; it never changes the working tree), then
   `git -C "../Backend Demo/backend" log --format='%h %ad %s' --date=short <last-synced>..origin/main`.
2. For each new commit, `git -C "../Backend Demo/backend" show --stat <sha>` and read the changed spec docs and TS files.
3. Sort each change into:
   - new feature
   - changed business rule
   - changed screen
   - bug fix
   - demo-only (no action)
4. Write the result as a new row below. Each row that needs work becomes a task in the implementation plan.
5. Do not pull the demo's working tree, because other sessions read it. Fetching and reading `origin/main` is enough.

## Log

| Date | Demo commit synced to | What changed in the demo | Our action |
|---|---|---|---|
| 2026-10-09 | `6be4474` (2026-10-08, "Add backend handover spec for C# re-implementation") | Baseline: 12 features, 178 routes, handover spec | Design starts from this commit |

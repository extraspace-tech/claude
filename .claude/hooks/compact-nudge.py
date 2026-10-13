#!/usr/bin/env python3
"""UserPromptSubmit hook: one-line nudge when the main session context is large.

Reads the last assistant usage record from the session transcript, sums
input + cache read + cache write (= the context the next call re-reads), and
prints a short note once the total passes COMPACT_NUDGE_THRESHOLD tokens
(default 150000), then again after every COMPACT_NUDGE_INTERVAL tokens of
growth (default 50000). State lives in /tmp per session. Idea from the ECC
strategic-compact skill; written here without the ECC runtime.
"""
import json, os, sys

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    path = data.get("transcript_path") or ""
    sid = data.get("session_id") or "nosession"
    if not path or "/subagents/" in path or not os.path.exists(path):
        return
    threshold = int(os.environ.get("COMPACT_NUDGE_THRESHOLD", "150000"))
    interval = int(os.environ.get("COMPACT_NUDGE_INTERVAL", "50000"))
    if threshold <= 0:
        return
    ctx = 0
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - 400_000))
            tail = f.read().decode("utf-8", "ignore").splitlines()
        for line in reversed(tail):
            if '"usage"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant":
                continue
            u = (d.get("message") or {}).get("usage") or {}
            ctx = (u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0)
            if ctx:
                break
    except Exception:
        return
    if ctx < threshold:
        return
    state = f"/tmp/claude-compact-nudge-{sid}"
    last = 0
    try:
        last = int(open(state).read().strip() or 0)
    except Exception:
        pass
    if last and ctx < last + interval:
        return
    try:
        open(state, "w").write(str(ctx))
    except Exception:
        pass
    print(f"[compact-nudge] Main context is about {ctx//1000}k tokens (threshold {threshold//1000}k). "
          "Every call re-reads it. If this prompt starts a new task, tell the user in one line: "
          "/rename then /clear. If it continues the same task at a boundary (plan or state already in a file), "
          "suggest /compact. Never suggest compacting mid-implementation. Then do the work.")

if __name__ == "__main__":
    main()

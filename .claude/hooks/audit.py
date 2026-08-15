#!/usr/bin/env python3
"""PostToolUse — one JSON line per tool call, to a daily log.

Vendored from uaziz1/claude-code-guardrails (MIT) at
0b8671079de887fbee051a8a8661c5a809a5c247, near-unchanged. See VENDOR.md.

Always exits 0. The entire body is wrapped: a read-only filesystem, a full
disk or a bad permission on the log directory would otherwise surface as a
hook failure and interrupt real work. An audit log that blocks the thing it
is auditing is worse than no audit log.

The log is the answer to "what did the agent actually do", which on this
machine is a question with real stakes. It is gitignored — it is machine
state, and it records command text that can carry credentials.
"""
import datetime
import json
import os
import pathlib
import sys


def main():
    try:
        data = json.load(sys.stdin)

        # Repo-local rather than upstream's ~/.claude/session-logs: this
        # machine's audit trail belongs with the repo that governs it, and
        # .gitignore already excludes .claude/audit/.
        log_dir = pathlib.Path(__file__).resolve().parent.parent / "audit"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / f"{datetime.date.today().isoformat()}.jsonl"

        ti = data.get("tool_input", {}) or {}
        tool = data.get("tool_name", "?")
        detail = (
            ti.get("command") if tool == "Bash" else
            ti.get("file_path") if tool in ("Read", "Edit", "Write") else
            ti.get("pattern") if tool == "Grep" else
            ti.get("url") if tool == "WebFetch" else
            None
        )
        if isinstance(detail, str) and len(detail) > 4000:
            detail = detail[:4000] + "…(truncated)"

        entry = {
            "ts": datetime.datetime.now(datetime.timezone.utc)
                  .isoformat().replace("+00:00", "Z"),
            "session_id": data.get("session_id"),
            "cwd": data.get("cwd"),
            "tool": tool,
            "detail": detail,
            "is_error": (data.get("tool_response") or {}).get("isError", False),
        }
        with log_file.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        return


if __name__ == "__main__":
    main()
    os._exit(0)

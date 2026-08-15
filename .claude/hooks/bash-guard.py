#!/usr/bin/env python3
"""PreToolUse:Bash guard — applies the reversibility ruleset.

Vendored from uaziz1/claude-code-guardrails (MIT) at
0b8671079de887fbee051a8a8661c5a809a5c247. See VENDOR.md for what was changed
and why. The machinery here is theirs; the ruleset in `_ruleset.py` is not.

Why a hook and not `settings.json` deny entries: declared permission rules are
prefix globs. `Bash(sudo *)` does not match `cd /tmp && sudo dd …`, and no
amount of glob writing fixes that, because the rule is matched against the
command as a unit. A PreToolUse hook receives the whole command string and can
scan anywhere in it. The deny entries in settings.json stay as a second layer;
this is the enforcement.

Three outcomes, and the middle one is the point:

    exit 2               DENY  — irreversible; stderr goes back to the agent
    exit 0 + JSON        ASK   — privileged and covered; the user decides
    exit 0, no output    —     — falls through to the normal permission flow

Fail-closed: if this hook raises, it denies. An exception here means the
ruleset did not run, and "the guard crashed" must never read as "allowed".
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _ruleset import ASK, DENY  # noqa: E402


def deny(label, why, cmd, pattern):
    """Exit 2. Claude Code feeds stderr back to the agent, so this text is
    addressed to it: say what tripped, and what the reversible route is."""
    print(f"DENIED (irreversible): {label}", file=sys.stderr)
    print(f"  why: {why}", file=sys.stderr)
    print(f"  command: {cmd}", file=sys.stderr)
    print(f"  pattern: {pattern}", file=sys.stderr)
    print(
        "\nThis is not a privilege block — sudo, rpm-ostree and systemctl are"
        "\nthis machine's ordinary work. It is denied because no rpm-ostree"
        "\nrollback, no etckeeper diff and no /var/home backup would bring it"
        "\nback. If you believe it is genuinely needed, say so and stop; a"
        "\nhuman runs it outside the session, or the ruleset changes first.",
        file=sys.stderr,
    )
    sys.exit(2)


def ask(label, why):
    """Exit 0 with a decision body. Claude Code prompts the user."""
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": f"{label} — {why}",
        }
    }))
    sys.exit(0)


def main():
    data = json.load(sys.stdin)
    if data.get("tool_name") != "Bash":
        sys.exit(0)

    cmd = data.get("tool_input", {}).get("command", "")
    if not cmd.strip():
        sys.exit(0)

    # DENY is checked in full before ASK. A command matching both is
    # irreversible — the deny wins, and the order here is what guarantees it.
    for pattern, label, why in DENY:
        if re.search(pattern, cmd):
            deny(label, why, cmd, pattern)

    for pattern, label, why in ASK:
        if re.search(pattern, cmd):
            ask(label, why)

    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 — deliberate catch-all
        # Fail closed. An unparseable payload or a bad pattern must not
        # degrade into "allowed".
        print(f"DENIED: bash-guard failed to evaluate the command: {exc}",
              file=sys.stderr)
        print("  Fix the guard before continuing. Do not work around it.",
              file=sys.stderr)
        sys.exit(2)

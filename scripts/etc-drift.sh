#!/usr/bin/env bash
# Confirms etckeeper actually committed the last /etc change. Per CLAUDE.md:
# an uncommitted /etc change is irreversible in practice, since etckeeper's
# git history is the only thing that makes docs/recovery.md Card 2 possible.
#
# Report-only: never runs `etckeeper commit` itself, only prints the exact
# command if something is uncommitted. Needs root to read /etc's git state,
# via pkexec (not sudo — this script has no TTY to prompt against when run
# non-interactively, and pkexec is CLAUDE.md's rule for root commands anyway).
#
# Idempotent: safe to re-run any time.
#
# Usage: scripts/etc-drift.sh

set -euo pipefail

out="$(pkexec bash -c '
if ! git -C /etc rev-parse --git-dir >/dev/null 2>&1; then
    echo "MISSING_REPO"
    exit 0
fi
echo "COMMIT $(git -C /etc log -1 --format="%h %ci %s")"
git -C /etc status --porcelain
')"

if [ -z "$out" ]; then
    echo "error   pkexec authentication failed or was cancelled" >&2
    exit 2
fi

if [ "$out" = "MISSING_REPO" ]; then
    echo "missing  /etc is not a git repository — etckeeper was never initialised"
    echo
    echo "Run: rpm-ostree install etckeeper && systemctl reboot"
    echo "Then: pkexec etckeeper init && pkexec etckeeper commit \"baseline\""
    exit 1
fi

last_commit="${out#COMMIT }"
last_commit="${last_commit%%$'\n'*}"
echo "last etckeeper commit: $last_commit"

dirty="$(printf '%s\n' "$out" | tail -n +2)"

if [ -n "$dirty" ]; then
    echo
    echo "missing  uncommitted changes in /etc:"
    echo "$dirty" | sed 's/^/  /'
    echo
    echo "Run: pkexec etckeeper commit \"describe the change\""
    exit 1
fi

echo "ok      /etc clean, nothing uncommitted"

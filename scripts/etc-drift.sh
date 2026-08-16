#!/usr/bin/env bash
# Confirms etckeeper actually committed the last /etc change. Per CLAUDE.md:
# an uncommitted /etc change is irreversible in practice, since etckeeper's
# git history is the only thing that makes docs/recovery.md Card 2 possible.
#
# Report-only: never runs `etckeeper commit` itself, only prints the exact
# command if something is uncommitted. Needs sudo to read /etc's git state —
# that's the ask-tier prompt working as intended, not a bug in this script.
#
# Idempotent: safe to re-run any time.
#
# Usage: scripts/etc-drift.sh

set -euo pipefail

if ! sudo git -C /etc rev-parse --git-dir >/dev/null 2>&1; then
    echo "missing  /etc is not a git repository — etckeeper was never initialised"
    echo
    echo "Run: rpm-ostree install etckeeper && systemctl reboot"
    echo "Then: sudo etckeeper init && sudo etckeeper commit \"baseline\""
    exit 1
fi

last_commit="$(sudo git -C /etc log -1 --format='%h %ci %s' 2>/dev/null || echo none)"
echo "last etckeeper commit: $last_commit"

dirty="$(sudo git -C /etc status --porcelain 2>/dev/null || true)"

if [ -n "$dirty" ]; then
    echo
    echo "missing  uncommitted changes in /etc:"
    echo "$dirty" | sed 's/^/  /'
    echo
    echo "Run: sudo etckeeper commit \"describe the change\""
    exit 1
fi

echo "ok      /etc clean, nothing uncommitted"

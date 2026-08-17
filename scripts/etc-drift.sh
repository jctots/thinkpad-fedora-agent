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

# Authenticate sudo up front, with stderr visible, so a TTY-less/auth
# failure here is reported as what it is instead of being swallowed by a
# later `git rev-parse` check and misread as "not a git repository".
if ! sudo -v; then
    echo "error   sudo authentication failed — run this in a real terminal" >&2
    echo "        (fingerprint/password prompts need a real TTY; this" >&2
    echo "        script cannot tell a failed sudo apart from a genuinely" >&2
    echo "        missing /etc git repo if this check is skipped)" >&2
    exit 2
fi

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

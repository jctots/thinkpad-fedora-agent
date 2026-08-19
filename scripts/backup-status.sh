#!/usr/bin/env bash
# Age of the last successful /var/home kopia snapshot. Referenced by
# docs/recovery.md Card 3 as the first check before trusting this layer —
# a backup that last ran nine days ago is not the layer you think you're
# standing on.
#
# Report-only: never creates a snapshot itself, only reads state.
# Idempotent: safe to re-run any time.
#
# Usage: scripts/backup-status.sh

set -euo pipefail

MAX_AGE_HOURS="${MAX_AGE_HOURS:-48}"

if ! command -v kopia >/dev/null 2>&1; then
    echo "missing kopia is not installed — scripts/layer-packages.sh"
    exit 1
fi

if ! kopia repository status >/dev/null 2>&1; then
    echo "missing kopia repository not connected — docs/recovery.md Card 3"
    exit 1
fi

result="$(kopia snapshot list "$HOME" --json 2>/dev/null | python3 -c "
import json, sys, datetime
snaps = json.load(sys.stdin)
if not snaps:
    print('NONE')
    sys.exit()
latest = max(snaps, key=lambda s: s['startTime'])
dt = datetime.datetime.fromisoformat(latest['startTime'].replace('Z', '+00:00'))
age_h = (datetime.datetime.now(datetime.timezone.utc) - dt).total_seconds() / 3600
print(f'{dt.isoformat()} {age_h:.0f}')
")"

if [ "$result" = "NONE" ]; then
    echo "missing no snapshot found for $HOME"
    exit 1
fi

read -r snap_time age_h <<< "$result"

if [ "$age_h" -gt "$MAX_AGE_HOURS" ]; then
    echo "stale   last snapshot ${age_h}h ago (threshold ${MAX_AGE_HOURS}h) — ${snap_time}"
    exit 1
else
    echo "ok      last snapshot ${age_h}h ago — ${snap_time}"
fi

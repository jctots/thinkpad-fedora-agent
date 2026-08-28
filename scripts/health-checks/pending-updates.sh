#!/usr/bin/env bash
# Check module for scripts/system-health-check.sh — see that file for the
# contract (exit 0 = healthy, exit 1 = alert, stdout is the detail).
#
# Base layer: read-only rpm-ostree/flatpak queries, no root needed, same
# commands `scripts/update-check.sh` already uses for the full report.
# Deliberately does NOT alert on "an update exists" — that would fire on
# most days and defeat the point of a quiet-unless-genuinely-wrong check.
# Instead it tracks how long an update has been sitting unapplied and only
# alerts once that exceeds STALE_DAYS. Run `scripts/update-check.sh` (or the
# /update-check skill) for the full itemized report once notified.
set -euo pipefail

STALE_DAYS=7
STATE_FILE="${HOME}/.local/state/system-health-check/pending-updates.state"
mkdir -p "$(dirname "$STATE_FILE")"

pending=""

if command -v rpm-ostree >/dev/null 2>&1; then
  if rpm-ostree upgrade --check 2>&1 | grep -qi "AvailableUpdate"; then
    pending="${pending}os-image "
  fi
fi

if command -v flatpak >/dev/null 2>&1; then
  fp_preview="$(printf 'n\n' | flatpak update 2>&1 || true)"
  if echo "$fp_preview" | grep -qE '^\s*[0-9]+\.'; then
    pending="${pending}flatpak "
  fi
fi

now="$(date +%s)"

if [ -z "$pending" ]; then
  rm -f "$STATE_FILE"
  echo "no updates pending"
  exit 0
fi

if [ -f "$STATE_FILE" ]; then
  first_seen="$(cat "$STATE_FILE")"
else
  first_seen="$now"
  echo "$first_seen" > "$STATE_FILE"
fi

age_days=$(( (now - first_seen) / 86400 ))

if [ "$age_days" -ge "$STALE_DAYS" ]; then
  echo "Updates pending for ${age_days}d (threshold ${STALE_DAYS}d): ${pending}— run /update-check for details"
  exit 1
fi

echo "updates pending (${pending}) for ${age_days}d, not yet stale (threshold ${STALE_DAYS}d)"

#!/usr/bin/env bash
# Check module for scripts/system-health-check.sh — see that file for the
# contract (exit 0 = healthy, exit 1 = alert, stdout is the detail).
#
# incidents/I037: Bitwarden's flatpak silently hid its
# "Unlock with system authentication" toggle when its local secret cache
# (a keyring-portal-backed file per app under ~/.var/app/*/data/keyrings/)
# went stale — no error surfaced anywhere except this exact journal line,
# and only fingerprint failing in the UI weeks later revealed it. This
# watches for the same failure class recurring, for any sandboxed app, not
# just Bitwarden.
#
# incidents/I038 false-alert follow-up: `journalctl --user` with no boot
# filter searches the whole persistent journal, not just the current boot.
# This machine has a known s2idle-resume clock-jump bug (see
# thinkpad-fedora-extras I003/I010) that can leave old log lines with
# timestamps skewed *ahead* of real time — a dead process from a prior boot
# can then still match a "last 15m" `--since` window today, alerting on an
# already-fixed, no-longer-running problem. `-b 0` scopes the search to the
# current boot only, which this check has no reason not to do anyway: a
# process from a previous boot can never be the live thing this check cares
# about.
set -euo pipefail

WINDOW="15 min ago"
matches="$(journalctl --user -b 0 --since "$WINDOW" --no-pager 2>/dev/null \
  | grep -iE "Credential Storage Listener.*(Incorrect secret|failed)" || true)"

if [ -z "$matches" ]; then
  echo "no credential-storage errors in the last 15m"
  exit 0
fi

count="$(echo "$matches" | wc -l)"
sample="$(echo "$matches" | tail -3)"
echo "credential storage errors in the last 15m (${count} lines) — likely an app's portal-backed secret cache is stale (see I037). Sample:
${sample}"
exit 1

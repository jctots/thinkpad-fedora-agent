#!/usr/bin/env bash
# Check module for scripts/system-health-check.sh — see that file for the
# contract (exit 0 = healthy, exit 1 = alert, stdout is the detail).
#
# incidents/I015: fprintd crashes inside the Goodix TOD driver (an upstream
# bug, no fix available) and, before the fix here, stayed dead indefinitely
# because the service had no restart policy of its own. I015 added a
# Restart=on-failure drop-in, so a crash now retries — but systemd's default
# start-limit (5 restarts / 10s) means a fast enough crash-loop still ends
# in `failed`, same detection shape as tb-bridge. No root needed:
# `systemctl is-active` on a system unit is readable by any user.
set -euo pipefail

active="$(systemctl is-active fprintd.service 2>/dev/null || true)"

if [ "$active" = "failed" ]; then
  echo "fprintd.service is failed (crash-looped past the I015 restart-policy limit) — see incidents/I015"
  exit 1
fi

echo "fprintd.service is '$active'"

#!/usr/bin/env bash
# Check module for scripts/system-health-check.sh — see that file for the
# contract (exit 0 = healthy, exit 1 = alert, stdout is the detail).
#
# Watches tb-bridge.service (docs/thunderbird-cli.md) for genuine failures.
# "Genuine failure" is deliberately narrow — the unit is `static` by design
# (started on demand by betterbird-with-bridge, not at login/boot), so "not
# active" is the normal idle state whenever Betterbird just isn't open yet.
# This only alerts on:
#   1. the unit in `failed` state (systemd gave up restarting it — the
#      crash-loop case from I029), or
#   2. Betterbird is running but the bridge isn't active (it should have
#      started alongside it via the wrapper and didn't).
set -euo pipefail

active="$(systemctl --user is-active tb-bridge.service 2>/dev/null || true)"

if [ "$active" = "failed" ]; then
  echo "tb-bridge.service is failed (crash-looped) — see incidents/I029"
  exit 1
fi

if flatpak ps 2>/dev/null | grep -q "eu.betterbird.Betterbird" && [ "$active" != "active" ]; then
  echo "Betterbird is running but tb-bridge.service is '$active', not active"
  exit 1
fi

echo "tb-bridge.service is '$active'"

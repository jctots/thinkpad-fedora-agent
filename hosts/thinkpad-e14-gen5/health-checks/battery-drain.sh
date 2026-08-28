#!/usr/bin/env bash
# Check module for scripts/system-health-check.sh — see that file for the
# contract (exit 0 = healthy, exit 1 = alert, stdout is the detail).
#
# Flags unusually high sustained battery discharge — the kind of thing that
# means a runaway process is about to strand this machine well before a
# scheduled charge. Deliberately requires two consecutive over-threshold
# runs (30 minutes apart) before alerting, so one noisy sample (a build, a
# video call) doesn't page for something that already passed. Only
# evaluated while actually discharging — charging/full/AC states are
# always silent.
#
# ALERT_WATTS is a first-pass heuristic, not a measured baseline: this
# host's normal idle draw is ~8-15W with the dGPU disabled (see I019,
# gpu-toggle.sh), a busy-but-not-abnormal session (several Claude CLI
# instances, Brave, VS Code, Betterbird) was observed at ~24W. 35W leaves
# headroom above that. Revisit using summary.log's history once there's a
# few weeks of real samples — this number is a guess, not a spec.
set -euo pipefail

ALERT_WATTS=35
STATE_FILE="${HOME}/.local/state/system-health-check/battery-drain.state"
BAT_DIR="/sys/class/power_supply/BAT0"

mkdir -p "$(dirname "$STATE_FILE")"

if [ ! -d "$BAT_DIR" ]; then
  echo "no BAT0 under /sys/class/power_supply — skipping (desktop or renamed battery)"
  exit 0
fi

status="$(cat "${BAT_DIR}/status" 2>/dev/null || echo unknown)"

if [ "$status" != "Discharging" ]; then
  echo 0 > "$STATE_FILE"
  echo "battery status: $status (not evaluating draw)"
  exit 0
fi

power_now_uw="$(cat "${BAT_DIR}/power_now" 2>/dev/null || echo 0)"
watts=$(( power_now_uw / 1000000 ))
streak="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"

if [ "$watts" -gt "$ALERT_WATTS" ]; then
  streak=$((streak + 1))
  echo "$streak" > "$STATE_FILE"
  if [ "$streak" -ge 2 ]; then
    pct="$(cat "${BAT_DIR}/capacity" 2>/dev/null || echo '?')"
    echo "Sustained high discharge: ${watts}W (threshold ${ALERT_WATTS}W) for ${streak} consecutive checks, battery at ${pct}%"
    exit 1
  fi
  echo "discharge ${watts}W over threshold (${ALERT_WATTS}W) — 1st occurrence, not yet sustained"
  exit 0
fi

echo 0 > "$STATE_FILE"
echo "discharge ${watts}W (threshold ${ALERT_WATTS}W)"

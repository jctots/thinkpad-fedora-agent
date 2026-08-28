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
# host's normal idle draw is ~8-15W with the dGPU `off` (see I019,
# gpu-toggle.sh), a busy-but-not-abnormal session (several Claude CLI
# instances, Brave, VS Code, Betterbird) was observed at ~24W. 35W leaves
# headroom above that. Revisit using the samples log below once there's a
# few weeks of real off-mode data — this number is a guess, not a spec.
#
# dGPU mode-aware since the nvidia-vs-nouveau battery-drain comparison this
# check exists to support (I019 follow-up): every discharging sample is
# tagged with the current gpu-toggle.sh mode and appended to
# battery-drain-samples.log regardless of whether it alerts, specifically
# so nvidia and nouveau runs can be diffed against each other later. The
# 35W ALERT_WATTS threshold only applies in `off` mode, where it was
# calibrated — `nvidia`/`nouveau` modes are expected to draw more just by
# having the dGPU loaded, so alerting there with an off-mode threshold
# would just be noise during the exact investigation this exists for.
set -euo pipefail

ALERT_WATTS=35
STATE_FILE="${HOME}/.local/state/system-health-check/battery-drain.state"
SAMPLES_FILE="${HOME}/.local/state/system-health-check/battery-drain-samples.log"
BAT_DIR="/sys/class/power_supply/BAT0"
CONF_FILE="/etc/modprobe.d/dgpu-driver-select.conf"

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

mode="nouveau"  # kernel default when no conf file is present at all
if [ -f "$CONF_FILE" ]; then
  if grep -q '^install nvidia ' "$CONF_FILE" && grep -q '^install nouveau ' "$CONF_FILE"; then
    mode="off"
  elif grep -q '^install nouveau ' "$CONF_FILE"; then
    mode="nvidia"
  elif grep -q '^install nvidia ' "$CONF_FILE"; then
    mode="nouveau"
  fi
fi

power_now_uw="$(cat "${BAT_DIR}/power_now" 2>/dev/null || echo 0)"
watts=$(( power_now_uw / 1000000 ))
pct="$(cat "${BAT_DIR}/capacity" 2>/dev/null || echo '?')"
streak="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"

echo "$(date -Iseconds) mode=${mode} watts=${watts} capacity=${pct}%" >> "$SAMPLES_FILE"

if [ "$mode" != "off" ]; then
  echo 0 > "$STATE_FILE"
  echo "discharge ${watts}W, dGPU mode '${mode}' — logged to samples file, not evaluated against ${ALERT_WATTS}W (that threshold is calibrated for 'off' mode only)"
  exit 0
fi

if [ "$watts" -gt "$ALERT_WATTS" ]; then
  streak=$((streak + 1))
  echo "$streak" > "$STATE_FILE"
  if [ "$streak" -ge 2 ]; then
    echo "Sustained high discharge: ${watts}W (threshold ${ALERT_WATTS}W) for ${streak} consecutive checks, battery at ${pct}%, dGPU mode 'off'"
    exit 1
  fi
  echo "discharge ${watts}W over threshold (${ALERT_WATTS}W) — 1st occurrence, not yet sustained"
  exit 0
fi

echo 0 > "$STATE_FILE"
echo "discharge ${watts}W (threshold ${ALERT_WATTS}W), dGPU mode 'off'"

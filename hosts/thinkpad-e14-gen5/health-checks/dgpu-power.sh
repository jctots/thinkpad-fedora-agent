#!/usr/bin/env bash
# Check module for scripts/system-health-check.sh — see that file for the
# contract (exit 0 = healthy, exit 1 = alert, stdout is the detail).
#
# Flags the NVIDIA MX550 dGPU drawing power while gpu-toggle.sh's selected
# mode says it should be fully idle. This is deliberately scoped to `off`
# mode only: whether the PCIe device is runtime-suspended (D3, near-zero
# draw) is the same signal that made nouveau's silent auto-bind visible in
# the first place (see hosts/thinkpad-e14-gen5/README.md § GPU) — a driver
# staying loaded/bound after a mode switch, or something waking the device
# back up, both show up here as "active" instead of "suspended".
#
# Deliberately does NOT alert during `nvidia`/`nouveau` mode: the device
# being "active" there is indistinguishable from a legitimate gaming
# session without per-process render-client attribution, which risks
# alerting on the exact thing those modes exist for. If sustained high
# *battery* draw during a nominally idle gaming-mode session turns out to
# be a real problem, that's battery-drain.sh's job (system-wide wattage),
# not this check's.
#
# Requires two consecutive over-threshold runs (30 minutes apart, same
# pattern as battery-drain.sh) before alerting, so a check that lands
# mid-mode-switch (before the next reboot fully applies a blacklist) or a
# brief PM transition doesn't page for something already settled.
set -euo pipefail

PCI_ADDR="0000:02:00.0"  # NVIDIA MX550 — see hosts/thinkpad-e14-gen5/README.md
CONF_FILE="/etc/modprobe.d/dgpu-driver-select.conf"
STATE_FILE="${HOME}/.local/state/system-health-check/dgpu-power.state"
RUNTIME_STATUS_FILE="/sys/bus/pci/devices/${PCI_ADDR}/power/runtime_status"

mkdir -p "$(dirname "$STATE_FILE")"

if [ ! -f "$RUNTIME_STATUS_FILE" ]; then
  echo "no PCI runtime PM status at ${RUNTIME_STATUS_FILE} — dGPU not present or path changed"
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

if [ "$mode" != "off" ]; then
  echo 0 > "$STATE_FILE"
  echo "mode: $mode — dGPU expected active, not evaluating (nvidia/nouveau gaming modes are out of scope, see header)"
  exit 0
fi

runtime_status="$(cat "$RUNTIME_STATUS_FILE" 2>/dev/null || echo unknown)"
streak="$(cat "$STATE_FILE" 2>/dev/null || echo 0)"

if [ "$runtime_status" != "suspended" ]; then
  streak=$((streak + 1))
  echo "$streak" > "$STATE_FILE"
  if [ "$streak" -ge 2 ]; then
    loaded="$(grep -oE '^(nvidia|nouveau)' /proc/modules | tr '\n' ' ' || echo none)"
    echo "dGPU mode is 'off' but PCI runtime status is '${runtime_status}' (expected 'suspended') for ${streak} consecutive checks — modules loaded: ${loaded:-none}. A reboot may be needed for the blacklist to fully apply, or something is waking the device."
    exit 1
  fi
  echo "mode 'off' but runtime status '${runtime_status}' — 1st occurrence, not yet sustained"
  exit 0
fi

echo 0 > "$STATE_FILE"
echo "mode 'off', PCI runtime status 'suspended' — dGPU idle as expected"

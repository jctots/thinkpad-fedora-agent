#!/usr/bin/env bash
# Toggle the NVIDIA MX550 dGPU on/off at the module level, for this host only.
#
# Why this exists: incidents/I019 — s2idle suspend fails 100% of the time on
# driver 610.57.04 due to an open upstream GSP-unload bug
# (NVIDIA/open-gpu-kernel-modules#1142), independent of local config. The
# `nvidia` module is normally loaded at every boot regardless of whether the
# dGPU is actually in use (Optimus/PRIME offload is opt-in per-app via env
# vars — see hosts/thinkpad-e14-gen5/README.md § GPU). This script blacklists
# the module by default so `nv_suspend_devices` never runs and s2idle can be
# tested/used on the Intel iGPU alone, then re-enables it on request (before
# a gaming session).
#
# Report-only status (`status`), plus `enable`/`disable` which write the
# blacklist file via pkexec (its own GUI auth dialog gates the change —
# no separate confirmation step) and commit it via etckeeper. Meant to be
# run directly at a terminal for the routine gaming-on/gaming-off case,
# without going through an agent session.
#
# A reboot is required either direction — see the module-in-use note below.
set -euo pipefail

BLACKLIST_FILE="/etc/modprobe.d/nvidia-disabled.conf"

usage() {
  echo "Usage: $0 {status|disable|enable}"
  echo
  echo "  status   report whether the dGPU is currently blacklisted, and whether"
  echo "           the nvidia module is loaded right now"
  echo "  disable  blacklist the nvidia module (stops it loading at boot) —"
  echo "           use to test/keep s2idle suspend working (incidents/I019)"
  echo "  enable   remove the blacklist — use before a gaming session"
  echo
  echo "Either direction needs a reboot to fully take effect: the module is"
  echo "in active use by GNOME Shell/Xorg/Wayland once loaded, so a live"
  echo "'rmmod nvidia' would fail with 'in use' or destabilize the running"
  echo "session rather than cleanly unloading it."
  exit 1
}

cmd="${1:-status}"

case "$cmd" in
  status)
    if [ -f "$BLACKLIST_FILE" ]; then
      echo "disabled (blacklisted) — $BLACKLIST_FILE present"
    else
      echo "enabled (not blacklisted) — $BLACKLIST_FILE absent"
    fi
    if grep -q '^nvidia ' /proc/modules; then
      echo "nvidia module: currently loaded this boot"
    else
      echo "nvidia module: not loaded this boot"
    fi
    ;;
  disable)
    if [ -f "$BLACKLIST_FILE" ]; then
      echo "already disabled — $BLACKLIST_FILE present, nothing to do"
      exit 0
    fi
    cat <<'EOF' | pkexec tee "$BLACKLIST_FILE" >/dev/null
# Disables the NVIDIA MX550 dGPU at the module level. See
# incidents/I019 and hosts/thinkpad-e14-gen5/README.md § GPU.
# Re-enable: hosts/thinkpad-e14-gen5/gpu-toggle.sh enable
# 'install ... /bin/false', not 'blacklist': plain blacklist only
# blocks alias-triggered autoload, not an explicit 'modprobe nvidia'
# call — something on this host still made that call even with
# nvidia-powerd masked (see I019 follow-up, cause not fully
# isolated). install intercepts both paths.
install nvidia /bin/false
install nvidia_drm /bin/false
install nvidia_modeset /bin/false
install nvidia_uvm /bin/false
EOF
    pkexec etckeeper commit 'Disable NVIDIA dGPU (I019 s2idle isolation test)'
    echo "Done. Reboot to take effect: systemctl reboot"
    ;;
  enable)
    if [ ! -f "$BLACKLIST_FILE" ]; then
      echo "already enabled — $BLACKLIST_FILE absent, nothing to do"
      exit 0
    fi
    pkexec rm "$BLACKLIST_FILE"
    pkexec etckeeper commit 'Re-enable NVIDIA dGPU (gaming session)'
    echo "Done. Reboot to take effect: systemctl reboot"
    ;;
  *)
    usage
    ;;
esac

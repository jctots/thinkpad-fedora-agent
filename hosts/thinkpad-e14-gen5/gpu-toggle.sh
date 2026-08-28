#!/usr/bin/env bash
# Select which driver (if any) claims the NVIDIA MX550 dGPU, for this host
# only, and keep Steam's per-game GPU offload env vars in sync with that
# choice so any game launched afterward routes to the right GPU without a
# separate manual step.
#
# Why this exists: incidents/I019 — s2idle suspend fails 100% of the time on
# the proprietary driver (610.57.04) due to an open upstream GSP-unload bug
# (NVIDIA/open-gpu-kernel-modules#1142), independent of local config. The
# `nvidia` module is normally loaded at every boot regardless of whether the
# dGPU is actually in use (Optimus/PRIME offload is opt-in per-app), so the
# module being loaded at all is what exposes the suspend path to that bug.
# This script blacklists it by default so s2idle can be tested/used on the
# Intel iGPU alone, then switches back on for a gaming session.
#
# Three modes, not a toggle: blacklisting `nvidia` alone does not idle the
# dGPU — the kernel's in-tree `nouveau` driver auto-binds to the same PCI
# device instead (confirmed live on this host: `lsmod`/`lspci -k` showed
# nouveau loaded and bound while `nvidia` sat blacklisted). So "off" has to
# blacklist both, and "nvidia" mode has to blacklist nouveau in turn so the
# two drivers don't race for the same device at boot.
#
#   off      dGPU fully idle — both drivers blacklisted, Intel iGPU only.
#            Use for s2idle testing / daily non-gaming use (I019).
#   nvidia   proprietary driver — CUDA, NVML (nvidia-smi/nvtop), the driver
#            this host's kmod-nvidia is pinned and signed for. Has the I019
#            suspend bug — expect suspend to fail/be untested while active.
#   nouveau  in-tree open driver — no CUDA, no NVML (nvtop/nvidia-smi see
#            nothing), but does not carry the I019 GSP-unload suspend bug
#            (nouveau doesn't use GSP the same way proprietary does — a
#            reasonable expectation, not verified with an actual suspend
#            cycle on this host yet).
#
# Each mode also rewrites Steam's Flatpak env overrides (Steam-wide, since
# every game is a child process of Steam and inherits them) so a game
# launched right after a mode switch offloads correctly without per-game
# launch-option edits:
#   off      no offload vars — everything renders on the iGPU anyway.
#   nvidia   __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia
#            (proprietary-only; confirmed a silent no-op under nouveau — I005)
#   nouveau  DRI_PRIME=1 (the proprietary vars are no-ops here; DRI_PRIME is
#            what worked under nouveau before this host switched to
#            proprietary for NVML visibility — see README.md § GPU)
# Steam overrides are skipped with a note, not a failure, if the Steam
# Flatpak isn't installed on this machine (extras-layer app, not universal).
#
# Report-only status (`status`), plus the three mode commands which write
# the modprobe config via pkexec (its own GUI auth dialog gates the change
# — no separate confirmation step) and commit it via etckeeper. Meant to be
# run directly at a terminal for the routine gaming-on/gaming-off case,
# without going through an agent session.
#
# `enable`/`disable` remain as aliases for `nvidia`/`nouveau` — the two
# modes those commands used to cover — since incidents/I019-I021 reference
# them by those names.
#
# A reboot is required for any mode change to fully take effect: whichever
# module is currently in active use by GNOME Shell/Xorg/Wayland can't be
# cleanly unloaded live — a 'rmmod' would fail with 'in use' or destabilize
# the running session rather than switching drivers underneath it.
#
# /etc/modprobe.d alone does NOT block nouveau on this host: nouveau.ko.xz
# is baked into the initramfs for early KMS (plymouth splash), and dracut's
# own copy of /etc/modprobe.d — snapshotted at initramfs-build time — never
# sees a rule written after that build. Confirmed live: the 'nvidia' mode
# conf (install nouveau /bin/false) was in place and etckeeper-committed,
# yet nouveau still bound the GPU at boot and nvidia's probe failed with
# "GPU already bound to nouveau" (I034). Fix: dracut has its own cmdline
# override, rd.driver.blacklist=<mod>, read directly inside the initrd
# regardless of what /etc/modprobe.d says — set via `rpm-ostree kargs` so
# it's baked into the boot entry itself, no initramfs rebuild required.
# Applied for 'off' and 'nvidia' modes (both need nouveau kept out);
# removed for 'nouveau' mode. Reversible the same way any kargs change is:
# `rpm-ostree kargs --delete=...` or `rpm-ostree rollback`.
set -euo pipefail

CONF_FILE="/etc/modprobe.d/dgpu-driver-select.conf"
OLD_CONF_FILE="/etc/modprobe.d/nvidia-disabled.conf"
STEAM_APP="com.valvesoftware.Steam"
NOUVEAU_KARG="rd.driver.blacklist=nouveau"

NVIDIA_MODULES=(nvidia nvidia_drm nvidia_modeset nvidia_uvm)

usage() {
  echo "Usage: $0 {status|off|nvidia|nouveau}"
  echo
  echo "  status   report the selected mode, which module is actually loaded"
  echo "           this boot, and Steam's current GPU offload env vars"
  echo "  off      blacklist both drivers — Intel iGPU only, for s2idle"
  echo "           testing / daily use (incidents/I019)"
  echo "  nvidia   proprietary driver — CUDA + nvidia-smi/nvtop visibility,"
  echo "           carries the I019 suspend bug"
  echo "  nouveau  in-tree open driver — no CUDA/NVML, does not carry I019's"
  echo "           GSP-unload bug (expected, not verified on this host)"
  echo
  echo "  enable   alias for nvidia (legacy name, see I019-I021)"
  echo "  disable  alias for nouveau (legacy name, see I019-I021)"
  echo
  echo "Either direction needs a reboot to fully take effect — the module"
  echo "in current use can't be cleanly swapped out from a live session."
  exit 1
}

module_loaded() {
  grep -q "^$1 " /proc/modules
}

karg_present() {
  rpm-ostree kargs 2>/dev/null | grep -qw -- "$NOUVEAU_KARG"
}

sync_nouveau_karg() {
  # $1 = mode. Keeps the rd.driver.blacklist=nouveau kernel arg in sync
  # with the selected mode — needed because dracut loads nouveau inside
  # the initrd itself, before /etc/modprobe.d is ever consulted.
  local want=0
  case "$1" in
    off|nvidia) want=1 ;;
  esac
  local have=0
  karg_present && have=1

  if [ "$want" = 1 ] && [ "$have" = 0 ]; then
    pkexec rpm-ostree kargs --append="$NOUVEAU_KARG"
  elif [ "$want" = 0 ] && [ "$have" = 1 ]; then
    pkexec rpm-ostree kargs --delete="$NOUVEAU_KARG"
  fi
}

steam_installed() {
  command -v flatpak >/dev/null 2>&1 && flatpak info "$STEAM_APP" >/dev/null 2>&1
}

set_steam_env() {
  # $1 = mode
  if ! steam_installed; then
    echo "Steam Flatpak not installed on this host — skipping offload env vars"
    return 0
  fi
  case "$1" in
    off)
      flatpak override --user --unset-env=__NV_PRIME_RENDER_OFFLOAD \
        --unset-env=__GLX_VENDOR_LIBRARY_NAME --unset-env=DRI_PRIME "$STEAM_APP"
      echo "Steam Flatpak: offload env vars cleared"
      ;;
    nvidia)
      flatpak override --user --unset-env=DRI_PRIME \
        --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__GLX_VENDOR_LIBRARY_NAME=nvidia \
        "$STEAM_APP"
      echo "Steam Flatpak: set for proprietary NVIDIA PRIME offload"
      ;;
    nouveau)
      flatpak override --user --unset-env=__NV_PRIME_RENDER_OFFLOAD \
        --unset-env=__GLX_VENDOR_LIBRARY_NAME --env=DRI_PRIME=1 "$STEAM_APP"
      echo "Steam Flatpak: set for DRI_PRIME/nouveau offload"
      ;;
  esac
}

write_conf() {
  # $1 = mode, writes the modprobe conf blocking whichever module(s)
  # should NOT load in that mode, removes the legacy filename if present,
  # and commits via etckeeper — all in one pkexec call/dialog.
  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  {
    echo "# Selects which driver (if any) claims the NVIDIA MX550 dGPU."
    echo "# See incidents/I019 and hosts/thinkpad-e14-gen5/README.md § GPU."
    echo "# Managed by: hosts/thinkpad-e14-gen5/gpu-toggle.sh"
    echo "# 'install ... /bin/false', not 'blacklist': plain blacklist only"
    echo "# blocks alias-triggered autoload, not an explicit 'modprobe'"
    echo "# call — something on this host still made that call even with"
    echo "# nvidia-powerd masked (see I019 follow-up, cause not fully"
    echo "# isolated). install intercepts both paths."
    case "$1" in
      off)
        for m in "${NVIDIA_MODULES[@]}"; do echo "install $m /bin/false"; done
        echo "install nouveau /bin/false"
        ;;
      nvidia)
        echo "install nouveau /bin/false"
        ;;
      nouveau)
        for m in "${NVIDIA_MODULES[@]}"; do echo "install $m /bin/false"; done
        ;;
    esac
  } > "$tmp"

  # etckeeper commit exits non-zero when there's nothing to commit (e.g.
  # re-running the same mode) — that's not a failure, so don't let it abort
  # the chain under set -e; install/rm having succeeded is what matters.
  pkexec bash -c "install -m 0644 -o root -g root '$tmp' '$CONF_FILE' && \
    rm -f '$OLD_CONF_FILE' && \
    { etckeeper commit 'gpu-toggle.sh: select $1 dGPU mode' || true; }"
}

cmd="${1:-status}"
case "$cmd" in
  enable) cmd=nvidia ;;
  disable) cmd=nouveau ;;
esac

case "$cmd" in
  status)
    mode="unknown / no conf file present (kernel default — nouveau binds)"
    if [ -f "$CONF_FILE" ]; then
      if grep -q '^install nvidia ' "$CONF_FILE" 2>/dev/null && grep -q '^install nouveau ' "$CONF_FILE" 2>/dev/null; then
        mode="off"
      elif grep -q '^install nouveau ' "$CONF_FILE" 2>/dev/null; then
        mode="nvidia"
      elif grep -q '^install nvidia ' "$CONF_FILE" 2>/dev/null; then
        mode="nouveau"
      fi
    elif [ -f "$OLD_CONF_FILE" ]; then
      mode="nouveau (legacy conf file $OLD_CONF_FILE — re-run a mode command to migrate)"
    fi
    echo "Selected mode: $mode"

    want_karg=0
    case "$mode" in
      off|nvidia) want_karg=1 ;;
    esac
    if karg_present; then
      have_karg=1
    else
      have_karg=0
    fi
    if [ "$want_karg" = "$have_karg" ]; then
      echo "nouveau initrd blacklist karg: $([ "$have_karg" = 1 ] && echo present || echo absent) (matches mode)"
    else
      echo "nouveau initrd blacklist karg: $([ "$have_karg" = 1 ] && echo present || echo absent) (MISMATCH — expected $([ "$want_karg" = 1 ] && echo present || echo absent); run '$0 $mode' again or reboot if just changed)"
    fi

    for m in nvidia nouveau; do
      if module_loaded "$m"; then
        echo "$m module: loaded this boot"
      else
        echo "$m module: not loaded this boot"
      fi
    done

    if steam_installed; then
      echo "Steam Flatpak offload env:"
      flatpak override --user --show "$STEAM_APP" 2>/dev/null | grep -A5 '^\[Environment\]' || echo "  (none set)"
    else
      echo "Steam Flatpak not installed on this host"
    fi
    ;;
  off|nvidia|nouveau)
    write_conf "$cmd"
    sync_nouveau_karg "$cmd"
    set_steam_env "$cmd"
    echo "Done. Reboot to take effect: systemctl reboot"
    ;;
  *)
    usage
    ;;
esac

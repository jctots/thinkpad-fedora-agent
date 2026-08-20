#!/usr/bin/env bash
# Fingerprint reader driver for this host's Goodix 27c6:550a sensor.
# Report-only, idempotent, same pattern as scripts/layer-packages.sh — this
# script never installs or overrides anything itself, only prints what's
# missing and the exact commands to run.
#
# Why an override, not a plain layer: 27c6:550a has no upstream libfprint
# support. The working driver is Lenovo's own proprietary TOD blob,
# repackaged (not authored) by the antiderivative Copr — see this
# directory's README.md § Fingerprint reader for the trust reasoning.
# Installing it replaces the base libfprint package.
#
# It has to be two separate `rpm-ostree` invocations, not one
# `override replace` — see incidents/I001-libfprint-tod-override-hardlink-checkout.md.
# `override replace` in one pass hits a real upstream hardlink-checkout bug
# (coreos/rpm-ostree#4116) when the base and replacement packages both ship
# a file at the same path with different content, which is exactly this
# case (/usr/lib/udev/hwdb.d/60-autosuspend-libfprint-2.hwdb). Removing the
# base package in its own pass first, then installing the replacement in a
# second pass, avoids it.

set -euo pipefail

COPR_REPOID="copr.fedorainfracloud.org:antiderivative:libfprint-tod-goodix-0.0.9"
REPO_FILE="/etc/yum.repos.d/_copr_antiderivative-libfprint-tod-goodix-0.0.9.repo"
REPO_URL="https://copr.fedorainfracloud.org/coprs/antiderivative/libfprint-tod-goodix-0.0.9/repo/fedora-\$(rpm -E %fedora)/antiderivative-libfprint-tod-goodix-0.0.9-fedora-\$(rpm -E %fedora).repo"

steps_needed=0

if [ -f "$REPO_FILE" ]; then
  echo "ok      copr repo file present ($REPO_FILE)"
else
  echo "missing copr repo file"
  steps_needed=1
fi

if rpm -q libfprint-tod-goodix >/dev/null 2>&1; then
  echo "ok      libfprint-tod-goodix installed"
else
  echo "missing libfprint-tod-goodix"
  steps_needed=1
fi

if rpm -q libfprint-tod >/dev/null 2>&1; then
  echo "ok      libfprint overridden with libfprint-tod (TOD-enabled build)"
else
  echo "missing libfprint override (still on stock libfprint, TOD sensors won't work)"
  steps_needed=1
fi

if rpm -q fprintd >/dev/null 2>&1; then
  echo "ok      fprintd"
else
  echo "missing fprintd"
  steps_needed=1
fi

overall_missing=0

if [ "$steps_needed" -eq 0 ]; then
  echo
  echo "all fingerprint driver components present — enrolment is still manual"
  echo "(fprintd-enroll), see docs/bootstrap.md Part 4"
else
  overall_missing=1
  echo
  echo "Run (as separate, reviewable commands — do not chain):"
  echo "  sudo curl -Lo $REPO_FILE \"$REPO_URL\""
  echo "  sudo rpm-ostree override remove libfprint"
  echo "  sudo rpm-ostree install libfprint-tod libfprint-tod-goodix"
  echo "  # ^ must be two separate invocations, not one 'override replace' —"
  echo "  #   see incidents/I001-libfprint-tod-override-hardlink-checkout.md"
  echo "  systemctl reboot"
  echo "  # after reboot: fprintd-enroll   (manual, needs a finger — not scripted)"
fi

echo

# --- NVIDIA MX550 dGPU: proprietary driver, pinned kmod-nvidia (RPM Fusion) ---
# This host has an NVIDIA GeForce MX550 (TU117) dGPU alongside the Intel
# Iris Xe iGPU (Optimus/hybrid graphics). It ran fine on the in-tree open
# `nouveau` driver (PRIME offload via DRI_PRIME worked), but nouveau has no
# NVML equivalent, so GPU monitoring tools (nvtop) can never see it — see
# thinkpad-fedora-agent GPU check, 2026-08-17.
#
# NOT using RPM Fusion's akmod-nvidia: its rpm-ostree `%post` build sandbox
# cannot see /etc/pki/akmods/private at build time, so the module it
# produces is never signed, even with a correctly enrolled MOK key — see
# incidents/I004-nvidia-akmod-unsigned-in-rpm-ostree-post-sandbox.md for the
# full diagnosis (proved via a toolbox-container reproduction).
#
# Instead: a `kmod-nvidia` package built and signed in a toolbox container
# (where the signing key IS visible), pinned to one exact kernel build, and
# layered as a LocalPackage. Trade-off, accepted deliberately (see I004 and
# the matching vault decision entry): this does NOT auto-rebuild on kernel
# updates like akmod-nvidia would. On the next `rpm-ostree upgrade` that
# bumps the kernel, this check will start failing — the fix is re-running
# the toolbox build+sign for the new kernel version and reinstalling.
#
# Secure Boot is enabled on this host; the MOK key from the original
# akmod-nvidia attempt is already enrolled and reused for this signing.

nvidia_missing=0
running_kernel="$(uname -r)"

installed_kmod="$(rpm -qa 'kmod-nvidia-*' 2>/dev/null | head -n1)"
if [ -n "$installed_kmod" ]; then
  if [[ "$installed_kmod" == "kmod-nvidia-${running_kernel}"* ]]; then
    echo "ok      $installed_kmod matches running kernel ($running_kernel)"
  else
    echo "missing kmod-nvidia for running kernel — installed package is"
    echo "        '$installed_kmod' but running kernel is '$running_kernel'."
    echo "        A kernel update landed since the pinned build; nouveau (or"
    echo "        nothing) is loading until this is rebuilt for the new kernel."
    nvidia_missing=1
  fi
else
  echo "missing kmod-nvidia (no pinned build installed — see incidents/I004)"
  nvidia_missing=1
fi

if rpm -q akmod-nvidia >/dev/null 2>&1; then
  echo "warn    akmod-nvidia is ALSO installed — this shouldn't be layered"
  echo "        alongside the pinned kmod-nvidia (see I004: its build is"
  echo "        unsigned on this host and will conflict). Expected fix:"
  echo "        sudo rpm-ostree uninstall akmod-nvidia"
  nvidia_missing=1
fi

simple_nvidia_pkgs=()

if rpm -q xorg-x11-drv-nvidia-cuda >/dev/null 2>&1; then
  echo "ok      xorg-x11-drv-nvidia-cuda installed"
else
  echo "missing xorg-x11-drv-nvidia-cuda"
  nvidia_missing=1
  simple_nvidia_pkgs+=("xorg-x11-drv-nvidia-cuda")
fi

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  echo "ok      nvidia-smi reports the driver is loaded and working"
else
  echo "missing nvidia-smi (module not loaded)"
  nvidia_missing=1
fi

if mokutil --list-enrolled 2>/dev/null | grep -qi akmods; then
  echo "ok      akmods signing key enrolled in MOK"
else
  echo "missing akmods signing key enrolled in MOK (required — Secure Boot is enabled on this host)"
  nvidia_missing=1
fi

# nvtop verifies this quirk works, not an app choice — belongs here rather
# than thinkpad-fedora-extras (moved from there 2026-08-17). Its NVIDIA
# support goes exclusively through NVML (libnvidia-ml.so), which only
# exists once the driver above is actually loaded — nvtop has no nouveau
# equivalent at all, so this check doubles as an end-to-end signal that the
# whole quirk (kmod-nvidia + MOK) is working, not just that the package is
# present.
if rpm -q nvtop >/dev/null 2>&1; then
  echo "ok      nvtop installed (GPU monitor — confirms this quirk end-to-end)"
else
  echo "missing nvtop"
  nvidia_missing=1
  simple_nvidia_pkgs+=("nvtop")
fi

kmod_missing=0
if [ -z "$installed_kmod" ] || [[ "$installed_kmod" != "kmod-nvidia-${running_kernel}"* ]]; then
  kmod_missing=1
fi

# Steam's flatpak-wide __GLX_VENDOR_LIBRARY_NAME=nvidia override is a silent
# no-op without a driver-version-matched GL.nvidia runtime extension — see
# I005. Checked here, not just documented, because there's no error when
# it's missing: GLVND just falls back to Mesa and the dGPU sits idle.
if command -v nvidia-smi >/dev/null 2>&1; then
  driver_version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null)"
  # Flatpak extension IDs use dashes (610-57-04), nvidia-smi reports dots (610.57.04).
  driver_version_dashed="${driver_version//./-}"
  if [ -n "$driver_version_dashed" ]; then
    flatpak_gl_missing=0
    if flatpak info "org.freedesktop.Platform.GL.nvidia-${driver_version_dashed}" >/dev/null 2>&1; then
      echo "ok      flatpak GL.nvidia-${driver_version_dashed} runtime installed (64-bit games)"
    else
      echo "missing flatpak GL.nvidia-${driver_version_dashed} runtime (64-bit games silently render on iGPU — see I005)"
      nvidia_missing=1
      flatpak_gl_missing=1
    fi
    if flatpak info "org.freedesktop.Platform.GL32.nvidia-${driver_version_dashed}" >/dev/null 2>&1; then
      echo "ok      flatpak GL32.nvidia-${driver_version_dashed} runtime installed (32-bit games)"
    else
      echo "missing flatpak GL32.nvidia-${driver_version_dashed} runtime (32-bit games silently render on iGPU — see I005)"
      nvidia_missing=1
      flatpak_gl_missing=1
    fi
    if [ "$flatpak_gl_missing" -eq 1 ]; then
      echo "Run: sudo flatpak install --system flathub org.freedesktop.Platform.GL.nvidia-${driver_version_dashed} org.freedesktop.Platform.GL32.nvidia-${driver_version_dashed}"
    fi
  fi
fi

if [ "${#simple_nvidia_pkgs[@]}" -gt 0 ]; then
  echo
  echo "Run: sudo rpm-ostree install ${simple_nvidia_pkgs[*]}   (reboot required)"
fi

# NVreg_TemporaryFilePath mitigation for a fatal s2idle suspend hang — driver
# 610.57.04's kernel-notifier suspend path (NVreg_UseKernelSuspendNotifiers=1)
# failed to allocate pinned memory to back up VRAM at suspend entry
# (NVRM: nvCheckOkFailedNoLog ... NV_ERR_NO_MEMORY, _memdescAllocInternal)
# despite several GB of free RAM — happened 5x across recent boots, fatal
# (unrecoverable hang) once. Redirecting the VRAM backup to a file sidesteps
# the allocation path that failed. See incidents/I018 and the
# "s2idle resume-hang investigation" project memory (still open — this
# mitigates one failure mode, not a confirmed root-cause fix).
if [ -f /etc/modprobe.d/nvidia-suspend-fix.conf ] && grep -q "NVreg_TemporaryFilePath" /etc/modprobe.d/nvidia-suspend-fix.conf 2>/dev/null; then
  echo "ok      NVreg_TemporaryFilePath suspend-OOM mitigation present (see I018)"
else
  echo "missing NVreg_TemporaryFilePath suspend-OOM mitigation (see I018) — GPU"
  echo "        may hard-hang on s2idle suspend under memory fragmentation"
  nvidia_missing=1
fi

if [ "$nvidia_missing" -eq 1 ]; then
  overall_missing=1
fi

if [ "$kmod_missing" -eq 1 ]; then
  echo
  echo "To (re)build a signed kmod-nvidia for the running kernel"
  echo "($running_kernel), in a toolbox container (see I004 for the full"
  echo "diagnosis of why it must be toolbox, not the rpm-ostree sandbox):"
  echo "  In toolbox: scripts/build-signed-kmod.sh nvidia xorg-x11-drv-nvidia-kmodsrc"
  echo "  It builds, signs, verifies, and prints the host-side"
  echo "  rpm-ostree uninstall/install/reboot commands to run."
  echo "  After reboot: nvidia-smi   (confirms the driver is loaded)"
fi

echo

# --- Xbox Wireless Controller (BT): proprietary rumble/mapping driver, pinned kmod-xpadneo ---
# Same shape as the NVIDIA quirk above, same root cause: RPM Fusion-style
# akmod-xpadneo builds unsigned in rpm-ostree's `%post` sandbox despite a
# correctly enrolled MOK — see
# incidents/I006-xpadneo-unsigned-akmod-and-truncated-descriptor-firmware.md.
# Fixed the same way: kmod-xpadneo built and signed in a toolbox container,
# pinned to one exact kernel build, layered as a LocalPackage. Same
# trade-off, same consequence: does NOT auto-rebuild on kernel updates, and
# this check starts failing the next time the kernel bumps.
#
# Second, unrelated finding from I006: even a correctly signed and loaded
# xpadneo can still fail to bind if the controller's own Bluetooth firmware
# is out of date — some units ship a truncated HID report descriptor. That
# has no driver-side fix; the controller has to be updated via the Xbox
# Accessories app (Windows/Xbox console/Android) at least once. This check
# can only verify the *driver* side; a controller with stale firmware will
# still fail to appear in `/proc/bus/input/devices` even with everything
# below green.

xpadneo_missing=0
installed_xpadneo_kmod="$(rpm -qa 'kmod-xpadneo-*' 2>/dev/null | head -n1)"
if [ -n "$installed_xpadneo_kmod" ]; then
  if [[ "$installed_xpadneo_kmod" == "kmod-xpadneo-${running_kernel}"* ]]; then
    echo "ok      $installed_xpadneo_kmod matches running kernel ($running_kernel)"
  else
    echo "missing kmod-xpadneo for running kernel — installed package is"
    echo "        '$installed_xpadneo_kmod' but running kernel is '$running_kernel'."
    echo "        A kernel update landed since the pinned build; the Xbox"
    echo "        controller will fall back to hid-generic (no rumble) or"
    echo "        fail to bind entirely until this is rebuilt."
    xpadneo_missing=1
  fi
else
  echo "missing kmod-xpadneo (no pinned build installed — see incidents/I006)"
  xpadneo_missing=1
fi

if rpm -q akmod-xpadneo >/dev/null 2>&1; then
  echo "warn    akmod-xpadneo is ALSO installed — this shouldn't be layered"
  echo "        alongside the pinned kmod-xpadneo (see I006: its build is"
  echo "        unsigned on this host and will conflict). Expected fix:"
  echo "        sudo rpm-ostree uninstall akmod-xpadneo"
  xpadneo_missing=1
fi

xpadneo_kmod_missing=0
if [ -z "$installed_xpadneo_kmod" ] || [[ "$installed_xpadneo_kmod" != "kmod-xpadneo-${running_kernel}"* ]]; then
  xpadneo_kmod_missing=1
fi

if [ "$xpadneo_missing" -eq 1 ]; then
  overall_missing=1
fi

if [ "$xpadneo_kmod_missing" -eq 1 ]; then
  echo
  echo "To (re)build a signed kmod-xpadneo for the running kernel"
  echo "($running_kernel), in a toolbox container (see I006, and I004 for the"
  echo "underlying sandbox-signing diagnosis this mirrors):"
  echo "  In toolbox: scripts/build-signed-kmod.sh xpadneo akmod-xpadneo"
  echo "  It builds, signs, verifies, and prints the host-side"
  echo "  rpm-ostree uninstall/install/reboot commands to run."
  echo "  After reboot: pair/reconnect the controller, check"
  echo "  /proc/bus/input/devices for an Xbox entry."
  echo
  echo "If the driver is signed and loaded but the controller still doesn't"
  echo "bind ('unbalanced collection' / 'parse failed' in journalctl -k),"
  echo "that's not this — see I006: update the controller's own Bluetooth"
  echo "firmware via the Xbox Accessories app (Windows/Xbox console/Android)."
fi

echo

# --- crash/hang forensics: baseline sensors (PERMANENT, generic) ---
# Standing capability, not tied to any one bug (thinkpad-fedora-agent
# decision D33). Catches any lockup, panic, or hard reset, not just
# s2idle — kept armed even after the investigation below closes.
#   - pm_debug_messages: verbose per-device suspend/resume timing. Resets
#     every boot (/sys/power node, not persisted); pm-debug-messages.service
#     re-arms it at boot.
#   - pm_trace: DROPPED FROM BASELINE 2026-08-20 (incident I017). Stamps a
#     magic code into RTC hardware right before each device's suspend/resume
#     callback — survives even a hard power-off, doesn't depend on journald
#     at all. In practice the RTC corruption it causes is not cosmetic: it
#     seeds a wrong system clock at every boot (RTC-in-localtime delta
#     applied before chrony starts) and only self-corrects once chrony
#     reaches an NTP server, which can take a while. Cost outweighed the one
#     lead it ever produced (`memory48`, one data point). `pm-trace.service`
#     disabled, `/sys/power/pm_trace` written back to 0 — no longer part of
#     this baseline. Re-arm by hand only for a specific future hang, not
#     permanently: `pkexec systemctl enable --now pm-trace.service`.
#   - sysrq bitmask: raises kernel.sysrq to 1 (adds SysRq+W dump-blocked-
#     tasks, SysRq+L backtrace-all-CPUs), usable by hand at the moment
#     something looks hung, before reaching for the power button.
#   - journald baseline sync: 10-crash-baseline-sync.conf loosens
#     SyncIntervalSec from the 5min default to 15s — cheap insurance
#     against losing the last seconds of log to an unflushed page cache
#     on any hard crash, without the continuous fsync/write-amplification
#     cost of a tighter interval held permanently.
#
# All /etc changes here are under etckeeper (reversible: `pkexec etckeeper
# vcs log -- <path>`). None of this is reverted when a single investigation
# closes — see the case-specific block below for what's actually temporary.

baseline_missing=0

if [ "$(cat /sys/power/pm_debug_messages 2>/dev/null)" = "1" ]; then
  echo "ok      pm_debug_messages armed for this boot"
else
  echo "missing pm_debug_messages not armed this boot"
  baseline_missing=1
fi

if systemctl is-enabled pm-debug-messages.service >/dev/null 2>&1; then
  echo "ok      pm-debug-messages.service enabled (re-arms on every boot)"
else
  echo "missing pm-debug-messages.service not enabled"
  baseline_missing=1
fi

if [ "$(cat /sys/power/pm_trace 2>/dev/null)" = "1" ]; then
  echo "warn    pm_trace armed for this boot — dropped from baseline (I017), was corrupting the RTC/clock; disarm with pkexec bash -c 'echo 0 > /sys/power/pm_trace'"
else
  echo "ok      pm_trace not armed (dropped from baseline 2026-08-20, see I017)"
fi

if systemctl is-enabled pm-trace.service >/dev/null 2>&1; then
  echo "warn    pm-trace.service enabled — dropped from baseline (I017); pkexec systemctl disable --now pm-trace.service"
else
  echo "ok      pm-trace.service not enabled (dropped from baseline 2026-08-20, see I017)"
fi

if [ "$(cat /proc/sys/kernel/sysrq 2>/dev/null)" = "1" ]; then
  echo "ok      sysrq bitmask raised (SysRq+W / SysRq+L available)"
else
  echo "missing sysrq bitmask not raised (99-sysrq-debug.conf missing or overridden)"
  baseline_missing=1
fi

if [ -f /etc/systemd/journald.conf.d/10-crash-baseline-sync.conf ]; then
  echo "ok      journald baseline sync drop-in present (10-crash-baseline-sync.conf, 15s)"
else
  echo "missing journald baseline sync drop-in (10-crash-baseline-sync.conf)"
  baseline_missing=1
fi

if [ "$baseline_missing" -eq 1 ]; then
  overall_missing=1
  echo
  echo "Run (as separate, reviewable commands — do not chain):"
  echo "  cat <<'EOF' | pkexec tee /etc/systemd/system/pm-debug-messages.service"
  echo "  [Unit]"
  echo "  Description=Enable verbose kernel PM (suspend/resume) debug messages"
  echo "  Documentation=man:systemd-sleep(8)"
  echo "  DefaultDependencies=no"
  echo "  Before=sysinit.target"
  echo "  "
  echo "  [Service]"
  echo "  Type=oneshot"
  echo "  ExecStart=/usr/bin/bash -c 'echo 1 > /sys/power/pm_debug_messages'"
  echo "  RemainAfterExit=yes"
  echo "  "
  echo "  [Install]"
  echo "  WantedBy=sysinit.target"
  echo "  EOF"
  echo "  pkexec mkdir -p /etc/systemd/journald.conf.d"
  echo "  cat <<'EOF' | pkexec tee /etc/systemd/journald.conf.d/10-crash-baseline-sync.conf"
  echo "  [Journal]"
  echo "  # Baseline for crash/hang forensics (thinkpad-fedora-agent decision D33)."
  echo "  # Permanent, generic, host-pinned — not tied to any single open"
  echo "  # investigation. Default SyncIntervalSec (5min) batches writes, so the"
  echo "  # last seconds before a hard power-cycle can be lost from the page cache."
  echo "  # 15s is loose enough to avoid meaningful fsync/write-amplification cost"
  echo "  # at idle, while still comfortably covering a hard-crash log-loss window."
  echo "  # A live investigation may layer a tighter override on top via a"
  echo "  # higher-sorting conf.d file (see 99-pm-debug-sync.conf) — remove only"
  echo "  # that override when the investigation closes; this baseline stays."
  echo "  SyncIntervalSec=15s"
  echo "  EOF"
  echo "  pkexec mkdir -p /etc/sysctl.d"
  echo "  cat <<'EOF' | pkexec tee /etc/sysctl.d/99-sysrq-debug.conf"
  echo "  # Raises the SysRq function set (adds 'w' dump-blocked-tasks and 'l'"
  echo "  # backtrace-all-CPUs) beyond Fedora's default of 16 (sync only), for"
  echo "  # manual use the moment something looks hung, before the power button."
  echo "  # Part of the permanent crash/hang forensics baseline (thinkpad-fedora-agent"
  echo "  # decision D33) — not tied to the s2idle investigation specifically,"
  echo "  # despite the sysrq being introduced during it."
  echo "  kernel.sysrq = 1"
  echo "  EOF"
  echo "  pkexec systemctl daemon-reload"
  echo "  pkexec systemctl enable --now pm-debug-messages.service"
  echo "  pkexec systemctl restart systemd-journald"
  echo "  pkexec sysctl --system"
  echo "  pkexec etckeeper commit 'Arm permanent crash/hang forensics baseline (D33)'"
fi

echo

# --- s2idle resume-hang investigation: case-specific escalation (TEMPORARY) ---
# Open bug, not a fix: lid-close suspend sometimes never resumes (hard
# power-cycle required). Two pieces layered on top of the permanent
# baseline above, both scoped to this investigation only:
#   - journald 1s fsync: 99-pm-debug-sync.conf overrides the 15s baseline
#     down to 1s (conf.d files apply in sort order, last wins) — a tighter
#     margin specifically because s2idle hangs have shown debug output
#     sitting unflushed at the point of a hard power-cycle.
#   - no_console_suspend kernel arg: keeps the kernel console live through
#     suspend instead of going silent, so messages may print to the
#     physical screen at the moment of freeze.
#
# To remove once the bug is caught — ONLY this block, the baseline above
# stays armed:
#   pkexec rm /etc/systemd/journald.conf.d/99-pm-debug-sync.conf
#   rpm-ostree kargs --delete=no_console_suspend
#   pkexec systemctl restart systemd-journald
#   pkexec etckeeper commit "Remove s2idle escalation, bug diagnosed (see incidents/I0NN)"
#   # then delete this block (not the baseline block above) from quirks.sh

s2idle_escalation_missing=0

if [ -f /etc/systemd/journald.conf.d/99-pm-debug-sync.conf ]; then
  echo "ok      journald escalation sync drop-in present (99-pm-debug-sync.conf, 1s)"
else
  echo "missing journald escalation sync drop-in (99-pm-debug-sync.conf)"
  s2idle_escalation_missing=1
fi

if grep -q 'no_console_suspend' /proc/cmdline 2>/dev/null; then
  echo "ok      no_console_suspend kernel arg active this boot"
else
  echo "missing no_console_suspend not active this boot (check 'rpm-ostree kargs', may need a reboot to apply)"
  s2idle_escalation_missing=1
fi

if [ "$s2idle_escalation_missing" -eq 1 ]; then
  overall_missing=1
  echo
  echo "Run (as separate, reviewable commands — do not chain):"
  echo "  pkexec mkdir -p /etc/systemd/journald.conf.d"
  echo "  cat <<'EOF' | pkexec tee /etc/systemd/journald.conf.d/99-pm-debug-sync.conf"
  echo "  [Journal]"
  echo "  # Case-specific escalation, layered on top of the permanent baseline in"
  echo "  # 10-crash-baseline-sync.conf (SyncIntervalSec=15s; conf.d files are"
  echo "  # applied in sort order, so this 99- file's value wins while present)."
  echo "  # Forces 1s fsyncs so kernel PM debug output survives a hard power-cycle"
  echo "  # during the s2idle resume-hang investigation specifically — see project"
  echo "  # memory \"s2idle resume-hang investigation\" in thinkpad-fedora-agent."
  echo "  # Remove ONLY this file once that investigation closes; the baseline"
  echo "  # reverts automatically, no other action needed (thinkpad-fedora-agent"
  echo "  # decision D33)."
  echo "  SyncIntervalSec=1s"
  echo "  EOF"
  echo "  pkexec systemctl restart systemd-journald"
  echo "  rpm-ostree kargs --append=no_console_suspend"
  echo "  pkexec etckeeper commit 'Arm s2idle debug escalation over crash-forensics baseline'"
fi

# --- fprintd Goodix driver crash-loop mitigation (TEMPORARY, incidents/I015) ---
# fprintd crashes inside libfprint-tod-goodix-550a-0.0.9.so (libusb bulk
# transfer), no fix available upstream (copr repo metadata frozen since
# 2026-03-19). Being D-Bus-activated with no restart policy, a crash left
# it dead until next login. Mitigation restores auto-restart + verbose
# logging while the root cause (possibly a loose charger cable that was
# separately found and fixed the same day — unconfirmed as the trigger)
# is still being watched. Restart=on-failure is a fine permanent default
# either way; only the verbose logging line is worth dropping once there
# has been a clean run with no further crashes.
#
# To remove once confirmed resolved (or the driver gets an upstream fix):
#   pkexec rm /etc/systemd/system/fprintd.service.d/override.conf
#   pkexec systemctl daemon-reload
#   pkexec etckeeper commit "Remove fprintd crash-loop mitigation, see incidents/I015"
#   # then delete this block from quirks.sh

fprintd_mitigation_missing=0

if [ -f /etc/systemd/system/fprintd.service.d/override.conf ]; then
  echo "ok      fprintd.service override present (Restart=on-failure + verbose logging, incidents/I015)"
else
  echo "missing fprintd.service override (incidents/I015 mitigation not applied)"
  fprintd_mitigation_missing=1
fi

if [ "$fprintd_mitigation_missing" -eq 1 ]; then
  overall_missing=1
  echo
  echo "Run (as separate, reviewable commands — do not chain):"
  echo "  pkexec mkdir -p /etc/systemd/system/fprintd.service.d"
  echo "  cat <<'EOF' | pkexec tee /etc/systemd/system/fprintd.service.d/override.conf"
  echo "  [Service]"
  echo "  Restart=on-failure"
  echo "  RestartSec=2"
  echo "  Environment=G_MESSAGES_DEBUG=all"
  echo "  EOF"
  echo "  pkexec systemctl daemon-reload"
  echo "  pkexec etckeeper commit 'Auto-restart fprintd on crash + verbose logging (incidents/I015)'"
fi

if [ "$overall_missing" -eq 1 ]; then
  exit 1
fi

echo "all quirks satisfied"

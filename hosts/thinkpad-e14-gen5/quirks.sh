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

if [ "$nvidia_missing" -eq 1 ]; then
  overall_missing=1
fi

if [ "$kmod_missing" -eq 1 ]; then
  echo
  echo "To (re)build a signed kmod-nvidia for the running kernel"
  echo "($running_kernel), in a toolbox container (see I004 for the full"
  echo "procedure and why it must be toolbox, not the rpm-ostree sandbox):"
  echo "  1. In toolbox: install rpmfusion-{free,nonfree}-release, pciutils,"
  echo "     xorg-x11-drv-nvidia-kmodsrc (version-matched), kernel-devel for"
  echo "     $running_kernel, akmods, gcc, make, elfutils-libelf-devel"
  echo "  2. Copy /etc/pki/akmods/private/private_key.priv and the matching"
  echo "     cert into /var/cache/akmods/, owned akmods:akmods, and put"
  echo "     .rpmmacros there too (NOT ~/.rpmmacros or /root/.rpmmacros —"
  echo "     akmodsbuild runs as the 'akmods' system user via runuser, which"
  echo "     can't see macros in root's or the invoking user's home; see I006)"
  echo "  3. akmods --kernels $running_kernel --kmod nvidia"
  echo "  4. Verify signed: modinfo shows '~Module signature appended~',"
  echo "     sig_id PKCS#7, signer matching the enrolled MOK"
  echo "  5. On host: sudo rpm-ostree uninstall akmod-nvidia   (if present)"
  echo "  6. sudo rpm-ostree install /path/to/kmod-nvidia-${running_kernel}-*.rpm"
  echo "  7. systemctl reboot"
  echo "  8. after reboot: nvidia-smi   (confirms the driver is loaded)"
  echo "  9. delete the copied private key from both host and toolbox"
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
  echo "underlying sandbox-signing procedure this mirrors):"
  echo "  1. In toolbox: install rpmfusion-{free,nonfree}-release,"
  echo "     kernel-devel for $running_kernel, akmods, gcc, make,"
  echo "     elfutils-libelf-devel, akmod-xpadneo (source package)"
  echo "  2. Copy /etc/pki/akmods/private/private_key.priv and the matching"
  echo "     cert into /var/cache/akmods/, owned akmods:akmods, and put"
  echo "     .rpmmacros there too (NOT ~/.rpmmacros or /root/.rpmmacros —"
  echo "     akmodsbuild runs as the 'akmods' system user via runuser; see I006)"
  echo "  3. akmods --kernels $running_kernel --kmod xpadneo"
  echo "  4. Verify signed: modinfo shows '~Module signature appended~',"
  echo "     sig_id PKCS#7, signer matching the enrolled MOK"
  echo "  5. On host: sudo rpm-ostree uninstall akmod-xpadneo   (if present)"
  echo "  6. sudo rpm-ostree install /path/to/kmod-xpadneo-${running_kernel}-*.rpm"
  echo "  7. systemctl reboot"
  echo "  8. after reboot: pair/reconnect the controller, check"
  echo "     /proc/bus/input/devices for an Xbox entry"
  echo "  9. delete the copied private key from both host and toolbox"
  echo
  echo "If the driver is signed and loaded but the controller still doesn't"
  echo "bind ('unbalanced collection' / 'parse failed' in journalctl -k),"
  echo "that's not this — see I006: update the controller's own Bluetooth"
  echo "firmware via the Xbox Accessories app (Windows/Xbox console/Android)."
fi

if [ "$overall_missing" -eq 1 ]; then
  exit 1
fi

echo "all quirks satisfied"

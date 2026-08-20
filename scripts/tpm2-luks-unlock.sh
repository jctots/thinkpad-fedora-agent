#!/usr/bin/env bash
# TPM2 auto-unlock readiness/status for the root LUKS volume.
# Report-only, idempotent, same pattern as layer-packages.sh and
# hosts/*/quirks.sh — never enrolls anything itself, only prints what's
# missing and the exact command to run.
#
# Why this is base layer, not a host quirk: the mechanism (systemd-cryptenroll
# + TPM2 + PCR 7) is identical on any Secure-Boot Fedora Silverblue machine
# with a TPM2 chip. Only the LUKS device differs per machine, and that is
# auto-detected below, not hardcoded.
#
# Why PCR 7 and not 0/4/8/9: PCR 7 measures Secure Boot state (enabled,
# trusted keys), which does not change across rpm-ostree deployments. PCRs
# covering the bootloader/kernel/initrd (4, 8, 9) change on every `rpm-ostree
# upgrade`, which would break auto-unlock on the next boot after every
# update. PCR 7 only breaks if Secure Boot state or trusted keys change,
# which is rare and something you'd want a passphrase fallback for anyway.
#
# Why this is never run automatically, even by this script: enrolling a TPM2
# keyslot requires typing the *existing* LUKS passphrase interactively to
# authorize adding the new slot. That is exactly the class of step
# docs/bootstrap.md Part 4 excludes from automation — it needs a human at
# the keyboard, not a scripted secret. The existing passphrase slot is never
# touched or removed, so this is reversible with
# `systemd-cryptenroll --wipe-slot=tpm2 <device>` if it ever needs undoing.

set -euo pipefail

steps_needed=0

if [ -e /dev/tpm0 ] || [ -e /dev/tpmrm0 ]; then
  echo "ok      TPM2 device present"
else
  echo "missing TPM2 device (/dev/tpm0, /dev/tpmrm0) — check firmware TPM is enabled in BIOS"
  steps_needed=1
fi

sb_enabled=0
if command -v mokutil >/dev/null 2>&1; then
  sb_state="$(mokutil --sb-state 2>/dev/null || true)"
  if grep -q "SecureBoot enabled" <<<"$sb_state"; then
    sb_enabled=1
  fi
fi
if [ "$sb_enabled" -eq 1 ]; then
  echo "ok      Secure Boot enabled (required for a PCR 7 binding that survives OS updates)"
else
  echo "missing Secure Boot enabled — PCR 7 binding will not be meaningful, enable it in firmware first"
  steps_needed=1
fi

if command -v systemd-cryptenroll >/dev/null 2>&1; then
  echo "ok      systemd-cryptenroll present"
else
  echo "missing systemd-cryptenroll"
  steps_needed=1
fi

ROOT_LUKS_UUID="$(findmnt -no SOURCE /sysroot 2>/dev/null | xargs -I{} lsblk -no UUID -s {} 2>/dev/null | tail -1 || true)"
if [ -z "$ROOT_LUKS_UUID" ]; then
  # Fallback: the crypto_LUKS partition backing whatever /sysroot's device tree resolves to.
  ROOT_LUKS_UUID="$(lsblk -rno NAME,FSTYPE,UUID | awk '$2=="crypto_LUKS"{print $3; exit}' || true)"
fi

if [ -z "$ROOT_LUKS_UUID" ]; then
  echo "missing — could not auto-detect the root LUKS device, check manually with lsblk"
  steps_needed=1
else
  echo "ok      root LUKS device detected: UUID=$ROOT_LUKS_UUID"
  cryptenroll_out="$(sudo -n systemd-cryptenroll "/dev/disk/by-uuid/$ROOT_LUKS_UUID" 2>/dev/null || true)"
  if grep -qi tpm2 <<<"$cryptenroll_out"; then
    echo "ok      TPM2 keyslot already enrolled on this device"
  else
    echo "missing TPM2 keyslot enrollment (or sudo needed a prompt to check — rerun with a terminal if unsure)"
    steps_needed=1
  fi
fi

if [ "$steps_needed" -eq 0 ]; then
  echo
  echo "TPM2 auto-unlock fully set up — reboot without entering the LUKS passphrase to confirm"
  exit 0
fi

echo
echo "Run yourself, interactively (needs the current LUKS passphrase to authorize"
echo "the new keyslot — never scripted, see docs/bootstrap.md Part 4):"
echo "  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-uuid/${ROOT_LUKS_UUID:-<uuid-from-lsblk>}"
echo "  # then reboot and confirm no passphrase prompt appears"
echo "  # undo any time with: sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-uuid/${ROOT_LUKS_UUID:-<uuid>}"
exit 1

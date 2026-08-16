#!/usr/bin/env bash
# The reproducible record of every Flatpak this machine needs, with the
# reason and the decision behind picking Flatpak over a layered RPM where
# that was a real choice. Report-only, same as layer-packages.sh: this
# script never calls flatpak itself, only prints what's missing.
#
# Idempotent: safe to re-run any time to check drift against this list.
#
# Update this file in the same commit as the flatpak install that
# satisfies it.

set -euo pipefail

# app-id|reason
flatpaks=(
  "com.visualstudio.code|editor — bootstrap.md §3.6. Flatpak chosen over the layered Microsoft RPM repo: no layering cost, no reboot, sandboxed. Provisional — the only trigger for revisiting is sandbox friction with host terminals/toolbox becoming a real hassle in practice, not a re-litigation on its own"
  "com.bitwarden.desktop|password manager desktop app — bootstrap.md §3.1/§3.9. Official upstream also ships an RPM via their own Cloudsmith repo, but that means adding a third-party .repo file plus a layered-package reboot; flatpak is lower-friction and matches the same reasoning as the VS Code choice above"
  "org.gnome.seahorse.Application|GUI to blank the GNOME Login keyring password so fingerprint login can unlock it — pam_fprintd has no password to hand pam_gnome_keyring, see docs/bootstrap.md Part 4. Flatpak over a layered RPM: same reasoning as VS Code/Bitwarden above, and this is a one-time manual task, not a daily-use app"
)

missing=()
for entry in "${flatpaks[@]}"; do
  id="${entry%%|*}"
  reason="${entry#*|}"
  if flatpak info "$id" >/dev/null 2>&1; then
    echo "ok      $id"
  else
    echo "missing $id  — $reason"
    missing+=("$id")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo
  echo "Run (as separate, reviewable commands — do not chain):"
  for id in "${missing[@]}"; do
    echo "  flatpak install flathub $id"
  done
  exit 1
fi

echo
echo "all flatpaks present"

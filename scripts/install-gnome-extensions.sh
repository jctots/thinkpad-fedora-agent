#!/usr/bin/env bash
# The reproducible record of every GNOME Shell extension this machine needs,
# with the reason. Report-only, same as layer-packages.sh and
# install-flatpaks.sh: this script never installs anything itself, only
# prints what's missing — there's no CLI installer tool on this machine
# (no gnome-extensions-cli/gext), so installing means opening the
# extensions.gnome.org page and using the browser toggle.
#
# Idempotent: safe to re-run any time to check drift against this list.
#
# Update this file in the same commit as the extension install that
# satisfies it.

set -euo pipefail

# uuid|extensions.gnome.org URL|reason
extensions=(
  "tailscale-gnome-qs@tailscale-qs.github.io|https://extensions.gnome.org/extension/9193/tailscale-qs/|Quick Settings toggle for Tailscale connect/disconnect + exit-node selection — Windows-tray-equivalent, chosen over the official \`tailscale systray\` (needs AppIndicator support first) and over Trayscale (unofficial flatpak, same AppIndicator dependency). Maintained fork of the abandoned joaophi/tailscale-gnome-qs; GNOME Shell 45+ required, this machine runs 50.4"
)

missing=()
for entry in "${extensions[@]}"; do
  uuid="${entry%%|*}"
  rest="${entry#*|}"
  url="${rest%%|*}"
  reason="${rest#*|}"
  if gnome-extensions list 2>/dev/null | grep -qx "$uuid"; then
    enabled="$(gnome-extensions info "$uuid" 2>/dev/null | grep -oP '(?<=Enabled: ).*' || echo unknown)"
    if [ "$enabled" = "Yes" ]; then
      echo "ok      $uuid"
    else
      echo "disabled $uuid  — installed but not enabled (gnome-extensions enable \"$uuid\")"
      missing+=("$uuid|$url")
    fi
  else
    echo "missing $uuid  — $reason"
    missing+=("$uuid|$url")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo
  echo "Install manually (no CLI installer present) — open each URL and use the browser toggle:"
  for entry in "${missing[@]}"; do
    echo "  ${entry#*|}"
  done
  exit 1
fi

echo
echo "all gnome extensions present"

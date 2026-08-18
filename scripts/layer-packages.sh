#!/usr/bin/env bash
# The reproducible record of every rpm-ostree layered package this machine
# needs, with the reason it's there. Report-only, deliberately: this script
# never calls rpm-ostree itself. It prints the missing commands and stops —
# each one still goes through the normal ask-tier prompt when actually run,
# so a wrapper script can never become a way to bundle host changes past
# the "show the command before running it" rule.
#
# Idempotent: safe to re-run any time to check drift against this list.
#
# Update this file in the same commit as the rpm-ostree install that
# satisfies it — that's what makes it a manifest instead of a guess.

set -euo pipefail

# name|reason
packages=(
  "git-core|source control — bootstrap.md §3.2, base image dependency"
  "etckeeper|/etc reversibility layer — bootstrap.md §3.8, required before /etc edits move from DENY-equivalent risk to ASK"
  "gitleaks|pre-commit secret scan — bootstrap.md §3.8, .githooks/pre-commit refuses to run without it"
  "make|this repo's documented interface (make probe, make check, make hooks) — bootstrap.md §3.7/§3.8"
  "tailscale|home-lab reachability off the LAN — bootstrap.md §3.4b, needed for the vault's RAG backend, the kopia NAS backup, and recovery.md Card 3"
  "v4l-utils|UVC camera diagnostics/controls (v4l2-ctl, qv4l2) — generic tool for any video-capture device, no host-specific quirk involved"
  "nodejs|node/npm/npx — general JS tooling dependency (MCP servers, CLIs), also needed by the ccusage-indicator GNOME extension"
)

missing=()
for entry in "${packages[@]}"; do
  name="${entry%%|*}"
  reason="${entry#*|}"
  if rpm -q "$name" >/dev/null 2>&1; then
    echo "ok      $name"
  else
    echo "missing $name  — $reason"
    missing+=("$name")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo
  echo "Run (as separate, reviewable commands — do not chain):"
  for name in "${missing[@]}"; do
    echo "  rpm-ostree install $name"
  done
  exit 1
fi

echo
echo "all layered packages present"

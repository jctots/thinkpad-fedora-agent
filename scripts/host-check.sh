#!/usr/bin/env bash
# Runs every report-only script in the base layer and every host profile
# directory, and summarizes ok/missing across all of them in one pass —
# the manual sweep this repo's own guardrails would otherwise require doing
# by hand at the start of a session.
#
# Explicit include list, not a blind glob over scripts/*.sh: some scripts in
# that directory mutate directly rather than reporting (install-hooks.sh sets
# git config; build-bitwarden-polkit-policy.sh builds a local RPM), and
# session-token-check.sh is a hook body, not a standalone check. Running
# those here would be a silent side effect disguised as a status check.
#
# Idempotent, read-only: safe to re-run any time. Each listed script already
# guarantees this on its own — see its own header.
#
# Usage: scripts/host-check.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

report_only_scripts=(
    "$REPO_ROOT/scripts/install-flatpaks.sh"
    "$REPO_ROOT/scripts/install-gnome-extensions.sh"
    "$REPO_ROOT/scripts/layer-packages.sh"
    "$REPO_ROOT/scripts/tpm2-luks-unlock.sh"
)

# hosts/*/*.sh — globbed, not DMI-detected: this repo currently has one host
# profile, and running another profile's report-only script is harmless (it
# just reports its own hardware as absent), so duplicating install.sh's
# vendor/product detection here isn't worth the maintenance surface yet.
for host_script in "$REPO_ROOT"/hosts/*/*.sh; do
    [ -e "$host_script" ] || continue
    report_only_scripts+=("$host_script")
done

failed=()
for script in "${report_only_scripts[@]}"; do
    [ -x "$script" ] || { echo "skip (not executable): $script"; continue; }
    echo "== ${script#"$REPO_ROOT"/} =="
    if ! "$script"; then
        failed+=("${script#"$REPO_ROOT"/}")
    fi
    echo
done

if [ "${#failed[@]}" -gt 0 ]; then
    echo "Scripts reporting something missing:"
    printf '  %s\n' "${failed[@]}"
    exit 1
fi

echo "all report-only scripts clean"

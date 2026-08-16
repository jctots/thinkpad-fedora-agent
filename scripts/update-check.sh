#!/usr/bin/env bash
# Report-only drift check across everything this project's manifests cover:
# the OS image (rpm-ostree) and every flatpak listed in this repo's
# scripts/install-flatpaks.sh plus, if EXTRAS_DIR is set, the private
# extras repo's flatpaks.sh. Same contract as those scripts: this one never
# calls rpm-ostree upgrade or flatpak update itself, only prints what's
# outdated and the exact command to fix it.
#
# Idempotent, read-only: safe to re-run any time. rpm-ostree upgrade --check
# and flatpak/remote-info queries touch the network but change nothing
# installed.
#
# Usage: scripts/update-check.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$REPO_ROOT/local/secrets.env" ]; then
    # shellcheck disable=SC1091
    . "$REPO_ROOT/local/secrets.env"
fi

# Pull the "id|reason" list out of a flatpaks.sh-shaped script without
# executing it, so this stays a pure reader of those files, not a second
# copy of the app list to keep in sync by hand.
extract_ids() {
    grep -oP '^\s*"\K[A-Za-z0-9._-]+(?=\|)' "$1" 2>/dev/null || true
}

echo "== OS image (rpm-ostree) =="
if command -v rpm-ostree >/dev/null 2>&1; then
    check_out="$(rpm-ostree upgrade --check 2>&1)" || true
    echo "$check_out" | grep -E "AvailableUpdate|No updates available|^error" || echo "$check_out" | tail -3
    if echo "$check_out" | grep -qi "AvailableUpdate"; then
        echo
        echo "Run: rpm-ostree upgrade && systemctl reboot"
    fi
else
    echo "rpm-ostree not found — skipping"
fi

echo
echo "== Flatpaks =="

declare -A sources=(
    ["public"]="$REPO_ROOT/scripts/install-flatpaks.sh"
)
if [ -n "${EXTRAS_DIR:-}" ] && [ "$EXTRAS_DIR" != "PLACEHOLDER" ] && [ -f "$EXTRAS_DIR/flatpaks.sh" ]; then
    sources["extras"]="$EXTRAS_DIR/flatpaks.sh"
fi

outdated=()
for label in "${!sources[@]}"; do
    manifest="${sources[$label]}"
    echo "-- $label ($manifest) --"
    while IFS= read -r id; do
        [ -z "$id" ] && continue
        if ! flatpak info "$id" >/dev/null 2>&1; then
            echo "not installed  $id  (see install-flatpaks.sh / extras flatpaks.sh for the install command)"
            continue
        fi
        installed_commit="$(flatpak info "$id" 2>/dev/null | awk '/Commit:/ {print $2; exit}')"
        remote_commit="$(flatpak remote-info flathub "$id" 2>/dev/null | awk '/Commit:/ {print $2; exit}')"
        if [ -z "$remote_commit" ]; then
            echo "unknown        $id  (couldn't reach flathub remote-info)"
        elif [ "$installed_commit" = "$remote_commit" ]; then
            echo "current        $id"
        else
            echo "outdated       $id"
            outdated+=("$id")
        fi
    done < <(extract_ids "$manifest")
done

if [ "${#outdated[@]}" -gt 0 ]; then
    echo
    echo "Run (as separate, reviewable commands — do not chain):"
    for id in "${outdated[@]}"; do
        echo "  flatpak update $id"
    done
    exit 1
fi

echo
echo "all checked flatpaks current"

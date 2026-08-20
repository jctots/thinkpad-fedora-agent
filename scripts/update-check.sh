#!/usr/bin/env bash
# Report-only drift check across everything this project's manifests cover:
# the OS image (rpm-ostree), every flatpak listed in this repo's
# scripts/install-flatpaks.sh plus, if EXTRAS_DIR is set, the private
# extras repo's flatpaks.sh, the full flatpak install (runtimes/extensions
# included, not just manifest apps — GNOME Software's "App Updates" list
# is often really a runtime update attributed to the apps that depend on
# it), and firmware via fwupd/LVFS. Same contract as install-flatpaks.sh:
# this one never calls rpm-ostree upgrade, flatpak update, or fwupdmgr
# update itself, only prints what's outdated and the exact command to fix
# it.
#
# Idempotent, read-only: safe to re-run any time. rpm-ostree upgrade --check,
# flatpak/remote-info queries, `flatpak update` answered "n" at its prompt,
# and fwupdmgr get-updates touch the network but change nothing installed.
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
        installed_commit="$(flatpak info "$id" 2>/dev/null | awk '/Commit:/ {print $2; exit}' || true)"
        remote_commit="$(flatpak remote-info flathub "$id" 2>/dev/null | awk '/Commit:/ {print $2; exit}' || true)"
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
else
    echo
    echo "all checked flatpaks current"
fi

echo
echo "== Flatpak, full system (runtimes/extensions included) =="
if command -v flatpak >/dev/null 2>&1; then
    # `flatpak update` queries for updates before it asks to proceed;
    # answering "n" aborts before anything is pulled or deployed. This is
    # the only way to see runtime/extension drift (e.g. a GL/VAAPI driver
    # extension) that the per-manifest commit comparison above can't catch,
    # since it only walks the app IDs literally listed in the manifests.
    fp_preview="$(printf 'n\n' | flatpak update 2>&1 || true)"
    if echo "$fp_preview" | grep -qE '^\s*[0-9]+\.'; then
        echo "$fp_preview" | grep -E '^\s*[0-9]+\.|^ID |^Ref '
        echo
        echo "Run: flatpak update   (interactive — review the list, confirm y)"
    elif echo "$fp_preview" | grep -qi "Nothing to do"; then
        echo "all installed flatpaks (system-wide) current"
    else
        echo "$fp_preview" | tail -5
    fi
else
    echo "flatpak not found — skipping"
fi

echo
echo "== Firmware (fwupd/LVFS) =="
if command -v fwupdmgr >/dev/null 2>&1; then
    fwupdmgr refresh >/dev/null 2>&1 || true
    fw_out="$(fwupdmgr get-updates 2>&1)" || true
    if echo "$fw_out" | grep -q "New version:"; then
        echo "$fw_out" | grep -E "^LENOVO|Current version:|New version:|Summary:" || echo "$fw_out"
        echo
        echo "Firmware updates flash hardware directly — none of this repo's three"
        echo "reversibility layers (OS image / /etc / /var/home) cover that, so this"
        echo "agent will not run fwupdmgr update itself. Run it yourself:"
        echo "  fwupdmgr update"
    else
        echo "no firmware updates available"
    fi
else
    echo "fwupdmgr not found — skipping"
fi

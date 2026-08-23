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
# copy of the app list to keep in sync by hand. De-duplicated: a script
# like the extras repo's flatpaks.sh declares some app IDs twice — once in
# its install array, again in a separate overrides array (same app, extra
# flatpak override flags) — and this is a plain list of IDs to check, not a
# structural parse, so it can't tell those apart without the dedup.
extract_ids() {
    grep -oP '^\s*"\K[A-Za-z0-9._-]+(?=\|)' "$1" 2>/dev/null | awk '!seen[$0]++' || true
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
if [ -n "${EXTRAS_DIR:-}" ] && [ "$EXTRAS_DIR" != "PLACEHOLDER" ] && [ -f "$EXTRAS_DIR/scripts/flatpaks.sh" ]; then
    sources["extras"]="$EXTRAS_DIR/scripts/flatpaks.sh"
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
echo "== npm global packages =="
if command -v npm >/dev/null 2>&1; then
    npm_globals="$(npm ls -g --depth=0 2>/dev/null | grep -oP '^\S+ \K[a-zA-Z0-9@/._-]+(?=@)' || true)"
    if [ -z "$npm_globals" ]; then
        echo "no npm global packages installed"
    else
        npm_outdated="$(npm outdated -g 2>/dev/null || true)"
        while IFS= read -r pkg; do
            [ -z "$pkg" ] && continue
            outdated_line="$(echo "$npm_outdated" | awk -v p="$pkg" '$1 == p {print $2, $4}')"
            if [ -n "$outdated_line" ]; then
                read -r current latest <<<"$outdated_line"
                echo "outdated       $pkg ($current -> $latest)"
            else
                echo "current        $pkg"
            fi
        done <<<"$npm_globals"
        if echo "$npm_outdated" | grep -qP '^\S+ '; then
            echo
            echo "Run: npm update -g   (or 'npm update -g <pkg>' for one at a time)"
        fi
    fi
else
    echo "npm not found — skipping"
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

#!/usr/bin/env bash
# Security + privacy posture sweep. Two parts:
#
# 1. Lynis (layered package, see PACKAGES.md) — general OS hardening audit:
#    boot/kernel, SELinux, SSH, cron, file integrity. Reused rather than
#    hand-rolled per CLAUDE.md's prior-art rule; needs root because most of
#    its checks require it to read kernel/boot state. Uses pkexec, not sudo,
#    per CLAUDE.md — also the only option that works at all here, since
#    sudo has no TTY to prompt against when this script runs non-interactively.
# 2. Native gsettings/flatpak checks for what Lynis doesn't know about on
#    this desktop: GNOME privacy settings, location services, and Flatpak
#    per-app permission overrides (camera/mic/location/filesystem grants
#    beyond the sandbox default). Same thin-wrapper pattern as every other
#    script here — no vendored code, just each tool's own report mode.
#
# Report-only: never installs, changes a setting, or revokes a permission.
# Idempotent: safe to re-run any time.
#
# Every run's full output is also written to .claude/security-reports/ —
# gitignored, machine-local point-in-time state, same reasoning as
# .claude/audit/. Not project narrative, so it doesn't belong in git.
#
# Usage: scripts/security-privacy-check.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="$REPO_ROOT/.claude/security-reports"
REPORT_FILE="$REPORT_DIR/$(date +%Y%m%d-%H%M%S).md"
mkdir -p "$REPORT_DIR"

# Tee everything below to the report file as well as stdout.
exec > >(tee "$REPORT_FILE") 2>&1

echo "security-privacy-check: $(date -Iseconds)"
echo

echo "== Lynis security audit =="
if ! rpm -q lynis >/dev/null 2>&1; then
    echo "missing lynis — rpm-ostree install lynis (see scripts/layer-packages.sh)"
else
    lynis_out="$(pkexec bash -c 'lynis audit system --quick --no-colors; echo ---LYNIS-REPORT---; cat /var/log/lynis-report.dat 2>/dev/null')"
    if [ -z "$lynis_out" ]; then
        echo "error   pkexec authentication failed or was cancelled — lynis needs root for a full scan" >&2
    else
        echo "${lynis_out%%---LYNIS-REPORT---*}"
        report_data="${lynis_out#*---LYNIS-REPORT---}"
        echo

        hardening_index="$(printf '%s\n' "$report_data" | awk -F= '/^hardening_index=/{print $2}')"
        warnings="$(printf '%s\n' "$report_data" | awk -F= '/^warning\[\]=/{c++} END{print c+0}')"
        suggestions="$(printf '%s\n' "$report_data" | awk -F= '/^suggestion\[\]=/{c++} END{print c+0}')"
        echo "hardening index: ${hardening_index:-unknown}/100"
        echo "warnings: $warnings, suggestions: $suggestions"
        echo "full report: pkexec lynis show report"
        echo
        echo "note: Lynis's boot/filesystem checks assume a traditional"
        echo "(non-ostree) layout — expect some findings there that are"
        echo "specific to that mismatch on this image-based root, not real"
        echo "issues. Read them, don't auto-action them."
    fi
fi

echo
echo "== GNOME privacy settings =="
gs() {
    gsettings get "$1" "$2" 2>/dev/null || echo "n/a (schema/key not present)"
}
echo "remember recent files:   $(gs org.gnome.desktop.privacy remember-recent-files)"
echo "recent files max age:    $(gs org.gnome.desktop.privacy recent-files-max-age)"
echo "remove old trash/temp:   $(gs org.gnome.desktop.privacy remove-old-trash-files)"
echo "report technical probs:  $(gs org.gnome.desktop.privacy report-technical-problems)"
echo "location services:       $(gs org.gnome.system.location enabled)"

echo
echo "== Flatpak permission overrides =="
overrides_found=0
if command -v flatpak >/dev/null 2>&1; then
    global_override="$(flatpak override --show 2>/dev/null)"
    if [ -n "$global_override" ]; then
        overrides_found=1
        echo "-- system-wide default --"
        echo "$global_override" | sed 's/^/  /'
    fi
    while IFS= read -r app; do
        [ -n "$app" ] || continue
        app_override="$(flatpak override --user --show "$app" 2>/dev/null)"
        if [ -n "$app_override" ]; then
            overrides_found=1
            echo "-- $app --"
            echo "$app_override" | sed 's/^/  /'
        fi
    done < <(flatpak list --app --columns=application 2>/dev/null)
else
    echo "n/a     flatpak not installed"
fi
if [ "$overrides_found" -eq 0 ]; then
    echo "ok      no per-app overrides beyond flatpak sandbox defaults"
fi

echo
echo "Pair this with /etc-drift for polkit/unit-file drift — Lynis and the"
echo "checks above don't see /etc history."
echo
echo "report saved: ${REPORT_FILE#"$REPO_ROOT"/}"

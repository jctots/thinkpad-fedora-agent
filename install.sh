#!/usr/bin/env bash
# Thin, idempotent orchestrator.
#
# Runs the base layer (scripts/) then the host profile (hosts/<slug>/). Every
# script it calls must be safe to re-run: check before acting, change nothing
# if the desired state already holds. Idempotency is not a nicety here — it is
# what the VM harness asserts by running this twice against one snapshot and
# requiring the second run to change nothing.
#
# Usage:
#   ./install.sh                    # detect host profile from DMI
#   HOST_PROFILE=thinkpad-e14-gen5 ./install.sh
#   ./install.sh --dry-run          # print what would run

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

log()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m warn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m fail:\033[0m %s\n' "$*" >&2; exit 1; }

# --- host profile detection ---------------------------------------------------
# Overridable so the VM can be told which profile to assume — it has no real DMI.

detect_host_profile() {
    if [ -n "${HOST_PROFILE:-}" ]; then
        echo "$HOST_PROFILE"
        return
    fi

    local vendor product
    vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo unknown)"
    product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"

    # Pinned 2026-08-16 from this machine: sys_vendor=LENOVO,
    # product_name=21JKCTO1WW. "21JK" is the Lenovo MTM prefix for the
    # E14 Gen 5 line; matched by prefix rather than the exact CTO suffix so
    # other configs of the same model still resolve instead of falling
    # through to "undetected".
    case "${vendor}|${product}" in
        LENOVO\|21JK*) echo "thinkpad-e14-gen5" ;;
        *)             echo "" ;;
    esac
}

# --- run ----------------------------------------------------------------------

run_script() {
    local script="$1"
    [ -f "$script" ] || return 0
    [ -x "$script" ] || die "not executable: $script"

    if [ "$DRY_RUN" = "1" ]; then
        log "would run: ${script#"$REPO_ROOT"/}"
        return 0
    fi

    log "${script#"$REPO_ROOT"/}"
    "$script"
}

main() {
    [ -r /etc/os-release ] || die "no /etc/os-release — is this a Fedora machine?"
    # shellcheck disable=SC1091
    . /etc/os-release
    [ "${ID:-}" = "fedora" ] || warn "expected Fedora, found '${ID:-unknown}' — continuing"

    if [ -f "$REPO_ROOT/local/secrets.env" ]; then
        log "sourcing local/secrets.env"
        # shellcheck disable=SC1091
        . "$REPO_ROOT/local/secrets.env"
    else
        warn "local/secrets.env missing — anything authenticated will be skipped"
        warn "  cp local/secrets.env.example local/secrets.env"
    fi

    log "base layer"
    local script
    for script in "$REPO_ROOT"/scripts/[0-9][0-9]-*.sh; do
        run_script "$script"
    done

    local profile
    profile="$(detect_host_profile)"
    if [ -z "$profile" ]; then
        warn "host profile not detected — base layer only"
        warn "  set HOST_PROFILE=<slug> to force one; see hosts/"
    elif [ ! -d "$REPO_ROOT/hosts/$profile" ]; then
        die "host profile '$profile' has no directory under hosts/"
    else
        log "host profile: $profile"
        for script in "$REPO_ROOT/hosts/$profile"/*.sh; do
            run_script "$script"
        done
    fi

    if [ -n "${EXTRAS_DIR:-}" ] && [ "$EXTRAS_DIR" != "PLACEHOLDER" ]; then
        if [ -d "$EXTRAS_DIR" ]; then
            log "extras: $EXTRAS_DIR"
            for script in "$EXTRAS_DIR"/scripts/*.sh; do
                run_script "$script"
            done
            if [ -n "$profile" ] && [ -d "$EXTRAS_DIR/hosts/$profile" ]; then
                log "extras host profile: $profile"
                for script in "$EXTRAS_DIR/hosts/$profile"/*.sh; do
                    run_script "$script"
                done
            fi
        else
            warn "EXTRAS_DIR is set to '$EXTRAS_DIR' but that directory does not exist — skipping"
        fi
    fi

    log "done"
}

main "$@"

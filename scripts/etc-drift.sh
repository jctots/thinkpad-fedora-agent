#!/usr/bin/env bash
# Confirms etckeeper actually committed the last /etc change. Per CLAUDE.md:
# an uncommitted /etc change is irreversible in practice, since etckeeper's
# git history is the only thing that makes docs/recovery.md Card 2 possible.
#
# `check` (default) is report-only. `fix` commits pending /etc changes via
# etckeeper directly — a single reversible commit to a repo that already
# exists, same trust level as gpu-toggle.sh, safe to run standalone. The
# MISSING_REPO case (etckeeper never initialised) stays print-only: it may
# need `rpm-ostree install etckeeper` first, an OS-image-layer change that
# stays manual.
#
# Needs root to read/write /etc's git state, via pkexec (not sudo — this
# script has no TTY to prompt against when run non-interactively, and pkexec
# is CLAUDE.md's rule for root commands anyway).
#
# Idempotent: safe to re-run any time.
#
# Usage: scripts/etc-drift.sh {check|fix}

set -euo pipefail

usage() {
  echo "Usage: $0 {check|fix} [commit message]"
  echo
  echo "  check  (default) report whether /etc has uncommitted changes"
  echo "  fix    commit pending /etc changes via etckeeper, if any"
  exit 1
}

read_state() {
  out="$(pkexec bash -c '
if ! git -C /etc rev-parse --git-dir >/dev/null 2>&1; then
    echo "MISSING_REPO"
    exit 0
fi
echo "COMMIT $(git -C /etc log -1 --format="%h %ci %s")"
git -C /etc status --porcelain
')"

  if [ -z "$out" ]; then
    echo "error   pkexec authentication failed or was cancelled" >&2
    exit 2
  fi
}

cmd="${1:-check}"

case "$cmd" in
  check)
    read_state
    if [ "$out" = "MISSING_REPO" ]; then
      echo "missing  /etc is not a git repository — etckeeper was never initialised"
      echo
      echo "Run: rpm-ostree install etckeeper && systemctl reboot"
      echo "Then: pkexec etckeeper init && pkexec etckeeper commit \"baseline\""
      exit 1
    fi

    last_commit="${out#COMMIT }"
    last_commit="${last_commit%%$'\n'*}"
    echo "last etckeeper commit: $last_commit"

    dirty="$(printf '%s\n' "$out" | tail -n +2)"

    if [ -n "$dirty" ]; then
      echo
      echo "missing  uncommitted changes in /etc:"
      echo "$dirty" | sed 's/^/  /'
      echo
      echo "Run: scripts/etc-drift.sh fix"
      exit 1
    fi

    echo "ok      /etc clean, nothing uncommitted"
    ;;
  fix)
    read_state
    if [ "$out" = "MISSING_REPO" ]; then
      echo "missing  /etc is not a git repository — etckeeper was never initialised"
      echo "Run: rpm-ostree install etckeeper && systemctl reboot"
      echo "Then: pkexec etckeeper init"
      exit 1
    fi

    dirty="$(printf '%s\n' "$out" | tail -n +2)"

    if [ -z "$dirty" ]; then
      echo "ok      /etc clean, nothing to commit"
      exit 0
    fi

    msg="${2:-Commit pending /etc changes (scripts/etc-drift.sh fix)}"
    echo "committing:"
    echo "$dirty" | sed 's/^/  /'
    pkexec etckeeper commit "$msg"
    echo "done    committed"
    ;;
  *)
    usage
    ;;
esac

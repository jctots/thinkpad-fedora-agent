#!/usr/bin/env bash
# Point git at the repo's tracked hooks.
#
# Git does not clone hooks, so this is a manual step on every fresh clone —
# which is precisely why it is one line and lives at a predictable path.
# Idempotent: safe to re-run.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

current="$(git config --get core.hooksPath || true)"
if [ "$current" = ".githooks" ]; then
    echo "hooks: already configured (core.hooksPath=.githooks)"
else
    git config core.hooksPath .githooks
    echo "hooks: core.hooksPath set to .githooks"
fi

chmod +x .githooks/* 2>/dev/null || true

if command -v gitleaks >/dev/null 2>&1; then
    echo "hooks: gitleaks found — $(gitleaks version 2>&1 | head -1)"
else
    echo "hooks: WARNING — gitleaks not installed; the pre-commit scan will refuse to run"
fi

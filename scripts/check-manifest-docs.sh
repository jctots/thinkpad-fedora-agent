#!/usr/bin/env bash
# Checks that every identifier declared in a manifest script's array (a
# package name, app-id, or extension UUID) has a matching row in the
# narrated .md doc it's supposed to be documented in. The scripts and docs
# are hand-edited in tandem by convention ("update both in the same
# commit"), and that convention has already drifted twice unnoticed
# (v4l-utils and nodejs landed in layer-packages.sh in separate commits on
# 2026-08-18 with no PACKAGES.md row until this check existed). This makes
# the drift a probe failure instead of something only caught by asking.
#
# Report-only, same contract as the manifest scripts themselves: never
# edits anything, only prints what's undocumented and exits 1.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0

# script|doc
pairs=(
  "scripts/layer-packages.sh|scripts/PACKAGES.md"
  "scripts/install-flatpaks.sh|scripts/PACKAGES.md"
  "scripts/install-gnome-extensions.sh|scripts/PACKAGES.md"
)

for pair in "${pairs[@]}"; do
  script="${pair%%|*}"
  doc="${pair#*|}"
  # Identifiers are the first pipe-delimited field of each quoted array
  # entry, e.g. "name|reason" or "app-id|reason" or "uuid|url|reason".
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    if ! grep -qF "$id" "$doc"; then
      echo "undocumented: \`$id\` declared in $script, missing from $doc"
      fail=1
    fi
  done < <(grep -oP '^\s*"\K[^"|]+(?=\|)' "$script")
done

if [ "$fail" -eq 0 ]; then
  echo "all manifest entries documented"
fi

exit "$fail"

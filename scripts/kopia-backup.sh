#!/usr/bin/env bash
# Runs a kopia snapshot of the home directory, excluding the rclone cloud
# mounts (Drive/OneDrive/Synology are FUSE views of data already stored
# durably elsewhere — walking them through kopia would be slow, fragile
# under a network hiccup mid-scan, and pointless), the Synology Drive
# client's local sync cache (same reasoning — redundant with the cloud copy),
# and disposable/reproducible local data (.cache, container images, Steam's
# library/userdata under .var) that would otherwise dominate snapshot time
# for no recovery value — all reinstallable or regenerated, not user data.
#
# Invoked by the kopia-backup.timer systemd --user unit (daily, persistent
# catch-up — see scripts/install-kopia-backup.sh). Safe to run by hand too:
# idempotent — the policy-set call is a no-op if already set, and a
# snapshot of an unchanged tree is cheap (content-addressed, only new or
# changed data uploads).
#
# Requires `kopia repository connect` already run once — see
# docs/recovery.md Card 3. This script never connects or creates a
# repository itself.
#
# Usage: scripts/kopia-backup.sh

set -euo pipefail

SNAPSHOT_PATH="${HOME}"

if ! kopia repository status >/dev/null 2>&1; then
    echo "error   kopia repository not connected — see docs/recovery.md Card 3" >&2
    exit 1
fi

kopia policy set "$SNAPSHOT_PATH" \
    --add-ignore "data/google-drive" \
    --add-ignore "data/one-drive" \
    --add-ignore "data/syno-drive" \
    --add-ignore ".SynologyDrive" \
    --add-ignore ".cache" \
    --add-ignore ".local/share/containers" \
    --add-ignore ".var/app/com.valvesoftware.Steam" \
    --keep-latest 3 \
    --keep-daily 3 \
    --keep-weekly 3 \
    --keep-monthly 3 \
    >/dev/null

kopia snapshot create "$SNAPSHOT_PATH"

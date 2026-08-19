#!/usr/bin/env bash
# Installs the systemd --user timer that runs scripts/kopia-backup.sh daily.
# Same shape as the Rclone UI app's own rclone-*.service units already on
# this machine (~/.config/systemd/user/) — hand-written here instead of
# GUI-generated, since kopia has no GUI installer for this.
#
# Persistent=true: if the laptop was asleep or offline at the scheduled
# time, the missed run fires at next wake instead of being silently
# skipped — the standard systemd fix for a machine that isn't always on.
#
# Idempotent: safe to re-run — rewrites the units and reloads.
#
# Requires kopia already layered (scripts/layer-packages.sh) and the
# repository already connected (docs/recovery.md Card 3) before the
# timer's first run will succeed — this script only installs the schedule.
#
# Usage: scripts/install-kopia-backup.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR="${HOME}/.config/systemd/user"
mkdir -p "$UNIT_DIR"

cat > "${UNIT_DIR}/kopia-backup.service" <<EOF
[Unit]
Description=kopia snapshot of /var/home
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${REPO_ROOT}/scripts/kopia-backup.sh
EOF

cat > "${UNIT_DIR}/kopia-backup.timer" <<'EOF'
[Unit]
Description=Daily kopia snapshot of /var/home

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now kopia-backup.timer

echo "kopia-backup.timer installed and enabled"
systemctl --user list-timers kopia-backup.timer --no-pager

#!/usr/bin/env bash
# Generic periodic health-check runner. Base layer — works unchanged on any
# machine this repo is deployed to, given a checks directory.
#
# Why this exists: incidents/I029 (tb-bridge crash-looped silently for
# hours) and I030 (the first version of this, single-purpose to tb-bridge
# only). Generalized so any number of independent checks can plug in
# without each reinventing its own timer/notification/logging.
#
# Check contract: every executable under `scripts/health-checks/*.sh` (base,
# any machine) and `hosts/<slug>/health-checks/*.sh` (host-specific quirks)
# is run with no arguments. Exit 0 = healthy — stdout is still logged but no
# notification fires. Exit 1 = alert — stdout becomes the notification body
# and fires `notify-send`. Anything else is treated as the check itself
# being broken and is reported as an alert with that distinction noted.
#
# Every run's full stdout+stderr is kept in
# ~/.local/state/system-health-check/<check-name>.log regardless of outcome,
# specifically so a human who gets notified can immediately ask the agent
# "what's wrong" and the agent has the verbose detail on disk to read
# without re-running anything or guessing from the terse notification text.
# `summary.log` appends one line per run across all checks, for checks (like
# battery-drain) that want to look at recent history.
#
# `run` (default) executes every check once — what the timer below calls.
# `install` writes and enables system-health-check.timer, same shape as
# scripts/install-kopia-backup.sh. Both idempotent.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR="${HOME}/.config/systemd/user"
LOG_DIR="${HOME}/.local/state/system-health-check"
HOST_SLUG="thinkpad-e14-gen5"

CHECK_DIRS=(
  "${REPO_ROOT}/scripts/health-checks"
  "${REPO_ROOT}/hosts/${HOST_SLUG}/health-checks"
)

cmd="${1:-run}"

notify() {
  notify-send --app-name="system-health-check" --urgency=critical \
    "System health: $1" "$2"
}

run() {
  mkdir -p "$LOG_DIR"
  local ts
  ts="$(date -Iseconds)"
  local any_failed=0

  for dir in "${CHECK_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    for check in "$dir"/*.sh; do
      [ -e "$check" ] || continue
      local name
      name="$(basename "$check" .sh)"
      local log="${LOG_DIR}/${name}.log"

      local output exit_code
      output="$("$check" 2>&1)" && exit_code=0 || exit_code=$?

      {
        echo "=== $ts (exit $exit_code) ==="
        echo "$output"
      } > "$log"
      echo "$ts $name exit=$exit_code" >> "${LOG_DIR}/summary.log"

      case "$exit_code" in
        0)
          echo "ok:    $name"
          ;;
        1)
          echo "ALERT: $name"
          notify "$name" "${output:-see ${log}}"
          any_failed=1
          ;;
        *)
          echo "BROKEN: $name (check script itself failed, exit $exit_code)"
          notify "$name (check broken)" "The check script exited $exit_code instead of 0/1 — it may be broken, not the thing it checks. See ${log}"
          any_failed=1
          ;;
      esac
    done
  done

  return $any_failed
}

install() {
  mkdir -p "$UNIT_DIR"

  cat > "${UNIT_DIR}/system-health-check.service" <<EOF
[Unit]
Description=Run system health checks and notify on genuine failure

[Service]
Type=oneshot
ExecStart=${REPO_ROOT}/scripts/system-health-check.sh run
EOF

  cat > "${UNIT_DIR}/system-health-check.timer" <<'EOF'
[Unit]
Description=Run system-health-check.service every 15 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now system-health-check.timer

  echo "system-health-check.timer installed and enabled"
  systemctl --user list-timers system-health-check.timer --no-pager
}

case "$cmd" in
  run) run ;;
  install) install ;;
  *)
    echo "Usage: $0 {run|install}" >&2
    exit 1
    ;;
esac

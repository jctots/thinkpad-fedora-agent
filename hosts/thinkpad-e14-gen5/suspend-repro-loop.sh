#!/usr/bin/env bash
# I021 repro loop — repeated s2idle suspend/resume cycles via
# systemctl suspend + an RTC wake alarm, no lid/keyboard/power-button
# interaction needed. See
# incidents/I021-acpi0007-second-suspend-hang.md.
#
# Rationale: the bug is intermittent and has hit both after a quick
# second suspend and after a single long overnight one — no known
# trigger sequence, so this maximizes shots at it by volume (randomized
# durations) rather than chasing a specific pattern.
#
# Suspend is triggered via `systemctl suspend` (the same logind path a
# real lid-close goes through — NetworkManager sleep handling, GNOME
# Shell's PrepareForSleep, /usr/lib/systemd/system-sleep/ hooks), not
# `rtcwake -m mem` directly: that writes straight to /sys/power/state and
# bypasses all of the above, confirmed empty of any logind/PrepareForSleep
# journal lines in an earlier smoke test on this host 2026-08-23 — too
# shallow to trust as a stand-in for what actually hangs. `rtcwake -m no`
# only arms the RTC wake alarm and returns immediately; the following
# `systemctl suspend` then blocks (frozen along with the rest of the
# system) until that alarm fires and the real resume path runs.
#
# If the bug reproduces, the machine hangs exactly as it has organically
# — unresponsive, needs a forced power-off — this script does not change
# that risk, it just triggers cycles unattended so a hang is more likely
# to happen while nobody's waiting on it. Every completed cycle and the
# hang itself (via absence of further log lines) show up in the journal
# under the `suspend-repro-loop` syslog tag, so `journalctl -t
# suspend-repro-loop` after a reboot tells you how far it got.
#
# Run via: pkexec hosts/thinkpad-e14-gen5/suspend-repro-loop.sh [cycles] [min_sleep_s] [max_sleep_s] [awake_gap_s]
# Defaults: 20 cycles, 60-300s asleep each, 45s awake between cycles
# (~180s average asleep + 45s awake = ~225s/cycle, so 20 cycles is
# ~75 minutes total — scale CYCLES up for a longer unattended run).
set -euo pipefail

CYCLES="${1:-20}"
MIN_SLEEP="${2:-60}"
MAX_SLEEP="${3:-300}"
AWAKE_GAP="${4:-45}"

if [[ $EUID -ne 0 ]]; then
  echo "Run via: pkexec $0 [cycles] [min_sleep_s] [max_sleep_s] [awake_gap_s]" >&2
  exit 1
fi

if grep -q '^nvidia ' /proc/modules; then
  echo "nvidia module is loaded this boot — I021's isolation expects the" >&2
  echo "dGPU disabled (hosts/thinkpad-e14-gen5/gpu-toggle.sh disable, then" >&2
  echo "reboot) so a hang can't be confounded with I019's GPU bug. Aborting." >&2
  exit 1
fi

logger -t suspend-repro-loop "starting: cycles=$CYCLES min=${MIN_SLEEP}s max=${MAX_SLEEP}s gap=${AWAKE_GAP}s"

for i in $(seq 1 "$CYCLES"); do
  dur=$(( RANDOM % (MAX_SLEEP - MIN_SLEEP + 1) + MIN_SLEEP ))
  logger -t suspend-repro-loop "cycle $i/$CYCLES: suspending for ${dur}s"
  rtcwake -m no -s "$dur" >/dev/null
  systemctl suspend
  logger -t suspend-repro-loop "cycle $i/$CYCLES: resumed cleanly"
  sleep "$AWAKE_GAP"
done

logger -t suspend-repro-loop "completed all $CYCLES cycles without a hang"

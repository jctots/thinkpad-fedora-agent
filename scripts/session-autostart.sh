#!/usr/bin/env bash
# Launched by ~/.config/autostart/thinkpad-fedora-agent.desktop on graphical
# login. If a handover file was left before a reboot, resume from it;
# otherwise start a fresh session.
#
# The handover file is consumed, not just read: it's renamed to
# .claude/handover.consumed.md *before* claude ever starts, so the
# .claude/handover.md existence check can never match the same file across
# two reboots. Without this, a stale handover.md left after being read once
# (e.g. the user just /exit's instead of asking for a fresh write) would
# surface as "resume from" instructions on every subsequent reboot, forever.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

if [[ -f .claude/handover.md ]]; then
  mv .claude/handover.md .claude/handover.consumed.md
  exec claude "Read .claude/handover.consumed.md and resume from where I left off."
else
  exec claude
fi

#!/usr/bin/env bash
# Launched by ~/.config/autostart/thinkpad-fedora-agent.desktop on graphical
# login. If a handover file was left before a reboot, resume from it;
# otherwise start a fresh session.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

if [[ -f .claude/handover.md ]]; then
  exec claude "Read .claude/handover.md and resume from where I left off."
else
  exec claude
fi

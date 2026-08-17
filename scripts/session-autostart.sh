#!/usr/bin/env bash
# Launched by ~/.config/autostart/thinkpad-fedora-agent.desktop on graphical
# login, and equally valid for a manually-typed launch in this repo.
#
# additionalContext from a SessionStart hook can't trigger a turn on its
# own — Claude Code only calls the model once the user submits a prompt, so
# a "silent" resume never actually appears until the user types something
# first (see incidents/I010). There is no supported invisible-trigger
# mechanism today (tracked upstream as anthropics/claude-code#69750).
#
# So every launch sends the same fixed prompt, unconditionally — no
# handover-file check here. The branching (resume from handover vs. plain
# greeting + quote) happens agent-side on receiving this trigger; see
# .claude/skills/handover/SKILL.md's read-mode section.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

exec claude "I'm back"

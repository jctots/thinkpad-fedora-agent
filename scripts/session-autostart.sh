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
#
# Fail-fast + log: if the network is unreachable, or `claude` itself exits
# non-zero (auth failure, usage exhausted), that means no model turn ever
# ran — so no skill can react to it from inside a session. This script logs
# the failure to local/session-launch-failures.log and drops into a plain
# interactive shell instead of letting the Ptyxis window vanish silently.
# The next successful "I'm back" session reads that log and surfaces it —
# see .claude/skills/handover/SKILL.md's read-mode.
set -uo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

log_file="$repo_dir/local/session-launch-failures.log"
mkdir -p "$repo_dir/local"

fail() {
    local reason="$1"
    printf '%s\t%s\n' "$(date -Is)" "$reason" >> "$log_file"
    echo
    echo "session-autostart: $reason"
    echo "Logged to local/session-launch-failures.log — the next successful launch will surface this."
    echo "Dropping to a plain shell; run: claude \"I'm back\"   once this is resolved."
    exec bash -l
}

if ! curl --silent --head --max-time 5 -o /dev/null https://api.anthropic.com; then
    fail "network-unreachable (preflight check against api.anthropic.com failed)"
fi

claude "I'm back"
status=$?

if [ "$status" -ne 0 ]; then
    fail "claude exited non-zero (status $status) — check auth/usage"
fi

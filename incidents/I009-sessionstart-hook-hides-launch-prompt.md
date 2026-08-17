<!--
Template: incidents/I{nnn}-{slug}.md
Use: one file per incident. I### increments from incidents/index.md; slug is kebab-case.
After writing: add a row to incidents/index.md (newest first).
-->

## I009 — 2026-08-17 — GNOME-autostart Claude session showed a visible fake "resume from handover" turn

**Area:** agent

**Symptom:** `scripts/session-autostart.sh` launched `claude` with a CLI
launch-prompt argument that told the model to read `.claude/handover.md`
and resume. That prompt showed up in the terminal as a real, visible first
user turn — cluttering every autostarted session (and every reboot-recovery
session) with boilerplate the human never typed.

**Cause:** The handover-resume instruction was being delivered as an
argument to `claude`'s launch prompt instead of through a silent context
channel. `claude`'s CLI prompt argument is inherently a visible turn; there
was no mechanism to inject the same instruction invisibly.

**Fix:** Added `.claude/hooks/session-start-greeting.sh`, wired into
`.claude/settings.json` under `hooks.SessionStart`. It performs the
`.claude/handover.md` → `.claude/handover.consumed.md` rename (atomic
consume, so a hang mid-session can't reprocess it) and picks a quote from
`scripts/quotes.txt`, then emits its output via
`hookSpecificOutput.additionalContext` — the same silent-injection channel
CLAUDE.md itself uses, not a visible chat turn.
`scripts/session-autostart.sh` was simplified to a bare `exec claude`, since
the hook now owns the resume logic. `.claude/skills/handover/SKILL.md`'s
"Consumed automatically" section was rewritten to describe the hook instead
of the old script-based mechanism.

**Tried first:** The fix itself was written and unit-tested (valid JSON via
`jq`, correct rename behavior for both handover-present and
handover-absent cases) in a prior session, but that session could not
observe an actual live `claude` launch or the GNOME autostart `.desktop`
path — both require a real session start, which only happens outside the
session that writes the fix. This session's very first turn was that live
test: the handover file was present, and the greeting came through as
clean `additionalContext` with no visible "Read .claude/handover.md..."
text before it — confirming the hook design works end to end, including
through the atomic rename.

**Reversibility:** `etckeeper`/rpm-ostree don't apply — this is all
`/var/home` repo state (hook script + settings.json + skill doc), covered
by the repo's own git history.

**Captured in:** `.claude/hooks/session-start-greeting.sh`,
`.claude/settings.json` (`hooks.SessionStart`), `scripts/session-autostart.sh`.

**Tally:** time-to-fix ~1m (confirmed instantly at this session's first
turn, after being written and unit-tested in the prior session) · first
proposal: ✓ right — the hook design worked on the first live run, no
iteration needed.

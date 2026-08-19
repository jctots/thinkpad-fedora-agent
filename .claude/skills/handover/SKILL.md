---
name: handover
description: Write or read .claude/handover.md, a session-continuity snapshot used instead of `claude -c` around a reboot-triggering action. Use in write mode proactively before anything likely to end the session (systemctl reboot, rpm-ostree rebase, anything requiring a restart); use in read mode whenever the session's first turn is the literal message "I'm back" — sent automatically by scripts/session-autostart.sh on every launch, not typed by the human — or when the user says they're back after a reboot by hand.
---

Normally reached via `/end-session`, which checks whether a reboot is
actually pending and invokes this skill's write mode only if so — don't
make the user track which mechanism applies. Invoke this skill directly
when you already know a reboot is imminent and want the snapshot written
without going through that check.

Formalizes the standing practice already recorded in this project's memory
(`feedback-handover-over-dash-c`): `claude -c` replays the entire prior
transcript as input tokens on every subsequent turn, including large
one-time outputs like full `rpm-ostree install` dumps — on a long
bootstrap-style session that cost compounds every turn for the rest of the
session. A bounded handover file plus memory gives the same continuity for a
fixed, small cost instead.

## Write mode — before a session-ending action

Trigger proactively, without being asked, before `systemctl reboot`,
`rpm-ostree rebase`, or anything else that requires a restart.

1. Snapshot: what's confirmed done, what's staged-but-unverified, known
   blockers, and the exact next step.
2. Explicitly check and record uncommitted/pending git state —
   `git status` / `git diff --cached` across any repo touched this session.
   This is a recurring near-miss; don't skip it.
3. Overwrite `.claude/handover.md` wholesale (gitignored, repo root) —
   never append. It's working state, not a log; once consumed and the phase
   it described has moved on, the next write replaces it rather than piling
   up. Durable narrative belongs in `incidents/` or the vault's `_inbox/`,
   not here.
4. Cross-reference what to read alongside it (this project's memory index,
   `incidents/index.md`, the relevant host README) rather than duplicating
   that content into the handover file itself.

## Read mode — "I'm back" / after a reboot

`scripts/session-autostart.sh` sends the literal trigger `"I'm back"` as
the CLI prompt argument on **every** launch — unconditionally, whether or
not a handover is actually pending. That's a deliberate simplification
(see "Why the trigger is unconditional" below): the branching happens here,
not in bash.

On receiving that trigger (or an equivalent manual "I'm back" from the
user):

1. Start a **new** session — no `-c`. Don't assume the old transcript is
   available or needed.
2. Check whether `.claude/handover.md` exists.
   - **Present:** rename it to `.claude/handover.consumed.md` (`mv`, so
     consumption is atomic — a hang mid-session can't reprocess the same
     file on the next launch), then read it plus this project's memory
     files. Surface the "Immediately next" step as the first thing said
     back to the user, not buried after a recap. Flag if the file looks
     stale — references a reboot that's now old, or contradicts current
     `git log` / `rpm-ostree status` — rather than trusting it blindly.
   - **Absent:** no resume needed. Give a plain, short greeting — who you
     are and an invitation to start, no recap of prior work unless asked —
     and close it with a quote picked via `shuf -n1 scripts/quotes.txt`
     (zero-token random pick; don't generate or web-search a quote
     yourself). Don't recite "there's nothing pending" as a status report.
3. Either way — present or absent — invoke the `reset-triage` skill next.
   It checks whether the *previous* boot ended cleanly, independent of
   whether a handover was staged: a crash can happen outside any planned
   reboot. It stays silent when the last boot was clean, so this doesn't
   add noise to the plain-greeting path.

## Why the trigger is unconditional

An earlier design (see `incidents/I009`, `incidents/I010`) tried to do the
handover check and rename silently via a `SessionStart` hook's
`additionalContext`, specifically to avoid a visible synthetic first turn.
That doesn't work: `additionalContext` only feeds the *next* model call —
Claude Code never calls the model until the user submits a prompt, so
nothing appeared until the human typed something first, at which point any
resume context looked stale. There is no supported way to get an invisible
proactive first turn today (tracked upstream:
anthropics/claude-code#69750, proposing an `autoPrompt` hook field).

Given that, `session-autostart.sh` doesn't try to inspect the filesystem
at all — it just always sends the same visible trigger, and this skill
does the branching once the model is actually running. That keeps the
script trivial (no bash logic that can drift out of sync with what this
skill expects) and means both outcomes — resume, or plain greeting + quote
— go through the exact same code path.

Because the rename happens here, not in the script, a handover file
written before a plain `/exit` (no autostart launch expected right after)
just sits there until the next `session-autostart.sh` run actually
reaches this skill. Prefer only writing one when another autostarted or
scripted session is actually expected next; a manually-launched `claude -c`
won't trigger this skill at all.

## When not to use this

A fresh bootstrap phase with no reboot pending doesn't need this — a plain
new session re-deriving from `docs/bootstrap.md` checkboxes, `git log`, and
`incidents/` is already the cheaper default. This is specific to sessions
expecting a mid-task reboot.

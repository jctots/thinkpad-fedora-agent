---
name: handover
description: Write or read .claude/handover.md, a session-continuity snapshot used instead of `claude -c` around a reboot-triggering action. Use in write mode proactively before anything likely to end the session (systemctl reboot, rpm-ostree rebase, anything requiring a restart); use in read mode when the user says they're back after a reboot.
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

1. Start a **new** session — no `-c`. Don't assume the old transcript is
   available or needed.
2. Read `.claude/handover.md` plus this project's memory files.
3. Surface the "Immediately next" step as the first thing said back to the
   user, not buried after a recap.
4. Flag if the file looks stale — references a reboot that's now old, or
   contradicts current `git log` / `rpm-ostree status` — rather than
   trusting it blindly.

## When not to use this

A fresh bootstrap phase with no reboot pending doesn't need this — a plain
new session re-deriving from `docs/bootstrap.md` checkboxes, `git log`, and
`incidents/` is already the cheaper default. This is specific to sessions
expecting a mid-task reboot.

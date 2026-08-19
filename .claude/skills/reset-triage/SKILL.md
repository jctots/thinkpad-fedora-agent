---
name: reset-triage
description: Detects whether the previous boot ended cleanly, and if not, surfaces a standard evidence bundle unprompted. Use on every "I'm back" session start, chained after handover's read-mode — regardless of whether a handover.md was present, since an unclean shutdown can happen outside any planned-reboot flow.
---

Generic, reactive half of this project's crash/hang forensics capability
(thinkpad-fedora-agent decision D33). The permanent baseline sensors that
make this possible — `pm_trace`, the sysrq bitmask, `pm_debug_messages`,
and a loosened journald sync interval — live in
`hosts/thinkpad-e14-gen5/quirks.sh` and are checked separately by
`/host-check`. This skill's only job is: did the last boot end badly, and
if so, hand over what was already captured. Follow-up on any specific
signature is case-by-case and out of scope here — see the relevant
`incidents/` entry or open a new one.

## When this runs

Invoked from the `handover` skill's read-mode, after that skill's own
present/absent branch on `.claude/handover.md` — both branches, since an
unclean shutdown isn't tied to whether a handover file exists. Not a
standalone entry point; don't invoke this before `handover` has run.

## Detection

```
last -x reboot | head -1
```

`last -x` reads wtmp and explicitly marks a boot session `crash` instead of
a clean end-time range when no matching "shutdown system down" record
exists for it — i.e. the machine came back up without ever writing a clean
shutdown record. This is the signal: look at the **most recent** `reboot`
line only.

- Ends with a time range (`- HH:MM (duration)`) → clean. Say nothing about
  this — no report, matching this project's no-news-is-no-report norm for
  routine skills. Move on silently.
- Ends with `- crash` → unclean. Continue to evidence collection below.

Only the single most recent boot matters. Older unclean boots already
further back in `last -x` history were either already triaged in a prior
session or predate this skill — don't re-surface them.

## Evidence collection (only when `crash` is found)

Gather, in order:

1. `journalctl --list-boots --no-pager | tail -3` — confirms the boot IDs
   and start/end timestamps for the crashed boot and the one before it.
   Watch for an end timestamp *earlier* than the start timestamp on the
   crashed boot — that's `pm_trace`'s bogus-RTC side effect firing, itself
   a positive signal that the trace actually caught something.
2. `journalctl -b -1 -k --no-pager | tail -60` — kernel log tail of the
   crashed boot, the most direct signature of what was happening right
   before it stopped.
3. `journalctl -b -1 -k --no-pager | grep -i "hash matches"` — the
   `pm_trace` device identification line, if armed and it caught a
   suspend/resume-path hang specifically. Empty output is normal if the
   hang wasn't in that path, or `pm_trace` wasn't armed that boot.
4. `journalctl -b 0 -k --no-pager | grep -i "hash matches"` — same check
   on the *current* boot's dmesg, since `pm_trace`'s identification line
   is written by the kernel on the boot **after** the trace fires, not
   into the crashed boot's own log.

## Reporting

Surface this unprompted, in the same register as handover's "Immediately
next" — first thing said back to the user, not buried after a recap:

- State plainly that the previous boot ended uncleanly, with its
  timestamp and duration.
- Give the `pm_trace` device signature if step 3/4 found one — that's the
  single strongest lead.
- Otherwise give a short characterization of the kernel log tail (last
  subsystem active, any obvious error/panic line) rather than dumping the
  full 60 lines into the reply.
- Do not attempt a diagnosis or fix here. If this looks like a recurrence
  of a known open investigation (check project memory / `incidents/` for
  a matching signature), say so and point at it. If it looks new, suggest
  opening one rather than improvising a response — the follow-up is
  inherently case-by-case per D33 and doesn't belong in this skill.

## Why `last -x`, not a custom heuristic

Considered comparing boot-to-boot timestamp gaps or checking for a
"Reached target Shutdown" journal line directly, but `last`'s `crash`
marker already does exactly this classification from wtmp, is a single
cheap command, and is what `s2idle` investigation's own hangs already
showed clearly (confirmed against boot `711aacda` from I-series
incidents: `last -x` marked it `crash` correctly while the two clean
reboots either side showed normal time ranges).

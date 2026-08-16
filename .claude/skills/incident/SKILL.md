---
name: incident
description: Scaffold a new incidents/I{nnn}-{slug}.md from the template and insert its row in incidents/index.md. Use right after a fix lands on this machine — a broken thing that this session's work fixed. Not for decisions (alternatives weighed, no breakage) or host facts (firmware, device IDs) — those go elsewhere per incidents/index.md's own header.
---

Write the entry when the problem is fixed, not at the end of the session —
CLAUDE.md and `incidents/index.md` both call this out: the failed attempts
are the part that's gone forever if it's left until later. Run this
proactively, right after landing a fix, without waiting to be asked.

1. **Determine the next number.** Read `incidents/index.md`'s table, take
   the highest existing `I{nnn}`, increment. Don't guess or reuse a number.

2. **Create `incidents/I{nnn}-{slug}.md`** from `incidents/_template.md`.
   Fill every field from what actually happened this session, not a
   generic description:
   - **Area** — one of the fixed vocabulary in the template's header
     comment and the index's "Areas" section: `rpm-ostree`, `flatpak`,
     `toolbox`, `gnome`, `hardware`, `network`, `etc`, `backup`, `agent`,
     `boot`.
   - **Symptom** — what was observed, verbatim where possible (error text),
     not the diagnosis.
   - **Cause / Fix** — what turned out to be true, and the exact
     copy-pasteable fix.
   - **Tried first** — what didn't work and why it looked plausible. This
     is the field most likely to be skipped under time pressure and the one
     the template calls "usually the most valuable paragraph in the file."
     Don't skip it.
   - **Reversibility** — name the actual layer: `rpm-ostree` rollback,
     `etckeeper` diff, `/var/home` backup, or none (say what the exposure
     was if none).
   - **Captured in** — the script this incident got automated into, or
     `not yet — still a one-off`.

3. **The Tally line is always asked, never guessed:** `time-to-fix ~Nm ·
   first proposal: right / wrong / n/a — agent unavailable`. Ask the user
   for the first-proposal verdict rather than inferring it — this is the
   one field CLAUDE.md is explicit about not fabricating, since it's the
   evidence the project's central claim rests on. An index with no `✗` is
   evidence of nothing except selective writing; don't round a wrong first
   guess up to a right one out of politeness.

4. **Insert the row into `incidents/index.md`** — newest first, at the top
   of the table, matching the existing column order.

5. If the fix also touched anything under `/etc`, this is also a natural
   moment to run `/etc-drift` — the two often go together.

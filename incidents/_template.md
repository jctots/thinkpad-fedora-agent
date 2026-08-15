<!--
Template: incidents/I{nnn}-{slug}.md
Use: one file per incident. I### increments from incidents/index.md; slug is kebab-case.
After writing: add a row to incidents/index.md (newest first).
-->

## I{nnn} — YYYY-MM-DD — {Short description of the symptom}

**Area:** rpm-ostree | flatpak | toolbox | gnome | hardware | network | etc | backup | agent | boot

**Symptom:** What was actually observed — the error text, the behaviour. Not the diagnosis.

**Cause:** What turned out to be true.

**Fix:** The command or change that worked. Exact, copy-pasteable.

**Tried first:** What did not work, and why it seemed plausible at the time. This is the part that is gone forever if it is not written down now, and it is usually the most valuable paragraph in the file.

**Reversibility:** Which layer covered this — `rpm-ostree` rollback, `etckeeper` diff, `/var/home` backup, or none. If none, say what the exposure was.

**Captured in:** `scripts/NN-thing.sh` | `hosts/<slug>/quirks.sh` | not yet — still a one-off

**Tally:** time-to-fix ~Nm · first proposal: right / wrong / n/a — agent unavailable

<!-- "n/a — agent unavailable" is for incidents recovered by hand via docs/recovery.md.
     Say in Fix: why the agent could not be reached. That is data, not an excuse. -->


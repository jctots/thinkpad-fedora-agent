## I017 — 2026-08-20 — System clock wrong after s2idle, RTC decades off

**Area:** boot

**Symptom:** User reported machine time wrong ("earlier it was correct").
`timedatectl status` showed local time correct-ish but drifting, `System clock
synchronized: no`, and `RTC time: Mi 2052-08-21 22:35:37` — 26 years in the
future. `chronyc tracking` showed the system clock tens of thousands of
seconds off NTP at points during the day. Kernel log had, twice in one day:
`PM: Possible incorrect RTC due to pm_trace, please use 'ntpdate' or 'rdate'
to reset it.`

**Cause:** `/etc/systemd/system/pm-trace.service` (added for the still-open
s2idle resume-hang investigation, see
[[project_s2idle_resume_hang_investigation]] / crash-forensics baseline D33)
armed `/sys/power/pm_trace = 1` at every boot. `pm_trace` is a kernel debug
feature that deliberately encodes suspend/resume trace data into the RTC's
time-of-day fields across every suspend cycle, scrambling the RTC's actual
time as a side effect — that's the documented behavior, not a malfunction.
Because this host has `RTC in local TZ: yes`, systemd applies the corrupted
RTC value (adjusted for timezone) to the system clock on every boot too, so
the bad time seeds in before chrony even starts. chrony (`makestep 1.0 3`,
`rtcsync`) was working correctly and did resync over NTP each time it reached
a server — but only for the first 3 corrections after start, and only once
network was up, so there were windows where the wall clock reflected the
corrupted RTC.

**Fix:**
```
pkexec systemctl disable --now pm-trace.service
pkexec bash -c 'echo 0 > /sys/power/pm_trace'
pkexec bash -c 'etckeeper commit "Disarm pm_trace: RTC corruption from s2idle forensic hooks was causing clock drift"'
pkexec chronyc makestep
pkexec hwclock --systohc --localtime -v
```
Confirmed via `chronyc tracking` (0.000000000 seconds slow, Leap status
Normal) and `timedatectl status` (RTC time now matches local time).

**Tried first:** Nothing discarded — the kernel's own `pm_trace` warning in
`journalctl -k` named the mechanism directly, so the trace from symptom to
cause to fix was straight-line once the boot log was checked.

**Reversibility:** `etckeeper` — the removed `pm-trace.service` symlink is a
plain `/etc` diff (commit `fc4206c`), fully revertible with `etckeeper vcs
revert` or by re-enabling the unit. The live `pm_trace` sysfs write and
`hwclock` resync are not tracked by any layer but are trivially
re-appliable (`echo 1 > /sys/power/pm_trace`, wrong RTC self-corrects via
NTP) — no meaningful exposure.

**Captured in:** not yet — still a one-off; `pm-trace.service` was already
tracked by `[[project_crash_forensics_baseline]]` (D33), this incident
supersedes that unit's use now that the RTC-corruption cost outweighed its
still-unused forensic value for the open s2idle bug.

**Tally:** time-to-fix ~15m · first proposal: right

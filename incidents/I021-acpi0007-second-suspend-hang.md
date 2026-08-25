## I021 — 2026-08-22 — Second consecutive suspend hangs, `pm_trace` points at ACPI0007:11 (not GPU)

**Area:** hardware

**Symptom:** Boot `c9ecce4b` (22:49–22:55) suspended cleanly once (22:54:07,
~213s asleep, resumed fine), then suspended again ~1 minute later at
22:55:11 and never came back. `journalctl -b -1` stops dead at
`PM: suspend entry (s2idle)` with nothing after — no NVIDIA driver
messages, no AVC denial, no panic, nothing. `last -x` marked the login
session `crash (00:28)`; `pm_trace` (armed by hand for this test, see
`incidents/I020`) confirmed the kernel caught it via a bogus-RTC
end-timestamp on `journalctl --list-boots`.

**Cause:** Unknown — open. `pm_trace`'s device identification, read from
the *next* boot's dmesg (`journalctl -b 0 -k | grep -i "hash matches"`),
points at `acpi ACPI0007:11: hash matches` — an ACPI Processor object, not
the GPU. This rules out a recurrence of `incidents/I020`'s NVRM-0x62/AVC
signature (confirmed absent from this boot's log entirely) but doesn't
identify what actually hung. No further evidence gathered yet: this is
where `reset-triage`'s evidence collection stops by design (case-specific
follow-up is explicitly out of its scope).

**Recurrence — 2026-08-23:** Same signature reproduced on a different boot
(`ab03f301`, login session started 22:18, crashed after 08:59). `pm_trace`
again pointed at `acpi ACPI0007:11: hash matches`, read from the next
boot's dmesg. Kernel log tail for the crashed boot again stops dead at
`PM: suspend entry (s2idle)` with nothing after — no NVIDIA messages, no
AVC denial, no panic — identical to the first occurrence.

New physical observation from the user, gathered by opening the lid rather
than from logs: before opening the lid, the ThinkPad's red LED was
**pulsating** — the normal suspended/sleep-breathing pattern, confirming
the machine really did reach s2idle successfully. On opening the lid, the
LED went **steady** (no longer pulsating) but the display stayed off and
neither the keyboard nor the power button produced any response — required
a forced power-off to recover.

This is the first evidence narrowing *where* in the suspend/resume cycle
the hang sits: the LED transitioning from pulsating to steady on lid-open
indicates the EC/hardware did register the wake event and the kernel
began the resume sequence, but something in the resume path — consistent
with `pm_trace` pointing at the `ACPI0007:11` processor object's
resume handler — never completes far enough to reinitialize the display
or restore input responsiveness. This rules out a failure to *enter*
suspend (already suspected unlikely given the pulsating LED beforehand)
and points specifically at resume, not entry.

**Debug mechanism added — 2026-08-23:** Two reversible levers staged to
bisect the cause, both OS-image layer (`rpm-ostree rollback`-covered):

1. `processor.max_cstate=1` kernel arg — caps CPU idle states at C1. If the
   hang stops recurring with this set, it strongly implicates deep C-state
   resume handling on the `ACPI0007:11` processor object specifically. If
   it still happens, C-states are cleared as a cause.
2. `acpi.debug_layer=0x2 acpi.debug_level=0x4` kernel args — verbose ACPI
   PM-layer tracing, added to capture more detail on the next occurrence.
   May print nothing extra if the freeze is a true hard lockup before any
   log call reaches the console/journal — itself informative, since
   `no_console_suspend` + `pm_debug_messages` (already active per I020's
   baseline) already produce zero output between `PM: suspend entry
   (s2idle)` and the hang, meaning the freeze isn't a logging gap.

Staged via `pkexec rpm-ostree kargs --append=processor.max_cstate=1
--append=acpi.debug_layer=0x2 --append=acpi.debug_level=0x4` — takes effect
next reboot, current boot unaffected. Status check and exact removal
commands are in `hosts/thinkpad-e14-gen5/quirks.sh`'s s2idle escalation
block (report-only there; run by hand). Also re-disabled the dGPU via
`hosts/thinkpad-e14-gen5/gpu-toggle.sh disable` to keep this test isolated
from I020's still-unverified SELinux/GPU fix — the GPU wasn't implicated
by `pm_trace` in either I021 occurrence, but leaving it enabled during a
C-state bisection would confound the result if a hang occurred. Re-enable
with `gpu-toggle.sh enable` once this investigation concludes, independent
of the kargs above.

**Repro script — 2026-08-23:** `hosts/thinkpad-e14-gen5/suspend-repro-loop.sh`
added to bisect via volume (randomized suspend durations, no known trigger
sequence to target directly) instead of waiting for another organic
occurrence. First version used `rtcwake -m mem -s N` directly — confirmed via
journal (`journalctl --since ... | grep -iE "logind|PrepareForSleep|
NetworkManager.*sleep"`, empty output) that this bypasses `systemd-logind`
entirely: no `PrepareForSleep`, no `systemd-sleep` hooks, no
`nvidia-suspend.service` condition check — too shallow to trust as a stand-in
for a real lid-close. Rewritten to `rtcwake -m no -s N` (arms the RTC wake
alarm only, returns immediately) followed by `systemctl suspend` (the real
logind path). Verified via 2-cycle smoke test 2026-08-23 18:35: journal shows
the full expected chain — `systemd-logind: The system will suspend now!` →
`nvidia-suspend.service` exec-condition check → `systemd-sleep`/
`systemd-suspend.service` → `PM: suspend entry (s2idle)` →
`Timekeeping suspended for 26.000 seconds` (matches the ~27s requested) →
`PM: resume from suspend-to-idle` → `PM: suspend exit`. Confirmed the loop
continues unattended through the screen-lock GNOME puts up after each
resume — cycle 2 started on schedule (~7s after cycle 1's resume, matching
the configured `AWAKE_GAP`) with nobody logging back in. `systemctl
suspend`/the script operate at the systemd/kernel level, independent of the
GNOME session or lock state.

One anomaly from an earlier (shallow, since-replaced) run worth re-checking
if it recurs: one cycle requested a 60s sleep but didn't log "resumed
cleanly" until ~2 hours later — script didn't hang, kept going normally
afterward, but the RTC alarm clearly didn't fire on schedule that one time.
Not yet understood; may be specific to the old `rtcwake -m mem` path, may
not be. Watch for it in the new (`systemctl suspend`) version's `journalctl
-t suspend-repro-loop` timestamps — a cycle where "resumed cleanly" lands far
past `suspending for Ns` plus the requested N is the signal.

To launch the full run: `pkexec hosts/thinkpad-e14-gen5/suspend-repro-loop.sh
[cycles] [min_sleep_s] [max_sleep_s] [awake_gap_s]` — needs to be launched
while physically at the machine (one polkit auth dialog on the local
display, no way to approve it remotely), then runs unattended for its full
duration. Defaults are 20/60/300/45 (~75 min); for a ~4h run used 64 cycles.
Script refuses to run if the nvidia module is loaded (checks
`/proc/modules`) — dGPU must stay disabled for I021 isolation. Check
progress/results any time via `journalctl -t suspend-repro-loop` (no login
or unlock needed, reads fine from a locked screen).

**Repro attempts:** 2026-08-24 14:21–16:27 (~2h6m), 32 cycles, 60–300s
asleep/45s awake gap, dGPU confirmed disabled beforehand, **connected to
AC power throughout**. All 32 cycles resumed cleanly — `completed all 32
cycles without a hang` in `journalctl -t suspend-repro-loop`. Verified
independently via kernel PM log, not just the script's own claim:
`journalctl -k` shows exactly 32 `PM: suspend entry (s2idle)` /
`PM: resume from suspend-to-idle` pairs in the run's time window, each
elapsed duration matching its requested sleep to within ~1s. No
recurrence of the earlier 2h-late-resume anomaly noted above. Does not
rule out the bug — it's intermittent and has hit both after a quick
second suspend and after a single long overnight one, so a clean run is
not evidence of a fix, just one more data point that this remains hard to
reproduce on demand.

**Correction — C-state cap was already live during today's clean run:**
`processor.max_cstate=1` (staged 2026-08-23, see "Debug mechanism added"
above) is confirmed active in the current boot's `/proc/cmdline` — kargs
take effect on the *next* reboot after staging, and there's been a reboot
since. So today's 2026-08-24 32-cycle AC run was never a "normal/uncapped
C-states" test; it already ran with deep C-states disabled. This means
the deep-C-state bisection lever has been live and untested-against-a-hang
since 08-23 — a clean run under it isn't yet evidence either way, since
there's no uncapped baseline on this host to compare it to. A future repro
attempt with the cap removed (`pkexec rpm-ostree kargs
--delete=processor.max_cstate=1`, reboot) is needed to get that baseline.
Also confirmed: `cat /sys/power/mem_sleep` shows only `[s2idle]` — no S3
fallback available on this hardware, ruling that out as a mitigation path.

**Debug instrumentation added — 2026-08-24:**
1. `hosts/thinkpad-e14-gen5/suspend-repro-loop.sh` now logs a
   `log_pm_snapshot` line (AC/battery state + cpu0 C-state residency
   counters from `/sys/devices/system/cpu/cpu0/cpuidle/state*/usage`)
   before each suspend and after each resume, tagged the same as the
   existing cycle log lines. Read-only sysfs reads, no system state
   changed. Reversible trivially — it's a script edit, `git diff`/revert
   in this repo.
2. `/etc/modprobe.d/thinkpad-acpi-debug.conf` — `options thinkpad_acpi
   debug=0xffff` (TPACPI_DBG_ALL: init, exit, rfkill, hotkey/EC events,
   fan, brightness, mixer), targeting the EC/charger-negotiation
   hypothesis specifically, which the existing generic `acpi.debug_layer`
   kargs don't cover. Written via `pkexec cp ... /etc/modprobe.d/`,
   confirmed committed by etckeeper (`255c6fc`). Takes effect on next
   module reload — `thinkpad_acpi` was already loaded this boot without
   the option, so effectively next reboot, or
   `pkexec rmmod thinkpad_acpi && pkexec modprobe thinkpad_acpi` to apply
   live. **Reverse:** `pkexec rm /etc/modprobe.d/thinkpad-acpi-debug.conf
   && pkexec etckeeper commit "revert I021 thinkpad_acpi debug"`, then
   reboot (or rmmod/modprobe again) to drop the verbosity.
3. Considered and rejected: `dynamic_debug` (debugfs) toggling for
   finer-grained live control without a reload — this host runs Secure
   Boot with kernel lockdown in `confidentiality` mode
   (`/sys/kernel/security/lockdown`), which blocks debugfs writes even as
   root. modprobe.d + module reload was the only route available.

**Untested variable — AC vs. battery:** every repro attempt so far
(before this one) ran on AC power. Neither of the two organic hangs
(2026-08-22, 2026-08-23) has AC/battery state recorded either, so this
axis is completely unexplored, not just untested-and-clean. Plausible
mechanism: ACPI0007 is a processor object, and CPU C-state/idle-loop
entry criteria plus EC/charger negotiation on resume both differ between
AC and battery — `power-profile-daemon` typically auto-switches to
`power-saver` on battery, changing what state the CPU is in when s2idle
freezes it. I019 is precedent that this hardware/firmware combo has at
least one other power-state-dependent suspend pathology. Next repro
attempt should run at least partly, ideally entirely, on battery to rule
this in or out. Also worth running longer (more cycles/overnight) to
widen the window regardless of power source.

**Repro attempt — 2026-08-24 17:00–18:01 (~61m), on battery:** 16 cycles,
60–300s asleep/45s awake gap, dGPU confirmed disabled beforehand
(`nvidia not loaded` check in the script), `processor.max_cstate=1` still
active in `/proc/cmdline` (not removed for this run — battery was the
only variable changed, cap removal is still a separate untested lever).
Battery held 53%→45% over the run, `AC=0` confirmed at every
pre-suspend/post-resume snapshot. All 16 cycles resumed cleanly —
`completed all 16 cycles without a hang` in
`journalctl -t suspend-repro-loop`. cpu0 C-state usage counters climbed
steadily every cycle (`C3_ACPI` 57966→111103) with no gaps or resets,
consistent with normal idle-loop behavior throughout. No recurrence.
Does not rule out the bug — still intermittent and now clean on both AC
(32 cycles) and battery (16 cycles) under the C-state cap. The
uncapped-C-state baseline (`processor.max_cstate=1` removed) remains the
one lever left untested.

**Uncapped-C-state baseline staged — 2026-08-24 (prep for overnight run):**
`pkexec rpm-ostree kargs --delete=processor.max_cstate=1` run — confirmed
via `rpm-ostree kargs` that the pending deployment's cmdline no longer
includes it (`acpi.debug_layer=0x2 acpi.debug_level=0x4` kept). Queued for
next boot, current boot unaffected, reversible via `rpm-ostree rollback`
or re-appending the karg. Not yet rebooted — staged ahead of an overnight
repro run so the reboot + launch can happen together when triggered.
Planned invocation once rebooted and dGPU-disabled confirmed:
`pkexec hosts/thinkpad-e14-gen5/suspend-repro-loop.sh 128 60 300 45`
(~8h at default 60–300s/45s-gap timing). Power source (AC vs. battery)
for this run still to be decided at launch time — both AC and battery are
now clean at capped C-states (32 and 16 cycles respectively), so this run
isolates the C-state variable alone if left on the same power source as
one of those, or stacks both untested variables if run on battery
overnight — worth deciding deliberately, not by default.

**Repro attempt — 2026-08-25 11:32–12:27 (~55m), AC + uncapped C-states:**
16 cycles, 60–300s asleep/45s awake gap. Confirmed before launch: dGPU not
loaded, `AC=1` throughout, and `/proc/cmdline` no longer carries
`processor.max_cstate=1` (the delete staged 2026-08-24 had since taken
effect over an intervening reboot) with `/sys/module/intel_idle/parameters/max_cstate`
reading `9` (uncapped) — so this was the AC-side half of the
previously-staged uncapped-C-state baseline. All 16 cycles resumed
cleanly — `completed all 16 cycles without a hang` in
`journalctl -t suspend-repro-loop`. No recurrence. Matrix so far: AC+capped
(32 cycles, 2026-08-24), battery+capped (16 cycles, 2026-08-24), AC+uncapped
(16 cycles, this run) all clean. **Battery+uncapped is the one remaining
untested cell.**

**Repro attempt — 2026-08-25 13:14–13:28 (~14m, cancelled by user), battery +
uncapped C-states:** Launched to fill the last untested matrix cell
(battery power + `processor.max_cstate` cap removed). Confirmed before
launch: dGPU not loaded, `AC=0`/`batt=68%`, uncapped C-state still active
from the prior run. User cancelled partway through; the outer task-tracker
kill only stopped the unprivileged wrapper shell, not the actual
root-owned script process (pkexec-launched, PID persisted past the tracked
task) — had to `pkexec kill -TERM` it directly to actually stop the loop.
5 of 16 cycles completed before cancellation, all resumed cleanly (68%→65%
battery, AC=0 confirmed at every snapshot) — no hang in the partial run.
Battery+uncapped remains the only matrix cell without a full-length clean
run; worth re-running to completion when convenient.

**Tried first:** `reset-triage` flagged the crash and collected the
standard evidence bundle (boot list, kernel log tail, `pm_trace` hash on
both the crashed and current boot). Initial hypothesis was that this was
I020's bug recurring, since it happened in the same boot as I020's fix
verification — checked for `NVRM: PM suspend notifier failed`, `krcWatchdog`,
and `AVC ... systemd_sleep_t` in the crashed boot and found none of them,
which correctly ruled that out rather than being a wrong turn. Also
verified `nvidia-suspend.service`'s "Skipped due to exec-condition" on
every suspend attempt was a red herring — that unit only runs when
`UseKernelSuspendNotifiers: 0` (confirmed via `/proc/driver/nvidia/params`
it's `1` on this system), so its skip is expected/inert and not evidence
either way.

**Reversibility:** none — read-only triage so far, no system changes made
for this incident specifically.

**Captured in:** not yet — still a one-off; no reproduction or fix attempt
yet.

**Tally:** time-to-fix — not yet fixed, still open · first proposal: right
— the diagnostic thread (ruling out I020's signature, confirming the
`nvidia-suspend.service` skip was inert, isolating the `ACPI0007:11`
`pm_trace` pointer) held up without having to be walked back.

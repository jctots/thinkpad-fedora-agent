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

**Fix:** none yet — open investigation.

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

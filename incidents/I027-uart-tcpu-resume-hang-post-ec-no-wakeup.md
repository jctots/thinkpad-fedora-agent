## I027 — 2026-08-25 — Suspend hang with heat + unresponsive LEDs, first boot after I026's `ec_no_wakeup=1` fix

**Area:** hardware

**Symptom:** User closed the lid to suspend. Confirmed the machine reached
s2idle by observation: the red ThinkPad LED was glowing/pulsating (the
normal sleep-breathing pattern) and the white power-button LED was also
lit. On returning and opening the lid, nothing responded — no wake on lid
open, no response to the power button — and both LEDs kept
pulsating/glowing rather than going steady or off. The machine was
noticeably hot to the touch. The only recovery was a forced shutdown via a
long power-button hold.

`reset-triage` on the next boot confirmed this from the logs: `last -x`
marked the login session `crash (00:22)` (16:49–17:11). `journalctl -b -1
-k` stops dead at `PM: suspend entry (s2idle)` (17:00:02) with nothing
after — identical in shape to `incidents/I021`. `pm_trace` (already armed
per `hosts/thinkpad-e14-gen5/quirks.sh`) identified two devices on the next
boot's dmesg:

```
acpi device:48: hash matches   ->  \_SB_.PC00.UA01 (ACPI path; sysfs hid=0x001e0001)
acpi device:1b: hash matches   ->  \_SB_.PC00.TCPU (ACPI path; sysfs hid=0x00040000)
```

`UA01` is a UART controller (commonly the Bluetooth HCI UART on this
platform generation); `TCPU` is a thermal/CPU power-management ACPI
object. Neither matches I021's signature (`ACPI0007:11`, a Processor
object) or I026's mechanism (EC GPE 0x6E wake-thrash from battery-status
`_Qxx` handlers) — I026's dGPU-GSP hypothesis (`incidents/I019`) is also
ruled out independently since the dGPU is disabled/blacklisted this boot
(`gpu-toggle.sh status` → `disabled`, `nvidia module: not loaded`).

**Cause:** Not yet root-caused. Working hypothesis, not yet verified: this
is the first full suspend attempt since `acpi.ec_no_wakeup=1` was
persisted via kargs (`incidents/I026`'s fix, confirmed active on this boot
via `/proc/cmdline` and `/sys/module/acpi/parameters/ec_no_wakeup` → `Y`).
I026's fix stops the machine from being woken every 30–90s by spurious EC
battery-status GPEs, which means a suspend attempt now stays in deep
s2idle for far longer per cycle than it did before the fix. It's plausible
this UART/TCPU resume hang pre-existed but was previously masked — no
single suspend cycle survived long enough on average to hit it before the
wake-thrash interrupted it first. Not independently confirmed; this boot
is also just the first data point of a different symptom, and could be an
unrelated coincidence of timing.

The heat report is the most distinctive new physical evidence: I021's
prior occurrences describe the red LED going from pulsating to steady on
lid-open, with no heat mentioned. Here both LEDs stayed in their
sleep-pattern state and the chassis got hot — more consistent with the CPU
package failing to reach a genuine low-power idle state at all (spinning
somewhere in the suspend or resume path) than with a clean freeze.
`TCPU` showing up in the `pm_trace` signature is circumstantially
consistent with that reading but does not prove it.

**Fix:** None yet — unresolved. The machine had to be hard power-cycled by
hand; the agent was not running/reachable during the hang itself (this is
inherently outside the agent's reach — a hung suspend cycle happens with
no session active to observe or intervene).

**Tried first:** N/A — this is the first occurrence of this specific
signature. Initially suspected as a straightforward I021 recurrence given
both are "log dies at suspend entry" + `pm_trace`-caught, but the LED
behavior, heat, and `pm_trace` device identities all differ, so recorded
separately rather than merged into I021.

**Reversibility:** None — read-only triage so far, no system changes made.
`acpi.ec_no_wakeup=1` remains active from I026; not yet decided whether to
keep, adjust, or roll back pending further evidence.

**Lost tooling, 2026-08-25:** A same-session first attempt at live capture
(`journalctl -f -k` streaming plus a 1s poll of the EC GPE counter,
thermal zones, and IRQ9) was started right before the lid-close that
produced this incident, writing to
`/tmp/claude-1000/.../scratchpad/i027/`. It caught nothing — `/tmp` on
this host is `tmpfs`, and the hard power-cycle needed to recover from the
hang wiped it along with everything else in RAM. The failure mode this
tooling exists to catch is exactly the one that destroys anything staged
in `/tmp`, which made that choice of location self-defeating. Confirmed on
the next boot: the target directory existed (created at 17:21) but was
empty. Lesson generalized: any instrumentation meant to survive a
hang-and-hard-reset must land somewhere that outlives `tmpfs` —
`journald` (persistent by default on this host) or a path under `/var`,
never `/tmp`.

**Captured in:** partially. `hosts/thinkpad-e14-gen5/suspend-repro-loop.sh`
now takes candidate (b) below — `log_pm_snapshot` snapshots
`/sys/firmware/acpi/interrupts/gpe_all`, IRQ9's count from
`/proc/interrupts`, and the `TCPU`/`acpitz` thermal zones (resolved by
`type`, not hardcoded zone index — sysfs zone numbering isn't guaranteed
stable across boots) alongside the existing AC/battery/C-state fields,
logged via `logger` straight to journald so it survives the crash this
incident is about. Remaining candidate next steps: (c) check whether
disabling Bluetooth before suspend (ruling out `UA01` specifically)
changes the outcome, as a cheap discriminator between the two originally
flagged devices.

**Second occurrence, 2026-08-25 (supervised lid-close soak test):** Ran
candidate (a) above — lid closed under observation with a 1s
`gpe_all`/`irq9`/`TCPU`/`acpitz` poller writing straight to journald
(`logger -t i027-soak`, bypassing the `/tmp` mistake from the first
occurrence). The machine hung again. `last -x` marked the session
`crash (00:12)` (17:35–17:46). Evidence from this run:

- Kernel log for the crashed boot stops dead at `PM: suspend entry
  (s2idle)` (17:46:29) — identical shape to the first occurrence and to
  I021, nothing logged after.
- Poller's last samples before the freeze: `gpe_all` 414→419 and `irq9`
  415→420 climbed together in the same final tick, while `TCPU`/`acpitz`
  stayed flat at 57050/57000 the whole run — no thermal ramp this time,
  unlike the heat reported in the first occurrence. The GPE/IRQ9
  co-increment right at the edge is the new signal this soak test was
  built to catch.
- `pm_trace` device match on the next boot: `tpm_crb_acpi MSFT0101:00` /
  `acpi MSFT0101:00` — **not** `UA01`/`TCPU` from the first occurrence.
  A third distinct device identity for what looks like the same failure
  shape (log dies at suspend entry, no resume). Read this as `pm_trace`'s
  single-shot device match being noisy/non-deterministic across
  occurrences rather than pinpointing one culprit device — three
  different flagged devices across two hangs weakens the UART/TCPU
  hypothesis specifically and points more toward a suspend-path timing
  issue that happens to trip whatever device's driver last touched a
  shared resource, not a defect in one driver.
- No orphaned poller process on the next boot (checked, none found) and
  no repro-loop cycle involved — this was a plain lid-close, not run
  through `suspend-repro-loop.sh`.
- `systemd-logind`'s own log for the crashed boot: `Lid closed.` /
  `Suspending...` at 17:46:27, then nothing — no `Lid opened`, no resume,
  no wake event of any kind logged before the next boot's cold start at
  17:47:59. The user reported opening the lid produced no wakeup at all
  (previously reliable). This is consistent with that: logind never
  logged receiving a lid-open signal, as opposed to receiving one and
  failing to act on it. Points at the hang being deep enough by the time
  the lid was reopened that even the lid-switch GPE wasn't being
  serviced, not a resume-path failure after a successful wake signal.

This is now two occurrences post-`ec_no_wakeup=1`, zero clean lid-close
soak results yet. Still not root-caused. The Bluetooth-disable
discriminator (c) becomes less promising given `UA01` didn't reappear
this time; next best step is probably repeating the soak test a few more
times to see whether the device identity keeps changing (supports the
noisy-match reading) or converges.

**Third occurrence, 2026-08-25 (soak test with `ec_intr=0` added):** Staged
`ec_intr=0` alongside `acpi.ec_no_wakeup=1` (I026's fix) specifically to
test against this incident, confirmed active via `/proc/cmdline` before the
lid-close. Hung again on the very first lid-close under the new karg.
`last -x` marked the session `crash (00:04)` (17:56–18:00). Evidence:

- Kernel log for the crashed boot stops dead at `PM: suspend entry
  (s2idle)` (18:00:35) — identical shape to both prior occurrences.
- `systemd-logind`: `Lid closed.` / `Suspending...` at 18:00:33, then
  nothing — no `Lid opened`, no resume logged. Same as the second
  occurrence: logind never saw a lid-open/resume signal at all.
- Poller's last samples before the gap: `gpe_all` 1141→1146 and `irq9`
  1147→1152 co-incremented in the final tick, matching the second
  occurrence's GPE/IRQ9-co-increment-at-the-edge signal. `TCPU`/`acpitz`
  stayed flat (59050/59000) the whole run — no thermal ramp, consistent
  with the second occurrence and unlike the first.
- `pm_trace` device match on the next boot: `memory memory75` — a
  **fourth** distinct device identity across three hangs (`UA01`/`TCPU`,
  then `tpm_crb_acpi MSFT0101:00`, now `memory75`). Treat this as
  confirming the noisy-match reading rather than narrowing toward one
  culprit device: `pm_trace` is not converging on a device here.
- Gap between suspend entry and next boot's first log line was short
  (~1m40s: 18:00:35 → 18:02:15), consistent with a fairly prompt forced
  power-button recovery rather than a long unattended hang.

**`ec_intr=0` is ruled out as a fix.** The hang recurred on the very first
lid-close after adding it, with the same signature (log dies at suspend
entry, no logind resume/lid-open event, GPE/IRQ9 co-increment at the
edge) as the pre-`ec_intr=0` second occurrence. This is now three
occurrences post-`acpi.ec_no_wakeup=1` and zero clean lid-close soak
results at any karg combination tried so far. Both EC-side kargs tried
to date (`ec_no_wakeup=1`, `ec_intr=0`) address wake-thrash/EC-interrupt
symptoms, not this hang — worth revisiting the reinstall-vs-BIOS-downgrade
conversation rather than continuing to iterate on EC kargs one at a time.

**Tally:** time-to-fix — not yet fixed, still open · first proposal:
n/a — agent unavailable (the hang itself happened with no session running
to observe or act on it; triage after the fact was same-session,
same-day). Second occurrence: same. Third occurrence: same — `ec_intr=0`
was the proposed fix candidate and did not hold; triage after the fact
was same-session, same-day.

**Workaround, 2026-08-25 (user call, not a fix):** User identified
`acpi.ec_no_wakeup=1` itself (I026's fix) as the point where lid-close
resume stopped working, matching this incident's own standing hypothesis
that EC wake-thrash was previously interrupting suspend before it could
reach this hang. Reverted both EC kargs to the pre-I026 baseline:
`pkexec rpm-ostree kargs --delete=acpi.ec_no_wakeup=1
--delete=ec_intr=0`, staged for next boot. Trade-off accepted explicitly:
this un-fixes I026 (EC GPE wake-thrash / battery drain returns) in
exchange for reliable lid-close resume while I027 stays unsolved. Not a
resolution of either incident — I026 is now open again pending a real fix
for I027, and I027's root cause is still unknown. Revert is a single
`rpm-ostree kargs --delete` away (see `incidents/I026` for the original
`--append`) if the trade needs reversing again.

**Fourth occurrence, 2026-08-25 (first lid-close test with the EC-karg
revert workaround active):** Rebooted with both EC kargs removed
(confirmed via `journalctl -b -1 -k | grep "Command line"` — neither
`acpi.ec_no_wakeup` nor `ec_intr` present). First lid-close under the
reverted kargs hung again. `last -x` marked the session `crash (00:03)`
(18:31–18:34). User's direct observation: machine went to standby
normally on lid-close; on lid-open the LEDs changed from pulsating
(sleep-breathing) to **steady**, but there was no other reaction — no
display, no input response. This is a different physical signature than
the first occurrence (heat, LEDs stayed pulsating) and matches I021's
original description almost exactly (LED pulsating→steady on lid-open,
no display/input). The LED transition itself isn't journald-visible (EC/
keyboard-controller state, not OS-logged), so logs neither confirm nor
contradict it directly — but they fully corroborate the "no other
reaction" half: nothing at all is logged after suspend entry, by any
service, kernel or userspace, all the way to the forced power-off.
Log evidence:

- `systemd-logind`: `Lid closed.` / `Suspending...` at 18:33:57, kernel
  log stops dead at `PM: suspend entry (s2idle)` (18:33:58) — identical
  shape to all three prior occurrences. No `Lid opened`, no resume logged
  — same as the second and third occurrences, logind never saw a
  lid-open/resume signal at all.
- `journalctl --list-boots` for this boot shows first-entry (20:31:26)
  *earlier* than last-entry (18:33:58) reversed — i.e. the crashed boot's
  recorded end timestamp is before its start timestamp, `pm_trace`'s
  bogus-RTC side effect (see I017) firing again, itself a positive signal
  that the trace caught something this cycle too.
- `pm_trace` device match on the next boot: `tty ttyS21` / `port
  serial8250:0.20` — a **fifth** distinct device identity across four
  hangs (`UA01`/`TCPU`, then `tpm_crb_acpi MSFT0101:00`, then `memory75`,
  now `ttyS21`/`serial8250:0.20`). Further confirms the noisy-match
  reading: `pm_trace` is not converging on a device across any of these
  occurrences. Notably this is the first occurrence where the flagged
  device is a literal UART (the `serial8250` driver), coincidentally
  matching this incident's title, but given the pattern of four different
  devices in four tries that's read as coincidence, not a new lead.

**The EC-karg-revert workaround does not fix this.** This was the user's
own hypothesis — that I026's `acpi.ec_no_wakeup=1` was itself masking a
pre-existing suspend hang by keeping cycles short via wake-thrash — and it
predicted this hang would stop once both EC kargs were removed. It did
not: the very first lid-close after the revert hung with the same
signature (log dies at suspend entry, no logind resume event, `pm_trace`
noise) as all three occurrences that happened *with* the kargs present.
This falsifies the standing hypothesis rather than just under-tuning it —
neither adding EC kargs (I026's fix, occurrences 1–3) nor removing them
(this occurrence) changes the outcome, which points toward the hang being
independent of the EC-wake-thrash mechanism entirely. Per the standing
guidance not to keep iterating on kargs one at a time: this is now four
occurrences, two different karg states, zero clean soaks — the
reinstall-vs-BIOS-downgrade conversation flagged after the third
occurrence is the more promising avenue, not a fifth karg to try. Karg
state currently: both EC kargs still reverted (I026 still open) since
reverting them bought nothing and there's no reason to re-add them yet.

**Tally, fourth occurrence:** time-to-fix — still open · first proposal:
n/a — agent unavailable (hang happened with no session running); this
occurrence also falsifies the user's own workaround hypothesis, not an
agent proposal — recorded here since CLAUDE.md asks the tally to count
misses generally, not just the agent's own.

**Test result, 2026-08-25 — first supervised cycle on BIOS 1.39 did not
reproduce the hang.** After downgrading firmware to test the 1.42→1.43
regression theory (see I026's "Decision, 2026-08-25" and "Test result,
2026-08-25" sections), one supervised lid-close/open cycle on 1.39
completed a full resume — `systemd-logind` logged `Operation 'suspend'
finished.` and `Lid opened.`, no dead-log signature. Not treated as a fix:
this incident's own occurrences have never been reliably reproduced
on-demand (four occurrences across unattended soak conditions, not single
supervised closes), so one clean single-cycle result on 1.39 has no more
weight than any of the clean cycles that happened between prior
occurrences under 1.43. Needs an actual unattended multi-cycle soak
(per the standing next-step note above) before 1.39 can be credited or
ruled out for this incident specifically — unlike I026, where the thrash
signature reproduced immediately and firmware was cleanly ruled out as a
fix for *that* incident on the first cycle.

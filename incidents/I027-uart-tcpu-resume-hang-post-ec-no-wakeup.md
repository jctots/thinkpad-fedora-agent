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

This is now two occurrences post-`ec_no_wakeup=1`, zero clean lid-close
soak results yet. Still not root-caused. The Bluetooth-disable
discriminator (c) becomes less promising given `UA01` didn't reappear
this time; next best step is probably repeating the soak test a few more
times to see whether the device identity keeps changing (supports the
noisy-match reading) or converges.

**Tally:** time-to-fix — not yet fixed, still open · first proposal:
n/a — agent unavailable (the hang itself happened with no session running
to observe or act on it; triage after the fact was same-session,
same-day). Second occurrence: same — hang happened with no session
observing, soak test triage was same-session, same-day.

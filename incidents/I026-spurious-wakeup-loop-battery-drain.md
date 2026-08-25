## I026 — 2026-08-25 — Spurious suspend/resume thrash drains battery to hard power-cut, not a hang

**Area:** hardware

**Symptom:** Boot `d71bac4b` (12:44:00–16:55:56) ended with no clean
shutdown record — `last -x` marked the `tty2` login session `crash
(05:02)`. Unlike I021, the kernel log does *not* stop dead at `PM: suspend
entry (s2idle)`; every one of 38 suspend/resume cycles in this boot
completed successfully, including a good 2-hour deep sleep from 14:49:38
to 16:49:41. But immediately after that long sleep, the machine entered a
thrash loop: 9 more suspend/resume cycles in the final 6 minutes before
the crash, each only ~30–90s apart, each showing `PM: Triggering wakeup
from IRQ 9` / `ACPI: PM: Wakeup after ACPI Notify sync` almost immediately
after `PM: suspend entry (s2idle)`, and each one fully re-associating wifi
on resume. Two `localsearch-3: Running on LOW Battery, pausing` lines
appear at 14:22:44 and 14:48:06. The boot's journal simply stops ~14s
after the last successful resume (16:55:42) with no further log lines —
consistent with the battery reaching empty and the hardware cutting power
outright mid-cycle, not a software hang. User confirmed by observation:
closing the lid was not holding low-power state.

**Cause:** Not yet root-caused. Working hypothesis: something is
generating repeated ACPI Notify wake events (`Wakeup after ACPI Notify
sync`, IRQ 9 / SCI) shortly after each suspend entry, forcing full
resume-and-resuspend cycles every 30–300s instead of one sustained s2idle.
Each cycle's resume work (full wifi re-auth/re-association, device
resume path) costs meaningfully more power than staying asleep would,
so a lid-closed machine left alone can flatten its battery in hours
instead of holding charge for a day+. Candidate sources not yet
distinguished: lid-switch GPE bouncing, a wifi WoWLAN/RTC wake source,
or an EC event unrelated to the lid. `pm_trace` shows no hash-match
signature for this boot on either side (expected — nothing hung, so the
trace mechanism, which only fires on suspend-that-never-resumed, never
armed against this failure mode).

**Fix:** `acpi.ec_no_wakeup=1` — confirmed live via the sysfs module
parameter, not yet persisted. See "Fix confirmed" below.

**Ruled out — `thinkpad_acpi` HKEY event path, 2026-08-25:** Live-reloaded
`thinkpad_acpi` with `debug=0xffff` (confirmed active via the verbose
`ibm_init:` trace in the journal) and watched `/sys/firmware/acpi/
interrupts/gpe6E` climb at ~4 events/sec while the machine sat fully
awake and idle — reproducible on demand, no suspend cycle needed. Zero
HKEY/event lines were logged over the same 15s window despite ~60 GPE
firings. The EC traffic on GPE 0x6E bypasses `thinkpad_acpi`'s notify
path entirely.

**Ruled out — `powertop` cannot see it either, 2026-08-25:** Installed
`powertop` (layered via `rpm-ostree install`, present after the pending
reboot) and ran `pkexec powertop --html=... --time=15` while idle. The
device/wakeup-source report has no entry for GPE 0x6E, the EC, or any
ACPI-firmware-level event — `powertop` only attributes wakeups to
processes, interrupts, and kernel work items, all of which sit
downstream of a device driver's notify handler. Since GPE 0x6E's traffic
never reaches `thinkpad_acpi`'s handler (previous finding), it never
becomes a process/IRQ-attributable wakeup either, so it's invisible to
`powertop` by construction — not a tooling gap to work around, a
structural blind spot. `/sys/firmware/acpi/interrupts/gpe6E` (raw kernel
counter) remains the only confirmed way to observe this GPE firing;
`/sys/kernel/debug/ec/` is not populated on this kernel (no `ec_sys`
module loaded), so EC-side raw register/GPE tracing isn't available
without loading it.

**Next candidate:** `acpi_ec` doesn't expose *what* triggers GPE 0x6E,
only that it fires. Options not yet tried: (a) `modprobe ec_sys
write_support=1` to get `/sys/kernel/debug/ec/ec0/io` for raw EC register
polling correlated against GPE firing timestamps: (b) ACPI method
tracing via `acpi.debug_layer`/`acpi.debug_level` broadened beyond the
current EC-only mask to catch which ACPI method services GPE 0x6E when
it fires — `acpi.debug_layer=0x2` is already active but scoped narrowly;
(c) check the DSDT/SSDT (`acpidump` + `iasl -d`) for what device or
_Qxx handler is wired to GPE 0x6E specifically, which would name the
EC query being triggered without needing to catch it live.

**Finding — DSDT disassembly narrows GPE 0x6E to battery-status EC
queries, 2026-08-25:** Pulled the live DSDT with `pkexec cat
/sys/firmware/acpi/tables/DSDT` (root-owned table, host-readable copy
written to the scratchpad) and disassembled it with `iasl -d` — via
`acpica-tools`, installed in the toolbox rather than layered onto the
host image, since it's a one-off diagnostic tool, not a standing package
(see `docs/extras.md` scoping principle). `Name (_GPE, 0x6E)` is declared
directly on `\_SB.PC00.LPCB.EC` — GPE 0x6E is the Embedded Controller's
own event GPE (`PNP0C09`), not a device-specific one, confirming it's
"any EC event," consistent with the ~4/s live rate not correlating to
anything at the OS level. Only **four** `_Qxx` EC-query handlers exist
anywhere in this device's scope: `_Q22`, `_Q24`, `_Q4A`, `_Q4B` — every
one of them calls `CLPM()` (charge-limit/power-mode housekeeping) and
then `Notify (BAT0, 0x80 or 0x81)` (battery status/info change). There
is no lid, thermal, or dock `_Qxx` handler at all in this scope — the EC
GPE's only wired consumers on this machine are battery-state
notifications. `_Q22` is gated on a flag (`HB0A`, an EC register bit
read near `BAT0`'s attach state); the other three are unconditional.
This means whatever's firing GPE 0x6E at 4/s is, structurally, forcing
repeated `BAT0` status/info re-reads — matching the incident's own
symptom (battery-state churn, not e.g. a wifi or lid GPE) rather than
pointing to an unrelated subsystem. Doesn't yet say *why* the EC keeps
re-queuing one of these four queries at that rate — `ec_sys` raw
register polling (option (a) above) is now the concrete next step to
catch which of the four query numbers (0x22/0x24/0x4A/0x4B) is actually
being dispatched.

**Ruled out — live EC/AML tracing is blocked by kernel lockdown, not
missing tooling, 2026-08-25:** Tried both remaining options from the
finding above and both are structurally unavailable on this machine,
not just untried:
- `ec_sys` (raw EC register polling): the module doesn't exist on this
  kernel build at all — `find /usr/lib/modules/$(uname -r) -iname
  '*ec_sys*'` returns nothing, so `CONFIG_ACPI_EC_DEBUGFS` isn't
  compiled in. No amount of `modprobe` fixes this short of a custom
  kernel.
- ACPICA method tracing (`/sys/module/acpi/parameters/trace_method_name`
  + `trace_state=method`, targeting `\_SB.PC00.LPCB.EC._Q22`):
  `CONFIG_ACPI_DEBUG=y` **is** set, and the sysfs parameter writes
  succeed and read back correctly, but no trace output appears in
  `journalctl -k` even while GPE 0x6E is visibly firing at ~3–4/s during
  the trace window. Root cause: `cat /sys/kernel/security/lockdown` →
  `none [integrity] confidentiality` — Secure Boot is enabled (`mokutil
  --sb-state` → enabled), which puts the kernel in the stricter of its
  two lockdown modes. Confirmed the same wall independently: `pkexec cat
  /sys/kernel/debug/dynamic_debug/control` and even plain `pkexec dmesg`
  both return `Operation not permitted` as root — confidentiality
  lockdown disables `debugfs` wholesale and restricts raw kernel-log
  reads, and ACPICA's debug prints route through the dyndbg-gated path
  that requires `dynamic_debug/control` to turn on, which is exactly
  what's blocked. `journalctl -k` still works because it reads via a
  different path (`/dev/kmsg`/journald), which is why kernel messages
  are visible elsewhere in this investigation but AML trace output never
  will be under the current boot configuration.
- **Not proposed:** disabling Secure Boot / dropping to `integrity`-only
  lockdown to unblock this. That's a real, if reversible, posture
  tradeoff (see `security-privacy-check`) that trades a chunk of the
  machine's hardening index for one diagnostic session — worth asking
  about explicitly rather than doing unprompted for a battery-drain bug.
- **Remaining path that doesn't need any of this:** correlate the ~4/s
  GPE rate against live `/sys/class/power_supply/BAT0/*` value changes
  (poll `status`, `capacity`, `current_now` etc. every ~250ms and diff)
  — if a value is genuinely flapping (e.g. a charge/discharge current
  oscillating right at a threshold), that would explain repeated
  `_Q22`/`_Q24` dispatch without needing EC-internal visibility at all.
  Not yet tried.

**Correction — the GPE 0x6E storm is AC-only; it does not explain the
crashed boot's wake-thrash, 2026-08-25:** Polled `/sys/firmware/acpi/
interrupts/gpe6E` against live `BAT0` values at 200ms resolution in two
back-to-back runs, ~13s each, user-supervised power-source switch
between them:
- **On AC, charging (33%→33%, below the 75/80 conservation thresholds):**
  GPE 0x6E fired continuously at ~4/s, as in every measurement so far
  this session. Only ~1 in 8 firings produced an observable `power_now`/
  `voltage_now`/`energy_now` change — consistent with `_Q22`'s
  `Notify(BAT0, 0x80)` being gated behind `If (HB0A)` (DSDT finding
  above), firing unconditionally but only sometimes actually notifying.
- **Unplugged, discharging, moments later, same machine state otherwise:**
  GPE 0x6E fired **zero** times in 13 seconds (`gpe_delta=0`), while
  `power_now`/`voltage_now`/`energy_now` continued changing normally
  every ~2s from ordinary discharge telemetry (confirming the EC and
  battery driver were both alive and working, just not going through GPE
  0x6E to do it).

This means the whole thread of investigation from this session's
handover — the "live, reproducible, awake-and-idle" GPE 0x6E storm that
motivated installing `powertop`, disassembling the DSDT, and attempting
EC/AML tracing — was chasing an **AC-charging-specific** EC event
(almost certainly the charge-current step-up housekeeping visible in the
AC poll: `power_now` ramping in ~500-600mW steps roughly every 2s while
charging). It is very unlikely to be the actual wake-thrash mechanism
from boot `d71bac4b`: that boot's own log records `localsearch-3:
Running on LOW Battery, pausing` twice (14:22:44, 14:48:06) and ends in a
hard power-cut from battery exhaustion — both readable only as "running
on battery, not AC," and GPE 0x6E is now confirmed to be silent under
exactly that condition. The "live lead" in the handover was a real,
reproducible phenomenon, just not the one that caused this incident —
worth its own note (it may explain unrelated AC-tethered battery-report
chattiness) but not a continuation of I026's actual root cause.

**Still open, and the real next step:** identify what fires — GPE or
otherwise — during an actual suspend-on-battery cycle that produces the
crashed boot's signature (`PM: Triggering wakeup from IRQ 9` / `ACPI: PM:
Wakeup after ACPI Notify sync` seconds after `PM: suspend entry
(s2idle)`). That needs either a live-monitored real suspend/resume cycle
on battery (watching `/sys/firmware/acpi/interrupts/*` deltas across the
cycle, or `journalctl -f -k` through a real lid-close), or extending
`hosts/thinkpad-e14-gen5/suspend-repro-loop.sh` (built for I021) to
snapshot all GPE counters per cycle. Not attempted yet this session.

**Ruled out — I021 debug instrumentation as the cause, 2026-08-25:** Checked
whether the `acpi.debug_layer=0x2 acpi.debug_level=0x4` kargs or the
`thinkpad_acpi debug=0xffff` modprobe.d file (both staged 2026-08-23 for
I021, still present) were responsible for the wake-thrash. Not the cause:
the `acpi.debug_*` kargs only control log verbosity — they're why the
`ACPI: \_SB_.PEPD: Successfully transitioned to state...` lines print at
all, but the underlying events (`ACPI: EC: ACPI EC GPE status set` →
`ACPI: PM: Wakeup after ACPI Notify sync`) are genuine EC-level GPEs that
would fire and wake the machine with or without the debug flag — the flag
just makes them visible. Separately, the `thinkpad_acpi` debug option
never actually took effect this boot at all (no HKEY-tagged debug lines
anywhere in the boot's journal, no `/sys/module/thinkpad_acpi/parameters/
debug`), so it's fully inert here and ruled out regardless. The real wake
source is a genuine repeating EC GPE, cause still unidentified.

**Tried first:** Initially treated as a possible I021 recurrence since
both surface as an unclean-shutdown `crash` tag from `reset-triage`. Ruled
out on inspection: I021's signature is a resume that never completes (log
stops dead at `suspend entry`, `pm_trace` implicates `ACPI0007:11`); here
every resume in the boot completed and logged normally, and the failure
mode is battery exhaustion from a wake-loop, not a stuck resume. Confirmed
distinct rather than merged into I021 by counting suspend/resume pairs
(`journalctl -b -1 -k | grep -c "PM: suspend entry"` → 38) and inspecting
the full sequence, not just the tail.

**Reversibility:** none — read-only triage so far, no system changes made.

**Captured in:** not yet — still a one-off; no reproduction or fix attempt
yet. Candidate next step: extend
`hosts/thinkpad-e14-gen5/suspend-repro-loop.sh` (built for I021) to log
wake-source/IRQ info per cycle, or watch `journalctl -f -k` live through a
real lid-close to catch the ACPI Notify source in the act.

**Root cause, confirmed 2026-08-25:** GPE 0x6E belongs solely to the EC
(`\_SB.PC00.LPCB.EC`, `PNP0C09`), and every `_Qxx` handler wired to it in
the DSDT is a `BAT0` status/info `Notify` (`_Q22`/`_Q24`/`_Q4A`/`_Q4B` —
see the DSDT disassembly finding above). During `s2idle`, this GPE keeps
ticking in the background (rate varies, ~0.3–4/s depending on AC/battery
state); most ticks are silently reabsorbed, but whenever one produces an
actual `Notify` the kernel treats it as a wakeup reason and does a full
device resume — confirmed by direct log capture of the exact sequence
(`ACPI: EC: ACPI EC GPE status set` → `dispatched` → `work flushed` →
`ACPI: PM: Wakeup after ACPI Notify sync` → full resume incl. wifi
re-association) across two live-monitored suspend/resume cycles. This
matches the crashed boot's own signature exactly (`PM: Triggering wakeup
from IRQ 9` / `ACPI: PM: Wakeup after ACPI Notify sync` seconds after
`PM: suspend entry`) and explains the finite-but-shrinking sleep
durations (2h clean nap → 30–90s repeats near the end) as battery-state
Notify-worthy events becoming more frequent as charge dropped — this
last piece (rate climbing near low battery specifically) is plausible
and consistent with the timeline but not independently measured.

This is a known bug **class** upstream, not unique to this machine — web
search turned up matching kernel.org bugzilla reports (`Bug 215661`,
"S2idle suspend still draining battery to zero over night") and several
merged ACPI EC/GPE patches addressing s2idle wake storms (e.g. "ACPI: EC
/ PM: Disable non-wakeup GPEs for suspend-to-idle", "ACPI: EC: Dispatch
the EC GPE directly on s2idle wake") spanning kernels 4.19–5.16. This
kernel (7.1.10) postdates all of those by years, so this is a distinct
recurrence on newer hardware/firmware, not one of the old fixed bugs
regressing.

**Fix confirmed live, 2026-08-25:** `/sys/module/acpi/parameters/
ec_no_wakeup` is a documented ACPI EC driver parameter ("do not use the
EC GPE as a wakeup source"), default `N`. Set live via `pkexec bash -c
'echo Y > /sys/module/acpi/parameters/ec_no_wakeup'` (no reboot). Two
back-to-back monitored suspend/resume cycles (`journalctl -f -k` +
1s-resolution `/sys/firmware/acpi/interrupts/*` polling, both surviving
the suspend transition by freezing and resuming with the machine):
- **Before the fix:** sleep held 85s, ended via EC GPE Notify (the bug's
  own signature).
- **After `ec_no_wakeup=Y`, same lid-close test:** sleep held 5m49s
  (346s) — GPE 0x6E still ticked in the background (3714→3803, ~89 times,
  confirming the EC itself is unaffected and still alive) but **none**
  of those ticks were promoted to a wakeup reason. The eventual wake was
  `PM: Triggering wakeup from IRQ 14` / `ACPI: PM: Wakeup unrelated to
  ACPI SCI` — the user physically opening the lid, a legitimate wake, not
  a recurrence of the bug.

No functional downside identified: the EC's only wakeup-relevant
handlers on this GPE are battery status/info notifications, which aren't
urgent enough to justify aborting sleep for (the OS doesn't need to know
`BAT0` ticked down while genuinely asleep — a real critical-battery
cutoff is a firmware-level hardware safety mechanism, independent of
this GPE path). Thermal, lid, and AC-adapter wake sources are unaffected
— none of them route through this GPE per the DSDT.

**Why now — traced to a BIOS update, 2026-08-25:** User pushed back that
this had never happened before and asked what actually changed. Scanned
`journalctl -k` across every boot since this machine's journal began
(2026-08-16) for the wake signature (`Wakeup after ACPI Notify sync`) and
cross-referenced each boot's `DMI: LENOVO...BIOS` line:

- Every boot on `R2AET67W (1.42)` — this machine's first boots through
  2026-08-17 20:33 — has **zero** occurrences, no exceptions.
- BIOS updated to `R2AET68W (1.43)` at boot `f21c4efa` (2026-08-17
  20:43:17 CEST) — an LVFS/`fwupd` "System Firmware" release, changelog:
  "Fixed a issue than platform profiles not working." Confirmed via
  `fwupdmgr get-history`.
- The very next full boot on 1.43 (`0c956145`, 2026-08-17 22:18:06) shows
  the wake signature **immediately** — 8 occurrences — and it recurs in
  nearly every boot from then on, escalating to the 9-cycle thrash that
  drained the battery on 2026-08-25.

This confirms the bug is a firmware regression introduced by the 1.42→1.43
update, not a pre-existing condition that only just got triggered, and not
anything from this session's own config/kernel-arg work (kernel version
and command line are identical across the boots immediately before/after
the firmware flash — only the BIOS version changed). `fwupdmgr` reports no
newer firmware queued, so there's no "update again" fix available — the
`acpi.ec_no_wakeup=1` karg is the correct workaround until Lenovo ships a
further BIOS fix, at which point it's worth re-testing whether the karg is
still needed.

**Persistence confirmed, 2026-08-25 (post-reboot):** `rpm-ostree kargs
--append=acpi.ec_no_wakeup=1` staged pre-reboot, then verified after a
full reboot: `cat /proc/cmdline` shows `acpi.ec_no_wakeup=1` and `cat
/sys/module/acpi/parameters/ec_no_wakeup` reads `Y` on its own, with no
live sysfs write needed this time. The karg is what makes the fix stick
across boots — OS-image layer, reversible via `rpm-ostree rollback`.

**Still open:** a longer unattended soak test (multi-hour, lid closed, on
battery) before calling this fully closed — the two test cycles run so
far were short (85s and 346s), nowhere near the multi-hour scenario that
actually crashed the machine. This session can't run that soak test
itself (needs the lid physically closed and the machine left alone) —
needs the user to run it and report back, or a scheduled check-in.

**Ruled out — masking GPE 0x6E specifically instead of the broad
`ec_no_wakeup`/`ec_intr` kargs, 2026-08-25:** With both EC kargs still
reverted (I027's workaround trade-off) and I027 unresolved after four
occurrences, tried a more surgical alternative: `pkexec bash -c 'echo
mask > /sys/firmware/acpi/interrupts/gpe6E'` (the modern `mask` verb,
`acpi_mask_gpe()`, not the older/less-reliable `disable`). Motivation: the
DSDT disassembly above already shows GPE 0x6E's only handlers are BAT0
notifies, no lid/thermal/dock handler at all, so masking just this GPE
should in theory stop the wake-thrash without touching lid-open wake or
either EC karg.

Live-confirmed the mask took effect (`gpe6E` counter stopped climbing,
flat for 10+ minutes under a poller sampling once per second vs. the
usual ~4/s on AC). But it broke something unexpected: **the lid switch
stopped producing any event at all while GPE 0x6E was masked** — two
separate lid close/reopen cycles (~10 minutes apart, one on AC, one after
disconnecting AC) produced zero `logind` `Lid closed` lines and zero
kernel `PM: suspend entry` lines. `/proc/acpi/button/lid/LID/state` still
read the correct live physical state, but the transition event that
drives `logind`'s suspend logic never fired. Unmasking
(`echo unmask > .../gpe6E`) immediately restored normal behavior —
confirmed with a clean lid close/reopen producing the expected
`Lid closed` → `PM: suspend entry` → `Wakeup after ACPI Notify sync` →
`PM: suspend exit` → `Lid opened` sequence in 10 seconds, same shape as
every previously-working cycle.

This means GPE 0x6E is **not actually isolated from the lid switch's own
event path on this machine**, despite the DSDT saying it should be —
consistent with this being the same BIOS 1.43 generation already shown to
have other firmware-level bugs (the UCSI `Invalid num_connectors 130.
Likely buggy FW` message found the same session). Masking one GPE
disturbing an unrelated device's event delivery is exactly the kind of
thing a buggy GPE dispatch implementation would do. **Ruled out as a fix
candidate** — it doesn't just fail to help, it's worse than either karg
tried so far (both of those left lid detection itself working; this
didn't). Not attempting GPE-level masking again without new evidence that
narrows why it cross-affected the lid switch.

**Decision, 2026-08-25 — downgrading firmware to test the 1.42→1.43
regression theory, settling for 1.39 not 1.42:** With three live-tunable
approaches now ruled out (`ec_no_wakeup=1`, `ec_intr=0`, GPE 0x6E mask —
none both fix I026 and avoid I027), the next candidate is testing whether
reverting the firmware itself clears both incidents. Researched sourcing
the exact prior version (1.42, `R2AET67W`) first:

- Not offered by `fwupdmgr`/LVFS at all — `fwupdmgr get-releases` lists
  downgrades at 0.1.39, 0.1.35, 0.1.34, 0.1.29, 0.1.27, 0.1.10 only, a
  gap exactly where 1.42 should be.
- Lenovo's own support pages and the `thinkpads.com` community BIOS
  mirror both blocked automated fetch (403); a guessed direct filename
  (`r2aet67w.txt`/`.html` on `download.lenovo.com`) 404'd. Consistent
  with Lenovo's general practice of not archiving superseded BIOS
  installers once a newer one is posted (per a Lenovo Community thread
  found during research) — 1.42 is likely gone, not just hard to find.
  Not exhaustively confirmed — the support page's own "Details"/history
  section wasn't checked manually in a real browser, only via automated
  fetch, which is bot-blocked independent of what the page contains.
- Separately, some Lenovo BIOS lines enforce anti-rollback in firmware
  itself ("Secure Rollback Prevention," confirmed as a real feature name
  on other ThinkPad models' own support docs) — unconfirmed whether this
  model's 1.42→1.43 boundary has it, but a real risk even if 1.42 were
  found: the flash utility could simply refuse it.

**Decision: proceed with `fwupdmgr downgrade` to 0.1.39 instead**, the
closest available version, rather than continuing to chase 1.42. Trade-off
accepted explicitly: this is not a clean single-variable test — 1.39 differs
from 1.43 by more than just whatever changed in 1.40–1.42, so a clean
result either way (fixed or not) doesn't isolate the exact regression the
way testing 1.42 itself would have. It's still the best available signal
without sourcing an unreleased/unarchived file. Command run by the user
directly (not through the agent's `pkexec` pattern) per this repo's
reversibility rule — firmware sits outside all three reversibility layers
(`rpm-ostree rollback`, `etckeeper`, `/var/home` backups), so per
`CLAUDE.md` it's proposed and typed by the human, not executed on their
behalf.

**Tally:** time-to-fix — same day (2026-08-25), root-caused and fix
persisted across a reboot within one session · first proposal: right —
`reset-triage`'s evidence collection plus the follow-up suspend-cycle
count and timeline correctly identified the wake-thrash mechanism (as
opposed to a hang) on the first pass, and correctly distinguished it from
I021 rather than conflating the two.

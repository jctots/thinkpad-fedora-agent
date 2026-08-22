## I020 — 2026-08-22 — s2idle crash misdiagnosed as upstream NVIDIA GSP bug; real cause is a local SELinux AVC denial

**Area:** hardware

**Symptom:** `incidents/I019` concluded the 260-attempt suspend-retry battery
drain (`NVRM: PM suspend notifier failed: 0x62`, `nv_suspend_devices`
WARNING, `krcWatchdog: GPU is probably locked!`) was an open,
unfixable-locally upstream bug
([NVIDIA/open-gpu-kernel-modules#1142](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1142)),
and disabled the dGPU by default (`gpu-toggle.sh disable`) as the only
mitigation. User asked, before accepting that conclusion further: "are you
sure it's applicable to our dGPU?"

**Cause:** It wasn't a straight match. The upstream issue's reporter has an
RTX 4050 Max-Q (Ada Lovelace, AD107M) with **no iGPU fallback**, KDE
Plasma/X11, driver 595.71.05 — materially different from this machine's
MX550 (Ampere GA107) with Intel iGPU hybrid graphics, GNOME, driver
610.57.04. But the issue thread's own follow-up comments revealed the *real*
root cause on the reporter's hardware: **not a driver bug** — SELinux's
`systemd_sleep_t` domain denies the write the driver performs into
`/var/tmp` (via `NVreg_TemporaryFilePath=/var/tmp`) at suspend entry, which
cascades into the identical `0x62` GSP-unload failure signature.

Checked our own crash boot (`journalctl -b -8`, the boot that hit I019's
260-retry loop) for the same signature and found it immediately, at the
exact moment of the first suspend attempt (16:57:32):
```
AVC avc: denied { write open } for pid=11886 comm="systemd-sleep"
  path=/var/tmp/#348713 (deleted) dev="dm-0" ino=348713
  scontext=system_u:system_r:systemd_sleep_t:s0
  tcontext=system_u:object_r:tmp_t:s0 tclass=file permissive=0
```
Same domain, same target context, same file class, same moment as the
upstream comment's own confirmed fix. This is not a coincidence: I018's
mitigation (`NVreg_TemporaryFilePath=/var/tmp`, meant to fix an unrelated
earlier OOM crash) is exactly the config that routes the driver into this
SELinux-blocked path. I019 was right to revert I018 as harm reduction, but
wrong to conclude the underlying bug was upstream and unfixable — it's a
local Fedora SELinux policy gap.

**Fix (applied, unverified pending reboot + real suspend test):**
1. `hosts/thinkpad-e14-gen5/gpu-toggle.sh enable` — un-blacklist `nvidia`
   (commit `5886900`, etckeeper).
2. Re-added `/etc/modprobe.d/nvidia-suspend-fix.conf`
   (`options nvidia NVreg_TemporaryFilePath=/var/tmp`) — reinstates I018's
   config, needed to exercise the exact path the SELinux fix targets
   (commit `0be1176`, etckeeper).
3. Generated a local SELinux module from the actual denial captured above
   (not copied from the issue thread) via
   `audit2allow -M systemdsleepnvidia`, installed with
   `semodule -i systemdsleepnvidia.pp`. Module contents:
   ```
   module systemdsleepnvidia 1.0;
   require {
       type tmp_t;
       type systemd_sleep_t;
       class file { open write };
   }
   allow systemd_sleep_t tmp_t:file { open write };
   ```
   Only the file-write rule — our own log did not show the `perfmon`
   capability denial the upstream reporter also hit, possibly because
   SELinux stopped logging after the first blocking denial. Re-check for a
   `capability2`/`perfmon` denial after the next real suspend attempt; if it
   appears, regenerate and reinstall the module to include it.
4. Reboot required (module load + modprobe option), then test: manual
   `systemctl suspend` (short, then longer), then a real lid-close cycle,
   checking `journalctl -p err` and AVC log stay clean each time.

**Tried first (this session, before the fix):** Initially accepted I019's
"open upstream bug, no fix" framing at face value when asked about tracking
driver updates for it. Only re-examined after the user explicitly asked
whether the linked issue actually applied to this GPU/config — fetching the
issue's raw comments (not just a summarized fetch, which speculated
inaccurately about "Ada Lovelace-specific") surfaced the SELinux root cause
and the follow-up comment thread. Lesson: a plausible-looking upstream
issue match on error text alone isn't confirmation — check the reporter's
actual hardware/config against ours, and read to the end of the thread for
later corrections, before treating a "known issue, no fix" conclusion as
settled.

**Reversibility:** `/etc` — both modprobe changes are `etckeeper`-committed
(`5886900`, `0be1176`); SELinux module removable with
`semodule -r systemdsleepnvidia`. dGPU blacklist toggle is the existing
`gpu-toggle.sh` mechanism (`disable` to revert). No OS-image layering
involved.

**Verification update (2026-08-22, post-reboot):** Reboot landed the fix
(`pkexec git -C /etc log` shows `0be1176` applied; `pkexec semodule -l`
confirms `systemdsleepnvidia` loaded; `/proc/driver/nvidia/params` shows
`UseKernelSuspendNotifiers: 1`, so `nvidia-suspend.service`'s
"Skipped due to exec-condition" on every suspend is expected/inert — that
unit is never the active path on this system regardless of the fix, since
its `ExecCondition` only fires when the param is `0`; the real suspend/resume
work happens via the driver's in-kernel PM ops).

First suspend/resume cycle that boot (22:54:07-22:54:08, ~213s asleep)
completed clean: no `AVC denied ... systemd_sleep_t`, no
`NVRM: PM suspend notifier failed`, no `krcWatchdog` — the exact signature
this incident targeted did not recur. That's the fix working, once.

But a **second** suspend ~1 minute later (22:55:11) hung and never resumed —
`last -x` marked the login session `crash (00:28)`, `pm_trace`'s bogus-RTC
end-timestamp confirms the kernel caught it. `journalctl -b -1` stops dead
at `PM: suspend entry (s2idle)` with nothing after: no NVIDIA driver
messages at all this time (unlike the first cycle, the GPU wasn't even
mid-transition when it died), no AVC denial. `pm_trace`'s device signature
(read from the *next* boot's dmesg, boot `ab03f301`) is `ACPI0007:11` — an
ACPI Processor object, not GPU-related. This does not match I019/I020's
NVRM/AVC signature and looks like a distinct hang, possibly specific to a
second suspend shortly after a resume (lid closed again ~1 min after
waking). Full triage evidence not yet gathered beyond the above — treat as
a new open lead, not yet its own incident.

**Captured in:** not yet — the SELinux fix has one clean verification cycle
but the immediately-following crash on a second suspend attempt means this
isn't yet a confirmed "fixed." Before updating
`hosts/thinkpad-e14-gen5/quirks.sh` / `README.md` / memory /
`incidents/I019` to point here as settled: (a) get more clean suspend/resume
cycles without the SELinux/NVRM signature recurring, and (b) separately
investigate the `ACPI0007:11` second-suspend hang — open its own incident if
it reproduces.

**Tally:** time-to-fix ~40m so far (diagnosis correction + fix applied) +
~20m verification/triage (2026-08-22) · first proposal: wrong — accepted
I019's upstream-bug conclusion without re-verifying applicability until the
user pushed back. Verification is partial: the targeted bug's signature
didn't recur once, but a different crash appeared in the same boot before a
second cycle could confirm it.

## I019 — 2026-08-20 — I018's NVIDIA suspend mitigation unmasked an upstream GSP-unload bug that turned a rare crash into a guaranteed suspend-retry loop

**Area:** hardware

**Symptom:** User closed the lid expecting normal suspend; came back hours
later to find the battery essentially empty (~1%), now charging on AC. The
crashed boot's journal (`journalctl -b -1`) shows `systemd-logind:
Suspending...` **260 times** in that boot, roughly every ~30 seconds,
starting 16:57:30 and continuing until the log ends abruptly at 19:10:21
(the unclean-shutdown boundary from `incidents/I018`'s `reset-triage` fix).
Every single attempt failed identically:

```
PM: suspend entry (s2idle)
WARNING: nvidia/nv.c:4574 at nv_suspend_devices+0x2ec/0x4a0 [nvidia]
WARNING: nvidia/nv.c:4872 at nv_suspend_devices+0x308/0x4a0 [nvidia]
NVRM: PM suspend notifier failed: 0x62
systemd-sleep: Failed to put system to sleep. System resumed again: Operation not permitted
systemd-suspend.service: Main process exited, code=exited, status=1/FAILURE
NVRM: krcWatchdog_IMPL: RC watchdog: GPU is probably locked!  Notify Timeout Seconds: 7
```

`systemd-logind` immediately retries suspend after each failure, so the
machine never actually slept — lid closed, screen off, but CPU/GPU spinning
through a failed-suspend cycle for 2h13m straight until the battery ran out
and the machine crashed.

**Cause:** This boot (crashed boot, `journalctl -b -1`) is the first boot to
run with the `incidents/I018` mitigation
(`/etc/modprobe.d/nvidia-suspend-fix.conf`,
`NVreg_TemporaryFilePath=/var/tmp`, committed 15:30) actually loaded —
confirmed via `/proc/driver/nvidia/params` showing `TemporaryFilePath:
"/var/tmp"` is active. That fix targeted a different, rarer failure
signature (`NV_ERR_NO_MEMORY` at `nv_suspend_devices`, from I018's original
crash). This boot never hits that OOM path at all — it fails later, at a
different pair of assertions in the same function (`nv.c:4574`,
`nv.c:4872`), with the driver logging `NVRM: PM suspend notifier failed:
0x62`.

That `0x62` signature matches a confirmed, currently-open upstream bug:
[NVIDIA/open-gpu-kernel-modules#1142](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1142)
— "GSP unload failed at suspend ... leaving the GPU in an invalid state,"
reported on driver 595.71.05 / kernel 7.0.4 (RTX 4050 Mobile); this host
runs driver 610.57.04 / kernel 7.1.8 (MX550), same signature, same
`nv_suspend_devices` WARNING pattern, same watchdog spam. It's a real
driver-level GSP-firmware defect, not something introduced by our
modprobe config — `NVreg_TemporaryFilePath` only governs where VRAM gets
backed up, and has no code path anywhere near GSP firmware unload.

The actual causal chain: **I018's fix didn't introduce this bug, it
unmasked it.** Before the fix, `nv_suspend_devices` was failing early, at
the VRAM-backup OOM step — so the downstream GSP-unload step was never
reached. After the fix, the OOM step succeeds, the suspend sequence
proceeds further, and hits the pre-existing, still-broken GSP-unload path
every single time. Net effect on this machine: I018 traded "rare fatal
crash, ~1 in 5 suspend cycles per I018's own isolation notes" for "100% of
suspend attempts fail, and `systemd-logind` retries forever instead of
completing or giving up" — 260 failed attempts, 2h13m, full battery drain,
lid closed the whole time. The second failure mode is worse in practice:
no crash to notice, no dialog, just silent battery drain.

**Fix applied:** Reverted the I018 mitigation —
`pkexec rm /etc/modprobe.d/nvidia-suspend-fix.conf && pkexec etckeeper commit "revert I018 mitigation -- caused suspend-retry battery drain, see I019"`
(commit `5349f22`). This is harm reduction, not a real fix: it restores the
rarer intermittent-OOM-crash behavior from before I018, which is safer
than a guaranteed multi-hour drain but still leaves s2idle suspend broken
on this driver+kernel combination — the actual bug lives upstream in
NVIDIA's GSP-unload code and has no known fix yet (the GitHub issue's own
workaround is masking suspend targets entirely, i.e. giving up on
low-power states).

**Next step — built and armed same session:** `hosts/thinkpad-e14-gen5/gpu-toggle.sh`
(`status`/`disable`/`enable`) blacklists/unblacklists the `nvidia` module
via `/etc/modprobe.d/nvidia-disabled.conf`, so the dGPU can be off by
default (removes `nv_suspend_devices` from the suspend path entirely,
cleanly isolating whether the driver is the whole story) and switched on
only for a gaming session. Documented in
`hosts/thinkpad-e14-gen5/README.md` § GPU on/off toggle. Disabled now
(commit `67b0ab8`), combined with the reboot already pending from the
I019 revert above — next boot will run on the Intel iGPU only. If s2idle
suspend is then stable across several lid-close cycles, that confirms the
isolation; re-enable before gaming with
`hosts/thinkpad-e14-gen5/gpu-toggle.sh enable`.

**Tried first:** Assumed (before the web search) that
`NVreg_TemporaryFilePath` itself was the proximate cause of the new
failure signature, based on it being the only local change between the
working boot and the failing one. The upstream issue search corrected
this — same error code, same function, same watchdog pattern, reported by
someone with no `TemporaryFilePath` setting at all. Worth the correction:
temporal correlation ("this changed right before it broke") pointed at the
wrong mechanism; the real story is the fix succeeding at its narrow job
and thereby reaching a second, unrelated, already-broken code path.

**Reversibility:** `/etc` — `etckeeper`, commit `5349f22`. To restore the
I018 mitigation (not recommended — reintroduces the rarer OOM crash):
recreate `/etc/modprobe.d/nvidia-suspend-fix.conf` with
`options nvidia NVreg_TemporaryFilePath=/var/tmp`, `pkexec etckeeper commit`, reboot.

**Captured in:** not yet — `hosts/thinkpad-e14-gen5/quirks.sh` once the
module-blacklist toggle is designed and built. Cross-reference:
`incidents/I018`, project memory `project_s2idle_resume_hang_investigation`.

**Tally:** time-to-fix ~20m (harm-reduction revert; root cause remains
open upstream) · first proposal: wrong — first attributed the new failure
to the local config change rather than the driver's GSP-unload code,
corrected after a web search surfaced the matching upstream issue.

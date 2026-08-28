## I031 — 2026-08-28 — Verified `nouveau` mode returns dGPU to low-power state after game exit, established as baseline

**Area:** hardware

**Symptom:** Not a failure — a verification. After the `gpu-toggle.sh` 3-mode
rebuild (see prior session, `52d5a3a`, mode set to `nouveau`) and a live
Portal 2 session under Steam Flatpak with `DRI_PRIME=1` offload, needed to
confirm the MX550 actually drops back to a low-power state once the game and
Steam are fully closed, rather than staying pinned active (the failure mode
that made `nvidia`/proprietary mode unsafe to leave on by default per I019).

**Cause:** N/A — confirms existing behavior. `nouveau`'s PCI runtime PM
(`power/control=auto`, `autosuspend_delay_ms=5000`) was already in effect
with no manual configuration needed.

**Fix:** N/A — nothing to fix. Verification steps, for reproducing this
check after any future driver change:

```sh
# 1. confirm no process still holds the dGPU render/card node open
fuser -v /dev/dri/renderD129 /dev/dri/card0

# 2. confirm PCI runtime PM actually suspended the device
cat /sys/devices/pci0000:00/0000:00:06.2/0000:02:00.0/power/runtime_status
# → suspended

# 3. confirm system-wide draw dropped back to idle baseline
cat /sys/class/power_supply/BAT0/power_now   # mW
```

Observed this session: while Portal 2 was running, draw was 20–25W
(`battery-drain-samples.log`, `mode=nouveau`); within the 5s autosuspend
window after quitting Steam entirely, `runtime_status` read `suspended` and
draw fell to **10.3W**.

**Baseline established — this is now the reference point for every future
driver/mode change.** `nouveau` mode: dGPU renders real workloads on demand
(confirmed via `glxinfo` reporting `NVIDIA GeForce MX550 (NVK TU117)` /
zink+NVK) *and* returns to a genuinely suspended, low-draw state the moment
nothing holds it open — no reboot, no manual toggle, no retry-loop drain.
This is the number to diff against whenever a new driver (proprietary kmod,
a future nouveau/NVK update, any signed-kmod rebuild) is tried: if idle draw
after workload exit is measurably higher than this ~10W floor, that driver
regressed idle power and is a worse default than `nouveau`. It's also the
default candidate mode for testing whether any currently-open GPU-adjacent
issue (I019's s2idle resume hang chief among them) is specific to the
proprietary driver's GSP-unload path rather than the hardware/kernel more
broadly — re-run those investigations under `nouveau` mode before assuming
they're unfixable.

**Caveat — no GPU usage/temp/power telemetry available under `nouveau` mode
for this card.** Followed up same session: neither the `Resource_Monitor@Ory0n`
GNOME extension nor `nvtop` shows the MX550 while in `nouveau` mode. Root
cause confirmed via sysfs, not a permissions or detection bug: `nouveau`
exposes no `gpu_busy_percent` file and no `hwmon` directory at all under
`/sys/class/drm/card0/device/` for this card (`test -e ... ; MISSING`) —
`amdgpu` and `i915` both implement that generic DRM sysfs interface, `nouveau`
never has, and Turing-and-newer chips (TU117 here) additionally need the
proprietary signed GSP firmware blob to do dynamic reclocking/telemetry at
all, which the open driver deliberately doesn't ship. Resource Monitor's GPU
support is sysfs-based (AMD/Intel, vendor-ID filtered) plus `nvidia-smi` for
NVIDIA — no nouveau branch exists in either project's GPU detection, and
there's no underlying data for either to read even if one did. `nvtop -s`
confirmed this directly: it correctly detects and reports Intel Iris Xe
figures but returns nothing for the MX550.

The baseline in this incident is still valid and still the number to diff
against, but "no live usage%/temp/power-draw monitoring in this mode" is
itself a property of the baseline, not a gap in how it was measured — the
only observables under `nouveau` are: `fuser /dev/dri/renderD129` (who's
holding the device open), `power/runtime_status` (active vs. suspended), and
system-wide `/sys/class/power_supply/BAT0/power_now` as a proxy for GPU load.
Web search (2026-08-28) turned up no GNOME extension that covers nouveau:
`Astra Monitor` (extensions.gnome.org #6682) requires `nvidia-smi` for NVIDIA
GPUs same as Resource Monitor, explicitly proprietary-driver-only; `NVIDIA
GPU Stats Tool` and `gnome-nvidia-extension` are both `nvidia-smi`-based too;
`GPU Profile Selector` only toggles PRIME profile, doesn't monitor. Checked
whether the newer DRM `fdinfo` per-process interface
(`/proc/<pid>/fdinfo/<fd>`, `drm-engine-*` fields — confirmed present and
populated for `i915` clients this session) is a viable nouveau-compatible
path any extension could read instead of `gpu_busy_percent`: plausible in
principle since it's a generic DRM standard, but unverified — no nouveau
client was running at check time (idle/suspended) to confirm whether nouveau
populates `drm-engine-render` the way `i915` does. No extension found today
implements an `fdinfo`-based backend at all. Follow-up if this baseline is
revisited: re-run the fdinfo check during an active nouveau game session,
and if it works, a local patch to `Resource_Monitor@Ory0n` adding a
`fdinfo`-driven nouveau path is the most promising concrete option — more so
than waiting on upstream, since none of the extensions found even attempt a
non-`nvidia-smi` NVIDIA path.

**Tried first:** N/A — first check (fuser + runtime_status + power_now) was
sufficient and confirmed the expected result directly.

**Reversibility:** N/A — read-only verification, no system state changed
this session.

**Captured in:** not yet — still a one-off. Verification steps above are
copy-pasteable but not yet scripted; a candidate follow-up is teaching
`hosts/thinkpad-e14-gen5/health-checks/dgpu-power.sh` to also alert if draw
stays above this ~10W idle floor for N minutes with no known GPU client,
regardless of mode (currently it only evaluates in `off` mode per the prior
session's handover).

**Tally:** time-to-fix ~10m · first proposal: right

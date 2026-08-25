## I024 — 2026-08-25 — Pinned kmod-nvidia/kmod-xpadneo blocked `rpm-ostree upgrade`, dropped both to unblock

**Area:** rpm-ostree

**Symptom:** `rpm-ostree upgrade` failed to depsolve against the new kernel
`7.1.10-200.fc44.x86_64`. `kmod-nvidia-7.1.8-200.fc44.x86_64` and
`kmod-xpadneo-7.1.8-200.fc44.x86_64` were `LocalPackages`, pinned to the
exact old kernel build (`7.1.8-200.fc44.x86_64`), so the new kernel had no
matching kmod available and the whole transaction failed. The chained
`rpm-ostree upgrade && systemctl reboot` meant the reboot never fired —
machine was untouched.

**Cause:** These kmods are built out-of-tree and version-locked to a
specific kernel build (I004, I006). Every kernel bump requires a matching
kmod rebuild before `rpm-ostree upgrade` can depsolve. The normal rebuild
path (`scripts/build-signed-kmod.sh`, toolbox-based) is itself broken per
I008 — toolbox can't read the host's MOK private key
(`/run/host/etc/pki/akmods/private` unreadable even as toolbox "root").
I008 was not solved this session (real Secure Boot signing key material,
out of scope for a quick unblock).

**Fix:** With the user's explicit choice, dropped NVIDIA/xpadneo support
rather than fix I008 first or defer the OS upgrade:
```
rpm-ostree uninstall kmod-nvidia-7.1.8-200.fc44.x86_64 \
  kmod-xpadneo-7.1.8-200.fc44.x86_64 xorg-x11-drv-nvidia-cuda
rpm-ostree upgrade
systemctl reboot
```
Staged and depsolved cleanly against the old base first, then the upgrade
layered on top. Booted `44.20260825.0` confirmed via `rpm-ostree status` —
`kmod-nvidia`/`kmod-xpadneo`/`xorg-x11-drv-nvidia-cuda` gone from
`LayeredPackages`/`LocalPackages`. dGPU was already disabled by default
(I019) before this, so no functional regression to iGPU-only operation
today. Xbox controller (Bluetooth, `kmod-xpadneo`) loses driver support
until re-added — re-adding requires solving I008 first.
`etckeeper` confirmed it committed the resulting `/etc` diff (NVIDIA
systemd unit symlinks, `OpenCL/vendors/nvidia.icd`, `kernel/cmdline`,
`sysconfig/kernel` removed) — `scripts/etc-drift.sh fix`, commit `422408f`.

**Tried first:** Considered fixing I008 first so the kmod rebuild could
happen and NVIDIA/xpadneo could stay pinned to the new kernel. Ruled out
mid-session as out of scope for an upgrade that was otherwise ready to
ship — I008 involves real Secure Boot signing key material and deserves
its own focused session, not a rushed fix under upgrade pressure.

**Reversibility:** `rpm-ostree rollback` covers the OS image change
(kmod removal + kernel upgrade) if needed. `etckeeper` diff covers the
`/etc` changes. No `/var/home` exposure — this was entirely OS-layer.

**Captured in:** not yet — still a one-off. If this recurs on future
kernel bumps before I008 is fixed, worth scripting the
uninstall-then-upgrade sequence.

**Tally:** time-to-fix ~20m · first proposal: right

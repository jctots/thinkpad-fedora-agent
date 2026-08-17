# thinkpad-e14-gen5 — host profile

Everything here is about *this device*, not about the software stack around it.
The test for whether something belongs in this directory rather than in
`scripts/`: would it be identical on a different laptop? If yes, it is base
layer. Most apparent hardware quirks are — the Bitwarden → polkit → `fprintd`
chain is the same everywhere; only reader support and driver choice are not.

Contents, as they get written:

- `packages.txt` — additive, on top of the base list
- `quirks.sh` — fingerprint reader *driver and configuration*, GPU, power
  management, firmware quirks, function keys. Not enrolment — that needs a
  finger, and stays on the manual list in `docs/bootstrap.md` § Part 4

## Pinned: DMI detection strings

Read 2026-08-16 off this machine:

```
sys_vendor:   LENOVO
product_name: 21JKCTO1WW
```

`install.sh`'s `detect_host_profile` matches `LENOVO|21JK*` — prefix match on
the MTM code (`21JK` = E14 Gen 5), not the full CTO suffix, so other
configurations of the same model still resolve to this profile.

## Fingerprint reader: Goodix, supported via third-party driver

```
lsusb: Bus 003 Device 002: ID 27c6:550a Shenzhen Goodix Technology Co.,Ltd. FingerPrint
```

Confirmed 2026-08-16: this is the Goodix variant, not Synaptics. `27c6:550a`
is **not supported by upstream libfprint** — Goodix's driver is proprietary
and ships as a "Touch-Only Device" (TOD) shim, `libfprint-tod-goodix`, not
present in Fedora's official repos. The only known working package is a
third-party COPR: `antiderivative/libfprint-tod-goodix-0.0.9`, which upstream
reports as tested specifically on a ThinkPad E14 Gen5 — matches this profile.

This is a **third-party, prebuilt binary driver from an unaudited COPR**, not
a source build — a different trust category from anything else layered so
far in this repo (`rpm-ostree install <pkg>` from Fedora's own repos). Adding
the COPR itself is an `/etc` change (a `.repo` file under `/etc/yum.repos.d/`)
and therefore ASK-tier, covered by `etckeeper`, but the *contents* of what it
installs are opaque. Enrolment quirks/config for this driver belong in
`quirks.sh` per this directory's layout; do not add the COPR without saying
so out loud first, separately from the rest of the fingerprint setup.

## GPU: Intel Iris Xe (iGPU) + NVIDIA MX550 (dGPU), Optimus/hybrid

```
00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] — driver i915/xe
02:00.0 3D controller: NVIDIA Corporation TU117M [GeForce MX550] — driver nvidia (pinned kmod-nvidia, see below)
```

Confirmed 2026-08-17: the dGPU worked out of the box on the in-tree open
`nouveau` driver — clean boot probe, PRIME offload via `DRI_PRIME=1
%command%` correctly routed a Steam game's render node to it (verified via
`/proc/<pid>/fdinfo`, `drm-driver: nouveau`), and it runtime-suspends when
idle. `nouveau` was working, not broken.

Switched to RPM Fusion's proprietary NVIDIA driver anyway, deliberately, for
one specific reason: **nouveau has no NVML equivalent, so no GPU monitoring
tool (`nvtop`, etc.) can ever see it** — confirmed via nvtop's own docs
(nvtop reads NVIDIA GPUs exclusively through `libnvidia-ml.so`, which only
ships with the proprietary driver). Wanted live utilization visibility while
testing GPU offload, not just perf. This is a real trade: proprietary driver
+ Secure Boot MOK enrolment + a kernel-module build maintenance burden, in
exchange for `nvidia-smi`/`nvtop` visibility and CUDA.

**Not running RPM Fusion's `akmod-nvidia`** — tried first, and it doesn't
work on this host: rpm-ostree's `%post` layering sandbox cannot see
`/etc/pki/akmods/private` at build time, so the module `akmodsbuild`
produces there is never signed, even with a correctly enrolled MOK key that
predates the build by 40+ minutes. Full diagnosis, including the
toolbox-container reproduction that proved it's a sandbox-visibility bug and
not a race: [I004](../../incidents/I004-nvidia-akmod-unsigned-in-rpm-ostree-post-sandbox.md).

**What's actually running:** a `kmod-nvidia` package built and signed
*outside* the sandbox — in a `toolbox` container, using the same MOK key,
matched to the exact kernel version — then layered as an rpm-ostree
`LocalPackage`. See `quirks.sh` for the full rebuild procedure and the
package list. **Accepted trade-off:** this does not auto-rebuild on kernel
updates the way `akmod-nvidia` would. The next `rpm-ostree upgrade` that
bumps the kernel will leave this driver stale until the toolbox build is
redone for the new kernel — `quirks.sh` detects and reports this mismatch
explicitly rather than silently falling back to nouveau. To abandon the
proprietary driver entirely instead of redoing the build:
`sudo rpm-ostree uninstall kmod-nvidia-<version> xorg-x11-drv-nvidia-cuda`
— the machine ran fine on nouveau and this returns to it cleanly.

`nvtop` is layered here (not in `thinkpad-fedora-extras`) specifically
because it functions as this quirk's end-to-end verification tool — it can
only see the dGPU once the signed module is actually loaded, so `quirks.sh`
checking for it doubles as confirmation the whole chain works, not just
that packages are present.

**Steam / GPU offload:** the `__NV_PRIME_RENDER_OFFLOAD` /
`__GLX_VENDOR_LIBRARY_NAME=nvidia` pair is proprietary-driver-only — it was
a no-op under nouveau (confirmed the hard way: it silently rendered on the
iGPU instead). `DRI_PRIME=1` alone remains correct if this ever reverts to
nouveau. As of 2026-08-17 this is applied **Steam-wide**, not per-game, via
a Flatpak env override on the Steam client itself (every game is a child
process of Steam and inherits it):

```
flatpak override --user --env=__NV_PRIME_RENDER_OFFLOAD=1 --env=__GLX_VENDOR_LIBRARY_NAME=nvidia com.valvesoftware.Steam
```

Reversible: `flatpak override --user --reset com.valvesoftware.Steam`.
Trade-off accepted: the Steam client UI itself now also renders on the dGPU
whenever open, not just during play, which keeps the MX550 from
power-suspending while Steam is merely open in the background — considered
acceptable since the machine stays plugged in during gaming sessions.
Steam package choice and rationale live in `thinkpad-fedora-extras`
`PACKAGES.md` (an app choice, not a host quirk) — this override is
documented there too since it's Steam-specific config, not GPU-driver setup.

Setup steps, MOK enrolment sequence, and current status: `quirks.sh`.

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

**Status as of 2026-08-25:** `kmod-nvidia` was dropped when a pinned build
blocked an OS upgrade ([I024](../../incidents/I024-pinned-kmod-blocked-upgrade-dropped-nvidia-xpadneo.md)),
and re-added the same day once [I008](../../incidents/I008-build-signed-kmod-toolbox-key-access.md)
(toolbox couldn't read the host's MOK key) was actually fixed —
`scripts/stage-mok-key.sh` now stages the key on the host first, outside
the toolbox's rootless permission boundary, and `scripts/build-signed-kmod.sh`
reads from there. A freshly built, signed `kmod-nvidia` is **staged via
`rpm-ostree install`, not yet booted into** — `rpm-ostree status` will show
it as the pending deployment until the next reboot. Until that reboot, the
machine is still running on `nouveau` as described in I024. `xorg-x11-drv-nvidia-cuda`
was not part of the I008 fix and remains uninstalled — re-add separately
if CUDA is needed again.

```
00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] — driver i915/xe
02:00.0 3D controller: NVIDIA Corporation TU117M [GeForce MX550] — driver nouveau until reboot, then pinned kmod-nvidia (I008)
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

**Env vars alone are not sufficient for 32-bit games**
([I005](../../incidents/I005-steam-flatpak-32bit-nvidia-prime-offload-missing-runtime.md)):
GLVND needs an actual NVIDIA GLX vendor library available inside the Steam
Flatpak's sandbox, driver-version-matched. Flatpak normally auto-installs
this on detecting the host driver, but that hook doesn't fire for this
host's manually pinned `kmod-nvidia` build (see I004) — Flatpak's detection
doesn't recognize it. Without the extension, `__GLX_VENDOR_LIBRARY_NAME=nvidia`
is silently ignored and GLVND falls back to Mesa; there is no error, only an
idle dGPU in `nvidia-smi`/`nvtop`. Required, version-matched to the running
driver (`nvidia-smi --query-gpu=driver_version --format=csv,noheader`):

```
sudo flatpak install --system flathub \
  org.freedesktop.Platform.GL.nvidia-<version> \
  org.freedesktop.Platform.GL32.nvidia-<version>
```

64-bit-only games need just the first; any 32-bit game (older Source engine
titles like Portal 2) needs the `GL32` variant too. Must be reinstalled to
match whenever the pinned driver version changes. `quirks.sh` checks both
are present for the currently running driver version.

Setup steps, MOK enrolment sequence, and current status: `quirks.sh`.

### GPU on/off toggle (I019): s2idle isolation, gaming-only dGPU

s2idle suspend fails **100% of the time** on driver 610.57.04, confirmed as
an open upstream bug — GSP firmware fails to unload during suspend
(`NVRM: PM suspend notifier failed: 0x62`), matching
[NVIDIA/open-gpu-kernel-modules#1142](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1142)
exactly. It is independent of local config — I018's suspend-OOM mitigation
(`NVreg_TemporaryFilePath`) was tried and reverted (see I019); it only
masked an earlier failure step and let the suspend sequence reach this
GSP-unload bug instead of avoiding it.

Since the `nvidia` module normally loads at every boot regardless of
whether the dGPU is actually rendering anything (PRIME offload is opt-in
per-app), the module being loaded at all is what exposes the suspend path
to this bug — even a session that never touches the dGPU still hits it.
`hosts/thinkpad-e14-gen5/gpu-toggle.sh` blacklists/unblacklists the module
so it can be switched off by default and only switched on for a gaming
session:

```
hosts/thinkpad-e14-gen5/gpu-toggle.sh status    # report only
hosts/thinkpad-e14-gen5/gpu-toggle.sh disable   # blacklist — for s2idle testing / daily use
hosts/thinkpad-e14-gen5/gpu-toggle.sh enable    # unblacklist — before gaming
```

Both directions print the exact `pkexec`/`etckeeper`/reboot commands rather
than running them — same report-only pattern as `quirks.sh`. A reboot is
required either direction; the module can't be cleanly hot-unloaded while
GNOME Shell/Xorg/Wayland holds it open. Reversible via `/etc`
(`etckeeper` commit each direction).

While disabled: `nvidia-smi`/`nvtop` will report no device, Steam's
`__NV_PRIME_RENDER_OFFLOAD`/`__GLX_VENDOR_LIBRARY_NAME=nvidia` overrides
become no-ops (same fallback-to-Mesa behavior documented above for
nouveau), and the machine runs on the Intel iGPU only. `quirks.sh` does
**not** currently flag the dGPU as "missing" while it's deliberately
disabled — the toggle's `status` output is the source of truth for current
intent, `quirks.sh` for whether the driver stack itself is intact.

## Xbox Wireless Controller (Bluetooth): two stacked bugs, both now fixed

**Status as of 2026-08-25:** dropped alongside `kmod-nvidia`
([I024](../../incidents/I024-pinned-kmod-blocked-upgrade-dropped-nvidia-xpadneo.md)),
re-built and re-staged the same day once
[I008](../../incidents/I008-build-signed-kmod-toolbox-key-access.md) was
fixed — same `stage-mok-key.sh`/`build-signed-kmod.sh` run that rebuilt
NVIDIA, same underlying MOK key, no controller-specific step needed beyond
the `<kmod-name> <akmod-package>` args. **Staged via `rpm-ostree install`,
not yet booted into** — the controller has no driver support until the
next reboot.

```
Bus=0005 Vendor=045e Product=028e — Xbox Wireless Controller (BT)
```

Never worked out of the box: `hid-generic` rejected the descriptor with
`unbalanced collection at end of report description` / `probe failed -22`.
Full diagnosis: [I006](../../incidents/I006-xpadneo-unsigned-akmod-and-truncated-descriptor-firmware.md).

**Same signing bug as the NVIDIA quirk above, same fix.** RPM Fusion's
`akmod-xpadneo` builds unsigned in rpm-ostree's `%post` sandbox for the exact
reason I004 documents. Fixed identically: `kmod-xpadneo` built and signed in
a toolbox container, matched to the exact kernel version, layered as a
`LocalPackage`. Same accepted trade-off as `kmod-nvidia`: no auto-rebuild on
kernel updates — this host now carries **two** kernel-version-pinned
`kmod-*` packages needing manual toolbox rebuild on every kernel bump.
`quirks.sh` detects a stale pin for both.

One new finding from I006, worth calling out separately since it likely also
silently applied to the earlier NVIDIA build: `akmods` compiles as the
**`akmods` system user** (via `runuser`), not as root or the invoking user —
`.rpmmacros` has to live in `/var/cache/akmods/`, owned `akmods:akmods`, not
in `~/.rpmmacros` or `/root/.rpmmacros`.

**Signing was necessary but not sufficient.** Even after `kmod-xpadneo`
loaded correctly signed, the controller still failed the identical
"unbalanced collection" probe — decoding the raw HID descriptor
(`debug_descriptor=1` module param) showed the controller's *own Bluetooth
firmware* ships a truncated descriptor (unclosed collections, cut off
mid-item). Confirmed against upstream `xpadneo` issues as a firmware-only
bug with no Linux-side fix — SteamOS has no workaround for this either, only
a recent warning added to Steam Deck for exactly this condition. Fixed by
updating the controller's firmware via the **Xbox Accessories app** on a
Windows machine (USB connection for the flash), then re-pairing over
Bluetooth. No further change needed here — `kmod-xpadneo` bound immediately
once the descriptor was valid.

Setup steps, MOK enrolment reuse, and current status: `quirks.sh`.

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
reads from there. The rebuilt, signed `kmod-nvidia` is **booted and
verified** — it's a `LocalPackage` on the active deployment, and `modinfo
nvidia` reports `sig_id: PKCS#7` with a signer CN matching
`mokutil --list-enrolled`. `xorg-x11-drv-nvidia-cuda` was not part of the
I008 fix and remains uninstalled — re-add separately if CUDA is needed
again.

The module is present and trusted but **not loaded**: the dGPU stays
disabled by default per [I019](../../incidents/I019-nvidia-suspend-fix-caused-retry-loop-battery-drain.md)
(see the toggle section below), so `lsmod | grep nvidia` is empty and
`nvidia-smi` reports no device until `gpu-toggle.sh enable`. That's the
intended resting state, not a broken driver.

```
00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [Iris Xe Graphics] — driver i915/xe
02:00.0 3D controller: NVIDIA Corporation TU117M [GeForce MX550] — pinned kmod-nvidia (I008), unloaded by default (I019)
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
`LocalPackage`. See `quirks.sh` for the package list.

**Rebuilding after a kernel bump** is now scripted end to end (I008), and
is the same two commands for either kmod:

```
scripts/stage-mok-key.sh                          # pkexec, host-side key read
scripts/build-signed-kmod.sh nvidia  akmod-nvidia
scripts/build-signed-kmod.sh xpadneo akmod-xpadneo
scripts/stage-mok-key.sh --cleanup                # remove the staged key
```

**Accepted trade-off:** this still does not auto-rebuild on kernel updates
the way `akmod-nvidia` would — the rebuild is scripted, not automatic. An
`rpm-ostree upgrade` that bumps the kernel will **fail to depsolve** while
the old pins are installed ([I024](../../incidents/I024-pinned-kmod-blocked-upgrade-dropped-nvidia-xpadneo.md)),
so the order is: uninstall the pins, upgrade, reboot, then rebuild against
the new kernel and re-install. `quirks.sh` detects and reports a stale pin
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

### GPU driver select (I019): off / nvidia / nouveau, gaming-only dGPU

s2idle suspend fails **100% of the time** on the proprietary driver
(610.57.04), confirmed as an open upstream bug — GSP firmware fails to
unload during suspend (`NVRM: PM suspend notifier failed: 0x62`), matching
[NVIDIA/open-gpu-kernel-modules#1142](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1142)
exactly. It is independent of local config — I018's suspend-OOM mitigation
(`NVreg_TemporaryFilePath`) was tried and reverted (see I019); it only
masked an earlier failure step and let the suspend sequence reach this
GSP-unload bug instead of avoiding it.

Since the `nvidia` module normally loads at every boot regardless of
whether the dGPU is actually rendering anything (PRIME offload is opt-in
per-app), the module being loaded at all is what exposes the suspend path
to this bug — even a session that never touches the dGPU still hits it.
Blacklisting `nvidia` alone does not idle the dGPU, though: the kernel's
in-tree `nouveau` driver auto-binds to the same PCI device the moment
`nvidia` is out of the way (confirmed live on this host — `lspci -k` showed
`Kernel driver in use: nouveau` while `nvidia` sat blacklisted and unloaded).
So `hosts/thinkpad-e14-gen5/gpu-toggle.sh` is a three-way driver select, not
a toggle:

```
hosts/thinkpad-e14-gen5/gpu-toggle.sh status    # report only
hosts/thinkpad-e14-gen5/gpu-toggle.sh off       # blacklist both — iGPU only, s2idle testing / daily use
hosts/thinkpad-e14-gen5/gpu-toggle.sh nvidia    # proprietary — CUDA + nvidia-smi/nvtop, carries the I019 bug
hosts/thinkpad-e14-gen5/gpu-toggle.sh nouveau   # in-tree open driver — no CUDA/NVML, expected not to carry I019
```

`enable`/`disable` remain as aliases for `nvidia`/`nouveau` respectively —
the two modes those names used to cover, before `off` needed splitting out
as its own mode — since I019 through I021 reference them by those names.

Each mode command also rewrites Steam's Flatpak env overrides Steam-wide
(every game is a child process of Steam and inherits them), so a game
launched right after a mode switch offloads correctly with no per-game
launch-option edit: `nvidia` sets `__NV_PRIME_RENDER_OFFLOAD=1
__GLX_VENDOR_LIBRARY_NAME=nvidia`; `nouveau` sets `DRI_PRIME=1` instead,
since the `__NV_*` vars are proprietary-only and silently no-op under
nouveau — confirmed the hard way in I005; `off` clears all of them since
everything renders on the iGPU regardless. This step is skipped with a note
(not a failure) if the Steam Flatpak isn't installed on the machine.

A reboot is required for any mode change to fully take effect; the module
currently in use can't be cleanly hot-swapped while GNOME
Shell/Xorg/Wayland holds it open. Reversible via `/etc` (`etckeeper`
commits each change).

While in `off` or `nouveau` mode: `nvidia-smi`/`nvtop` will report no
device — nouveau has no NVML equivalent, so GPU monitoring is only
available in `nvidia` mode. `quirks.sh` does **not** currently flag the
dGPU as "missing" while it's deliberately off — the toggle's `status`
output is the source of truth for current intent, `quirks.sh` for whether
the driver stack itself is intact.

`health-checks/dgpu-power.sh` watches for the dGPU drawing power while
`off` mode says it shouldn't be — it reads the same PCI runtime-PM status
(`/sys/bus/pci/devices/0000:02:00.0/power/runtime_status`) that first
exposed nouveau's silent auto-bind, and alerts if it isn't `suspended`
after two consecutive 15-minute checks. Deliberately out of scope in
`nvidia`/`nouveau` mode, where "active" is indistinguishable from a
legitimate gaming session without per-process attribution.

`health-checks/battery-drain.sh` is mode-aware for the same reason (I019
follow-up: comparing nvidia-vs-nouveau battery drain). Every discharging
sample is tagged with the current mode and appended to
`~/.local/state/system-health-check/battery-drain-samples.log` regardless
of whether it alerts, so switching modes and letting this run for a while
under each produces a directly comparable dataset. The 35W alert threshold
only applies in `off` mode, where it was calibrated — `nvidia`/`nouveau`
modes log but don't alert, since higher draw there is expected, not a
fault.

**`nouveau` mode's suspend safety is expected, not verified** — nouveau
doesn't use GSP firmware the same way the proprietary driver does, so it's
a reasonable expectation it avoids I019's specific bug, but nobody has run
an actual suspend/resume cycle with nouveau bound and active on this
BIOS/kernel combo. Treat it as untested until a supervised suspend test
confirms it.

## Xbox Wireless Controller (Bluetooth): two stacked bugs, both now fixed

**Status as of 2026-08-25:** dropped alongside `kmod-nvidia`
([I024](../../incidents/I024-pinned-kmod-blocked-upgrade-dropped-nvidia-xpadneo.md)),
re-built and re-staged the same day once
[I008](../../incidents/I008-build-signed-kmod-toolbox-key-access.md) was
fixed — same `stage-mok-key.sh`/`build-signed-kmod.sh` run that rebuilt
NVIDIA, same underlying MOK key, no controller-specific step needed beyond
the `<kmod-name> <akmod-package>` args. **Booted and confirmed working** —
the controller pairs over Bluetooth and input works, tested with the
hardware in hand.

Note the module is named **`hid-xpadneo`**, not `xpadneo` — `modinfo
xpadneo` reports "not found" while the module is perfectly fine at
`/usr/lib/modules/<kernel>/extra/xpadneo/hid-xpadneo.ko.xz`. It's also not
resident in `lsmod` unless the controller is actually connected, since it
autoloads on connect.

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

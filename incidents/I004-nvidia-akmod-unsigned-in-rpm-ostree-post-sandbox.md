<!--
Template: incidents/I{nnn}-{slug}.md
Use: one file per incident. I### increments from incidents/index.md; slug is kebab-case.
After writing: add a row to incidents/index.md (newest first).
-->

## I004 — 2026-08-17 — NVIDIA MX550: akmod-nvidia builds unsigned kernel module inside rpm-ostree's `%post` sandbox

**Area:** rpm-ostree

**Symptom:** After enrolling a MOK signing key and blacklisting `nouveau`
via kernel args, `akmod-nvidia` layered and rebuilt cleanly on every kernel
bump, but the resulting `nvidia.ko` was never signed. Secure Boot refused to
load it; `nvidia-smi` failed and `lsmod` showed no `nvidia` module.
`journalctl -k` showed an "unsigned module" rejection at load time even
though the MOK key had existed on disk for 40+ minutes before the relevant
build ran.

**Cause:** rpm-ostree's client-side `%post` sandbox — where `akmodsbuild`
actually compiles and signs the module during a layered install — cannot
see `/etc/pki/akmods/private` at build time, even though the same path is
fully populated and correctly permissioned (`root:akmods 640`/`750`) on the
live host and the build genuinely runs as root inside the sandbox (verified
via `akmodsbuild`'s own root-guard, which is a `-w /var` writability check,
not a UID check, so it doesn't fire there). Proved by building the identical
SRPM, for the identical kernel, with the identical key, in a `toolbox`
container instead of the rpm-ostree sandbox — that build succeeded and
produced a module with a valid `PKCS#7` signature matching the enrolled MOK.
Same key, same kernel, same SRPM; only the build environment (rpm-ostree
sandbox vs. toolbox) differed. This looks like a genuine rpm-ostree/akmods
sandbox-visibility bug, not a one-off race.

**Fix:** Built a **pinned** `kmod-nvidia` package for the exact running
kernel, in a toolbox container where the signing key is visible, then
swapped it in for `akmod-nvidia`:

```
# in toolbox (fedora-toolbox-44), with rpmfusion-{free,nonfree}-release,
# pciutils, xorg-x11-drv-nvidia-kmodsrc (version-pinned), kernel-devel
# matching `uname -r`, akmods, gcc, make, elfutils-libelf-devel installed,
# and the MOK key/cert copied to a user-owned dir with ~/.rpmmacros
# pointing _kmodtool_signmodules_privkey/_pubkey at the copies:
akmods --kernels $(uname -r) --kmod nvidia
# verify: modinfo shows "~Module signature appended~", sig_id PKCS#7,
# signer matching the enrolled MOK

# on host:
sudo rpm-ostree uninstall akmod-nvidia
sudo rpm-ostree install /path/to/kmod-nvidia-<kernel>-<driver_ver>.rpm
sudo systemctl reboot
```

**Trade-off accepted (deliberate, discussed with user):** `kmod-nvidia` is
pinned to the exact kernel build it was compiled for. `akmod-nvidia`
auto-rebuilds for whatever kernel is current, but is broken by this sandbox
bug on this box. **On the next kernel update, the driver will silently stop
matching and nouveau (or nothing) will load** until this toolbox
build+install is redone for the new kernel version. This is accepted, not a
bug to chase — `hosts/thinkpad-e14-gen5/quirks.sh` should check for and warn
about the mismatch.

**Tried first:** (1) MOK enrollment alone — necessary but not sufficient,
module still built unsigned. (2) Kernel-arg nouveau blacklist — necessary
and confirmed persistent, but didn't address signing. (3) Reinstalling
`akmod-nvidia` outright, on the theory the key simply hadn't existed yet at
a prior build — ruled out by `journalctl` timestamps showing the key
predated the relevant build by 40+ minutes; module was still unsigned after
reinstall. Each of these looked plausible in turn and consumed a full
reboot cycle before being ruled out — the real cause (sandbox can't see
`/etc/pki/akmods/private`) only surfaced once the identical build was
reproduced *outside* the sandbox for direct comparison.

**Reversibility:** `rpm-ostree` rollback covers the deployment swap
(`akmod-nvidia` deployment still present and selectable via
`rpm-ostree status` / bootloader). The MOK private key was briefly copied
out of its protected location to a user-owned toolbox/home directory for
the build — a real if narrow exposure window; both copies were deleted
immediately after the build was confirmed signed and the driver confirmed
working.

**Captured in:** `hosts/thinkpad-e14-gen5/quirks.sh` (NVIDIA driver checks
added this session) and `hosts/thinkpad-e14-gen5/README.md` GPU section —
still needs the kernel-version-mismatch warning added per the trade-off
above.

**Tally:** time-to-fix ~3h across 5 reboots · first proposal: wrong

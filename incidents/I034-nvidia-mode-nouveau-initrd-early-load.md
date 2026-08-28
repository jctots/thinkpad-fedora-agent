## I034 — 2026-08-28 — `gpu-toggle.sh nvidia` failed to bind the GPU to nvidia despite correct modprobe.d config

**Area:** rpm-ostree

**Symptom:** After `gpu-toggle.sh nvidia` + reboot, nvidia's probe failed with
"GPU already bound to nouveau" even though `/etc/modprobe.d/dgpu-driver-select.conf`
correctly contained `install nouveau /bin/false`, was etckeeper-committed, and
`gpu-toggle.sh status` reported the config as correct. Separately, re-running
`gpu-toggle.sh` on a mode it had already selected sometimes aborted partway
through with a non-zero exit from `etckeeper commit`.

**Cause:** Two independent bugs.

1. `/etc/modprobe.d` is not consulted early enough. `nouveau.ko.xz` is baked
   into the initramfs for early KMS (plymouth splash), and dracut's own copy
   of `/etc/modprobe.d` is snapshotted at initramfs-build time — a rule
   written after that build is invisible to the initrd's own module loading,
   so nouveau still bound the GPU before the real root's modprobe.d rule
   could ever apply.
2. `etckeeper commit` exits non-zero when there is nothing to commit (e.g.
   re-running the same mode with no config change). Under `set -euo pipefail`
   that aborted the whole `write_conf` pkexec chain, even though the
   preceding `install`/`rm` had already succeeded.

**Fix:** For bug 1: use dracut's own cmdline override,
`rd.driver.blacklist=nouveau`, which the initrd reads directly regardless of
what `/etc/modprobe.d` says. Set via `rpm-ostree kargs --append=...` /
`--delete=...` so it's baked into the boot entry itself — no initramfs
rebuild needed. Applied for `off` and `nvidia` modes (both need nouveau kept
out of the initrd); removed for `nouveau` mode. `gpu-toggle.sh status` now
also reports whether the karg matches the selected mode.

For bug 2: wrap the etckeeper commit as `{ etckeeper commit '...' || true; }`
so a "nothing to commit" exit doesn't abort the chain — the install/rm having
succeeded is what actually matters.

**Tried first:** Assumed the modprobe.d blacklist alone was sufficient, since
that's how `off` mode had worked previously — did not initially account for
nouveau being loaded straight out of the initrd before the real root's
modprobe.d is ever read. Confirmed live: the conf file was in place and
etckeeper-committed, yet nouveau still bound the GPU at boot.

**Reversibility:** `rpm-ostree kargs` changes are covered by `rpm-ostree
rollback` / `rpm-ostree kargs --delete=...`, same as any other kernel
argument change — fully reversible. The `/etc/modprobe.d` piece is covered by
`etckeeper` git diff.

**Captured in:** `hosts/thinkpad-e14-gen5/gpu-toggle.sh`

**Tally:** time-to-fix ~2h (spread over two sessions) · first proposal:
wrong — an earlier handover predicted a plain reboot would clear the nvidia
bind failure; it did not, the initrd/karg root cause had to be found first.
Once root-caused, the karg fix worked correctly on the first attempt and was
confirmed end-to-end (CS2 running on the dGPU, no `imem: OOM` crash
signature since).

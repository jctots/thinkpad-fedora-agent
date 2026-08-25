<!--
Template: incidents/I{nnn}-{slug}.md
Use: one file per incident. I### increments from incidents/index.md; slug is kebab-case.
After writing: add a row to incidents/index.md (newest first).
-->

## I008 — 2026-08-17 — `build-signed-kmod.sh` can't read the MOK private key from inside a toolbox

**Area:** toolbox

**Symptom:** First live run of `scripts/build-signed-kmod.sh nvidia
xorg-x11-drv-nvidia-kmodsrc` (written last session from I004/I006's
documented steps, never previously executed) failed at the key-copy step:

```
install: cannot stat '/etc/pki/akmods/private/private_key.priv': No such file or directory
```

**Cause:** Two compounding problems, neither anticipated when the script was
transcribed:

1. `/etc/pki/akmods` inside the toolbox is the **container's own** tree,
   created empty by the toolbox's local `akmods` package install — not the
   host's. The host's real key is reachable from inside the toolbox only via
   `/run/host/etc/pki/akmods/{private,certs}`.
2. Even at that path, reading fails with `Permission denied` under `sudo`
   run inside the toolbox. `toolbox` containers are rootless: "root" inside
   the container maps to a subuid range on the host, not real UID 0, so it
   cannot read the host's root:958-owned, mode-750 key directory even
   through the `/run/host` bind mount.

Separately, and making the fix non-trivial to just patch: the host's own
`akmods` package is **not currently installed** (`id akmods` → no such
user), and `/etc/pki/akmods/private` on the host is owned by an orphaned
GID 958 with no matching `/etc/group` entry. The repo has no recorded
mechanism for how the key material was moved from host to toolbox during
the original I004/I006 manual builds — it wasn't scripted, and git history
has no trace of the transfer step, only its result (a working signed
`kmod-nvidia`/`kmod-xpadneo`).

**Fix (resolved 2026-08-25):** Split the privileged read out of the
toolbox entirely — the only process that can actually read
`/etc/pki/akmods/private` is a real host process, so it has to happen on
the host, before the toolbox build starts.

New `scripts/stage-mok-key.sh`, run on the bare host: `pkexec` copies
`/etc/pki/akmods/{private/private_key.priv,certs/public_key.der}` into
`~/kmod-builds/.keystage`, owned by the invoking user, mode 0600/0644.
Every toolbox container already bind-mounts `$HOME` by default, so the
staged copy is visible inside without any extra wiring.
`build-signed-kmod.sh` now reads the key from that staged path instead of
`/etc/pki/akmods` directly — a plain user-owned file, no `sudo` needed for
that specific read. `stage-mok-key.sh --cleanup` removes the staged copy
once all builds for the session are done.

Fixing just the key-read surfaced four more bugs in
`build-signed-kmod.sh` that had never actually been exercised end to end
(see the caveat this file itself carried: "do not treat the script as
working until this is resolved and re-tested"):

1. `kernel-devel` alone doesn't create the
   `/usr/lib/modules/<kernel>/build` symlink `akmods` needs — that step
   was done by hand in the original I004/I006 builds and never scripted.
   Now created explicitly if missing.
2. The script's own usage docs named the wrong package
   (`xorg-x11-drv-nvidia-kmodsrc`, which never registers with `akmods` at
   all — only a real `akmod-*` package does). Corrected to `akmod-nvidia`.
3. `akmods` itself needs to run as root (missing `sudo`), and
   `/var/cache/akmods` (mode 0750, owned `akmods:akmods`) isn't readable
   by the invoking user at all — every `find`/copy of the build output now
   goes through `sudo`.
4. The signature-verification grep looked for the literal string
   `signer.*akmods`, which never appears — the signer field is the MOK's
   own CN (e.g. `fedora_1786956117_e9a2fc71`). Fixed to check for the
   presence of `sig_id`/`signer` lines instead, and confirmed the CN
   matches the enrolled key via `mokutil --list-enrolled`.

Verified end to end for both `nvidia` and `xpadneo` with the identical,
unmodified script (only the `<kmod-name> <akmod-package>` args differ) —
both produced signed RPMs, `sig_id: PKCS#7`, signer CN matching the
enrolled MOK. Staged on the host via `rpm-ostree install` (both RPMs at
once); not yet rebooted into.

**Tried first:** Confirmed the failure was real (not a stale toolbox) by
checking `toolbox list` (container present, last used ~24h earlier),
re-running dependency install (succeeded, already-installed — consistent
with the toolbox being the same one used for I004/I006), then tracing the
path mismatch via `find` on both the toolbox's own `/etc/pki/akmods` and
`/run/host/etc/pki/akmods`, and confirming the permission model with `id`/
`stat`/`getent` on both host and toolbox. Considered two fixes (`sudo podman
cp` from a real host shell to stage the key inside the running container;
or asking where the key currently lives if not at the assumed host path)
but stopped short of applying either — this involves real Secure Boot
signing key material and there's no documented source of truth for the
original transfer, so it needs a deliberate decision, not an improvised
workaround mid-session.

**Reversibility:** The 2026-08-17 investigation touched nothing (read-only).
The 2026-08-25 fix: `rpm-ostree install` of the two signed kmods is a
staged deployment, reversible by `rpm-ostree rollback` or simply not
rebooting into it. The staged MOK key copy under `~/kmod-builds/.keystage`
is `/var/home` — covered by backup — and deleted via `--cleanup` once done
regardless. No `/etc` changes; the host's actual key material was only
ever read, never modified or moved.

**Captured in:** `scripts/build-signed-kmod.sh` (fixed) and
`scripts/stage-mok-key.sh` (new). Verified working end to end for both
`kmod-nvidia` and `kmod-xpadneo`.

**Tally:** time-to-fix (2026-08-25 resolution session) ~40m · first
proposal: ✗ wrong — the staging-split design was right, but four more
bugs in the untested tail of the script (module-dir symlink, wrong
package name, missing `sudo` on `akmods`/`find`, wrong signature grep)
surfaced only by actually running it, one at a time. Original 2026-08-17
diagnosis session: time-to-fix unresolved (stopped deliberately, not
agent unavailability) · first proposal: ✗ wrong.

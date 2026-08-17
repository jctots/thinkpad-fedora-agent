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

**Fix:** Not applied yet — see below.

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

**Reversibility:** None of this touched the system — read-only
investigation inside a disposable toolbox container plus `stat`/`find` on
the host. No `/etc` or rpm-ostree state changed.

**Captured in:** `scripts/build-signed-kmod.sh` — the bug is IN the script,
not yet fixed there. Do not treat the script as working until this is
resolved and re-tested end to end.

**Tally:** time-to-fix — unresolved (stopped deliberately mid-session, not
agent unavailability) · first proposal: ✗ wrong — the script assumed a
`sudo`-inside-toolbox read of `/etc/pki/akmods/private` would work,
untested until this run.

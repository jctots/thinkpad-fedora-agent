# Flatpak VSCode + rootless Podman + Dev Containers

This machine only has flatpak VSCode (`com.visualstudio.code`, currently
1.130.0) — no host-native `code`. Its Dev Containers extension attaching to
rootless Podman needs one-time host setup beyond what any individual
project's `run.sh` covers, because the flatpak sandbox does not see the
host's container socket by default. This doc is that setup, and applies to
every container this machine attaches to, not just one project.

## Why `filesystems=host` in the app manifest isn't enough

VSCode's own flatpak manifest already grants `filesystems=host`, `devel`,
and `network`. That's necessary but not sufficient:

- Inside the sandbox, `/run/user/1000` is flatpak's own private tmpfs, not
  the host's — the host's `/run/user/1000/podman/podman.sock` isn't visible
  there even with `filesystems=host`.
- `/run/host/run` doesn't exist on this machine, so there's no host-run
  bind-mount to fall back on either.
- There's no `podman` binary inside the sandbox. `flatpak-spawn --host` is
  the only way out to the host from inside it.

So the socket has to be (a) actually running on the host and (b) explicitly
exposed into the sandbox by path.

## Setup

Scripted end to end in `scripts/install-devcontainers-host.sh` — run it,
it does all three steps below and is safe to re-run. Manual detail on each
step follows for reference.

```
scripts/install-devcontainers-host.sh
```

### 1. Enable the podman socket (host, user-level)

```
systemctl --user enable --now podman.socket
```

Verify:

```
systemctl --user is-active podman.socket    # active
systemctl --user is-enabled podman.socket   # enabled
ls /run/user/1000/podman/podman.sock        # exists
```

Reversible: `systemctl --user disable --now podman.socket`.

### 2. Expose it to the VSCode flatpak sandbox

```
flatpak override --user --filesystem=xdg-run/podman com.visualstudio.code
```

`xdg-run/<name>` is flatpak's portable alias for
`$XDG_RUNTIME_DIR/<name>` (i.e. `/run/user/1000/podman` on this machine) —
it survives a UID change, an explicit absolute-path override wouldn't.

Verify with `flatpak override --user --show com.visualstudio.code` (should
list `filesystems=xdg-run/podman` under `[Context]`), then restart VSCode
and confirm `/run/user/1000/podman/podman.sock` is readable from inside it.

Reversible: `flatpak override --user --reset com.visualstudio.code` (or
`--nofilesystem=xdg-run/podman` to remove just this grant).

### 3. Host-command wrapper scripts

Dev Containers, running inside the sandbox, needs to invoke `podman` (and
`podman-compose`, if a project's dev container uses it) on the host. Neither
binary is present in the sandbox — `flatpak-spawn --host <cmd>` is the
sandbox's only route out. Two thin wrappers in `~/.local/bin` (already on
the sandbox's visible filesystem, already home to this machine's other
wrapper scripts) make that route point-and-click for the extension's
configuration:

`~/.local/bin/podman-host` (mode 755):

```sh
#!/bin/sh
exec flatpak-spawn --host podman "$@"
```

`~/.local/bin/podman-compose-host` (mode 755, only if `podman-compose` is
installed on the host — the script checks `command -v podman-compose`
itself, and skips creating this one rather than installing anything):

```sh
#!/bin/sh
exec flatpak-spawn --host podman-compose "$@"
```

`flatpak-spawn` itself is provided by the sandbox runtime when VSCode runs
as a flatpak — it is not a host package and won't resolve from a plain host
shell (a Claude Code session running directly on the host, for instance,
has no `flatpak-spawn` and can't smoke-test these wrappers itself; they
only resolve from inside the sandbox, e.g. VSCode's integrated terminal).
Reversible: delete the two files.

All three steps live only under `/var/home` (`~/.config/systemd/user/`,
the flatpak override under `~/.local/share/flatpak/`, and the wrapper
scripts) — none touch `/etc` or the OS image, so kopia's daily
`/var/home` snapshot already covers all of it as backup, on top of each
step's own one-command reversal above.

## Known non-host failure mode

If the Dev Containers server fails to start inside a *target* container,
the usual cause is a missing `procps` (`ps`) package in that container's
image — VSCode's server probes for it. That's the container image's
`Containerfile` to fix, not a host change; nothing here addresses it.

## Verified

2026-08-27, at second-brain's request (`_infrastructure/agent-container/`):

- `podman.socket` enabled and active, socket file present.
- Flatpak override applied and shown in `--show` output.
- `podman-host` and `podman-compose-host` created, mode 755 (`podman-compose`
  was present on the host — `/usr/bin/podman-compose` — so both wrappers
  were created; neither required installing anything).
- Not independently re-verified from inside a running VSCode flatpak
  session in this pass — do that once, and if the socket isn't readable
  there despite the override, revisit step 2 first.
- Scripted into `scripts/install-devcontainers-host.sh` (idempotent —
  re-ran clean after the manual pass above) so a machine rebuild picks
  this up automatically instead of relying on this doc being followed by
  hand; see `docs/bootstrap.md` §3.6.

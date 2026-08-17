---
name: update-check
description: Check for OS image updates (rpm-ostree), drift/updates across both flatpak manifests (this repo's scripts/install-flatpaks.sh and the private extras repo's flatpaks.sh, if EXTRAS_DIR is set), the full flatpak install including runtimes/extensions, and firmware (fwupd/LVFS). Use when the user asks to check for updates, upgrade the system, or update installed apps.
---

Run `scripts/update-check.sh` from the repo root and show its output as-is —
it already reports, per CLAUDE.md's "deny what cannot be undone" rule:

- OS image staleness via `rpm-ostree upgrade --check` (read-only, no deploy)
- every flatpak in the public manifest and, if `EXTRAS_DIR` is set, the
  private extras manifest: `current`, `outdated`, `not installed`, or
  `unknown` (remote unreachable)
- the full flatpak install, runtimes and extensions included, via
  `flatpak update` answered "n" at its prompt — this is what actually
  matches GNOME Software's "App Updates" list, which often attributes a
  runtime/extension update (e.g. a GL/VAAPI driver) to every app that
  depends on it rather than listing the runtime itself
- firmware via `fwupdmgr get-updates` (LVFS)

It never runs `rpm-ostree upgrade`, `flatpak update`, or `fwupdmgr update`
itself — same report-only contract as `install-flatpaks.sh`. After showing
the output:

- If an OS update is available: show the printed `rpm-ostree upgrade &&
  systemctl reboot` command and ask before running it. This is the
  reboot-required, `rpm-ostree rollback`-covered layer — never auto-run it,
  same as every other host-level command in this repo.
- If any flatpaks are outdated: show the printed `flatpak update <id>`
  commands. These are lower-stakes and individually reversible
  (`flatpak update` keeps the previous deploy), but still host-level —
  propose them, don't run them silently. Batch confirmation across several
  ids in one ask is fine; running them without asking is not.
- If anything is `not installed`, point back at the relevant manifest
  script (`scripts/install-flatpaks.sh` or the extras repo's `flatpaks.sh`)
  for the install command rather than improvising one here.
- `unknown` entries usually mean no network to Flathub — say so, don't
  treat it as "current".
- If the full-system flatpak preview lists runtimes/extensions, show the
  printed `flatpak update` command and ask before running it — same
  reversible, propose-then-confirm handling as manifest flatpak updates.
- If a firmware update is listed: show the printed `fwupdmgr update`
  command, but do not offer to run it yourself even with confirmation —
  it flashes hardware directly and isn't covered by any of this repo's
  three reversibility layers. Say why, and have the user run it.

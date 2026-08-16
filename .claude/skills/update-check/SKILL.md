---
name: update-check
description: Check for OS image updates (rpm-ostree) and drift/updates across both flatpak manifests (this repo's scripts/install-flatpaks.sh and the private extras repo's flatpaks.sh, if EXTRAS_DIR is set). Use when the user asks to check for updates, upgrade the system, or update installed apps.
---

Run `scripts/update-check.sh` from the repo root and show its output as-is —
it already reports, per CLAUDE.md's "deny what cannot be undone" rule:

- OS image staleness via `rpm-ostree upgrade --check` (read-only, no deploy)
- every flatpak in the public manifest and, if `EXTRAS_DIR` is set, the
  private extras manifest: `current`, `outdated`, `not installed`, or
  `unknown` (remote unreachable)

It never runs `rpm-ostree upgrade` or `flatpak update` itself — same
report-only contract as `install-flatpaks.sh`. After showing the output:

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

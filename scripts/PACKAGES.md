# Layered packages, Flatpaks, and GNOME extensions

The narrated companion to [`layer-packages.sh`](layer-packages.sh),
[`install-flatpaks.sh`](install-flatpaks.sh), and
[`install-gnome-extensions.sh`](install-gnome-extensions.sh). Those three
scripts are the source of truth — report-only, idempotent, safe to re-run to
check this machine against the list. This file explains *why* each entry is
there and when it was added; it does not enforce anything and can drift, so if
the two ever disagree, trust the script and fix this file.

Update both in the same commit as the install that satisfies an entry.

## rpm-ostree layered packages

| Package | Added | Why |
|---|---|---|
| `git-core` | 2026-08-16 (§3.2) | Source control — base image dependency, bootstrap.md §3.2 |
| `etckeeper` | 2026-08-16 (§3.8) | The `/etc` reversibility layer. Before this, an `/etc` edit had no undo path, which is the reasoning behind CLAUDE.md marking `/etc` changes ASK rather than DENY — the ask-tier trusts etckeeper is there to catch a mistake |
| `gitleaks` | 2026-08-16 (§3.8) | `.githooks/pre-commit` refuses to run without it — this repo is public, so the secret scan is a hard requirement, not a nicety |
| `make` | 2026-08-16 (§3.8) | This repo's documented interface (`make probe`, `make check`, `make hooks`). §3.7 had to work around its absence with the `bash test/probe --suite` fallback |
| `tailscale` | 2026-08-16 (§3.4b) | Home-lab reachability off the LAN. Three later things need it: the vault's RAG backend (Ollama/Qdrant), the `/var/home` kopia backup target, and `docs/recovery.md` Card 3. Staged, pending reboot as of this entry |

## Flatpaks

| App ID | Added | Why |
|---|---|---|
| `com.visualstudio.code` | 2026-08-16 (§3.6) | Editor. Chosen over the layered Microsoft RPM repo: no layering cost, no reboot, sandboxed. **Provisional** — the only trigger for revisiting is Flatpak sandbox friction with host terminals/`toolbox` becoming a real practical hassle, not a re-litigation on its own. Decision captured live to the vault's `_inbox/` on 2026-08-16 for filing as a proper decision doc |
| `com.bitwarden.desktop` | 2026-08-16 (§3.1/§3.9) | Password manager desktop app. Bitwarden also publishes an official RPM, but via their own Cloudsmith-hosted repo — that means a third-party `.repo` file under `/etc/yum.repos.d/` plus a layered-package reboot. Flatpak is lower-friction and follows the same reasoning as the VS Code choice above |
| `eu.betterbird.Betterbird` | 2026-08-16 (user request) | Email client (Thunderbird fork). Unlike VS Code/Bitwarden above, this isn't a friction trade-off against a layered alternative — Betterbird has no RPM or COPR, upstream ships only a Linux tarball and this official Flathub build, so Flatpak is the only packaged install path |
| `org.gnome.seahorse.Application` | 2026-08-16 (fingerprint+keyring follow-up) | GUI to blank the GNOME Login keyring password — needed because `pam_fprintd` has no login password to hand `pam_gnome_keyring`, so fingerprint login otherwise still prompts for the keyring separately. General PAM/gnome-keyring behavior, not specific to this host's fingerprint reader. One-time manual task (see `docs/bootstrap.md` Part 4), so Flatpak over a layered RPM, same reasoning as VS Code/Bitwarden. **Kept installed permanently, not removed after the one-time task** — considered uninstalling since Bitwarden covers password management, but Seahorse manages GPG/SSH keys and the system secrets keyring, which Bitwarden doesn't touch; there were no keys in it to justify removal either way, and keeping it avoids adding an uninstall step to bootstrap for a 5MB app |

## GNOME Shell extensions

| UUID | Added | Why |
|---|---|---|
| `tailscale-gnome-qs@tailscale-qs.github.io` | 2026-08-16 (post-§3.4b) | Quick Settings toggle for Tailscale connect/disconnect + exit-node selection — the persistent-tray-icon equivalent the user asked for. Chosen over the official `tailscale systray` (bundled in the `tailscale` package already, but needs the AppIndicator extension installed first since GNOME dropped the legacy tray) and over Trayscale (unofficial Flatpak GUI, same AppIndicator dependency, heavier). This is the only one of the three that doesn't need AppIndicator as a prerequisite. Third-party (not Tailscale Inc.), maintained fork of the abandoned `joaophi/tailscale-gnome-qs`; requires GNOME Shell 45+, this machine runs 50.4. No CLI installer is present on this machine (no `gnome-extensions-cli`/`gext`), so install is manual via the extensions.gnome.org browser toggle — `install-gnome-extensions.sh` only reports the gap |

## What this deliberately doesn't cover

- **Host-specific hardware packages** (e.g. fingerprint reader support once
  §3.9/the fingerprint task lands) belong in
  [`hosts/thinkpad-e14-gen5/`](../hosts/thinkpad-e14-gen5/), not here — this
  file and its scripts are the base layer, reusable on any Fedora machine.
- **`local/`-sourced state** (secrets, kopia repo config, Tailscale auth) —
  covered by `docs/bootstrap.md` and `docs/recovery.md`, not by a package list.

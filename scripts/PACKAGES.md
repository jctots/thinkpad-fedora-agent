# Layered packages and Flatpaks

The narrated companion to [`layer-packages.sh`](layer-packages.sh) and
[`install-flatpaks.sh`](install-flatpaks.sh). Those two scripts are the source
of truth — report-only, idempotent, safe to re-run to check this machine
against the list. This file explains *why* each entry is there and when it
was added; it does not enforce anything and can drift, so if the two ever
disagree, trust the script and fix this file.

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

## What this deliberately doesn't cover

- **Host-specific hardware packages** (e.g. fingerprint reader support once
  §3.9/the fingerprint task lands) belong in
  [`hosts/thinkpad-e14-gen5/`](../hosts/thinkpad-e14-gen5/), not here — this
  file and its scripts are the base layer, reusable on any Fedora machine.
- **`local/`-sourced state** (secrets, kopia repo config, Tailscale auth) —
  covered by `docs/bootstrap.md` and `docs/recovery.md`, not by a package list.

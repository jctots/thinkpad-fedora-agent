# thinkpad-fedora-agent — Bootstrap Manual

Manual procedure for taking the ThinkPad E14 Gen 5 from Windows 11 to the point where `thinkpad-fedora-agent` can take over. Everything here is done by hand — this is the part that cannot be scripted, because the machine that would run the script does not exist yet.

> **Export this before you start.** Print it, or save it as a PDF on your phone. During the reformat there is no vault, no repo and no laptop — this document and the Bitwarden app on your phone are the two things that cannot be recovered from anything else. Everything else can.

**Scope ends** at a working Silverblue install with Bitwarden, git, SSH, Claude Code, VS Code and both repos cloned, the guardrails proven by `make probe`, and the reversibility floor — `etckeeper` and a tested `/var/home` backup — in place. From there, work continues in a Claude Code session started inside the `thinkpad-fedora-agent` repo, and the first task is the fingerprint reader.

---

## Part 1 — Pre-flight (on Windows, before wiping)

### 1.1 Two-device check

Do this first. If it fails, stop — everything downstream depends on it.

- [ ] Open the Bitwarden **web vault** on your phone, using mobile data, not the laptop. Confirm you can unlock it.
- [ ] Confirm any 2FA on the Bitwarden account does not depend on the laptop or on the vault. If the TOTP seed for Bitwarden itself lives inside Bitwarden or in a file on this machine, you have a lockout loop — break it now.
- [ ] Save Bitwarden's emergency recovery codes somewhere off the laptop.
- [ ] Confirm this document is on the phone or printed.

### 1.2 Credentials that must be in Bitwarden before the wipe

The install has a bootstrap ordering problem: you need Wi-Fi to reach Bitwarden, and the Wi-Fi password is in Bitwarden. Break it by having these readable from the phone offline (Bitwarden's mobile app caches the vault) or written down.

- [ ] Home Wi-Fi SSID and PSK
- [ ] Gitea instance URL, username, password
- [ ] GitHub username, password, 2FA method
- [ ] Anthropic / Claude account credentials
- [ ] A generated passphrase for the new disk encryption — create the Bitwarden entry **now**, so at install time you read it off the phone rather than inventing one under pressure
- [ ] The kopia repository password, and the NAS transport credentials it connects with. Same bar as the LUKS passphrase and for the same reason: `docs/recovery.md` Card 3 restores `/var/home` on a machine that has just been reinstalled, and without this that card stops at step 4. The backup is not a layer if the key to it is only on the machine it protects
- [ ] Tailscale account credentials — Card 3 reaches the NAS over Tailscale, not the LAN

### 1.3 Git sweep — every clone, not just the vault

An unpushed branch or a stash dies with the wipe. Sweep every repository on the machine, not the two you happen to be thinking about.

```powershell
Get-ChildItem -Path C:\Users\jcdedios -Recurse -Depth 6 -Directory -Filter .git -Force -ErrorAction SilentlyContinue |
  ForEach-Object {
    $r = $_.Parent.FullName
    $dirty   = git -C $r status --porcelain
    $unpushed = git -C $r log --branches --not --remotes --oneline
    $stashes = git -C $r stash list
    if ($dirty -or $unpushed -or $stashes) {
      Write-Output "=== $r"
      if ($dirty)    { Write-Output "  uncommitted:"; $dirty }
      if ($unpushed) { Write-Output "  unpushed:";    $unpushed }
      if ($stashes)  { Write-Output "  stashes:";     $stashes }
    }
  }
```

- [ ] Run it. Resolve every repo it prints — commit and push, or consciously discard.
- [ ] Re-run until it prints nothing.
- [ ] A submodule, a vendored upstream clone, or a repo under a sync folder sits deeper than the obvious two levels. The depth above is deliberately generous; do not lower it. It also matches `.git` directories left behind in caches and temp paths, which are noise — check the remote before treating one as real.
- [ ] Repos under a cloud-sync folder are replicated off-machine already and are not wipe-fatal. Say so explicitly rather than leaving them in the output to be re-triaged on every re-run.
- [ ] A project whose notes record uncommitted work may not have a clone on *this* machine at all. Confirm against the sweep output, not against the notes.

### 1.3b This repo, specifically

The sweep above covers it, but it is called out because it is the one repository whose loss cannot be worked around later: **this manual is inside it.**

- [ ] Decide the license. It blocks commit one and nothing else does
- [ ] Commit, create the GitHub repo, push
- [ ] Confirm from the phone that `github.com/jctots/thinkpad-fedora-agent` resolves and the tree is there

§3.7 clones this repo onto the new machine. If it only exists on this laptop when the disk is wiped, the entire project is gone, and the checklist telling you to recover it went with it.

### 1.4 The files git will not restore

Cloning a repo gives you a tree that looks complete and silently is not. Everything deliberately kept out of git is missing — and those are the files holding credentials and machine-local configuration.

```powershell
# per repo — lists ignored files; expect noise from build dirs
git -C <repo> status --ignored --porcelain | Select-String '^!!'
```

Ignore `node_modules`, `.venv`, build output. Look for small config-shaped files:

- [ ] `.env` files in every repo
- [ ] `.mcp.json` (vault root, and any other repo using MCP servers)
- [ ] `.rag-status`
- [ ] Vikunja API token and any other service tokens
- [ ] Claude Code user config — `~/.claude/settings.json`, the only authored file there. Skip the runtime dirs: `projects/`, `sessions/`, `shell-snapshots/`, `file-history/`, `debug/`, `plans/`. `.credentials.json` is not carried — you re-auth on the new machine
- [ ] `~/.claude.json` — **check before carrying it.** It can hold `mcpServers` entries with tokens, at top level or per project, but on a setup where every MCP server is declared in a project-scoped `.mcp.json` it holds only cache, telemetry and conversation history, and is worth nothing. Inspect the keys; carry it only if MCP entries are actually in there
- [ ] Per-repo `.claude/settings.local.json` where it is gitignored. Note the vault tracks its own, so nothing to extract there
- [ ] Anything in a `local/` or `secrets/` directory

Run the inverse check too. A private infrastructure repo may deliberately **track** its `.env` files, in which case they never appear in the `--ignored` output and there is nothing to extract — cloning restores them. Confirm with `git ls-files | grep '\.env$'` before assuming a missing `.env` means a lost credential, and before hand-copying one git already has.

Copy what is left into Bitwarden as secure notes, or onto an encrypted USB stick. Not into a repo.

Prefer **one** consolidated note over one note per file, if the total fits the note size limit. It is a single paste to make and a single thing to find later, and it can carry the restore path for each file alongside its contents. End it with an explicit last-line marker — `=== END OF BUNDLE (n/n) ===` — and confirm that marker is visible **on the phone**, not on this machine. A note truncated at paste time is indistinguishable from a good one until the day it is needed.

Do not encrypt the bundle to a file unless you have already confirmed the tool that opens it will exist on the new machine before you need it. Ciphertext on a USB stick is not reachable from a phone, which is the property §1.7 requires.

### 1.5 SSH keys

Recommended: **do not export the private keys.** Generate a fresh keypair on Fedora and register the new public key. Exporting private keys off a machine you are about to destroy is worse hygiene than issuing a new one, and you have web access to add it.

That requires password login to Gitea and GitHub, so:

- [ ] Confirm both passwords work by logging in from the phone browser now
- [ ] Note where in each web UI SSH keys are added, so you are not hunting for it later
- [ ] Leave the old public keys in place until the new key is confirmed working, then remove them

If any service only accepts key auth and has no password path, that key must be exported to encrypted storage instead. Check before assuming.

### 1.6 Non-git data

- [ ] Documents, photos, downloads — anything under the user profile not in a repo
- [ ] Browser bookmarks and profile data worth keeping
- [ ] Software licences and product keys tied to this machine
- [ ] Anything under `C:\` outside the user profile you put there deliberately
- [ ] Windows recovery media, if you want the option of going back

### 1.7 Final gate

- [ ] Fedora Silverblue ISO written to a USB stick, and the checksum verified
- [ ] The USB boots on this laptop — confirm before wiping, not after
- [ ] Git sweep prints nothing, or prints only repos consciously written off
- [ ] **The 1.4 credential bundle is in Bitwarden and its end marker is visible from the phone**
- [ ] **`thinkpad-fedora-agent` is pushed to GitHub and reachable from the phone** (1.3b)
- [ ] **`make probe` passes** — the guardrails are real before the agent gets privilege, not after
- [ ] **`docs/recovery.md` exported to the phone or printed**, alongside this manual. If the agent is unreachable when the machine breaks — no network, a usage limit, an outage — that card is the entire recovery path
- [ ] Every item above ticked

---

## Part 2 — Fedora Silverblue install

Nothing here is unusual; it is listed so the manual is complete.

- [ ] Boot the USB. On the ThinkPad this is `F12` for the boot menu, `F1` for BIOS.
- [ ] Secure Boot can stay enabled — Fedora is signed. Leave it on unless something later requires otherwise.
- [ ] Wipe the disk. This destroys Windows.
- [ ] Enable **full disk encryption** and use the passphrase from Bitwarden (1.2).
- [ ] Create the user account.
- [ ] Reboot, complete the GNOME first-boot wizard. Skip online accounts for now.
- [ ] Connect Wi-Fi.

---

## Part 3 — Bootstrap chain

Order matters: each step supplies something the next one needs. Steps marked **verify** are ones where you check the machine rather than trusting this document — Silverblue's base image contents and installer URLs change, and this file is a snapshot of what was believed on 2026-08-14.

### 3.1 Bitwarden — credentials available

The **web vault in Firefox is enough**. The desktop app, browser extension and fingerprint unlock are a later convenience, not a bootstrap dependency — they are the project's first real task, handled inside the repo.

- [ ] Open `vault.bitwarden.com` in Firefox, log in
- [ ] Everything below reads credentials from here

### 3.2 git — verify

- [ ] `which git`
- [ ] If missing: `rpm-ostree install git`, then reboot. This is the first reviewed system-level change; on Silverblue layering requires a reboot to take effect.
- [ ] `git config --global user.name` / `user.email`

### 3.3 SSH key

- [ ] `ssh-keygen -t ed25519 -C "e14-fedora"`
- [ ] `cat ~/.ssh/id_ed25519.pub`
- [ ] Add the public key to Gitea via its web UI
- [ ] Add the same public key to GitHub
- [ ] Test both: `ssh -T git@<gitea-host>` and `ssh -T git@github.com`

### 3.4 Claude Code — verify

- [ ] `curl -fsSL https://claude.ai/install.sh | bash` — a self-contained native binary into `~/.local/bin`, no Node.js and no package layering. Confirm the URL is still current before running it; do not pipe a stale URL to a shell.
- [ ] Confirm `~/.local/bin` is on `PATH`
- [ ] `claude` — log in through the browser flow

### 3.4b Home-lab reachability

Three later steps need the home lab, and none of them work over the LAN alone once the laptop leaves the house: the vault's RAG index (§3.5) talks to Ollama and Qdrant there, the `/var/home` backup targets the NAS (§3.8), and `docs/recovery.md` Card 3 restores from it.

- [ ] Install Tailscale and bring it up, using the account credentials from §1.2
- [ ] Confirm the NAS and the Ollama/Qdrant host resolve and answer from the laptop

Do this before §3.5, or that step will look like it passed when it did nothing.

### 3.5 The vault

- [ ] `git clone <gitea-url>/second-brain` into its intended location
- [ ] Restore the gitignored files saved in 1.4 — `.env`, `.mcp.json`, tokens. The clone is not complete without them
- [ ] Build the RAG index: `python _scripts/rag-embed.py`. It reads `OLLAMA_HOST` and `QDRANT_HOST` from the restored `.env`, and both are home-lab services — §3.4b has to be done first
- [ ] **Read its output, do not just check the exit code.** With those variables unset it prints `RAG not configured — skipping embed` and exits *successfully*. A green run that embedded nothing is the failure mode here, and it looks exactly like a pass
- [ ] Start a Claude Code session **in the vault** and confirm both context injection and RAG retrieval fire

This proves the vault works standalone. It does **not** prove it works from the session you will actually use — that check is §3.7, and it is a different test.

The vault is not a dependency of this machine. Incidents live in the `thinkpad-fedora-agent` repo. If the vault is broken you lose the narrative, not the ability to fix the laptop — keep it that way.

### 3.6 VS Code — decision, not a formality

Two paths on Silverblue, and they behave differently:

| Path | Trade-off |
|---|---|
| Flatpak | No layering, no reboot, sandboxed. Friction with host terminals, `toolbox`, and anything expecting host binaries |
| Layered Microsoft RPM repo | Behaves like a normal install, integrates with host tooling. Costs a layered package and a reboot |

- [ ] Pick one and install it. Alternatives were weighed, so this is a decision, not an incident — record which and why as a decision once the repo exists. This is exactly the kind of choice the project is for.

### 3.7 thinkpad-fedora-agent

- [ ] `git clone git@github.com:jctots/thinkpad-fedora-agent.git`
- [ ] `cd` into it and **prove the guardrails on this machine before using them**:

  ```bash
  which make && make probe || bash test/probe --suite
  ```

  `make` is probably not in the Silverblue base image — check rather than assume. It gets layered in §3.8 with everything else, so there is one reboot instead of three; the `bash` form is only for this first run, which happens before any layering. Both run the identical suite.

  They passed on the old laptop, which proves the ruleset is coherent, not that it is right about paths that only exist here. If anything reads ALLOW that should read DENY, stop and fix it — that is the one thing standing between the agent and an unrecoverable command.

- [ ] `scripts/install-hooks.sh` — git does not clone hooks, so the gitleaks pre-commit scan is off on a fresh clone until this runs
- [ ] Start a Claude Code session in a **terminal**, with that repo as the working directory — not the VS Code extension. Its `.claude/settings.json` carries the permission rules and wires the `PreToolUse` guard and the audit hook; all of it resolves from the session's working directory, so a session started anywhere else runs unguarded
- [ ] Attach only the vault's `_inbox/` — not the vault root — as a permanent, gitignored local setting rather than a per-session flag:

  ```json
  // .claude/settings.local.json (create if missing — already gitignored)
  {
    "permissions": {
      "additionalDirectories": [
        "/absolute/path/to/second-brain/_inbox"
      ]
    }
  }
  ```

  This grants writes into `_inbox/` and nothing else, with no config discovery — `_inbox/` has no `.claude/` of its own anyway. Takes effect on the next session start; no restart of an already-running session needed to pick up a settings file change
- [ ] **Verify the attach, not the vault's hooks.** Write a throwaway file into `_inbox/` from this session and confirm it appears on disk in the vault clone. That is the only capability this session needs from the vault
- [ ] Read [`../.claude/proposals/README.md`](../.claude/proposals/README.md) once. It is where the agent puts rule changes it cannot make itself, and knowing it exists is what stops the first wrong rule turning into an argument mid-incident
- [ ] The manual ends here. Continue in that session.

### 3.8 The reversibility floor

**Do this before asking the agent to change anything.** The deny list is calibrated on the assumption that all three layers of the triad exist. Two of them do not exist on a fresh install, and `rpm-ostree` rollback covers neither.

- [ ] `rpm-ostree install etckeeper` and reboot. Then `sudo etckeeper init && sudo etckeeper commit "baseline"` — from here every `/etc` change is a git diff, which is the entire reason `/etc` edits are ASK rather than DENY
- [ ] Stand up the `/var/home` backup — kopia to the home-lab NAS over Tailscale (§3.4b). The intended shape, including the install and connect commands, is [`recovery.md`](recovery.md) Card 3; it is design, not procedure, so correct it as you go. **Run a snapshot once, then pull one file back out.** Nothing else covers `/var/home`, and an untested backup is not a layer — it is a belief
- [ ] `rpm-ostree install gitleaks make` — gitleaks because the pre-commit hook refuses to run without it, and committing with `SKIP_GITLEAKS=1` retires a commit-one guardrail on day one; `make` because it is this repo's documented interface (`make probe`, `make check`, `make hooks`) and §3.7 had to work around its absence. Batch with `etckeeper` above if you have not rebooted yet — one reboot, not three
- [ ] `rpm-ostree status` — confirm there are two deployments. Until the first layered change reboots, there is nothing to roll back to
- [ ] **Walk [`recovery.md`](recovery.md) once, on a working machine.** Roll a deployment back, revert one `/etc` file, pull one file out of the backup. Correct the card wherever it turns out to be wrong — it was written from documentation, not from this hardware. An untested recovery card is the same kind of lie as an untested backup, and it is read on the day you can least afford to debug it

Record these as the first entries in `incidents/` if any of them fight back. That is the loop starting.

### 3.9 Pin what only this machine knows

Two values are guesses in the repo today, and both are ten seconds of work while you are sitting in front of it.

- [ ] `cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name` — pin these in `install.sh`'s `detect_host_profile`, which currently fails loudly rather than guessing
- [ ] `lsusb | grep -iE 'synaptics|goodix|fingerprint'` — record the vendor:product ID in `hosts/thinkpad-e14-gen5/README.md` and check it against libfprint's supported list. This decides whether the first task is possible at all

---

## Part 4 — What is never scripted

By design. The reproducibility bar is ~90–95% from scripts, with this covering the rest.

- Disk encryption passphrase entry
- Wi-Fi credentials
- GNOME first-boot wizard
- Account logins — Bitwarden, Claude, GNOME online accounts
- SSH key generation and registration
- Fingerprint enrolment
- TPM2 auto-unlock enrolment for the root LUKS volume — `scripts/tpm2-luks-unlock.sh`
  reports readiness and prints the exact command, but enrolling requires typing
  the current LUKS passphrase interactively to authorize the new keyslot
- Anything requiring a browser login flow

Keep this list in step with reality. When a script starts covering one of these, delete it from here.

# thinkpad-fedora-agent 💻🐧

A Fedora Silverblue ThinkPad operated by a privileged AI agent. 🤖

The agent debugs, fixes, configures and restores the machine. It holds real
privilege, under manual approval, with a guardrail layer that denies only what
the system cannot undo. Because every change it makes is recorded as it happens,
the machine can also be rebuilt from this repo — that is a consequence of
keeping the record, not the goal.

**🎯 The bet:** maintaining a Linux desktop by hand costs more time than it
should. A privileged agent plus reversibility closes that gap, and past a
point reverses it — not by hiding the system, but by making it answerable.
This project is the test.

**✅ What makes it safe enough to try:**

- ⏪ `rpm-ostree` rollback for the OS image
- 📓 `etckeeper` for `/etc`, so every config change is a diff
- 💾 backups for `/var/home`, which nothing else covers
- 🚫 a deny list scoped to the irreversible, not to the privileged
- 🖐️ manual approval throughout, and an audit log of every command

## 🧩 A worked example: driver churn across a kernel upgrade

Abstract claims about reversibility are cheap. Here is one chain of real
incidents, each one checkable against its own file.

Wanted the proprietary NVIDIA driver for one specific reason — `nvtop`/
`nvidia-smi` visibility, which the in-tree `nouveau` driver can't provide.
RPM Fusion's `akmod-nvidia` built unsigned inside rpm-ostree's layering
sandbox regardless of a correctly enrolled Secure Boot key
([I004](incidents/I004-nvidia-akmod-unsigned-in-rpm-ostree-post-sandbox.md)).
Worked around it: build and sign `kmod-nvidia` in a `toolbox` container
instead, pin it as an `rpm-ostree` `LocalPackage` matched to the exact
kernel build — and write down, at the time, the trade-off that pinning
implies: no auto-rebuild on the next kernel bump. The same signing bug hit
the Xbox controller's Bluetooth driver a few days later
([I006](incidents/I006-xpadneo-unsigned-akmod-and-truncated-descriptor-firmware.md))
and got the identical fix, because the first write-up made the second
diagnosis a lookup instead of a re-investigation.

The pinning trade-off wasn't hypothetical. Rebuilding the kmod from inside
`toolbox` turned out to be broken too — it can't read the host's MOK
private key
([I008](incidents/I008-build-signed-kmod-toolbox-key-access.md)) —
and that got recorded as an open, unresolved incident rather than quietly
patched over or left undocumented. Weeks later, an OS upgrade landed on a
new kernel and the pinned kmods blocked it outright: `rpm-ostree upgrade`
failed to depsolve, and the chained `&& systemctl reboot` never fired, so
the machine sat untouched rather than half-upgraded
([I024](incidents/I024-pinned-kmod-blocked-upgrade-dropped-nvidia-xpadneo.md)).
With I008 still open, the choice was drop the driver or block the upgrade
— made explicitly, by the human, in the moment: uninstall the pinned
kmods, then upgrade cleanly on top. `etckeeper` picked up the resulting
`/etc` diff automatically; `rpm-ostree rollback` stayed available the
entire time if the call had gone the other way.

Nothing here required a clean install to fix. The whole arc — driver
added, trade-off named up front, the same bug reused across two devices,
the trade-off's cost eventually paid, the decision to pay it made
in the open — is four files in [`incidents/`](incidents/index.md), each
one linked from the next, still readable and still reversible today.

### Without the agent

The `incidents/index.md` tally is measured — logged as it happened. This
is not that; it's the counterfactual, argued rather than timed, for the
same four-incident chain above. Take it as reasoning about where the time
actually goes, not as a second data point.

| Step | With this project | Without it |
|---|---|---|
| Diagnose the unsigned-akmod build (I004) | Fixed and shown live in the terminal already running with real privilege; the finding is written to `incidents/I004` the moment it's confirmed | Paste the build error into a browser AI tab, copy back its guesses, run them by hand, paste results back for the next round — no execution access on that side, no record left behind once the tab closes |
| Reuse the fix for the Xbox controller (I006), days later | `grep incidents/` or "same as I004?" turns the second diagnosis into a lookup | No link back to the earlier fix unless a human happened to keep their own notes; more likely, the identical bug gets re-diagnosed from scratch |
| Name the pinning trade-off at the time it's made | Written into the incident file as part of landing the fix, not as an afterthought | Usually skipped under "just get it working" pressure — the trade-off only surfaces later, as a mystery, when the next kernel bump breaks and nobody remembers why |
| Kernel bump blocks the upgrade, weeks later (I024) | Reads I008 directly, confirms the toolbox/MOK rebuild path is already known broken, decision made in one sitting with the trade-off already on record | Re-diagnoses the toolbox/MOK failure from scratch under time pressure from a blocked upgrade — the conditions that produce a rushed `--force` or a stray `rm -rf` instead of a clean uninstall |
| Confirm the fix stuck (`etckeeper` commit, rollback still live) | Checked in the same sitting as a standing habit (`/etc-drift`, `rpm-ostree status`) | Depends on a human remembering to check, with nothing auditing whether they did |

None of this requires the agent to reason better than a browser tab running
the same model. The difference is that it holds the shell, the file
history, and the incident record in the same place a human would otherwise
be manually relaying between — so nothing has to be re-explained,
re-pasted, or re-diagnosed from session to session.

## 🛡️ How the guardrails classify

Privilege is not the axis. `sudo`, `rpm-ostree` and `systemctl` are the job.
What gets denied is what no rollback, no `etckeeper` diff and no backup can
undo.

| Class | Examples | Rule |
|---|---|---|
| ⏪ Reversible by rollback | `rpm-ostree install/override/rebase`, `flatpak`, `systemctl`, `toolbox` | allow or ask |
| ✍️ Reversible by hand | `/etc` edits, unit masking | ask — `etckeeper` makes each one a diff |
| ⛔ Irreversible | `wipefs`, `mkfs.*`, `dd` to `/dev/*`, `cryptsetup luksFormat/luksErase`, destructive `sgdisk`/`parted`, `ostree admin undeploy` of the rollback target, `rm -rf` on `/sysroot` or `/var/home` | deny, always |

On an atomic system this classification is checkable rather than a judgement
call, which is what makes the whole arrangement defensible.

The full account — where the ruleset came from, how it is enforced and proved,
what it does *not* protect against, and who is allowed to change it — is in
**[`docs/guardrails.md`](docs/guardrails.md)**. It is the most important
document here after this one.

## 🗂️ Layout

```
README.md              this file
CLAUDE.md              standing rules for the agent session
VENDOR.md              what is vendored, from where, at which commit
Makefile               `make probe` — the acceptance test for the guardrails
incidents/             one file per incident + an index that doubles as the tally
docs/bootstrap.md      bare metal → the point the agent takes over
docs/guardrails.md     the guardrail layer: design, provenance, change policy, limits
docs/recovery.md       restoring the machine without the agent
install.sh             idempotent orchestrator; selects the host profile
scripts/               base layer — hardware-agnostic
hosts/<slug>/          host profile layer — one directory per machine
local/                 gitignored — secrets, identity, home-lab endpoints
.claude/               permission rules, guardrail hooks, audit log
test/                  kickstart + VM harness
docs/extras.md          optional private layer for fork-specific app installs
```

## 📊 Status

Bootstrapped and active. The machine runs Fedora Silverblue, the agent has
real privilege under the guardrail layer, and the fingerprint reader, TPM2
disk auto-unlock, and package/extension manifests reflect real work rather
than a plan. Scripts crystallise out of real use rather than being written up
front, so expect [`incidents/`](incidents/index.md) to lead and `scripts/` to
follow. A reinstall now starts from `docs/bootstrap.md` on an existing Fedora
install, not from a different OS.

The incident index is also the project's own scoreboard: every entry records
time-to-fix and whether the agent's first proposal was right. The claim above
is meant to be checkable against it.

## Skills

Reusable routines for recurring project chores, on top of the base
guardrails. Not all of these hit the system — most are read/report/propose
only, which is why several are safe for the agent to run on its own instead
of waiting to be asked.

| Skill | Does | Who invokes it |
|---|---|---|
| `/vendor-update` | Diffs each pinned commit in `VENDOR.md` against upstream, walks the Local Changes table, writes findings to `.claude/proposals/` | Human — no natural trigger event, occasional cadence |
| `/incident` | Scaffolds `incidents/I{nnn}-{slug}.md` from the template and inserts the index row | Agent, proactively, right after a fix lands — except the ✓/✗ first-proposal tally, always asked, never guessed |
| `/host-check` | Runs every report-only script (`scripts/*.sh`, `hosts/<slug>/*.sh`) and summarizes ok/missing | Agent, freely — read-only execution of scripts already guaranteed idempotent |
| `/etc-drift` | Checks `etckeeper` actually committed the last `/etc` change | Agent for the check; human approves the shown `etckeeper commit` if one's needed |
| `/handover` | Snapshots session state to `.claude/handover.md` before a reboot-triggering action, and reads it back in on the next session | Agent, proactively — already standing practice, this just formalizes it |
| `/update-check` | Reports OS image staleness (`rpm-ostree upgrade --check`) and drift across both flatpak manifests (public + private extras) — current/outdated/missing, never runs the upgrade itself | Agent for the check; human approves the shown `rpm-ostree upgrade` or `flatpak update` if one's needed |
| `/reset-triage` | On every session start, checks whether the previous boot ended uncleanly (`last -x` crash marker) and, if so, surfaces a standard evidence bundle (`journalctl -b -1 -k` tail, `pm_trace` hash-match, boot timestamps) unprompted; silent otherwise | Agent, proactively, chained off `/handover`'s read-mode |
| `/security-privacy-check` | Runs a Lynis hardening audit (via `pkexec`, report-only) plus GNOME privacy settings, location services, and Flatpak per-app permission overrides; saves each run to `.claude/security-reports/` (gitignored) | Agent, freely — read-only, never installs or changes a setting |

The dividing line isn't privilege, same as the guardrails themselves: it's
whether a step is read-only/reversible-by-git (agent runs it unasked) or a
real system mutation (shown as a command, human approves), per CLAUDE.md's
working rules.

### Crash/hang forensics

Recurring lockups, panics, and hard resets are handled as a standing
capability, not reinvented per-bug (see decision D33 in the project vault).
Three layers, sorted by actual idle cost rather than by which investigation
introduced them:

- **Baseline sensors** — `pm_trace` (pstore), the sysrq bitmask, and
  `pm_debug_messages` stay armed permanently; each costs effectively
  nothing at idle, and unlike a reactive check, they've already captured
  evidence by the time anyone knows a crash happened. The journald sync
  interval joins this layer too, tuned to a loose, host-profile-tunable
  default rather than the aggressive value an active investigation might
  need.
- **`/reset-triage`** — reactive and generic: detects an unclean prior boot
  on session start and reports a standard evidence bundle, regardless of
  which subsystem broke.
- **Case-specific escalation** — heavier, bug-specific instrumentation
  (targeted kernel args, a tightened sync interval) stays scoped to one
  open incident, armed deliberately and reverted when it's fixed — this is
  where the current s2idle resume-hang scaffolding in
  `hosts/thinkpad-e14-gen5/quirks.sh` lives.

Pinned to `hosts/thinkpad-e14-gen5/` for now; promotion to the generic
`scripts/` layer waits for a second host to validate the sensor set
against.

## ❓ FAQ

The reasoning behind the non-obvious choices. Each answer is the conclusion and
the one reason it turned on; the long form is in
[`docs/guardrails.md`](docs/guardrails.md) and the decision log.

**🔑 You gave an AI `sudo` on your daily driver?**
Yes, under manual approval on every command. Privilege is not the risk axis —
irreversibility is. Almost everything privileged on this machine is covered by
a rollback, a git diff or a backup, and what is left is denied outright. The
question worth asking is not whether the agent has power but whether the last
hour can be undone.

**📦 Why not sandbox the agent instead?**
Because then it cannot do the job. Sandboxes like `ai-jail` confine an agent to
a project directory to protect the host — this project's entire purpose is that
the agent changes the host. `ai-jail`'s own write-up recommends Silverblue as
the backstop for when an agent escapes its sandbox; this repo uses that same
property as the reason it is affordable to let the agent in deliberately.

**⚖️ Why deny by reversibility rather than by privilege?**
Every comparable guardrail config hard-blocks `sudo`, `dd`, `mkfs.*` and
`wipefs`. Adopting any of them unmodified forbids this machine's ordinary work
— and the one best engineered of them ships a hardcoded personal escape hatch,
which is what a rule nobody can actually live with looks like in practice.

**❄️ Why not NixOS?**
NixOS does "capture intent, not state" properly, with guarantees idempotent bash
only approximates. The requirement here is a low-friction vanilla-GNOME daily
driver, and Fedora is the best-supported route to that; the Nix language and
FHS breakage are a weeks-long detour from it. The honest consequence: on NixOS
this project would largely dissolve, because there would be no imperative
commands to review and no intent to recover after the fact.

**🔷 Why Silverblue and not Workstation?**
`rpm-ostree` rollback is the first layer of the triad, and it is what makes
"reversible" a mechanical fact rather than a judgement call. On Workstation the
OS layer does not exist and a large part of what is ASK here would have to
become DENY.

**🏗️ Why not BlueBuild or a custom image?**
Strictly more reproducible, and deferred to v2. Scripts crystallise out of real
incidents here; there is not yet enough settled package set to declare. Building
the image first would be capturing intent that has not been formed.

**🔒 What if I want an app installed that doesn't belong in a public manifest?**
`install.sh` supports an optional private layer — a private sibling repo of
your own, connected only by `EXTRAS_DIR` in your gitignored
`local/secrets.env`, running alongside the base and host-profile layers under
the same guardrails. No submodule, no private URL in this repo's history, and
every fork is unaffected until it opts in. This repo's own scope is narrow —
infrastructure/harness plus a small foundational app set (editor, password
manager) — so **a new app defaults to the private repo**, not this one, unless
it's something near any fork would also need. Full walkthrough for setting one
up, and the default-placement rule, in [`docs/extras.md`](docs/extras.md).

**🗄️ Where is the rest of the reasoning?**
The full decision log — alternatives weighed, options rejected — is kept in a
private vault, because it is interleaved with personal notes. Anything another
person would need to evaluate or reuse this repo is published here, and that is
the line: conclusions and mechanisms public, the diary not.

## 🙏 Attribution

This repo vendors and borrows from other people's work.

| Project | License | Taken |
|---|---|---|
| [uaziz1/claude-code-guardrails](https://github.com/uaziz1/claude-code-guardrails) | MIT | The hook harness — pattern matching that survives chaining, wrappers and subshells, plus the non-blocking JSONL audit logger. The pattern set is replaced |
| [swiencki/claude-code-guardrails](https://github.com/swiencki/claude-code-guardrails) | MIT | The probe method and its interface. No code — their probe reads exit status alone, which reports every ASK as ALLOW |
| [dwarvesf/claude-guardrails](https://github.com/dwarvesf/claude-guardrails) | MIT | Two ideas: deny the agent editing its own settings, and block the permission-bypass flags |
| [bitwarden/clients](https://github.com/bitwarden/clients) | GPL-3.0 | The polkit action file Bitwarden's desktop app needs for biometric unlock, taken verbatim since it has to match the app's own action ID |

Also read and deliberately not used —
[rulebricks](https://github.com/rulebricks/claude-code-guardrails) (fails open
on quota exhaustion), [panuhorsmalahti's
permissions-hook](https://github.com/panuhorsmalahti/claude-code-permissions-hook)
(unlicensed) and [akitaonrails/ai-jail](https://github.com/akitaonrails/ai-jail)
(GPL-3.0, and the contrast case this project inverts). The reversible /
compensatable / irreversible axis itself is established agent-governance
practice and is not claimed here; what is new is the substrate.

**Why each verdict fell the way it did** is in
[`docs/guardrails.md`](docs/guardrails.md) § 3. **Upstream URLs, pinned commits,
local modifications and the refresh procedure** are in
[`VENDOR.md`](VENDOR.md). This table is the credit; those are the substance.

## 📜 License

MIT — see [`LICENSE`](LICENSE).

The guardrail components vendored here are MIT, so this is the compatible
answer for the differentiated part of the repo, and no attribution obligation
is left dangling there. Copyleft was the live alternative for the guardrail
layer specifically; it was not chosen, since that layer is only useful if it
spreads, and the reversibility ruleset is meant to be lifted into other
people's setups without them having to think about licensing at all.

One exception: `scripts/bitwarden-polkit-policy/com.bitwarden.Bitwarden.policy`
is vendored verbatim from Bitwarden's GPL-3.0 `clients` repo — a data file, not
code this repo builds on, kept under its own upstream license rather than
relicensed.

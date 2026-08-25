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

Then the chain closed. Paying the cost made I008 worth fixing properly, so
it was — the privileged key read moved out of the rootless container onto
the host, which promptly exposed four more bugs in a script that had been
written from I004/I006's notes but never actually run end to end. Both
drivers rebuilt against the new kernel with the same unmodified script,
signed, verified against the enrolled key, and booted the same day.

Nothing here required a clean install, at any point. The whole arc is four
files in [`incidents/`](incidents/index.md), each linked from the next,
still readable and still reversible today. Note which part did the work:
the write-up that recorded I008 as *unfixed* is what made it cheap to fix
later. That is the mechanism, and it is the part that survives the agent
being wrong — which, per the tally, it often is.

### Without the agent

The tally in `incidents/index.md` is measured. This is not — it's the
counterfactual for that same chain, argued rather than timed.

| Step | With this project | Without it |
|---|---|---|
| Reuse I004's fix for the Xbox controller (I006), days later | `grep incidents/` turns the second diagnosis into a lookup | No link back unless a human kept their own notes; more likely the identical bug is re-diagnosed from scratch |
| Name the pinning trade-off when it's made | Written into the incident file as part of landing the fix | Skipped under "just get it working" pressure — it resurfaces later as a mystery when the kernel bumps |
| Kernel bump blocks the upgrade weeks later (I024) | Reads I008, confirms the rebuild path is already known broken, decides in one sitting | Re-diagnoses under time pressure — the conditions that produce a rushed `--force` instead of a clean uninstall |

None of this requires the agent to reason better than a browser tab running
the same model. The difference is that it holds the shell, the file
history, and the incident record in the same place a human would otherwise
be relaying between by hand.

## 📊 Status

Bootstrapped and active. The machine runs Fedora Silverblue, the agent has
real privilege under the guardrail layer, and the fingerprint reader, TPM2
disk auto-unlock, and package/extension manifests reflect real work rather
than a plan. Scripts crystallise out of real use rather than being written up
front, so expect [`incidents/`](incidents/index.md) to lead and `scripts/` to
follow. A reinstall now starts from `docs/bootstrap.md` on an existing Fedora
install, not from a different OS.

The incident index is also the project's own scoreboard: every entry records
time-to-fix and whether the agent's first proposal was right — misses
included, or the column would measure nothing. The bet at the top of this
file is meant to be checkable against it.

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

## Skills

Reusable routines for recurring project chores, on top of the base
guardrails. Not all of these hit the system — most are read/report/propose
only, which is why several are safe for the agent to run on its own instead
of waiting to be asked.

| Skill | Does | Who invokes it |
|---|---|---|
| `/host-check` | Runs every report-only script and summarizes ok/missing | Agent, freely |
| `/update-check` | Reports OS image staleness and drift across both flatpak manifests — never runs the upgrade itself | Agent for the check, human approves the upgrade |
| `/etc-drift` | Checks `etckeeper` actually committed the last `/etc` change | Agent for the check, human approves the commit |
| `/reset-triage` | Detects an unclean prior boot and surfaces an evidence bundle unprompted; silent otherwise | Agent, chained off `/handover`'s read-mode |
| `/end-session` | Wraps up: decides whether a reboot is actually pending, delegates to `/handover` if so, saves anything memory-worthy | Human, at session end — the one command to reach for |
| `/handover` | Snapshots session state before a reboot-triggering action, reads it back on the next session | Agent, proactively (or via `/end-session`) |
| `/incident` | Scaffolds an incident file and its index row | Agent, right after a fix lands — except the ✓/✗ tally, always asked |
| `/security-privacy-check` | Lynis hardening audit plus GNOME privacy and Flatpak permission overrides | Agent, freely |
| `/vendor-update` | Diffs each pinned commit in `VENDOR.md` against upstream, writes findings to `.claude/proposals/` | Human — occasional cadence |

The dividing line isn't privilege, same as the guardrails themselves: it's
whether a step is read-only/reversible-by-git (agent runs it unasked) or a
real system mutation (shown as a command, human approves). Each skill's
full contract is in its own `.claude/skills/<name>/SKILL.md`.

Crash forensics is layered by idle cost rather than by which bug
introduced it: permanent sensors (`pm_trace`, sysrq bitmask,
`pm_debug_messages`) stay armed because they cost nothing and have already
captured evidence by the time anyone knows a crash happened;
`/reset-triage` is the generic reactive check; bug-specific instrumentation
stays scoped to one open incident and is reverted when it closes. Pinned to
`hosts/thinkpad-e14-gen5/` until a second host can validate the sensor set.

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

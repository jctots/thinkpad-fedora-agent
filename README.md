# thinkpad-fedora-agent

A Fedora Silverblue ThinkPad operated by a privileged AI agent.

The agent debugs, fixes, configures and restores the machine. It holds real
privilege, under manual approval, with a guardrail layer that denies only what
the system cannot undo. Because every change it makes is recorded as it happens,
the machine can also be rebuilt from this repo — that is a consequence of
keeping the record, not the goal.

**The bet:** maintaining a Linux desktop by hand costs more time than it
should. A privileged agent plus reversibility closes that gap, and past a
point reverses it — not by hiding the system, but by making it answerable.
This project is the test.

**What makes it safe enough to try:**

- `rpm-ostree` rollback for the OS image
- `etckeeper` for `/etc`, so every config change is a diff
- backups for `/var/home`, which nothing else covers
- a deny list scoped to the irreversible, not to the privileged
- manual approval throughout, and an audit log of every command

## How the guardrails classify

Privilege is not the axis. `sudo`, `rpm-ostree` and `systemctl` are the job.
What gets denied is what no rollback, no `etckeeper` diff and no backup can
undo.

| Class | Examples | Rule |
|---|---|---|
| Reversible by rollback | `rpm-ostree install/override/rebase`, `flatpak`, `systemctl`, `toolbox` | allow or ask |
| Reversible by hand | `/etc` edits, unit masking | ask — `etckeeper` makes each one a diff |
| Irreversible | `wipefs`, `mkfs.*`, `dd` to `/dev/*`, `cryptsetup luksFormat/luksErase`, destructive `sgdisk`/`parted`, `ostree admin undeploy` of the rollback target, `rm -rf` on `/sysroot` or `/var/home` | deny, always |

On an atomic system this classification is checkable rather than a judgement
call, which is what makes the whole arrangement defensible.

The full account — where the ruleset came from, how it is enforced and proved,
what it does *not* protect against, and who is allowed to change it — is in
**[`docs/guardrails.md`](docs/guardrails.md)**. It is the most important
document here after this one.

## Layout

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
```

## Status

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

## FAQ

The reasoning behind the non-obvious choices. Each answer is the conclusion and
the one reason it turned on; the long form is in
[`docs/guardrails.md`](docs/guardrails.md) and the decision log.

**You gave an AI `sudo` on your daily driver?**
Yes, under manual approval on every command. Privilege is not the risk axis —
irreversibility is. Almost everything privileged on this machine is covered by
a rollback, a git diff or a backup, and what is left is denied outright. The
question worth asking is not whether the agent has power but whether the last
hour can be undone.

**Why not sandbox the agent instead?**
Because then it cannot do the job. Sandboxes like `ai-jail` confine an agent to
a project directory to protect the host — this project's entire purpose is that
the agent changes the host. `ai-jail`'s own write-up recommends Silverblue as
the backstop for when an agent escapes its sandbox; this repo uses that same
property as the reason it is affordable to let the agent in deliberately.

**Why deny by reversibility rather than by privilege?**
Every comparable guardrail config hard-blocks `sudo`, `dd`, `mkfs.*` and
`wipefs`. Adopting any of them unmodified forbids this machine's ordinary work
— and the one best engineered of them ships a hardcoded personal escape hatch,
which is what a rule nobody can actually live with looks like in practice.

**Why not NixOS?**
NixOS does "capture intent, not state" properly, with guarantees idempotent bash
only approximates. The requirement here is a low-friction vanilla-GNOME daily
driver, and Fedora is the best-supported route to that; the Nix language and
FHS breakage are a weeks-long detour from it. The honest consequence: on NixOS
this project would largely dissolve, because there would be no imperative
commands to review and no intent to recover after the fact.

**Why Silverblue and not Workstation?**
`rpm-ostree` rollback is the first layer of the triad, and it is what makes
"reversible" a mechanical fact rather than a judgement call. On Workstation the
OS layer does not exist and a large part of what is ASK here would have to
become DENY.

**Why not BlueBuild or a custom image?**
Strictly more reproducible, and deferred to v2. Scripts crystallise out of real
incidents here; there is not yet enough settled package set to declare. Building
the image first would be capturing intent that has not been formed.

**Where is the rest of the reasoning?**
The full decision log — alternatives weighed, options rejected — is kept in a
private vault, because it is interleaved with personal notes. Anything another
person would need to evaluate or reuse this repo is published here, and that is
the line: conclusions and mechanisms public, the diary not.

## Attribution

This repo vendors and borrows from other people's work.

| Project | License | Taken |
|---|---|---|
| [uaziz1/claude-code-guardrails](https://github.com/uaziz1/claude-code-guardrails) | MIT | The hook harness — pattern matching that survives chaining, wrappers and subshells, plus the non-blocking JSONL audit logger. The pattern set is replaced |
| [swiencki/claude-code-guardrails](https://github.com/swiencki/claude-code-guardrails) | MIT | The probe method and its interface. No code — their probe reads exit status alone, which reports every ASK as ALLOW |
| [dwarvesf/claude-guardrails](https://github.com/dwarvesf/claude-guardrails) | MIT | Two ideas: deny the agent editing its own settings, and block the permission-bypass flags |

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

## License

MIT — see [`LICENSE`](LICENSE).

The vendored components are MIT, so this is the compatible answer and no
attribution obligation is left dangling. Copyleft was the live alternative,
since the differentiated part here is a safety mechanism. It was not chosen:
the guardrail layer is only useful if it spreads, and the reversibility ruleset
is meant to be lifted into other people's setups without them having to think
about licensing at all.

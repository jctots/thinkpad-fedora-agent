# The guardrail layer

This machine is operated by an AI agent holding real privilege. This document
is the account of what stops that from being reckless: what the layer denies,
where it came from, what it does *not* protect against, who is allowed to
change it, and how to lift it into your own setup.

It is the most important document in this repo after `README.md`. If you read
only the classification table there and stopped, this is the rest.

---

## 1. What this protects against

The threat model is not a malicious agent. An agent that has decided to destroy
your machine and is actively working around a regex will succeed, and nothing
in this repo pretends otherwise. **This is defence in depth, not a security
boundary.**

What it is actually for, in descending order of likelihood:

**The confident wrong fix.** The realistic failure. The agent diagnoses
plausibly, proposes a command that follows from the diagnosis, the diagnosis is
wrong, and the command runs. Every layer of the reversibility triad exists so
that this costs minutes instead of a reinstall. The guardrail's job is to make
sure the one command per thousand that *cannot* be walked back is not the one
that goes through on autopilot.

**Drift.** Not catastrophe — accumulation. A hundred small changes made across
six months, none recorded, until the machine works and nobody including the
agent knows why. This is the failure that actually ends projects like this one,
and the guardrail layer only helps at the margin: `etckeeper` and `incidents/`
are the real counter, and both depend on being used rather than installed.

**Prompt injection.** Worse here than for a coding agent, because the privilege
is real. Content fetched from the web enters a session that can run
`rpm-ostree`. The specific consequence this layer is built around is that an
injected instruction must not be able to *weaken the layer itself* — see §6.

What it explicitly does **not** protect against:

- An operator who approves without reading. Every ASK is a prompt, and a prompt
  that is always answered `yes` is decoration.
- A destructive line inside a script the agent is asked to run. The ruleset
  reads command strings, not file contents.
- Anything after the point where you type
  `--dangerously-skip-permissions`. That flag is itself denied, but a human at
  a shell is not bound by any of this.

## 2. The axis: reversibility, not privilege

Privilege is not the risk. `sudo`, `rpm-ostree`, `systemctl`, `flatpak` and
`toolbox` are this machine's ordinary work, and a guardrail that blocks them
forbids the agent from doing the job it exists to do. Every comparable config
surveyed in §3 blocks exactly those, which is why none of them could be adopted.

What gets denied is what falls outside all three layers of the reversibility
triad:

| Layer | Mechanism | Covers |
|---|---|---|
| OS image | `rpm-ostree rollback` | layered packages, rebases, kernel args |
| `/etc` | `etckeeper` git diff | unit files, polkit rules, config edits |
| `/var/home` | backups | dotfiles, project state, anything written as the user |

This is the part that is genuinely different, and it is a property of the
substrate rather than a cleverness in the rules. On an atomic system, *"is this
reversible?"* has a mechanical answer. There is a previous deployment pinned or
there is not. There is an `etckeeper` commit or there is not. The classification
is checkable, not a judgement call — which is what makes it safe to write rules
against instead of asking an LLM to adjudicate each command.

Three verdicts follow:

| Verdict | Signal | Meaning |
|---|---|---|
| DENY | exit 2, stderr to the agent | Irreversible. No layer brings it back |
| ASK | exit 0 + a `permissionDecision` body | Privileged and covered. You read it, then approve |
| — | exit 0, silent | No rule matched; the normal permission flow applies |

**The middle row is the design.** A layer with only DENY and silence is a
privilege blocker, which is the thing every surveyed alternative is. ASK is
where almost all of this machine's real work lives, and the prompt is there so
the command is read before it runs, not to discourage it.

The test for adding a rule follows directly: *name the layer that would have to
undo it, and say why that layer cannot.* If you cannot name the layer, the rule
belongs in ASK.

### What is denied, and why

Grouped by why no layer reaches it. The authoritative list is
[`.claude/hooks/_ruleset.py`](../.claude/hooks/_ruleset.py); each entry there
carries its own one-line justification.

| Group | Examples | Why no layer covers it |
|---|---|---|
| Filesystem destruction | `wipefs`, `mkfs.*`, `blkdiscard`, `shred`, `dd of=/dev/…`, `> /dev/…`, `tee /dev/…` | Every layer that could restore it lived on the device |
| Disk encryption | `cryptsetup luksFormat` / `luksErase` / `luksKillSlot` | The LUKS header is the only copy of the key material. The passphrase in your vault then decrypts nothing |
| Partition tables | `sgdisk --zap-all`, `parted mklabel`, partition deletion, LVM removal | The container the filesystem lives in |
| **The rollback target itself** | `ostree admin undeploy`, `rpm-ostree cleanup --rollback`, `ostree prune` | Not destructive in the usual sense — they delete the thing that makes everything *else* reversible |
| **The `/var/home` layer itself** | `kopia snapshot delete`, `kopia snapshot expire --delete`, `kopia blob delete` | Same class. Retention and maintenance changes are ASK instead, because a regex cannot tell a lengthened policy from a shortened one |
| Unrecoverable roots | `rm -rf` on `/`, `/sysroot`, `/ostree`, `/boot`, `/etc`, `/var`, `/home`, `~` | Outside every layer, or the layer's own storage |
| **The guardrail layer** | Shell writes to `.claude/hooks/` or `settings.json`; permission-bypass flags | Self-modification — see §6 |
| Credential exfiltration | `curl --data @.env`, `scp id_ed25519 …` | Not reversibility but disclosure, which has the same shape: it cannot be undone |
| Published history | `git push --force`, `filter-branch` | The record is this project's deliverable |

The fourth and sixth groups are the ones a privilege-shaped guardrail misses
entirely. Neither `rpm-ostree cleanup --rollback` nor editing a hook file looks
dangerous. Both quietly remove a safety net, and the damage only appears at the
moment you need it.

## 3. Where this came from

Five Claude Code guardrail configurations and two agent sandboxes were read —
the repositories themselves, not their READMEs — before anything was written
here. The default was to take an existing implementation and replace the parts
that assume a developer machine. That is what happened.

**The finding that shaped everything:** every one of the five treats privileged
system work as the threat and hard-blocks `sudo`, `dd`, `mkfs.*` and `wipefs`.
Adopting any of them unmodified forbids this project's entire purpose. In the
best-engineered of them, `\bsudo\b` is tiered *catastrophic*, with a source
comment stating the block "stays fully in force."

The same file carries a hardcoded escape hatch gated on the author's own
hostname and jump host — which is both the practical refutation of the blanket
block and a live example of the credential leak that a gitignored `local/`
exists to prevent.

| Project | License | Taken |
|---|---|---|
| [uaziz1/claude-code-guardrails](https://github.com/uaziz1/claude-code-guardrails) | MIT | **The harness.** Tiered pattern matching, the build/strict mode switch, the write-scope check, the non-blocking JSONL audit logger. Its regexes survive command chaining, wrappers, subshells and `docker exec` — that is the hard part and it already existed. The pattern set is entirely replaced |
| [swiencki/claude-code-guardrails](https://github.com/swiencki/claude-code-guardrails) | MIT | **The proof method,** and the interface expressing it: `--command`, `--expect`, ALLOW/DENY/ASK, `make probe`. No code — their probe reads a hook's exit status alone, and ASK here is exit 0 with a JSON body, so every ASK would have reported ALLOW. For a reversibility ruleset that is the majority verdict. `test/probe` is written against the real hook contract instead |
| [dwarvesf/claude-guardrails](https://github.com/dwarvesf/claude-guardrails) | MIT | Two ideas: deny edits to `settings.json` so the agent cannot weaken its own guardrails, and block the literal permission-bypass flags |

Read and deliberately not used:

- **[rulebricks/claude-code-guardrails](https://github.com/rulebricks/claude-code-guardrails)** — POSTs every command to a hosted API and fails *open* on 401, 402, 429, 5xx and network errors. A guardrail that stops guarding under quota exhaustion is worse than none, because you stop watching.
- **[panuhorsmalahti/claude-code-permissions-hook](https://github.com/panuhorsmalahti/claude-code-permissions-hook)** — no LICENSE and `license` commented out in `Cargo.toml`, so nothing could be copied. Its TOML-driven rules and audit levels are good ideas, arrived at independently here.
- **[akitaonrails/ai-jail](https://github.com/akitaonrails/ai-jail)** (GPL-3.0) — sandboxes the agent away from the host with bubblewrap and Landlock, and its write-up names Silverblue as the backstop *for when the agent escapes the sandbox*. This repo runs the same fact the other way round: the substrate is what makes deliberately letting the agent in affordable. That inversion is the positioning of the whole project.
- **Claude Code's own sandbox layer** — protects the host *from* the agent by confining it to the project directory. This project's purpose is that the agent changes the real host. Do not mistake it for this layer; it is also a separate mechanism from permissions, and a sandbox filesystem block is not enforced if managed settings disable filesystem isolation.

The reversible / compensatable / irreversible classification, with irreversible
actions gated on a human, is **not novel** — it is established agent-governance
practice, stated directly in IBM Research's undo-and-retry agent work and in
Tuskira's reversibility argument. All of that literature is cloud, API and
enterprise-agent framing. What is new here is landing it on a desktop OS whose
substrate makes the classification mechanically checkable. The axis is
borrowed; the substrate is the contribution.

Upstream URLs, pinned commits and local modifications are in
[`VENDOR.md`](../VENDOR.md). That file is the pin; this section is the reasoning.

## 4. How it is enforced

Two mechanisms, deliberately redundant, neither trusted alone.

```
.claude/settings.json     permission rules — deny / ask / allow lists
.claude/hooks/
  _ruleset.py             the reversibility ruleset — DENY and ASK patterns
  bash-guard.py           PreToolUse:Bash — applies the ruleset
  audit.py                PostToolUse — daily JSONL of every tool call
```

**The hook is the enforcement.** Declared permission rules match unreliably
against compound commands, pipes and multiline input: `Bash(sudo *)` is a prefix
glob, and `cd /x && sudo y` walks straight past it
([anthropics/claude-code#18846](https://github.com/anthropics/claude-code/issues/18846),
closed without a visible fix). A `PreToolUse` hook receives the full command
string and blocks on exit 2 regardless of permission mode.

So every pattern in `_ruleset.py` matches *anywhere* in the command string,
not anchored to its start. That is deliberate: the threat is the dangerous text
appearing at all, including inside chains (`a && b`), wrappers
(`timeout 30 wipefs …`), subshells and `toolbox run …`.

**The deny list is the second layer.** It catches the plain forms, it is
readable by a human auditing the setup in ten seconds, and it keeps working if
`python3` is missing or a hook path breaks. It is redundant with the ruleset on
purpose.

**The audit log never blocks.** `audit.py` wraps its entire body in a
catch-all; a logging failure must not prevent work. It writes daily JSONL to a
gitignored `.claude/audit/`.

There is no auto-approve mode configured and there must never be one. Default
manual mode is the arrangement that makes real privilege affordable.

### One risk this section must not bury

Under Fedora's privilege-escalation policy, `rpm-ostree` operations on signed
packages from configured repos **do not re-prompt a `wheel` user for a
password**. For a large class of this agent's ordinary work there is no second
challenge behind the Claude Code prompt. The hook layer *is* the control there,
not defence in depth. See §8.

## 5. How to prove it

```bash
make probe                                       # the acceptance set
make check CMD='wipefs -a /dev/nvme0n1' EXPECT=deny
```

**A passing unit suite is not evidence that a guardrail fires.** Feeding
`wipefs /dev/nvme0n1` to the real hook and reading DENY on the way out is. The
probe runs the actual `bash-guard.py` with the actual ruleset and reports
ALLOW / DENY / ASK, which is why it can be trusted to catch a rule that reads
correctly and behaves wrongly.

This is not a formality, and the evidence is that the first version of the
ruleset let three real commands through, **all of which read as ASK**:

| Command | Why it slipped |
|---|---|
| `rm -rf /*` | The glob form. `/*` is how `rm -rf /` actually gets written, and the path-end pattern did not accept it |
| `rm -rf "/var/home"` | Quoted. The pattern matched the bare path only |
| `tee` to a block device | The third spelling of `dd`, after `dd of=` and `>`. Neither of the first two rules covered it |

None was visible by reading the patterns. All three are permanent regression
cases now. If you change a rule, add the case that would have caught the bug
before you change it.

The wrapped and chained forms are the ones that matter in the suite. A bare
`wipefs` is caught by anything; `cd /tmp && sudo wipefs …` is what walks past a
naive prefix rule.

**Re-run `make probe` on any machine before trusting it there.** Passing on one
box proves the ruleset is coherent, not that it is right about paths that only
exist on another.

## 6. The human in the loop

Three places, and they are not interchangeable.

**At execution.** Every ASK is a prompt shown before the command runs. Nothing
is auto-approved, and the permission-bypass flags are denied outright.

**At the irreversible boundary.** When the agent needs something denied, the
answer is not to lift the rule — it is that **you type the command yourself**.
The guardrail was never blocking the machine, only the agent's hand. That escape
hatch already exists, requires no configuration change, and is why keeping the
rules immutable in-session costs almost nothing operationally.

**At rule changes.** The agent cannot modify its own guardrails. This is
enforced on both paths, deliberately:

- `Edit`/`Write` on `.claude/hooks/**` and `.claude/settings.json` — denied in
  `settings.json`
- Shell writes to the same paths (`>`, `>>`, `tee`, `sed -i`, `mv`, `rm`) —
  denied in `_ruleset.py`

An agent that can edit its own ruleset has no ruleset. This holds regardless of
how trustworthy the agent is, because the case that matters is the injected
instruction: a prompt-injection that can weaken the layer becomes a *permanent*
compromise instead of a single bad command.

### The change policy is asymmetric

The direction of a proposed change is the whole risk. Treating both directions
with one rule gets it wrong in one of them.

| Direction | Who | When | Gate |
|---|---|---|---|
| Add a DENY, or tighten one | Agent may propose | Same session is fine | A new probe case passes |
| Narrow or remove a DENY | Human only | **Never in the session that asked for it** | Probe passes, and a commit citing the incident |
| Edit `hooks/` or `settings.json` | Human, outside the agent session | — | Denied in-session by design |

The middle row is the one that matters. Incident time is exactly when a
persuasive case for loosening will be constructed — *"I need `wipefs` to fix
this"* — and exactly when you are least able to evaluate it: under pressure, on
a broken machine, reading an argument written by the party that benefits from
it. A guardrail that can be argued away by the thing it constrains is not a
guardrail.

### The proposal channel

The agent writes to [`.claude/proposals/`](../.claude/proposals/), which is
committed, not loaded, and not enforced. One file per proposal, carrying the
proposed diff, the incident that motivated it, and **a probe case that fails
against the current ruleset**. A human applies it; `make probe` gates it; the
commit cites the incident.

This is expected to see traffic. The ruleset has never run on a live Silverblue
machine, and rules written against paths that do not yet exist will be wrong in
ways no amount of reading catches. The answer to that is a cheap, recorded
change loop — not a mutable one.

## 7. Keeping it current

**When upstream changes.** The procedure lives in
[`VENDOR.md`](../VENDOR.md) § Refreshing a vendored component, next to the pins
it operates on, because that is the file open during a refresh. In short: the
agent reads the diff and reports, a human applies the code, harness changes only
— the pattern set here is never merged from upstream — and `make probe` gates
it. A refresh is a human action by construction, since `.claude/hooks/` is
denied to the agent.

**When a rule changes.** Every rule change lands with (a) a probe case that
fails before it and passes after, and (b) a commit message naming the incident
or proposal that motivated it. A rule with no case is not a rule, it is a
comment.

**When the substrate changes.** The rules encode three specific reversibility
layers. If one of them stops being true, the classification behind every ASK
stops being true with it. Specifically: if `etckeeper` is not committing, `/etc`
edits are not reversible and should not be ASK; if the `/var/home` backup has
not run, `rm -rf ~/anything` is not covered. §8 has this as a named risk because
it is the failure the layer cannot detect on its own.

## 8. Residual risks — named and accepted

A safety mechanism that lists only what it catches is advertising. These are the
gaps that remain with the entire layer working as designed.

- **Manual approval is thinner on Silverblue than it looks.** `rpm-ostree`
  operations on signed packages from configured repos do not re-prompt a `wheel`
  user for a password, so for much of this agent's ordinary work the Claude Code
  prompt is the only challenge. (The related unauthenticated-local-package hole,
  `rohanssrao/silverblue-privesc`, was fixed in Fedora 41 and is not live.)
- **Drift beats catastrophe as the likely failure.** The realistic bad outcome
  is not a wiped disk. It is a hundred small unrecorded changes that leave the
  machine unrebuildable. `etckeeper` and `incidents/` are the counter, and both
  depend on being used every time rather than on being installed.
- **Prompt injection is worse here than for a coding agent**, because the
  privilege is real. Content fetched from the web enters a session that can run
  `rpm-ostree`.
- **`/var/home` is the soft spot.** It is where the agent does most of its work,
  and the only layer of the triad whose reversibility depends on a backup that
  has to actually be running. A stale backup here is an irreversible change that
  looks covered.
- **The ruleset is a regex over a command string.** It does not resolve
  variables, aliases or scripts. `BAD=wipefs; sudo $BAD /dev/nvme0n1` is not
  caught, and neither is a destructive line inside a script the agent is asked
  to run. This is a deliberate limit — parsing does not fix it either — and the
  answer is that scripts get read before they are run, not that the guard is
  assumed total.
- **None of this survives an operator who approves without reading.** The layer
  converts an irreversible risk into a prompt. What the prompt is worth depends
  entirely on the person answering it.
- **Tool-level restriction on one agent session does not bound another
  session's shell.** `incidents/I023`: a same-user local service
  (thunderbird-cli's `tb-bridge`) had no auth of its own, so this session —
  with zero mail tools configured — read a full mailbox anyway, just by
  shelling out to its CLI. The fix (`docs/thunderbird-cli.md`) is a bearer
  token, and a shared secret cannot divide a trust domain it lives inside:
  both this agent and the second-brain agent run as the same uid. If
  `tb accounts` returns `AUTH_REQUIRED` from this session, that is the fix
  working as intended — do not read the token or otherwise route around it.
  Any local service reachable only by convention, not by an auth check of
  its own, is this same gap waiting to be found again.

## 9. Lifting this into your own setup

`_ruleset.py` is deliberately a standalone module with no imports from the hook
that applies it, so it can be vendored on its own — by a home lab, a VM, or a
different harness entirely.

```python
from _ruleset import DENY, ASK   # lists of (pattern, label, why) tuples
```

Each entry is a regex, a short human label, and the sentence explaining why no
layer covers it. Matching is `re.search` against the raw command string. Write
whatever adapter your harness needs around that; here it is
`bash-guard.py`, and it is under a hundred lines.

Two things to check before you trust it:

**Your substrate must actually have the layers.** These rules classify against
`rpm-ostree` rollback, `etckeeper` and a `/var/home` backup. On a non-atomic
distribution the OS layer does not exist, and a large part of the ASK list —
package operations, rebases, kernel args — is not reversible for you and should
move to DENY. The ruleset is portable; the *classification* is a claim about a
particular machine.

**Probe it on your own box.** `test/probe` is small and harness-shaped; port it
or write your own, but run the acceptance set before the first privileged
session, not after the first incident. Three real bypasses in this ruleset were
found that way and none of them by reading.

Licensed MIT precisely so this is possible. Copyleft was the live alternative,
since a safety mechanism is the kind of thing you might want to keep free — it
was not chosen, because this is only worth anything if people lift it without
having to think about licensing at all.

# thinkpad-fedora-agent — Agent Instructions

You are operating a Fedora Silverblue ThinkPad. You hold real privilege under
manual approval. Read this before proposing anything that touches the system.

## The rule that matters

**Deny what cannot be undone. Everything else is the job.**

Privilege is not the axis. `sudo`, `rpm-ostree`, `systemctl`, `flatpak` and
`toolbox` are ordinary work here. Before proposing a command, ask which of the
three reversibility layers covers it:

| Layer | Mechanism | Covers |
|---|---|---|
| OS image | `rpm-ostree rollback` | layered packages, rebases, kernel args |
| `/etc` | `etckeeper` git diff | unit files, polkit rules, config edits |
| `/var/home` | backups | dotfiles, project state, anything written as the user |

If none of the three covers it, it is irreversible: do not propose it, and say
why instead. The deny list in `.claude/` enforces this, but the reasoning is
yours to apply first — a hook is a backstop, not a substitute for thinking.

## Working rules

- **Show the command before running it.** Never propose an auto-approve
  permission mode for host-level work.
- **Commands needing root: use `pkexec <command>`, not plain `sudo`.**
  `pkexec` triggers GNOME's own polkit dialog — a real window that appears
  on screen unprompted, so it needs no separate heads-up (my tool output
  isn't streamed live to the screen, but the dialog itself is visible
  regardless). It authenticates via the same `system-auth` PAM stack as
  `sudo` (`authselect`'s `with-fingerprint` feature covers both — verified
  2026-08-18), so fingerprint still works, with password as its own
  built-in fallback — one mechanism, not two to maintain. It also closes
  itself on success or cancel, unlike a hand-fired notification.
  This is still a double gate, not a shortcut around approval: Claude
  Code's own per-call approval fires first, then the polkit dialog
  authenticates. See `incidents/I011`, `incidents/I012`, and
  `.claude/proposals/P005-fingerprint-gate-for-sudo-pkexec-approval.md`
  (superseded — records why a plain-`sudo` + hand-rolled notification
  pattern was dropped in favor of this).
- **Prefer idempotent commands** — check before acting, safe to re-run.
- **After any system change**, update the relevant script and manifest, and
  write up anything non-obvious: `incidents/I{nnn}-{slug}.md` from
  `incidents/_template.md`, plus a row in `incidents/index.md`. The failed
  attempts are worth as much as the fix — write the entry when the problem is
  fixed, not at the end of the session.
- **Log the tally.** Every entry records time-to-fix and whether the first
  proposal was right, and `incidents/index.md` carries those as columns. That table
  is the evidence for this project's central claim, and it is worthless if only
  the successes get written down. Record your own misses.
- **Never commit secrets.** Anything authenticated — Wi-Fi PSKs, kickstart
  passwords, tokens, registry logins, home-lab hostnames and endpoints — is
  sourced from the gitignored `local/`, never inlined. This repo is public.
- **New app requests default to the private extras layer (`EXTRAS_DIR`), not
  this repo.** This repo's scope is the harness/infrastructure (`scripts/`,
  `hosts/`, `.claude/`) plus the small foundational app set already in
  `scripts/install-flatpaks.sh` — an editor and a password manager, the ones
  bootstrap/recovery themselves depend on or that near any fork of this
  project would want. Everything else — a specific app, personal or
  employer-specific software — goes to the private repo unless the user says
  "public" explicitly. When it's a judgment call, ask rather than guess; see
  `docs/extras.md`.
- **Prefer explicit `gsettings set` lines** over a committed `dconf dump` blob.
  A blob drags in recent-file paths and account names, and nobody reviews it.
- **After changing anything under `/etc`**, confirm `etckeeper` committed it.
  An uncommitted `/etc` change is an unreversible one in practice.
- **You do not change your own guardrails.** `.claude/hooks/` and
  `.claude/settings.json` are denied to you on both the Edit path and the shell
  path, deliberately. If a rule is wrong, write the case to
  `.claude/proposals/` — the diff, the incident that motivated it, and a probe
  case that fails today — and say so out loud. Tightening a rule can ship the
  same session. Narrowing one never ships in the session that asked for it. If
  an irreversible command genuinely has to run right now, propose it and let
  the human type it; that costs a minute and keeps the layer honest.
- **Record incidents you did not fix.** If the agent was unreachable and the
  human recovered the machine by hand, that is still an incident, and the tally
  column is `n/a — agent unavailable`. Availability is part of the cost this
  project claims to beat. A tally counting only the sessions where the agent
  was working measures the arrangement on its best days and proves nothing.

## Before building a component

Check the prior-art record before writing a component from scratch. Every part
of this repo has existing implementations — the default is to read them, take
the machinery, and replace the parts that assume a developer machine. Building
from scratch is a decision that needs a reason, recorded as one.

Anything taken gets credited in `README.md` § Attribution and pinned in
`VENDOR.md` with its upstream URL, commit SHA and local changes. Refreshing a
vendored component follows `VENDOR.md` § Refreshing a vendored component: you
read the diff and report, a human applies the code.

`_ruleset.py` imports nothing harness-specific and never will. Claude Code is a
named dependency of this repo, but the ruleset is the portable part — the
binding to the harness is confined to `bash-guard.py` and `audit.py`, and it
stays that way so the rules can be lifted without them.

## Agent tool usage

When spawning non-fork subagents via the Agent tool, route by task shape, not
a single fixed model: `haiku` for mechanical/bounded work (pure search, grep,
well-specified boilerplate, status parsing, single-doc summarization),
`sonnet` for most implementation/debugging/judgment work (also the
no-override default), `opus` for ambiguous/high-stakes/architectural work
(planning, security-sensitive review, deep code review, root-causing without
a repro). Applies only to non-fork agents — a `fork` always inherits the
parent's model since it's continuing the same context, so the override is a
no-op there. Before delegating at all, weigh whether the context a fresh
agent needs (it starts with zero memory of the conversation) would itself
cost more tokens than doing the task inline — if so, skip delegation
entirely regardless of which tier would apply. Same rule kept consistent
across this repo, the second-brain vault, and `3etn-net-iac`.

## Session shape

This session runs in a terminal with this repo as the working directory — not
the VS Code extension. Guardrails, hooks and permissions resolve from the
working directory, so a session rooted anywhere else runs without them. Only the vault's `_inbox/` is attached, via `permissions.additionalDirectories`
in `.claude/settings.local.json` (gitignored — the absolute path is
host-specific, and this repo is public) — not the vault root, and not
`--add-dir`. The settings-key form grants file access only, with no config
discovery at all, which is what this session actually needs: `_inbox/` has no
`.claude/` of its own to load, and nothing here depends on the vault's
context-injection or RAG hooks firing.

Project narrative — decisions, memory, distilled insight — lives in the vault
at `public/projects/thinkpad-fedora-agent/`. Code, guardrails, manifests and
`incidents/` live here.

**Capturing something into the vault from this session.** Do not wait until
the session ends — a reboot, hang, or crash mid-`rpm-ostree` loses anything not
already written. The moment something is decision- or insight-worthy (not a
routine incident — those stay in `incidents/`), write one file directly into
the vault's `_inbox/`, named
`_inbox/{YYYY-MM-DD}-thinkpad-fedora-agent-{slug}.md`. One file per event,
never appended — never write to a file this session created earlier in the
same run. Contents: a one-line pointer (likely target project; a reference
into this repo's `incidents/` if the fuller narrative lives there), then a
marker line using the vault's existing vocabulary:

```
> Captured live by thinkpad-fedora-agent. Likely target: public/projects/thinkpad-fedora-agent.
> Detail: thinkpad-fedora-agent repo, incidents/007.md

🧠 [memory event]: one-line description
```

`🧠` memory / `🗂️` distill-worthy cross-project insight / `✅` next action /
`👤` observation about the human — same taxonomy the vault uses everywhere
else. A vault-side session processes these later; this session's job is only
to capture, not to file it correctly. See
`public/projects/thinkpad-fedora-agent/decisions/D26-vault-attach-scoped-to-inbox-live-capture-not-full-vault-hooks.md`
in the vault for the full reasoning.

The split is by kind, not by importance: a **decision** is a choice with
alternatives that were weighed, and goes to the vault's `decisions/`. An
**incident** is something that broke and this fixed it, and stays here in
`incidents/`. A fact about this particular machine — firmware strings, device
IDs, hardware support — is neither, and belongs in `hosts/<slug>/`. When a run
of incidents starts implying a decision, say so rather than writing the decision
into an incident.

## Repo layout

```
scripts/       base layer — runs unchanged on any Fedora machine
hosts/<slug>/  host profile — GPU, fingerprint reader, power, firmware quirks
incidents/     one file per incident, index doubles as the tally
local/         gitignored — secrets, identity, home-lab endpoints
test/          kickstart + VM harness
docs/          bootstrap manual
```

Where does a thing belong? Ask whether it is about *the device* or *the
software stack around it*. Most apparent hardware quirks are the latter and
belong in `scripts/`.

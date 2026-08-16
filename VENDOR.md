# Vendored components

What was taken, from where, at which commit, and what was changed locally.

**Vendored, not submoduled.** A clone without `--recursive` yields an absent
guardrail that looks installed. Copies live in-tree and are updated
deliberately.

Every entry here also appears in `README.md` § Attribution. Keep the two in
step: this file is the mechanical record, that one is the credit.

## Refreshing a vendored component

Read this before pulling upstream changes. It applies to every entry below.

**The agent does the reading; a human applies the code.** `.claude/hooks/` is
denied to the agent on both the Edit and the shell path, so a refresh is a human
action by construction — see [`docs/guardrails.md`](docs/guardrails.md) §6. That
is deliberate and stricter than it looks: a refresh replaces the *enforcement
code*, not the rules. A wrong rule produces a wrong verdict and `make probe`
catches it; a wrong harness can break the ASK path — exit 0 with a malformed
body reads as *no rule matched* — and whether the probe notices depends on probe
coverage, which is thinner. The more dangerous edit gets the stricter policy.

1. **Agent:** diff upstream against the pinned commit and read it. Do not merge
   it.
2. **Take harness changes only.** The pattern set in `_ruleset.py` is this
   repo's own and is never merged from upstream — upstream tiers `sudo`, `dd`,
   `mkfs.*` and `wipefs` as catastrophic, and pulling its rules back in forbids
   this machine's ordinary work. That is the whole reason for the fork.
3. **Agent:** walk the **Local changes** table for that component row by row
   against the new source and report which rows still hold. A local change that
   upstream has since adopted gets deleted from the table, not left claiming
   credit. Deliver this as a proposal, not as an applied change.
4. **Human:** apply the code, then `make probe`. **If it fails after a refresh,
   the refresh is wrong, not the suite.**
5. **Human:** land the commit pin, the retrieved date and the local-changes
   table *in the same commit as the code*. This file is not a guarded path, so
   the agent can edit it — which means a pin can silently get ahead of the tree.
   A wrong pin is worse than a stale one: the next refresh diffs against a base
   that was never vendored.

---

## uaziz1/claude-code-guardrails

- **Upstream:** https://github.com/uaziz1/claude-code-guardrails
- **Commit:** `0b8671079de887fbee051a8a8661c5a809a5c247`
- **Retrieved:** 2026-08-15
- **License:** MIT — © 2026 Umair Aziz
- **Vendored to:** `.claude/hooks/bash-guard.py`, `.claude/hooks/audit.py`
- **Taken:** the hook harness. The `PreToolUse` contract (exit 2 to deny,
  exit 0 with a `permissionDecision` body to ask), the substring-scan approach
  that survives chaining, wrappers, subshells and `docker exec`, the shape of
  the deny message, and `audit.py`'s never-block JSONL logger with detail
  truncation.

### Local changes

| Change | Why |
|---|---|
| `PATTERNS` replaced entirely by `_ruleset.py` | Upstream tiers `sudo`, `dd`, `mkfs.*` and `wipefs` as *catastrophic* (`hooks/bash-guard.py:151` at this commit). Adopting the set unmodified forbids this machine's ordinary work. The axis here is reversibility, not privilege |
| Split the ruleset into its own module | So a second machine — the home lab, a VM — can vendor the rules without the harness. This replaces the plan to take swiencki's JSON-fragment merge; see D17 |
| Added an ASK tier | Upstream's tiers (`catastrophic` / `strict`) select which rules apply in which *mode* — every match is a deny. A reversibility ruleset needs a middle outcome, and it is where most of the real work lands |
| Dropped `_mode.py` and the build/strict switch | A documented way to make the guard stop enforcing is the wrong feature for this repo. There is no mode in which `wipefs` becomes acceptable |
| Dropped the write-scope check | It asks when a write lands outside the project root. Here every write lands outside the project root — that is the job. It would have been noise on every command |
| Stripped the hardcoded escape hatch | Upstream carries an opt-in bypass keyed to the author's own host and jump host (`bash-guard.py:279-281`). Dead weight here, and a live example of the credential leak that gitignored `local/` exists to prevent |
| `audit.py` writes to `.claude/audit/` | Upstream uses `~/.claude/session-logs`. This machine's audit trail belongs with the repo that governs it; `.gitignore` already excludes the path |
| Fail-closed wrapper on `main()` | An exception in the guard must read as DENY, never as allowed |

### Upstream drift to watch

Its regex work on chained and wrapped commands is the part worth re-reading on
any future check — that is the hard problem it already solved, and the part
this repo did not re-derive.

---

## swiencki/claude-code-guardrails

- **Upstream:** https://github.com/swiencki/claude-code-guardrails
- **Commit:** `bc795ccaa370684791756efe0c8ccf841643d285`
- **Retrieved:** 2026-08-15
- **License:** MIT — © 2026 swiencki
- **Vendored to:** nothing. The idea was taken; no code was copied.
- **Taken:** the probe concept and its interface — `--command`, `--expect`,
  an ALLOW/DENY/ASK verdict, nonzero exit on mismatch, reached through
  `make probe`. This is the right acceptance test for a guardrail and it is
  their idea.

### Why no code was copied

`scripts/probe-fragment.sh` decides a hook's verdict from its **exit status
alone** (`evaluate_hooks`: nonzero → deny, zero → allow). This repo's guard
signals ASK as exit 0 *with a JSON body on stdout*, which that probe would
report as ALLOW — silently losing the outcome most of the ruleset produces.

`test/probe` is therefore this repo's own, written against the real hook
contract. Their interface, our implementation. Recorded as D17.

The fragment/profile architecture was also planned and not taken: the ruleset
needs three outcomes and regex, which is Python, not mergeable JSON. The
sharing goal it existed for is served by `_ruleset.py` being importable on its
own.

---

## dwarvesf/claude-guardrails

- **Upstream:** https://github.com/dwarvesf/claude-guardrails
- **License:** MIT
- **Vendored to:** nothing — two ideas, reimplemented.
- **Taken:** deny the agent editing `~/.claude/settings.json` and
  `settings.local.json` so it cannot weaken its own guardrails, and block the
  literal permission-bypass flags. Both appear in `.claude/settings.json`
  (`permissions.deny`) and in the ruleset's *guardrail layer defending itself*
  block, which also covers the shell-side forms (`sed -i`, `tee`, `mv`) that a
  tool-level deny does not see.

---

## bitwarden/clients — polkit action file

- **Upstream:** https://github.com/bitwarden/clients
- **Commit:** `92a620dd9c06c46127164d3c7a103aeafff92708`
- **Retrieved:** 2026-08-16
- **License:** GPL-3.0
- **Vendored to:** `scripts/bitwarden-polkit-policy/com.bitwarden.Bitwarden.policy`
- **Taken:** `apps/desktop/resources/com.bitwarden.desktop.policy`, verbatim,
  no local changes. It has to match the action ID (`com.bitwarden.Bitwarden.unlock`)
  the desktop app actually checks, so it is taken rather than hand-written.
  Needed because the Bitwarden Flatpak's own biometrics setup writes this file
  straight to `/usr/share/polkit-1/actions`, which fails on this machine's
  read-only `/usr` — see `incidents/I002-bitwarden-flatpak-polkit-policy-readonly-usr.md`.
  `scripts/build-bitwarden-polkit-policy.sh` packages it into a local RPM and
  layers it via `rpm-ostree` instead.

---
name: etc-drift
description: Check whether etckeeper actually committed the last change to /etc — an uncommitted /etc change is irreversible in practice per CLAUDE.md, since etckeeper's git history is what makes docs/recovery.md Card 2 possible. Use after any system-touching session, or when the user asks to check /etc drift or etckeeper status.
---

Run `scripts/etc-drift.sh` from the repo root and show its output as-is.

It needs `sudo` to read `/etc`'s git state (`sudo git -C /etc status` /
`log`), which is genuinely read-only but still an ask-tier command per
`.claude/settings.json` — that prompt is expected and correct, not a bug.
The script itself never runs `etckeeper commit` or writes anything; it only
reports.

Three possible outcomes:
- **`/etc is not a git repository`** — etckeeper was never initialised. This
  is the state a fresh install is in until `docs/bootstrap.md` §3.8 runs;
  show the printed `rpm-ostree install etckeeper` + `etckeeper init` commands
  and ask before running them (a layered package + reboot, real host
  mutation).
- **Uncommitted changes found** — show the diff-shaped output and the
  printed `sudo etckeeper commit "..."` command; ask before running it, same
  as any other `/etc` write.
- **Clean** — nothing to do, just report it.

Run this reflexively after any session that touched `/etc`, unit files, or
polkit rules — CLAUDE.md's own working rules call this out explicitly
("after changing anything under /etc, confirm etckeeper committed it").

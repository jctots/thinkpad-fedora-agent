---
name: vendor-update
description: Check every vendored component in VENDOR.md against its upstream, walk the Local Changes table, and write findings to .claude/proposals/ — never applied directly. Human-invoked, occasional cadence — no natural trigger event to run this proactively.
---

Follow `VENDOR.md`'s own "Refreshing a vendored component" section — that's
the authoritative procedure, this skill just executes it. Re-read that
section first; it's short and this summarizes it:

1. **For each entry in `VENDOR.md`** with a real upstream URL (skip entries
   whose "Vendored to" says "nothing — reimplemented", there's no commit to
   diff): fetch upstream at its current default branch and diff against the
   pinned commit for the specific vendored path(s), not the whole upstream
   repo.

   ```bash
   gh api repos/<owner>/<repo>/compare/<pinned-sha>...HEAD --jq '.files[] | select(.filename | startswith("<vendored-path>")) | .filename'
   ```

   or, without `gh`, a shallow clone and `git log <pinned-sha>..HEAD -- <path>`.

2. **Read the diff, don't merge it.** The agent's job here is analysis, not
   application — `.claude/hooks/` and any file this repo vendors code into
   are agent-denied on the write path by design.

3. **Take harness/mechanism changes only**, never the pattern set. Per
   `VENDOR.md`: `_ruleset.py`'s rules are this repo's own and are never
   merged from upstream, since upstream's tiering forbids ordinary work on
   this machine. Report what changed upstream, but don't propose pulling in
   rule changes.

4. **Walk the Local Changes table for that component, row by row,** against
   the new upstream source. A local change upstream has since adopted
   independently gets marked for deletion from the table (it's no longer
   this repo's own contribution) — don't leave it claiming credit for
   something upstream now does natively.

5. **Write findings to `.claude/proposals/P{nnn}-{slug}.md`** — the diff,
   what it means for the Local Changes table, and an explicit recommendation
   (take the harness change / don't / not applicable). Never apply the code
   directly: `VENDOR.md` is explicit that a human applies vendored code and
   runs `make probe` afterward, and a wrong harness refresh can break the ASK
   path silently (exit 0 with a malformed body reads as "no rule matched").

6. If nothing has changed upstream for a component since the pinned commit,
   say so plainly rather than writing an empty proposal — this skill's value
   is in catching drift, and "checked, nothing to do" is a valid, useful
   outcome to report back.

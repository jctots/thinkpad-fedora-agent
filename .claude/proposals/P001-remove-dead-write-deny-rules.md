## P001 — 2026-08-16 — Remove dead `Write(...)` deny rules from settings.json

**Direction:** loosen (narrows/removes two DENY lines) — but see verification below; net protection is unchanged.

> Loosening never ships in the session that asked for it. If something
> irreversible has to run now, say so and let the human type the command.

**Motivating incident:** this conversation. The change was made by jc in a
separate Claude Code session (rooted in the `second-brain` vault) earlier on
2026-08-16, landing as an uncommitted working-tree diff in this repo. A fresh
`thinkpad-fedora-agent` session flagged the diff on sight — `.claude/settings.json`
had lost `Write(.claude/hooks/**)` and `Write(.claude/settings.json)` from the
deny list, which on its face looks like exactly the kind of guardrail
self-loosening CLAUDE.md forbids. jc confirmed intent and asked for
verification before anything is committed.

**What happens today:** the working tree (not yet committed) reads:

```
"deny": [
  "Edit(.claude/hooks/**)",
  "Edit(.claude/settings.json)",
  "Edit(~/.claude/settings.json)",
  "Edit(~/.claude/settings.local.json)",
  ...
]
```

i.e. the `Write(...)` lines are already gone, `Edit(...)` lines are untouched.

**What should happen, and why:** nothing further — the removal is correct as
made. Per Claude Code's own docs (`permissions.md` §"Read and Edit",
`tools-reference.md` §"Configure tools", requires v2.1.210+), the permission
engine checks file-modifying tool calls against `Edit(path)` rules only.
`Write`, `NotebookEdit`, `Glob`, and legacy `MultiEdit` path-scoped rules are
accepted syntactically but never consulted — Claude Code warns about this at
startup. `Edit(path)` is documented as applying to Edit, Write, and
NotebookEdit alike. So `Write(.claude/hooks/**)` and
`Write(.claude/settings.json)` never gated anything; the `Edit(...)` rules
immediately above them were always the only rules doing the work, and remain
in place, untouched, after this change. No reversibility layer is implicated
because no capability changed.

Verified independently (not taken on jc's word) via a `claude-code-guide`
subagent research task, which fetched and quoted both docs pages directly —
see this conversation for the full citation.

**Proposed diff:** already applied to the working tree; this proposal
documents and ratifies it rather than proposing it fresh:

```diff
--- a/.claude/settings.json
+++ b/.claude/settings.json
@@ -14,9 +14,7 @@
   "permissions": {
     "deny": [
       "Edit(.claude/hooks/**)",
-      "Write(.claude/hooks/**)",
       "Edit(.claude/settings.json)",
-      "Write(.claude/settings.json)",
       "Edit(~/.claude/settings.json)",
       "Edit(~/.claude/settings.local.json)",
       "Read(./local/secrets.env)",
```

**Probe case that fails today:** not applicable in the usual sense — this
proposal doesn't touch `_ruleset.py` / `bash-guard.py`, so there is no
`make check CMD=…` case to run. The relevant check is `test/probe --suite`,
which exercises the bash-guard hook end-to-end and is unaffected by this
settings.json change (different enforcement layer). Ran it before and after:
38/38 cases pass both times, no case moved between DENY/ASK/ALLOW.

**Blast radius:** none. The `Edit(.claude/hooks/**)` and
`Edit(.claude/settings.json)` deny rules are untouched, so Edit-path attempts
to modify hooks or settings are still denied. Write-tool attempts to the same
paths were never actually gated by the removed lines (per verification above)
and remain gated now by the surviving `Edit(...)` rules, since Edit(path)
covers Write per the docs. No other line in the deny/ask/allow lists changed.

**Outcome:** applied 2026-08-16 — jc made the edit in the vault session; this
proposal is the after-the-fact record and sign-off gate CLAUDE.md requires
before it's committed here.

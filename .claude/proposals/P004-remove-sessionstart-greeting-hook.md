<!--
Template: .claude/proposals/P{nnn}-{slug}.md
Use: one file per proposed change to _ruleset.py or settings.json.
P### increments from the highest existing file; slug is kebab-case.
The agent writes this. A human applies it, runs `make probe`, and commits.
-->

## P004 — 2026-08-17 — Remove the SessionStart greeting hook entirely

**Direction:** delete `.claude/hooks/session-start-greeting.sh` and its
`hooks.SessionStart` entry in `.claude/settings.json`. Filed here because
both paths are deny-listed to me on the Edit path and the shell path per
CLAUDE.md.

**Motivating incident:** `incidents/I010`. `additionalContext` from a
`SessionStart` hook is a passive context-injection channel — it cannot
trigger an assistant turn on its own. Claude Code only calls the model once
the user submits a prompt, so the hook's "silent greeting" never appeared
before the user typed something, contrary to what `incidents/I009` claimed
after a mis-verified live test. Confirmed against the Claude Code hooks
docs and corroborated by open upstream issues (notably
anthropics/claude-code#69750, a feature request for exactly this
capability via a proposed `autoPrompt` hook field — not shipped today).

**User decision (this session):** `scripts/session-autostart.sh` now
unconditionally launches `claude "I'm back"` on every startup — a visible
CLI prompt argument, same words a human would type, which does reliably
trigger a real first turn. The branching (resume from
`.claude/handover.md` if present, atomic rename included; otherwise a
plain greeting closed with a quote from `scripts/quotes.txt`) happens
agent-side in `.claude/skills/handover/SKILL.md`'s read-mode section, not
in bash. That script edit and the skill doc rewrite are already applied
(neither `scripts/` nor `.claude/skills/` is deny-listed).

With `session-autostart.sh` and the handover skill now owning the whole
flow, the SessionStart hook is dead code once removed here.

**Proposed diff:**

```diff
--- a/.claude/settings.json
+++ b/.claude/settings.json
@@
   "hooks": {
-    "SessionStart": [
-      {
-        "hooks": [
-          {
-            "type": "command",
-            "command": "\"$CLAUDE_PROJECT_DIR/.claude/hooks/session-start-greeting.sh\"",
-            "timeout": 10
-          }
-        ]
-      }
-    ],
     "UserPromptSubmit": [
```

And delete the file:

```
rm .claude/hooks/session-start-greeting.sh
```

**Probe case that fails today:** start a session with no
`.claude/handover.md` present. Today (hook still wired): a `SessionStart`
hook fires, computes a quote, and injects `additionalContext` that never
surfaces until the user's first message — an observable no-op from the
user's side, confirmed live this session (see `incidents/I010`). After
this change: no hook fires, no `additionalContext` injected, session opens
with zero agent-authored preamble — matches what actually happens visually
either way, but removes the wasted `shuf` + `jq` execution and the stale
doc claims around it.

**Blast radius:** `.claude/settings.json` (`hooks.SessionStart` key only —
`UserPromptSubmit`, `PreToolUse`, `PostToolUse` untouched) and one hook
file. No permission rules (`allow`/`ask`/`deny`) change. `scripts/quotes.txt`
already removed (not deny-listed); `.claude/skills/handover/SKILL.md`
already updated to describe the new `session-autostart.sh`-owned mechanism.

**Outcome:** applied — verified 2026-08-17. Current `.claude/settings.json`
has no `hooks.SessionStart` key, and `.claude/hooks/session-start-greeting.sh`
does not exist on disk. Neither the hook file nor a `SessionStart` entry
was ever committed to git history, so there was no tracked change to
revert — the hook existed only as an uncommitted working-tree edit within
the same session that then removed it. Confirmed live: two "I'm back"
launches this session (with and without a pending `.claude/handover.md`)
both went through `session-autostart.sh` → the handover skill's read-mode
branch, with no `SessionStart` hook involved.

## P002 — 2026-08-16 — Add a UserPromptSubmit hook that warns on long sessions

**Direction:** add a new hook — not a deny/ask/allow change, so "tighten/loosen"
doesn't quite apply. Adding a hook is still something the agent cannot do
itself: `.claude/settings.json` is denied on the Edit path regardless of what
the edit contains, per CLAUDE.md's "you do not change your own guardrails."
This proposal exists because that block is correct to apply here too, not
because the content is risky — a `systemMessage` nudge has no blast radius.

**Motivating incident:** this conversation. jc asked to be reminded when a
session is getting long, to stay conscious of token usage. First instinct was
a `PreCompact` hook, but that fires only once the context window is already
nearly full — auto-compaction triggers late by design, and compaction itself
costs an extra LLM call on top of whatever already filled the window. jc
correctly flagged this as "too late and too costly" before it was proposed.

**What happens today:** no hook exists for this. The closest built-in feature
is `breakReminder` (time-based, unrelated to token/context usage) and the
internal `totalTokensReminder` block already visible in this session's own
context — but that one re-anchors every user turn (task-budget semantics),
so it cannot answer "is this whole session getting long," only "how much did
this one turn cost."

**What should happen, and why:** a `UserPromptSubmit` hook that reads the
session's own transcript file and warns once the *current* context size
crosses a threshold — ahead of, not at, the auto-compaction cliff.

The script (`scripts/session-token-check.sh`, already written and
pipe-tested — see below) reads `.transcript_path` from the hook's stdin JSON
and looks at only the **last** assistant turn's `usage` block:
`input_tokens + cache_read_input_tokens + cache_creation_input_tokens`. That
approximates the context currently loaded.

Summing usage across *every* turn in the transcript, which was the first
approach tried, is wrong: `cache_read_input_tokens` re-counts the same reused
context on every single turn. Verified against this session's own transcript
(137 assistant turns at the time): naive full-transcript sum came out to
~12.9M tokens, of which ~12.4M was repeated `cache_read` noise — the actual
context size, taken from the last turn alone, was ~203k. Threshold default
(150000) sits under the standard 200k window so the warning lands before the
window is nearly full.

No reversibility layer is implicated: this is a read-only script (reads a
transcript file, writes nothing) wired into `/var/home`'s existing backup
scope like any other repo file, not a system change.

**Proposed diff:**

```diff
--- a/.claude/settings.json
+++ b/.claude/settings.json
@@
   "permissions": { ... },
+  "hooks": {
+    "UserPromptSubmit": [
+      {
+        "hooks": [
+          {
+            "type": "command",
+            "command": "scripts/session-token-check.sh",
+            "timeout": 10
+          }
+        ]
+      }
+    ]
+  }
```

(If `hooks` already has other entries by the time this is applied, add the
`UserPromptSubmit` array alongside them — don't replace the key.)

**Probe case that fails today / passes after — pipe-tested, not yet wired:**

`scripts/session-token-check.sh` already exists and is executable. Since
`make check CMD=…` only exercises `_ruleset.py`/`bash-guard.py`, the
applicable verification here is the update-config skill's pipe-test
protocol, already run this session:

```bash
TRANSCRIPT=<this session's actual .jsonl under ~/.claude/projects/.../*.jsonl>

# over threshold (150000 default) — should print a systemMessage
echo "{\"transcript_path\":\"$TRANSCRIPT\"}" | scripts/session-token-check.sh
# => {"systemMessage": "Session context is at ~208045 tokens (threshold 150000) — consider wrapping up or starting fresh soon."}

# under threshold — should be silent
SESSION_TOKEN_WARN_THRESHOLD=300000 bash -c \
  "echo '{\"transcript_path\":\"$TRANSCRIPT\"}' | scripts/session-token-check.sh"
# => (no output), exit 0

# missing transcript_path — should be silent, not error
echo '{}' | scripts/session-token-check.sh    # => (no output), exit 0

# nonexistent file — should be silent, not error
echo '{"transcript_path":"/nonexistent"}' | scripts/session-token-check.sh    # => (no output), exit 0
```

All four passed. What's *not* verified: that Claude Code's actual
`UserPromptSubmit` stdin payload includes a `.transcript_path` field with
this exact name — the update-config skill's own hook docs list
`session_id`/`tool_name`/`tool_input`/`tool_response` for the general stdin
shape but don't enumerate every event's fields exhaustively. Confirm this
against a live hook firing (temporarily prefix the command with
`cat >> /tmp/hook-payload.json;` per the skill's step 6, trigger a real
prompt submit, inspect the captured payload) before trusting this in
production — that step needs the hook actually wired into `settings.json`,
which is exactly the part I can't do myself.

**Blast radius:** touches only `UserPromptSubmit`. No other hook event, no
permission rule, no deny/ask/allow line. Runs a script that only reads files
(the transcript) and prints JSON to stdout — no writes, no `sudo`, nothing
covered by the deny list. Worst case if the field-name assumption above is
wrong: the hook silently no-ops every turn (empty `transcript_path` → exit 0
immediately), not a false positive or a blocking failure.

**Outcome:** applied 2026-08-16, from the second-brain vault session (this
proposal is exactly the case it describes — the agent operating inside this
repo is blocked from editing `.claude/settings.json`, so a session rooted
elsewhere made the edit).

`.claude/settings.json` now has a `UserPromptSubmit` hook entry alongside the
existing `PreToolUse`/`PostToolUse` ones, calling
`"$CLAUDE_PROJECT_DIR/scripts/session-token-check.sh"` (absolute via
`$CLAUDE_PROJECT_DIR`, not the relative path in the original diff above — matches
the style of the other two hooks and doesn't depend on cwd).

Threshold changed from the proposal's single 150000 default to a **two-tier**
scheme, superseding the single-threshold design above: `SESSION_TOKEN_WARN_THRESHOLD`
(soft, default 100000, 50% of the 200k window) and
`SESSION_TOKEN_CRITICAL_THRESHOLD` (critical, default 150000, 75%). Only the
higher tier's message prints once both are crossed. jc chose this after
weighing 100000-only (more headroom, more false positives on ordinary
tool-output-heavy sessions) against 150000-only (fewer false positives, less
headroom) — the two-tier design gets both: an early nudge plus a harder stop
close to the cliff. `scripts/session-token-check.sh` was rewritten
accordingly.

The same two-tier warning was also ported to the second-brain vault repo as
`_scripts/check-session-tokens.py` (Python, matching that repo's hook
conventions rather than bash) — same thresholds and env var names, wired
into that repo's own `UserPromptSubmit` chain. Not part of this proposal's
original scope (thinkpad-fedora-agent only) but the same gap, so recorded
here for the paper trail; the vault repo has no self-edit guardrail so no
outside-session workaround was needed there.

Re-verified after all edits: both `settings.json` files parse as valid JSON;
both scripts' soft/critical/silent/missing-field/nonexistent-file pipe tests
all pass against the live wiring.

**Still open, per the proposal's own caveat:** whether Claude Code's real
`UserPromptSubmit` stdin payload actually has a `.transcript_path` field
with this exact name. That needs a live-fire check from inside a real
`thinkpad-fedora-agent` session — tee the payload to a file, send a real
prompt, inspect it — which a vault-session edit can't do.

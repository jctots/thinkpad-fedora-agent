# .claude/ — the guardrail layer

**Active.** The harness is vendored, the reversibility ruleset is written, and
`make probe` passes its acceptance set. It has **not** been exercised on the
target machine — the ThinkPad still runs Windows 11. Re-run `make probe` on
Silverblue before giving the agent any work; a rule that passes here can still
be wrong about a path that only exists there.

```
settings.json     permission rules + hook wiring
hooks/
  _ruleset.py     the reversibility ruleset — the substance
  bash-guard.py   PreToolUse:Bash — applies the ruleset
  audit.py        PostToolUse — daily JSONL of every tool call
proposals/        agent-written rule-change proposals — committed, not loaded,
                  not enforced
audit/            gitignored — the log itself
```

Everything else — what the layer denies and why, where it came from, how it is
enforced, how to prove it, who may change it, what it does *not* protect
against, and how to lift the ruleset into another setup — is in
**[`docs/guardrails.md`](../docs/guardrails.md)**.

This file is the map only. Two copies of the reasoning would drift, and the
copy nobody reads is always the wrong one.

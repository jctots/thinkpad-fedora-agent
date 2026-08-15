# Rule-change proposals

The agent cannot edit `.claude/hooks/` or `.claude/settings.json` — denied on
both the Edit path and the shell path. When it thinks a rule is wrong, it
writes here instead.

One file per proposal, `P{nnn}-{slug}.md`, from
[`_template.md`](_template.md). A human applies it, `make probe` gates it, and
the commit cites the incident that motivated it.

**This directory is committed and is not loaded by anything.** Nothing in here
affects a running session; a proposal is a document, not a configuration.

## The direction decides the handling

| Direction | Handling |
|---|---|
| Add a DENY, or tighten one | Can ship the same session, once a probe case passes |
| Narrow or remove a DENY | **Never in the session that asked for it.** Human only, with a commit citing the incident |

Incident time is when the most persuasive case for loosening a rule gets
written, and when you are least able to judge it. If an irreversible command
genuinely has to run right now, the answer is not a rule change — it is that a
human types the command. See [`docs/guardrails.md`](../../docs/guardrails.md)
§6.

## Rejected proposals stay

A proposal that was turned down is worth as much as one that shipped: it
records a rule that looked wrong and was not. Mark the outcome in the file
rather than deleting it.

## Expect traffic here

The ruleset has never run on a live Silverblue machine. Rules written against
paths that do not yet exist will be wrong in ways no amount of reading catches,
and the answer to that is a cheap recorded change loop — not a mutable ruleset.

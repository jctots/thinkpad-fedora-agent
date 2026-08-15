<!--
Template: .claude/proposals/P{nnn}-{slug}.md
Use: one file per proposed change to _ruleset.py or settings.json.
P### increments from the highest existing file; slug is kebab-case.
The agent writes this. A human applies it, runs `make probe`, and commits.
-->

## P{nnn} — YYYY-MM-DD — {What the rule should do}

**Direction:** tighten (add or widen a DENY) | loosen (narrow or remove a DENY)

> Loosening never ships in the session that asked for it. If something
> irreversible has to run now, say so and let the human type the command.

**Motivating incident:** `I{nnn}` — or the command that was blocked or allowed
and should not have been. Exact text, not a description.

**What happens today:** the verdict the current ruleset gives, from
`make check CMD='…'`. Not what you expect it to give — what it actually
printed.

**What should happen, and why:** name the reversibility layer. For a tighten:
which layer would have to undo this, and why it cannot. For a loosen: which
layer *does* cover it, and the evidence that it does — a rollback that worked, an
`etckeeper` commit, a restore that was tested.

**Proposed diff:**

```diff
```

**Probe case that fails today:**

```bash
make check CMD='…' EXPECT=deny
```

Paste the failing output. A proposal without a case that fails before and passes
after is not a proposal — the case is how anyone knows the change did what it
claimed.

**Blast radius:** what else the new pattern matches. Run the existing suite
against it and say whether anything that used to be ASK is now DENY, or the
reverse. This is the field that catches over-broad regexes.

**Outcome:** applied YYYY-MM-DD | rejected — reason | open

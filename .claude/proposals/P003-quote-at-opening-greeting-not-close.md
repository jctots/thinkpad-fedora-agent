<!--
Template: .claude/proposals/P{nnn}-{slug}.md
Use: one file per proposed change to _ruleset.py or settings.json.
P### increments from the highest existing file; slug is kebab-case.
The agent writes this. A human applies it, runs `make probe`, and commits.
-->

## P003 — 2026-08-17 — Show the quote in the opening greeting, not at session close

**Direction:** not a ruleset/permission change — a behavior change to
`.claude/hooks/session-start-greeting.sh`. Filed here anyway because that
file sits under `Edit(.claude/hooks/**)`, which is deny-listed to me on both
the Edit path and the shell path per CLAUDE.md, same as a ruleset edit
would be.

**Motivating incident:** none — a direct user correction this session. I
gave a plain no-quote greeting after reboot with no pending handover; user's
expectation was greeting + quote together at the open, not the quote held
back for the close message (`end-session` skill).

**What happens today:** `session-start-greeting.sh`'s no-handover branch
sets:

```
context="This is a fresh session with no pending handover. A plain greeting as the thinkpad-fedora agent is appropriate, asking what to do. Suggested closing quote: $quote"
```

`additionalContext` says "closing quote" — I correctly read that as
"hold this for later" and produced a bare greeting. Confirmed live this
session: greeting rendered with no quote.

**What should happen, and why:** for the no-handover branch specifically,
the quote should be presented as part of the opening greeting, not deferred.
This is a wording/intent change to the injected context string, not a
security-relevant one — no reversibility layer is implicated (pure
`/var/home` repo file, covered by this repo's own git history same as any
other tracked change).

The handover-present branch is unaffected — leave "Suggested closing quote"
there, since that path already carries a substantive resume narration and
tacking a quote onto the front of it is more clutter than value; only
raised here if the user wants it changed too.

**Proposed diff:**

```diff
--- a/.claude/hooks/session-start-greeting.sh
+++ b/.claude/hooks/session-start-greeting.sh
@@
 else
-  context="This is a fresh session with no pending handover. A plain greeting as the thinkpad-fedora agent is appropriate, asking what to do. Suggested closing quote: $quote"
+  context="This is a fresh session with no pending handover. Greet as the thinkpad-fedora agent, ask what to do, and close the greeting with this quote: $quote"
 fi
```

**Probe case that fails today:**

Not a `make check` permission probe — this hook has no CLI-testable verdict
via that harness. The manual probe: start a session with no
`.claude/handover.md` present and confirm the rendered opening greeting
includes a quote line. Today's transcript (this session) is the failing
case: greeting rendered, no quote attached.

**Blast radius:** touches only the no-handover branch's `context` string in
one hook file. No permission rules, no other branch, no other script.

**Outcome:** superseded — the hook this proposal targets is being removed
entirely (see `incidents/I010`, `P004`). The no-handover branch no longer
exists to carry a quote at all; the user decided the greeting/quote
mechanism isn't worth trying to make proactive-turn-only and dropped it.

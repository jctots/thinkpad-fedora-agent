<!--
Template: .claude/proposals/P{nnn}-{slug}.md
Use: one file per proposed change to _ruleset.py or settings.json.
P### increments from the highest existing file; slug is kebab-case.
The agent writes this. A human applies it, runs `make probe`, and commits.
-->

## P005 — 2026-08-17/18 — Let a verified fingerprint stand in for Claude Code's own approval click, for `sudo`/`pkexec` only

**Direction:** loosen (`bash-guard.py` gains a new `ALLOW` path it did not
have before, for one narrow command class).

> Reviewed and implemented across two sessions with the human directing the
> design at every step (2026-08-18) — this was not applied unreviewed. See
> "Design history" below for what changed from the first draft and why.

**Motivating incident:** `incidents/I011`, `incidents/I012`. Both record
that `sudo <cmd>` (fingerprint path) and `pkexec <cmd>` (password
fallback) already require the human to physically authenticate — fingerprint
touch or password entry — as a *second*, independent gate after Claude
Code's own approval click. A verified fingerprint identifies the specific
person; a click only proves someone has mouse access to the session. The
question: for this command class, is the click adding a distinct signal, or
asking the same person to confirm the same intent twice?

**Final design — two independent touches, not one:**

1. **Gate #1 (new, this proposal): the click, replaced.** `bash-guard.py`'s
   existing `ASK` dispatch, on a match, now calls `fingerprint_gate(cmd)`
   before falling to the normal `ask()` prompt. That function:
   - re-checks the command is literally a bare `sudo `/`pkexec ` prefix
     (the `ASK` patterns are substring searches over the whole command, so
     `cd /tmp && sudo …` still reaches `ASK`; fingerprint standing in for
     approval needs the plain form actually shown, not a fragment of
     something longer)
   - `notify-send -u critical` showing the exact command
   - `fprintd-verify`, bounded by a timeout
   - `gdbus … CloseNotification` regardless of outcome
   - on a clean `verify-match`: returns `True` → `bash-guard.py` emits
     `permissionDecision: allow`, skipping Claude Code's prompt entirely
   - on anything else (no-match, timeout, missing binary, no D-Bus session):
     returns `False` → falls through to the existing `ask()` call, unchanged
2. **Gate #2 (unchanged, already live): sudo/pkexec's own PAM auth.**
   Untouched by this change. When the actual `sudo <cmd>` executes, PAM/
   `fprintd` still gates it independently, per I011/I012. This proposal
   does not call `sudo -v` or otherwise try to collapse the two touches
   into one — two independent fingerprint actions for one privileged
   command was accepted as fine, in exchange for a much simpler mechanism.

**Design history — what changed from the first draft, and why:**

- *First draft* sketched a brand-new `PreToolUse` hook, matched separately
  to `Bash(sudo:*)|Bash(pkexec:*)`, competing with `bash-guard.py`'s
  existing match on plain `Bash`. **Rejected**: Claude Code's docs do not
  specify how two matching `PreToolUse` hooks' conflicting decisions merge
  for one tool call, and the likely unstated behavior (most-restrictive-
  wins) would mean `bash-guard.py`'s own `ask` — which already fires for
  every `sudo`/`pkexec` command via `_ruleset.py`'s `ASK` list — silently
  wins over a competing hook's `allow`, defeating the whole point. Fixed by
  making the decision inline, in `bash-guard.py` itself: one decision
  point, no merge ambiguity.
- *First draft* also included a `sudo -v` warm-up in the hook, intended to
  authenticate once and let the real command ride sudo's credential
  timestamp cache — avoiding a second touch. **Rejected on review**: sudo's
  cache doesn't distinguish *which* command was approved — a second,
  unrelated `sudo` call within the cache window (5–15 min by default) would
  pass gate #1 silently, no touch at all, on a credential warmed by a
  *different* command's approval. That defeats "one touch per command",
  which was the actual goal. Simplified instead to accepting two
  independent touches per privileged command — gate #1 authenticates
  nothing about the command's execution, only replaces the click; gate #2
  (sudo/pkexec's own PAM step) is untouched and still fires normally.
- Classified as a **harness change**, not a rule change (`_ruleset.py`
  edits are data — patterns fed to an unchanged decision loop; this adds a
  new conditional branch with external side effects and new failure modes
  to `bash-guard.py` itself) — see `VENDOR.md`'s stricter policy for harness
  edits. Implemented from a session outside this repo (the vault), the same
  path D31 and the `SessionStart` hook fix used, with the human directing
  and reviewing every step of the design in that session before the code
  was written — the review this project's proposal process asks for
  happened in conversation, not after the fact.

**Why this isn't the auto-approve mode `settings.json`'s header rules
out:** that line means no tool call proceeds with *no* live human action at
the moment of the call. That invariant is preserved, not removed — every
`sudo`/`pkexec` call still blocks on a synchronous, real-time authentication
event (in fact two, independently) before it runs. What changed is only
*which* mechanism Claude Code uses to collect that authorization for gate
#1: an external, biometric-mediated touch instead of a click inside its own
UI — arguably stronger evidence of consent, not weaker.

**Known residual gap, accepted as-is:** the OS-level PAM/polkit prompt
gate #1's `fprintd-verify` call and gate #2's real auth are each generic —
neither cryptographically binds the fingerprint touch to the specific
command text you read a moment earlier in the terminal. The `notify-send`
in gate #1 does display the exact command, which is the mitigation; nothing
stronger than "read it, then touch, in that order" enforces the binding.
Named and accepted, not solved.

**Probe suite:** `test/probe` now exports `CLAUDE_HOOK_PROBE=1` when
invoking the hook, which `fingerprint_gate()` checks first and returns
`False` on unconditionally — the suite's `sudo`/`pkexec` `ASK` cases land on
`ASK` exactly as before, non-interactively, in CI or without hardware. This
can only ever suppress the `ALLOW` path, never produce one, so it cannot be
used to weaken a verdict. `make probe` run 2026-08-18: all cases match,
unchanged. This resolves the gap the first draft flagged (no verdict type
for a runtime-conditional check) without needing a new verdict type — the
static suite simply can't and doesn't try to exercise the live fingerprint
path; that path is verified by hand, on the machine.

**Blast radius:** `.claude/hooks/bash-guard.py` (new `fingerprint_gate()`
and `allow()` functions, one new branch in `main()`'s `ASK` dispatch),
`test/probe` (one env var added to `evaluate()`). `settings.json`'s
`permissions.ask` entries for `sudo`/`pkexec` are untouched and stay as the
documented second layer. Does not touch `_ruleset.py`'s `DENY` logic, the
`DENY` dispatch, or any other command class.

**Verification done:** `make probe` — all 33 acceptance cases pass
unchanged. Manual invocation of the hook against `sudo whoami` outside probe
mode, in a session with no notification/D-Bus infrastructure present, fails
closed to `ASK` in ~0.1s (no hang).

**Verification still needed, on the real machine, by a human:** a live
`sudo <cmd>` from an actual Claude Code session, confirming the
`notify-send` fires, a real fingerprint touch produces `allow` and skips the
click, a withheld/wrong touch falls through to the normal click, and gate #2
(sudo's own PAM prompt) still fires independently afterward on the real
execution.

**Outcome:** implemented, then live-tested 2026-08-18 and found **blocked —
the mechanism cannot achieve its stated goal.**

**Live test result:** on a real `sudo whoami` from an actual Claude Code
session, the sequence observed was: `notify-send` fires → fingerprint touch
→ gate #1 (`fprintd-verify` inside the hook) succeeds → **the interactive
approval dialog still appears** → human clicks yes → sudo's own PAM step
(gate #2) asks for a second, separate touch, with no notification of its
own → command runs. Three factors fired (touch, click, touch), not the two
independent touches the design intended to replace the click with.

**Root cause, confirmed against Claude Code's own hooks documentation**
(`https://code.claude.com/docs/en/hooks`, "PreToolUse decision control"):
a `PreToolUse` hook's `permissionDecision: "allow"` overrides the
`permissions.ask` *rule verdict*, but does **not** suppress the interactive
confirmation dialog in **Manual mode** — only in **Auto mode** does an
`allow` decision skip user interaction entirely. This session (and this
project, as a matter of policy) runs in Manual mode: CLAUDE.md's "Working
rules" say plainly, *"Never propose an auto-approve permission mode for
host-level work."* Auto mode is the only mode where the mechanism this
proposal built would work, and it is permanently off the table here. The
premise — "a verified touch can stand in for Claude Code's own click" — was
false for this project's permission mode from the start; this was not
discoverable by reading the docs section that was actually consulted during
design (it undersells the Manual/Auto distinction), only by testing live.

**Disposition:** superseded. `fingerprint_gate()` and `allow()` in
`bash-guard.py`, and the `CLAUDE_HOOK_PROBE` plumbing in `test/probe`, add a
new external dependency (`notify-send`, `fprintd-verify`, `gdbus`), a new
failure mode (the cold-start race observed during testing — see below), and
meaningful code surface, for zero net reduction in required human actions:
gate #1's touch is pure overhead on top of the click it was meant to
replace, since the click still fires regardless. Recommend reverting the
`bash-guard.py` and `test/probe` diffs entirely on the next session that
touches `.claude/hooks/` — flagged here rather than done directly, since
`.claude/hooks/` is denied to the agent on both the Edit and shell path.

**Secondary finding, worth keeping if any future proposal revisits this
area:** during testing, `fprintd.service` was observed cold-starting
(`Starting fprintd.service...` in the journal) coincident with the first
touch of a session; a verify attempt racing that cold start appears able to
silently fail and fall through to `ask()` (caught by `fingerprint_gate()`'s
blanket `except`), consuming a touch with no visible feedback that it
didn't count. Not chased further since the proposal is superseded on the
Manual-mode finding alone, but relevant if fprintd-based gating is
attempted again elsewhere.

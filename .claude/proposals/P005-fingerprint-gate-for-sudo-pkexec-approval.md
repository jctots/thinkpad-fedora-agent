<!--
Template: .claude/proposals/P{nnn}-{slug}.md
Use: one file per proposed change to _ruleset.py or settings.json.
P### increments from the highest existing file; slug is kebab-case.
The agent writes this. A human applies it, runs `make probe`, and commits.
-->

## P005 — 2026-08-17 — Let a verified fingerprint stand in for Claude Code's own approval click, for `sudo`/`pkexec` only

**Direction:** loosen (a `PreToolUse` hook would auto-decide `allow` for a
matched command instead of surfacing Claude Code's interactive approval
prompt).

> Loosening never ships in the session that asked for it. Filed here for
> review; not applied.

**Motivating incident:** `incidents/I011`, `incidents/I012`. Both record
that `sudo <cmd>` (fingerprint path) and `pkexec <cmd>` (password
fallback) already require the human to physically authenticate —
fingerprint touch or password entry — as a *second*, independent gate
after Claude Code's own approval click. The question that came up live
this session: since a fingerprint identifies the specific person (not
just "someone at the keyboard," which is all a keypress proves), is the
first gate still adding anything for this specific command class, or is
it asking the same yes/no twice?

**What happens today:** `sudo:*` and `pkexec:*` are both in
`permissions.ask` in `.claude/settings.json` — every call surfaces Claude
Code's interactive prompt, then (if approved) the command itself still
requires fingerprint or password via PAM/polkit. Two prompts, two
distinct actions, for one decision.

**What should happen, and why — the case for:** A verified fingerprint is
strictly stronger evidence of "the specific authorized person consented"
than a keypress is. For this narrow command class (`sudo`/`pkexec`,
already singled out in `permissions.ask`), the fingerprint step is not
optional or skippable — it's real authentication happening regardless.
Requiring the Claude Code click *in addition* doesn't add a distinct
signal, it just asks the same person to confirm the same intent twice.

**The case against — read this before applying:** `.claude/settings.json`
states, in its own header comment, "There is no auto-approve mode here
and there must never be one. Default (manual) mode is the arrangement
that makes real privilege affordable." A `PreToolUse` hook that returns an
`allow` decision for a matched command *is* an auto-approve mode from
Claude Code's perspective — it bypasses the interactive prompt
programmatically, the same mechanism an unconditional auto-approve would
use, just gated on a condition (fingerprint success) instead of always
firing. The distinction — "gated auto-approve keyed to a real biometric
check" vs. "the thing this file says must never exist" — is a judgment
call for whoever applies this, not something I can resolve by writing the
diff more carefully. If the fingerprint check has a bug (wrong exit-code
handling, a race, a spoofable fallback path), the failure mode is a
silent `allow` with no interactive prompt at all, which is a different
risk shape than today's belt-and-suspenders double gate.

**Proposed diff (illustrative — verify the `PreToolUse` hook JSON schema
against current Claude Code docs before applying; `permissionDecision`
field name/values may have changed):**

```diff
--- a/.claude/settings.json
+++ b/.claude/settings.json
@@
     "PreToolUse": [
       {
         "matcher": "Bash",
         "hooks": [
           {
             "type": "command",
             "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/bash-guard.py\"",
             "statusMessage": "Checking reversibility"
           }
+        ]
+      },
+      {
+        "matcher": "Bash(sudo:*)|Bash(pkexec:*)",
+        "hooks": [
+          {
+            "type": "command",
+            "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/fingerprint-gate.py\"",
+            "statusMessage": "Waiting for fingerprint"
+          }
         ]
       }
     ],
```

New `.claude/hooks/fingerprint-gate.py` (sketch, not final):
1. Read the tool-call JSON on stdin; confirm the command actually starts
   with `sudo ` or `pkexec ` (don't trust the matcher alone — same
   prefix-glob caveat `bash-guard.py`'s own comments already call out).
2. `notify-send -u critical -i fingerprint -p "Claude Code" "Place your
   finger to approve: <command>"` — show the real command in the
   notification body, not a generic message, so the fingerprint really is
   informed consent.
3. Run `fprintd-verify` with a bounded timeout.
4. Close the notification (`gdbus … CloseNotification`) regardless of
   outcome.
5. On verify-match: emit the JSON that signals `allow` for this
   `PreToolUse` call (bypasses the interactive prompt). On anything else
   (no-match, timeout, error): emit nothing / fall through to the normal
   `ask` prompt — never emit `deny` on a hook-level failure, since that
   would block a command the human might still want to approve by hand.

**Probe case that fails today:**

```bash
make check CMD='sudo whoami' EXPECT=ask
```
Today: `ask` (Claude Code prompt), independent of any fingerprint. After
this change, applied and working: the interactive prompt is skipped when
`fprintd-verify` succeeds; `make check`'s static verdict would need a new
test mode to express "conditionally allow" rather than a fixed verdict,
since the real behavior now depends on a runtime biometric check the
static ruleset can't evaluate. That gap — `_ruleset.py` has no concept of
a runtime-conditional verdict — needs a decision before this ships: either
extend the ruleset's verdict type, or accept that `make check` can no
longer fully characterize `sudo`/`pkexec` behavior and say so in its
output.

**Blast radius:** `.claude/settings.json` (`permissions.ask` entries for
`sudo`/`pkexec` become moot in the success path but should stay listed as
the fallback), one new hook file. Does not touch `bash-guard.py`,
`_ruleset.py`'s DENY logic, or any other command class — scoped
deliberately to the two prefixes already singled out in `permissions.ask`
for this reason.

**Outcome:** open.

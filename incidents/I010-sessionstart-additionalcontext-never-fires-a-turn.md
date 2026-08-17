## I010 — 2026-08-17 — SessionStart hook's silent greeting never appears before the user types anything

**Area:** agent

**Symptom:** After I009 shipped, a fresh session showed no greeting or quote
until the user typed a message first — at which point the greeting appeared
tacked onto the reply to that message, not as a standalone first turn. User
report: "this is weird. i am expecting that the first turn will be the
agent, without my input first," with a pasted transcript showing exactly
that ordering.

**Cause:** I009 mis-verified its own fix. `hookSpecificOutput.additionalContext`
from a `SessionStart` hook is a purely passive context-injection channel —
the same one CLAUDE.md uses. It has no ability to trigger an API call or an
assistant turn on its own; Claude Code's interactive REPL only calls the
model when the user submits a prompt. Confirmed against the Claude Code
hooks docs (`claude-code-guide` agent, citing the hooks guide directly):
additionalContext is described as being "added ... to Claude's context,"
and the docs themselves recommend CLAUDE.md instead of SessionStart for
this exact use case — which would be redundant advice if SessionStart could
fire a turn. I009's incident file claimed "the greeting came through as
clean additionalContext" as confirmation the design worked end to end; that
observation was real, but its interpretation — that this counted as a
proactive first turn — was not checked against what the terminal actually
showed at that moment, and was wrong.

**Fix:** No supported Claude Code mechanism gives a silent,
non-user-authored proactive first turn in interactive mode (confirmed via
docs and corroborated by open upstream issues, notably
anthropics/claude-code#69750 — a feature request for exactly this,
proposing an `autoPrompt` hook field, not shipped). Given that, the user
chose to embrace a visible triggered turn rather than route around it:

`scripts/session-autostart.sh` now unconditionally launches
`claude "I'm back"` on every startup — no filesystem check in bash at all.
`.claude/skills/handover/SKILL.md`'s read-mode section does the branching
once the model is running: if `.claude/handover.md` exists, rename it to
`.claude/handover.consumed.md` and resume from it; if not, give a plain
greeting closed with a quote from `scripts/quotes.txt`
(`shuf -n1`, zero tokens). This is simpler than I009's hook-based design —
one code path instead of a hook plus two script branches — and it's the
"embrace the constraint" option rather than trying to defeat it.

The now-dead `.claude/hooks/session-start-greeting.sh` and its
`hooks.SessionStart` entry in `.claude/settings.json` are queued for
removal in `.claude/proposals/P004-remove-sessionstart-greeting-hook.md`
(both paths are deny-listed to the agent; a human applies it).

**Tried first:** Nothing new tried this session — this incident is a
correction of I009's verification, surfaced by the user's report rather
than by re-testing before claiming done.

**Reversibility:** `/var/home` repo state only, covered by this repo's git
history. No system-level change.

**Captured in:** `scripts/session-autostart.sh`,
`.claude/skills/handover/SKILL.md`, `scripts/quotes.txt` (recreated —
the original was accidentally deleted mid-session while options were
still being weighed, no backup existed since it was untracked; replaced
with a fresh systems-thinking-themed list per the user). Pending human
action: `.claude/proposals/P004-remove-sessionstart-greeting-hook.md`.

**Tally:** time-to-fix ~30m end to end (root cause via docs check ~5m,
design iteration + rewrite ~25m) · first proposal (I009): ✗ wrong —
verified against the wrong observation and shipped a design that cannot do
what it was built for. Recording this as I009's actual outcome per
CLAUDE.md's rule to log misses, not just hits. This incident's own first
proposal (delete the greeting mechanism outright) was also revised
mid-session after the user pushed back and asked to try the unconditional
visible-trigger approach instead — a second, smaller miss worth naming
rather than smoothing over.

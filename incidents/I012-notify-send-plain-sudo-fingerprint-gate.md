<!--
Template: incidents/I{nnn}-{slug}.md
Use: one file per incident. I### increments from incidents/index.md; slug is kebab-case.
After writing: add a row to incidents/index.md (newest first).
-->

## I012 — 2026-08-17 — Agent had no live cue to touch the fingerprint reader; notify-send + plain sudo is the fix

**Area:** agent

**Symptom:** Following I011's `pkexec` fix, the human had no way to know
*when* to place a finger on the reader — the PAM "place your finger"
message only appears in the agent's Bash tool output, which is captured
and returned after the command finishes, not streamed live to the screen.
In practice the human had to guess and pre-emptively touch the sensor
before running a command, which worked by luck but wasn't a real signal.

**Cause:** No desktop notification was fired before the blocking auth
call, so there was no on-screen cue timed to when the prompt actually
needed a touch. Separately, I011's diagnosis (that no controlling TTY
blocks *all* `sudo` prompting, fingerprint included) was too broad — see
correction added to I011.

**Fix:** Two-part pattern, verified end-to-end with a positive and a
negative control:

1. `NID=$(notify-send -u critical -i fingerprint -p "Claude Code" "Place
   your finger now")` fires a real GNOME banner *before* the blocking
   call, giving a correctly-timed cue. `-p` prints the notification ID.
2. Plain `sudo <cmd>` (no `-A`, no askpass, no `pkexec`) then blocks on
   the fingerprint step directly — confirmed genuinely gated, not cached:
   told to withhold a touch, it timed out and failed
   (`sudo: a password is required`, non-zero exit) rather than silently
   succeeding.
3. `gdbus call --session --dest org.freedesktop.Notifications
   --object-path /org/freedesktop/Notifications --method
   org.freedesktop.Notifications.CloseNotification "$NID"` clears the
   banner right after, instead of leaving it to be dismissed by hand.

`pkexec <cmd>` (I011) remains the fallback specifically for the *password*
path, since that genuinely does need a TTY-equivalent — its GUI dialog —
which plain `sudo` doesn't have without one.

**Tried first:** `notify-send` + `fprintd-verify` (a separate,
privilege-free confirm-only check) paired with `pkexec` doing the actual
privileged run — proposed as a way to decouple "did the human consent" from
"does this need root." Technically sound and still useful for
non-privileged approval-only cases, but heavier than necessary once it
turned out plain `sudo` already blocks correctly on fingerprint without
any TTY workaround at all — the notify-send heads-up was the only missing
piece, not a new auth primitive.

**Reversibility:** None needed — no system state was changed; this is a
command pattern, not an install.

**Captured in:** not yet — still a one-off pattern: `notify-send -p` →
`sudo <cmd>` (fingerprint) or `pkexec <cmd>` (password fallback) →
`gdbus ... CloseNotification`.

**Tally:** time-to-fix ~25m (same session as I011) · first proposal: right

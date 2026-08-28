## I029 — 2026-08-27 — tb-bridge.service down, missing env file also broke Betterbird's taskbar launch

**Area:** agent

**Symptom:** User reported Betterbird wouldn't launch from the GNOME taskbar icon
(worked fine when run directly via `flatpak run eu.betterbird.Betterbird`).
Investigating the taskbar path found `~/.local/bin/betterbird-with-bridge`
(the `.desktop` override's `Exec=`) failing silently: `systemctl --user start
tb-bridge.service` errored with `Failed to load environment files: No such
file or directory`, and `set -euo pipefail` aborted the whole wrapper before
Betterbird ever ran. `journalctl --user -xeu tb-bridge.service` showed
`EnvironmentFile=%h/.config/thunderbird-cli/bridge-daemon.env` pointed at a
path where the entire `~/.config/thunderbird-cli/` directory was gone —
`Restart=on-failure` had it crash-looping (restart counter in the 30s) by
the time this was noticed.

**Cause:** `bridge-daemon.env` (holding `TB_AUTH_TOKEN`) never had a backup
per D39 — it's designed to live in exactly one place. The directory was
missing on the host entirely; root cause of *why* it disappeared wasn't
determined (second-brain agent's containerization was checked and ruled out
— its container only reaches tb-bridge over the network per D148/D162, no
host volume mount involved). Separately, the launch wrapper had no
resilience to a bridge failure: mail access shouldn't depend on the bridge
being up.

**Fix:** Two independent fixes, one per layer:
1. Wrapper resilience (this session, immediately): changed
   `systemctl --user start tb-bridge.service` to
   `systemctl --user start tb-bridge.service || true` in
   `~/.local/bin/betterbird-with-bridge` so a bridge failure no longer blocks
   Betterbird's own launch.
2. Credential restore (via handover from second-brain agent, which is
   structurally blocked from touching this file by its own `env-guard.py`):
   ```
   mkdir -p ~/.config/thunderbird-cli
   echo "TB_AUTH_TOKEN=$(openssl rand -hex 32)" > ~/.config/thunderbird-cli/bridge-daemon.env
   chmod 600 ~/.config/thunderbird-cli/bridge-daemon.env
   systemctl --user restart tb-bridge.service
   ```
   Confirmed `active (running)`, bridge listening on `:7700`/`:7701`, auth
   enabled. Also sanity-checked `~/.npm-global/lib/node_modules/thunderbird-cli-bridge/`
   is still a real self-contained directory, not a symlink into a source
   clone.

**Tried first:** Initially launched Betterbird directly with `flatpak run`
to unblock the user immediately — that worked and masked the taskbar issue
until asked to reproduce it via the icon specifically. Direct launch bypasses
the `.desktop`/wrapper path entirely, so it never exercises the bridge-start
step — worth remembering next time "it works from the terminal but not the
icon" comes up on this machine.

**Reversibility:** `/var/home` layer — both the wrapper edit and the new env
file are plain home-directory files, trivially revertable/regeneratable.
Old token itself was not recoverable (by design, per D39 — a fresh token was
generated rather than restored).

**Captured in:** `~/.local/bin/betterbird-with-bridge` (edited directly;
not tracked in this repo — see thunderbird-cli-email-agent memory for where
this wrapper's design lives).

**Tally:** time-to-fix ~15m · first proposal: right

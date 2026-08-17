## I007 — 2026-08-17 — Ptyxis autostart + handover resume verified over reboot; duplicate window on login

**Area:** gnome

**Symptom:** Built `scripts/session-autostart.sh` plus a host-local
`~/.config/autostart/thinkpad-fedora-agent.desktop` entry to open a Ptyxis
window running Claude Code, resuming from `.claude/handover.md` if present.
Manual execution of the `Exec` line worked, but the actual GNOME
login/autostart path was untested. After the reboot, **two** Ptyxis windows
opened instead of one — one correctly running the autostart script and
resuming from the handover file, one extra.

**Cause:** `org.gnome.Ptyxis restore-session` was `true`. GNOME/Ptyxis's own
session restore reopens the window(s) open at last logout, independently of
and in addition to the autostart `.desktop` entry's own
`ptyxis --new-window -d ... -x "..."`. Two separate mechanisms were each
opening a window on login.

**Fix:**
```
gsettings set org.gnome.Ptyxis restore-session false
```

**Tried first:** Nothing wrong tried — `gsettings list-recursively
org.gnome.Ptyxis | grep -i restore` immediately showed `restore-session
true` alongside `restore-window-size true`, and disabling the former was
the direct fix. Worth noting because the two settings look similar enough to
mix up: `restore-window-size` (harmless, keeps window geometry) was not the
culprit.

**Reversibility:** none needed — reversible in place any time via
`gsettings set org.gnome.Ptyxis restore-session true` (dconf-level user
setting, no `/etc` or OS-image write involved).

**Captured in:** not yet — still a one-off `gsettings set`; `session-autostart.sh`
(committed) covers the autostart-resume half of this incident.

**Tally:** time-to-fix ~5m · first proposal: right

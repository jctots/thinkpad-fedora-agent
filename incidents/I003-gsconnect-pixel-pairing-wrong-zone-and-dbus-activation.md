## I003 — 2026-08-16 — GSConnect installed and firewall opened, but Pixel never showed up to pair

**Area:** gnome

**Symptom:** GSConnect extension installed (`Enabled: Yes`, `State: ACTIVE`
per `gnome-extensions info`), KDE Connect app installed on the paired Pixel
phone, both on the same Wi-Fi subnet — neither side ever saw the other in
its device list. `journalctl --user` showed repeated
`GSConnect: Gio.DBusError: The name is not activatable` and
`GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name is not
activatable`. `~/.config/gsconnect/` didn't exist at all — the backend
daemon had never started once, so no cert, no listener.

**Cause:** Two separate problems stacked:
1. The firewalld rule for the `kdeconnect` service was added to the
   `public` zone, but `firewall-cmd --get-active-zones` showed the Wi-Fi
   interface (`wlp0s20f3`) was actually in zone `FedoraWorkstation` — the
   rule never applied to live traffic.
2. Even after fixing the zone, pairing still failed: GSConnect's
   `~/.local/share/dbus-1/services/org.gnome.Shell.Extensions.GSConnect.service`
   file was present and correct (points at `daemon.js`, `gjs` present,
   executable bit set), but the session D-Bus bus never picked it up —
   it was dropped in by the extension install after the session bus had
   already started, and dbus-broker doesn't reliably re-scan its service
   directory for new files mid-session on Wayland. The daemon was never
   actually spawned, so the firewall was moot until this was fixed.

**Fix:** Logged out and back in (full GNOME Shell + session D-Bus restart).
After that, `~/.config/gsconnect/{certificate,private}.pem` appeared
(daemon finally started), and the Pixel paired within the same GSConnect
session — confirmed via
`dconf read /org/gnome/shell/extensions/gsconnect/devices`.

**Tried first:** Opened the firewalld `kdeconnect` service on the `public`
zone, reasoning that firewalld was the obvious blocker for LAN discovery
traffic. Plausible because `public` is firewalld's most common default
zone name and the service showed as active overall — but this machine's
NetworkManager connection profile puts the Wi-Fi interface in a custom
`FedoraWorkstation` zone instead, so the rule silently applied to a zone
nothing was actually using. Re-added to the correct zone next, which
*looked* like the fix but wasn't sufficient by itself — the D-Bus
activation issue was the actual blocker and only surfaced once `sudo`
calls were run with a real TTY (this session's own `sudo` calls kept
failing silently on a missing TTY, which separately produced a false
"etckeeper never initialized" reading from `scripts/etc-drift.sh` — see
that script's swallowed-stderr bug, not yet fixed).

**Reversibility:** `etckeeper` diff — the firewalld zone rule (both the
initial wrong-zone one and the corrected one) are `/etc` changes, committed
by etckeeper's daily autocommit (confirmed via `scripts/etc-drift.sh`,
commit `cb88e65`). The GSConnect extension itself lives under
`~/.local/share/gnome-shell/extensions/` and `~/.config/gsconnect/` —
`/var/home` layer, covered by backups. No OS-image layer involved.

**Captured in:** `/var/home/jcdedios/code/thinkpad-fedora-extras/gnome-extensions.sh`
(new entry for `gsconnect@andyholmes.github.io`) — the firewalld zone
lookup itself is not yet automated into any script; a future version of
that manifest could check `firewall-cmd --get-active-zones` instead of
assuming `public`.

**Tally:** time-to-fix ~45m · first proposal: wrong

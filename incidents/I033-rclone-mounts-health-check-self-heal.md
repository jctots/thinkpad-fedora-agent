## I033 — 2026-08-28 — No monitoring on the 3 rclone cloud mounts

**Area:** agent

**Symptom:** No standing check on `google-drive`, `one-drive`, `syno-drive` (systemd `--user` services `rclone-googledrive.service`/`rclone-onedrive.service`/`rclone-synology.service`, mounted at `~/data/*`). A dead or hung FUSE mount would only be noticed the next time someone tried to actually use one — same gap I029/I030 fixed for `tb-bridge`, never extended to these.

**Cause:** Not a bug — a genuine monitoring gap. These mounts are expected to be up whenever there's real internet, with no "normal absence" state to tolerate (unlike I032's phone mount, which is legitimately unmounted most of the day).

**Fix:** Added `thinkpad-fedora-extras/health-checks/rclone-mounts.sh`, picked up via the `EXTRAS_DIR/health-checks` hook built for I032. Gates the whole check on `nmcli networking connectivity check` reporting `full` — no alert when genuinely offline (plane, hotel captive portal, ISP outage), since that's not these mounts' fault. For each of the 3 mounts, checks `systemctl --user is-active`, `mountpoint -q`, and a 5s-timeout `ls` (catches a hung FUSE mount that's still nominally "active," not just a dead service). On a real problem, self-heals with `systemctl --user restart <service>` (safe, idempotent, `--user` scope, no root) before deciding whether to alert — matches the self-heal pattern from I032's `gsconnect-mount.sh`, per user preference to keep both extras checks consistent.

**Tried first:** Nothing wrong this time — one clarifying question (self-heal-and-alert vs. alert-only; chose self-heal to match the I032 precedent), then straight to a verified implementation, no false starts.

**Reversibility:** `/var/home` — the check script is a plain file in the extras repo; `systemctl --user restart` only touches user-scope services, no `/etc` or OS-image state.

**Captured in:** `thinkpad-fedora-extras/health-checks/rclone-mounts.sh`

**Tally:** time-to-fix ~20m · first proposal: right

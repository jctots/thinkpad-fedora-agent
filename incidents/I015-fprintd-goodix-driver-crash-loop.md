## I015 — 2026-08-19 — fprintd crashes repeatedly inside the Goodix TOD driver, stays dead (no restart policy)

**Area:** hardware

**Symptom:** User reported the fingerprint reader LED cycling blinking →
steady → blinking, alongside a repeated connect/disconnect chime (the
chime turned out to be unrelated — see below). Fingerprint unlock silently
unavailable. `systemctl status fprintd.service` showed `Active: failed
(Result: core-dump)` since this boot's start, with no further restart
attempts. `coredumpctl list` showed ~15 fprintd crashes (`SIGSEGV`/
`SIGABRT`) over the prior 3 days, most recently `11:45:20` the same boot as
a suspend hang ([[project_s2idle_resume_hang_investigation]] notes this
crash pattern too, unconnected so far).

**Cause:** `coredumpctl info` on one crash produced a fully symbolized
backtrace — the fault is inside the driver itself, not fprintd's own code:
```
#10 0x00007f7a782de4cc n/a (libfprint-tod-goodix-550a-0.0.9.so + 0x534cc)
```
in a `libusb_bulk_transfer` call chain. This is a bug in the
`libfprint-tod-goodix-0.0.9-1.fc44` package (from copr
`antiderivative/libfprint-tod-goodix-0.0.9`), not in this repo's config.
Checked that copr repo for a newer build — its metadata hasn't changed
since 2026-03-19, so no fix is available upstream right now.

Separately diagnosed in the same session: the connect/disconnect **sound**
the user heard was not this bug at all — `udevadm monitor` showed the
USB-C `port0-partner` (charger PD partner) repeatedly `add`/`remove`ing
every 1-2s in lockstep with `AC`/`BAT0` power-supply change events, i.e. a
physical charger-cable/port contact issue, unrelated to the fingerprint
reader. Not further investigated this session — no evidence yet on cable
vs. port; flag if it recurs.

**Fix:** No real fix available (upstream driver bug, no newer package).
Applied a mitigation only: `fprintd.service` is `Type=dbus`,
D-Bus-activated, with no restart policy of its own, so a crash left it
dead indefinitely instead of just failing until the next D-Bus activation.
Added a drop-in:
```
# /etc/systemd/system/fprintd.service.d/override.conf
[Service]
Restart=on-failure
RestartSec=2
Environment=G_MESSAGES_DEBUG=all
```
`pkexec systemctl daemon-reload`, then `pkexec systemctl reset-failed
fprintd.service && pkexec systemctl start fprintd.service` to bring it
back up immediately. This restores fingerprint auth after each crash
instead of leaving it dead for weeks, and the added `G_MESSAGES_DEBUG=all`
gives richer glib logging context ahead of the next crash.

**Tried first:** Checked whether a newer `libfprint-tod-goodix` build
existed in the copr repo before reaching for a restart-policy mitigation —
it doesn't (repo metadata frozen since March). Confirmed
`rpm -q libfprint2 libfprint2-tod-goodix` reports "not installed" — the
actual installed package is named `libfprint-tod-goodix` (no `2`), a naming
trap worth remembering if searching for it again.

**Reversibility:** `etckeeper` — plain `/etc` drop-in, committed
(`b217fa7`). Fully reversible: `pkexec rm
/etc/systemd/system/fprintd.service.d/override.conf && pkexec systemctl
daemon-reload && pkexec etckeeper commit "..."`.

**Captured in:** `hosts/thinkpad-e14-gen5/quirks.sh` (drift check for the
override, same case-specific-escalation pattern as the s2idle block).

**Update, same day:** user found and fixed a loose charger cable — the
connect/disconnect sound and the fingerprint LED's blink/steady/blink
cycle were both explained by the USB-C `port0-partner` flapping identified
above, not the fprintd bug. Open question, not yet confirmed: the same
power fluctuation could plausibly have been *triggering* the fprintd
crashes too (fits the `libusb_bulk_transfer` fault site). Decided to leave
both the `Restart=on-failure` and the `G_MESSAGES_DEBUG=all` mitigation in
place for now rather than reverting — a clean run with no further fprintd
crashes post-cable-fix would be the confirming signal; a recurrence with
the cable solid would rule the cable theory out and point back at the
driver itself. `Restart=on-failure` should stay permanently either way;
the verbose logging is the only part to reconsider dropping once there's
a few days of evidence either way.

**Tally:** time-to-fix ~30m (mitigation applied; root cause still open,
possibly the same loose cable — unconfirmed) · first proposal: ✓ right
(one syntax fix needed — `tee` failed because
`fprintd.service.d/` didn't exist yet, `mkdir -p` first fixed it; the
diagnosis and mitigation approach itself was correct on the first pass)

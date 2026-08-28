## I035 — 2026-08-28 — Logitech Unifying receiver: Solaar couldn't see device, then cursor didn't move after pairing

**Area:** hardware

**Symptom:** Flatpak Solaar (`io.github.pwr_solaar.solaar`) couldn't see an
already-enumerated Logitech Unifying receiver (046d:c52b, bound via
`logitech-djreceiver`). After fixing that and pairing an Ergo M575
trackball, `pkexec libinput debug-events` showed clean `POINTER_MOTION`
events matching physical movement, but the GNOME cursor never moved on
screen.

**Cause:** Two independent causes, one per symptom:
1. Fedora's default `70-uaccess.rules` only grants hidraw uaccess to
   specific device classes (AV controllers, lights, hardware wallets, 3D
   mice) — not generic Logitech receivers. The RPM `solaar` package
   normally ships its own udev rule granting this; installing via Flatpak
   instead skipped that rule, so `/dev/hidraw*` stayed `root:root 0600`
   with no ACL even though the Flatpak's `devices=all` permission got past
   the sandbox itself.
2. Solaar's software pairing of the M575 added a new hidraw+event child
   node under the receiver's already-enumerated USB interface. Mutter's
   udev listener didn't hot-add this new child device — a known class of
   issue where a session restart is needed for GNOME Shell to pick up a
   new evdev node appearing under an interface it already knew about.

**Fix:**
1. `/etc/udev/rules.d/42-logitech-unify-permissions.rules`:
   `TAG+="uaccess"` scoped to `idVendor==046d`, written via `pkexec install`,
   `udevadm control --reload-rules && udevadm trigger`.
2. Log out/reboot to restart the GNOME session — confirmed working after
   the reboot that also carried the `gpu-toggle.sh nvidia` mode switch
   (I034).

**Tried first:** Nothing ruled out before the udev rule — the hidraw
permission gap was identified directly from `ls -l /dev/hidraw*` plus
knowledge of Fedora's uaccess rule scope, confirmed correct on the first
try. The libinput-level check (`pkexec libinput debug-events`) was used
deliberately to bisect the problem — it confirmed kernel/driver/permissions
were all fine and narrowed the remaining cursor-not-moving symptom to the
compositor layer before proposing the session-restart fix, rather than
guessing at GNOME Settings or config causes first.

**Reversibility:** `etckeeper` diff — the udev rule lives under `/etc`,
committed (`5c45f90`), confirmed clean via `scripts/etc-drift.sh`.

**Captured in:** not yet — still a one-off; worth folding the udev-uaccess
rule into `hosts/thinkpad-e14-gen5/quirks.sh` if a second Unifying receiver
or flatpak-only HID device shows the same gap.

**Tally:** time-to-fix ~1h · first proposal: right

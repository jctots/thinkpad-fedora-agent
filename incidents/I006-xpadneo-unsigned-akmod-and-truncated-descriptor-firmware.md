## I006 — 2026-08-17 — Xbox Wireless Controller (BT) never worked: two stacked problems, only one of them the driver

**Area:** rpm-ostree

**Symptom:** Xbox Wireless Controller paired over Bluetooth but never became a usable
input device. `journalctl -k` showed:
```
hid-generic 0005:045E:02FD.0002: unbalanced collection at end of report description
hid-generic 0005:045E:02FD.0002: probe with driver hid-generic failed with error -22
```
Layering `akmod-xpadneo` and rebooting produced the same "unbalanced collection /
parse failed / probe failed -22" error, now from `xpadneo` instead of `hid-generic`,
plus (initially) `Loading of unsigned module is rejected` in `journalctl -k` — the
`%post` sandbox akmod build was unsigned despite an enrolled MOK, the same failure
mode as I004.

**Cause:** Two independent bugs stacked on top of each other:
1. **Signing** — identical root cause to I004: rpm-ostree's `%post` sandbox builds
   akmods unsigned. Same fix pattern applies (build + sign in a toolbox, install the
   resulting RPM as a `LocalPackage`).
2. **Firmware** — even after xpadneo was correctly built, signed, and loaded, it
   still failed to bind. Decoding the raw HID report descriptor
   (`debug_descriptor=1` module param) showed the controller's own Bluetooth
   firmware ships a **truncated descriptor**: two `Collection` items opened and
   never closed, descriptor cut off mid-item at byte 306 of a claimed 306-byte
   total. This is a firmware bug, not a Linux/driver bug — xpadneo's own log line
   said as much (`buggy firmware detected, please upgrade to the latest version`)
   and the upstream maintainer confirms in
   [atar-axis/xpadneo#100](https://github.com/atar-axis/xpadneo/issues/100) and
   [#407](https://github.com/atar-axis/xpadneo/issues/407) that this exact
   "unbalanced collection" signature is normally only fixed by updating the
   controller's firmware — no driver-side workaround exists, because the kernel
   HID core rejects the device (no `hidraw` node is even created) before any
   driver's `probe()` gets a chance to run.
   Confirmed by contrast: SteamOS itself has no fix for this either — Valve's own
   recent Steam Deck update only *detects and warns* about out-of-date Xbox
   controller BT firmware and points the user at the same Windows-only Xbox
   Accessories app fix.

**Fix:**
1. Signing — same recipe as I004: build `kmod-xpadneo` in the existing
   `fedora-toolbox-44` container with matching `kernel-devel`, sign with the
   enrolled MOK key, install the finished RPM as a pinned `LocalPackage`:
   ```
   sudo rpm-ostree uninstall akmod-xpadneo
   sudo rpm-ostree install /tmp/kmod-xpadneo-<kver>-0.10.2-1.fc44.x86_64.rpm
   sudo systemctl reboot
   ```
   **New finding beyond I004's writeup:** `akmods` internally does
   `runuser -s /bin/bash -c "...akmodsbuild..." akmods` — the actual compile+sign
   step runs as the **`akmods` system user** (home=`/var/cache/akmods`), not as
   root and not as the invoking user. `.rpmmacros` in `/root` or the invoking
   user's home is invisible to that step; it has to live in
   `/var/cache/akmods/.rpmmacros`, owned `akmods:akmods`, alongside copies of the
   signing key material there. This likely silently affected the I004 NVIDIA
   build too unless that was done differently — worth a cross-reference note in
   I004, not yet written.
2. Firmware — on a Windows 11 machine: install the **Xbox Accessories** app
   (Microsoft Store), connect the controller (USB preferred for the flash),
   apply the firmware update it offers, then re-pair over Bluetooth back on this
   machine. No further Linux-side change needed — `kmod-xpadneo` was already
   correctly installed and bound immediately once the descriptor was well-formed
   (`report descriptor: known checksum ... name 'Xbox Wireless Controller (modern)'`,
   `js0` created, rumble self-test ran, full button/axis map present).

**Tried first:** Layering `akmod-xpadneo` directly via `rpm-ostree install` and
rebooting — looked like the obvious first move (same shape as any other kernel
module) and is exactly what failed unsigned in I004, so it should have been ruled
out immediately by that precedent rather than re-attempted. After the signing fix
landed and the module loaded+bound with a valid signature, it still looked driver-side
(same error text as before, `xpadneo` in place of `hid-generic`) and cost real time
before the raw descriptor dump made clear the actual cause was upstream firmware, not
anything on this machine.

**Reversibility:** `rpm-ostree` — the `kmod-xpadneo` LocalPackage layering is a normal
`rpm-ostree rollback`-covered change, same as I004's `kmod-nvidia`. No `/etc` changes
were made. Controller firmware itself has no rollback — Xbox controller firmware
updates are one-directional — but it's a known-good vendor update, not a risk
specific to this fix.

**Captured in:** not yet — still a one-off. Candidate follow-up: cross-reference this
`.rpmmacros`-location finding into I004, and flag in
`hosts/thinkpad-e14-gen5/quirks.sh`/README that this host now carries **two**
kernel-version-pinned `kmod-*` packages (`kmod-nvidia`, `kmod-xpadneo`) needing
manual toolbox rebuild on every kernel bump — worth considering as its own decision
in the vault rather than two independent incidents, per CLAUDE.md's split.

**Tally:** time-to-fix ~4h across two sessions (akmod dead-end + toolbox
rebuild/signing + reboot ~3h, matching I004's pattern; raw-descriptor debugging +
firmware-update diagnosis ~1h) · first proposal: wrong — same unsigned-akmod dead
end as I004 was retried before the toolbox-signing fix was reached, and the signing
fix alone was not sufficient; the actual blocker (firmware) wasn't identified until
after that fix had already landed.

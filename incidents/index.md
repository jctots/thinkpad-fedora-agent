# Incidents — index

The why behind every non-obvious thing on this machine, written when it happens
rather than reconstructed later. One file per incident, newest first.

An incident is something that broke and this fixed it. A choice with
alternatives that were weighed is a decision, not an incident, and lives in the
vault. A fact about this particular machine — firmware strings, device IDs,
hardware support — belongs in `hosts/<slug>/`.

This index leads and `scripts/` follows. A script is what a set of incidents
becomes once the same problem has come up enough times to be worth automating.

## The tally

The columns below are the evidence for this project's central claim: that a
privileged agent plus reversibility makes a Linux desktop cheaper to live with
than maintaining it by hand. The claim is only falsifiable if the misses are
recorded as faithfully as the hits. **An index with no `✗` in the last column
is evidence of nothing except selective writing.**

An incident fixed by hand because the agent was unreachable — no network, a
usage limit, a broken session, an outage — still gets a row, with
`n/a — agent unavailable` in the first-proposal column. Those rows are not
noise. Availability is part of that cost, and a tally that silently drops the
times the agent could not help is measuring the arrangement on its best days.
`docs/recovery.md` is the path those entries come from.

| # | Date | Area | Symptom | Time to fix | 1st proposal right? | Captured in |
|---|---|---|---|---|---|---|
| [I027](I027-uart-tcpu-resume-hang-post-ec-no-wakeup.md) | 2026-08-25 | hardware | First suspend attempt after I026's `acpi.ec_no_wakeup=1` karg took effect: lid-close suspend never resumed — red LED and white power LED both stayed lit/pulsating, machine got very hot, unresponsive to power button, required a forced power-off. `journalctl -b -1` stops dead at `PM: suspend entry (s2idle)`, same shape as I021 but `pm_trace` points at a different device every occurrence (`UA01`/`TCPU`, `MSFT0101` TPM, `memory75`, `ttyS21`/`serial8250` — four hangs, four devices) — reads as a noisy device match, not a single culprit driver. `ec_intr=0` was tried as a fix candidate and hung on its very first lid-close soak. User's own hypothesis — revert both EC kargs entirely — was tried fourth and also hung on the first lid-close, falsifying that theory rather than confirming it: neither adding nor removing the EC kargs changes the outcome. Cause still open, four hangs, zero clean soaks at any karg state tried; reinstall/BIOS-downgrade is the next avenue, not another karg | not fixed yet | n/a — agent unavailable | `hosts/thinkpad-e14-gen5/suspend-repro-loop.sh` (`log_pm_snapshot`) |
| [I026](I026-spurious-wakeup-loop-battery-drain.md) | 2026-08-25 | hardware | Boot ended with an unclean shutdown, but not a hang — 38 suspend/resume cycles completed fine, then 9 rapid re-wake cycles in the final 6 minutes (spurious `ACPI Notify` wakeups every 30–90s) burned the battery until the hardware cut power outright. Root cause: EC GPE 0x6E battery-status Notify promoted to a wakeup reason during s2idle, introduced by the 2026-08-17 BIOS 1.42→1.43 update (traced via journal, zero occurrences before, present in every boot after). Fixed via `acpi.ec_no_wakeup=1` karg, persisted and verified across reboot. **Reopened 2026-08-25:** karg reverted as part of I027's workaround (wake-thrash traded back in exchange for working lid-close resume) — see I027. A more surgical alternative (masking just GPE 0x6E via `/sys/firmware/acpi/interrupts/gpe6E`, sparing the lid per its DSDT-only-BAT0-handlers) was tried and ruled out: it broke lid-switch event delivery entirely on this buggy BIOS 1.43, worse than either karg. Confirmed the wake-thrash mechanism is still live (EC-GPE resume signature reproduced on a real lid-close). `intel_idle.max_cstate=1` tested and ruled out — a genuine cap this time (prior `processor.max_cstate=1` test turned out to be a no-op, wrong karg for this machine's `intel_idle` driver); thrash reproduced worse under the cap (187 cycles vs. prior 15–57 range), and the bogus `~7198.9`s settling-cycle duration fingerprint repeated again — user caught that the whole 187-cycle storm actually took ~5 real seconds (monotonic clock), not the ~2h03m the corrupted realtime timestamps implied; the RTC/EC garbage-duration bug corrupts the system's realtime clock itself, so realtime timestamps aren't trustworthy evidence for this bug | reopened, see I027 | ✓ | not yet |
| [I025](I025-vikunja-mcp-binary-missing-since-windows-migration.md) | 2026-08-25 | agent | second-brain vault's `vikunja-mcp` MCP server failing to connect (`ENOENT`) since at least 2026-08-15 — binary never installed during the Windows-to-Fedora migration | ~10m | ✓ | `thinkpad-fedora-extras/scripts/vikunja-mcp.sh` |
| [I024](I024-pinned-kmod-blocked-upgrade-dropped-nvidia-xpadneo.md) | 2026-08-25 | rpm-ostree | `rpm-ostree upgrade` failed to depsolve — `kmod-nvidia`/`kmod-xpadneo` pinned to old kernel build, I008 kmod rebuild still broken; dropped both to unblock the upgrade | ~20m | ✓ | not yet — still a one-off |
| [I023](I023-tb-bridge-no-auth-agent-read-full-mailbox.md) | 2026-08-23 | agent | thunderbird-cli's `tb-bridge` had no auth at all — this agent (zero MCP wiring, no mail tools) shelled out to `tb` via Bash and read the full mailbox across all 6 accounts. Patched to require `TB_AUTH_TOKEN`; upstreamed as PR #21. Fix removes bare `tb` access from this session by design — that is the intended outcome, not a regression | n/a — found/fixed in a second-brain session, recorded here after the fact | n/a | `docs/thunderbird-cli.md` |
| [I022](I022-update-check-extras-flatpaks-never-checked.md) | 2026-08-23 | agent | `/update-check`'s extras Flatpaks section never appeared in any run — stale hardcoded path (`$EXTRAS_DIR/flatpaks.sh`) left over from before the extras repo's scripts/docs/hosts restructure; all 12 extras apps had silently gone unchecked | ~10m | partial | `scripts/update-check.sh` |
| [I021](I021-acpi0007-second-suspend-hang.md) | 2026-08-22 | hardware | Suspend hangs on resume, never comes back — `pm_trace` points at `ACPI0007:11` (an ACPI Processor object), not the GPU; distinct from I020's signature. Recurred 2026-08-23 with the same signature; user observed LED pulsating (suspended) then steady on lid-open with no display/input response, pointing at resume specifically, not entry. Cause still open | not fixed yet | ✓ | not yet |
| [I020](I020-s2idle-selinux-avc-not-upstream-gsp-bug.md) | 2026-08-22 | hardware | I019's "open upstream GSP bug" diagnosis was wrong — same `0x62` signature traced to a local SELinux AVC denial (`systemd_sleep_t` blocked from writing `/var/tmp`), fixable with a local policy module; dGPU re-enabled + fix applied, reboot/verification pending | ~40m so far (unverified) | ✗ | not yet |
| [I019](I019-nvidia-suspend-fix-caused-retry-loop-battery-drain.md) | 2026-08-20 | hardware | I018's mitigation unmasked an open upstream NVIDIA GSP-unload bug (0x62, matches open-gpu-kernel-modules#1142) — suspend went from a rare fatal crash to a 100%-failure retry loop, 260 attempts, lid closed, battery drained to ~1% over 2h13m; reverted the mitigation as harm reduction, root cause stays open upstream | ~20m (harm reduction only) | ✗ | not yet |
| [I018](I018-reset-triage-crash-marker-on-wrong-last-x-line.md) | 2026-08-20 | agent | `reset-triage` skill reported no crash after a real one — its `last -x reboot` detection filter can never see `last`'s `crash` tag, which is only ever written on the tty/login-session line, not the `reboot` line; underlying crash was a suspend hang with an NVRM out-of-memory signature (open s2idle investigation) | ~15m | ✓ | `.claude/skills/reset-triage/SKILL.md` |
| [I017](I017-clock-wrong-after-s2idle-pm-trace-rtc-corruption.md) | 2026-08-20 | boot | Machine clock wrong, RTC showing year 2052 — `pm-trace.service` (armed for s2idle hang debugging) scrambles the RTC's time-of-day fields on every suspend/resume by design | ~15m | ✓ | not yet — one-off; superseded `pm-trace.service`'s active use |
| [I016](I016-sudo-needs-tty-security-privacy-check-pkexec.md) | 2026-08-19 | agent | `security-privacy-check.sh`'s Lynis section (and, same bug, `etc-drift.sh`) failed with `sudo: a terminal is required` on first real run — `sudo -v` has nothing to prompt against when Claude Code runs a script non-interactively | ~10m | ✓ | `scripts/security-privacy-check.sh`, `scripts/etc-drift.sh` |
| [I015](I015-fprintd-goodix-driver-crash-loop.md) | 2026-08-19 | hardware | fprintd crashing ~15x/3 days inside the Goodix driver, no restart policy so it stayed dead; separately, a loose charger cable was cycling charge/discharge and causing the connect/disconnect sound + LED blink the user reported alongside it | ~30m | ✓ | `hosts/thinkpad-e14-gen5/quirks.sh` (pending) |
| [I014](I014-kopia-backup-missing-cache-container-steam-exclusions.md) | 2026-08-19 | backup | `kopia-backup.sh`'s exclusion list only covered the rclone cloud mounts — first real run walked 33GB of Steam data under `.var` before the user flagged the slowness | ~15m | ✗ | `scripts/kopia-backup.sh` |
| [I013](I013-kopia-sftp-connect-auth-and-known-hosts.md) | 2026-08-19 | backup | `kopia repository connect sftp` per `docs/recovery.md`'s prior (unexercised) command failed missing auth flags, then `knownhosts: key mismatch` even with the correct single key — needed all host-key algorithms in a persistent `known_hosts` file | ~25m | ✗ | `docs/recovery.md` Card 3 |
| [I012](I012-notify-send-plain-sudo-fingerprint-gate.md) | 2026-08-17 | agent | No live cue to touch the fingerprint reader (Bash tool output isn't streamed); `notify-send` + plain `sudo` blocks correctly on fingerprint with no TTY workaround, `pkexec` only needed for the password fallback | ~25m | ✓ | not yet — one-off pattern |
| [I011](I011-sudo-gui-auth-for-agent-pkexec-over-askpass.md) | 2026-08-17 | agent | Agent-run `sudo` needs GUI auth (no controlling TTY); `openssh-askpass` worked but fingerprint prompt never surfaced — `pkexec` (existing polkit agent) supports both, no extra package. Diagnosis corrected in-place — see I012 | ~45m | ✓ | not yet — one-off, `pkexec <cmd>` for password fallback |
| [I010](I010-sessionstart-additionalcontext-never-fires-a-turn.md) | 2026-08-17 | agent | I009's "silent greeting" never appears until the user types first — additionalContext can't trigger a turn on its own; replaced with an unconditional visible `claude "I'm back"` trigger, branching handled agent-side | ~30m | ✗ (both I009 and this incident's first proposal) | `scripts/session-autostart.sh`, `.claude/skills/handover/SKILL.md` |
| [I009](I009-sessionstart-hook-hides-launch-prompt.md) | 2026-08-17 | agent | GNOME-autostart Claude session showed a visible fake "resume from handover" turn — moved resume logic into a silent SessionStart hook | ~1m (confirmed at next launch) | ✗ — see I010 | `.claude/hooks/session-start-greeting.sh` |
| [I008](I008-build-signed-kmod-toolbox-key-access.md) | 2026-08-17 | toolbox | `build-signed-kmod.sh`'s first live run fails to read the MOK private key — wrong path inside toolbox, and even the right path is unreadable due to rootless-container permissions. **Resolved 2026-08-25**: split the privileged read to a new host-side `stage-mok-key.sh`; four more untested bugs in the script fixed along the way; verified end to end for nvidia and xpadneo, booted and confirmed signed-and-trusted at runtime, controller input working | unresolved 2026-08-17, ~40m to resolve 2026-08-25 | ✗ both sessions | `scripts/build-signed-kmod.sh`, `scripts/stage-mok-key.sh` |
| [I007](I007-ptyxis-autostart-handover-resume-duplicate-window.md) | 2026-08-17 | gnome | Ptyxis autostart + handover resume verified over reboot; GNOME session restore opened a duplicate window alongside it | ~5m | ✓ | not yet — one-off `gsettings set` |
| [I006](I006-xpadneo-unsigned-akmod-and-truncated-descriptor-firmware.md) | 2026-08-17 | rpm-ostree | Xbox Wireless Controller (BT) never worked — unsigned akmod (same as I004) + separately, controller's own BT firmware shipped a truncated HID report descriptor | ~4h (2 sessions) | ✗ | `hosts/thinkpad-e14-gen5/quirks.sh` |
| [I005](I005-steam-flatpak-32bit-nvidia-prime-offload-missing-runtime.md) | 2026-08-17 | flatpak | Steam-wide PRIME offload env vars set correctly but 32-bit games (Portal 2) still rendered on iGPU — missing matching GL32.nvidia Flatpak runtime | ~20m | ✓ | `hosts/thinkpad-e14-gen5/quirks.sh` |
| [I004](I004-nvidia-akmod-unsigned-in-rpm-ostree-post-sandbox.md) | 2026-08-17 | rpm-ostree | akmod-nvidia builds unsigned kernel module inside rpm-ostree's `%post` sandbox despite valid enrolled MOK key | ~3h | ✗ | `hosts/thinkpad-e14-gen5/quirks.sh` |
| [I003](I003-gsconnect-pixel-pairing-wrong-zone-and-dbus-activation.md) | 2026-08-16 | gnome | GSConnect installed, firewall opened, but Pixel never appeared to pair | ~45m | ✗ | `thinkpad-fedora-extras/gnome-extensions.sh` |
| [I001](I001-libfprint-tod-override-hardlink-checkout.md) | 2026-08-16 | rpm-ostree | `override replace` hardlink-checkout failure replacing `libfprint` with the Goodix TOD build | ~25m | ✗ | `hosts/thinkpad-e14-gen5/quirks.sh` |
| [I002](I002-bitwarden-flatpak-polkit-policy-readonly-usr.md) | 2026-08-16 | rpm-ostree | Bitwarden Flatpak biometric-unlock docs write to read-only `/usr` | ~30m | ✗ | `scripts/build-bitwarden-polkit-policy.sh` |

## Adding an entry

1. Create `incidents/I{nnn}-{slug}.md` from `incidents/_template.md`,
   incrementing from the top row.
2. Add a row here.

Write the entry when the problem is fixed, not at the end of the session — the
failed attempts are the part that is gone forever if it is left until later.

## Areas

Keep the `Area` column to a small vocabulary so the table stays sortable:
`rpm-ostree`, `flatpak`, `toolbox`, `gnome`, `hardware`, `network`, `etc`,
`backup`, `agent`, `boot`.

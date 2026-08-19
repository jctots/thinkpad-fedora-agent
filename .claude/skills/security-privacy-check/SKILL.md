---
name: security-privacy-check
description: Run a security + privacy posture sweep — Lynis system audit (hardening index, warnings, suggestions) plus GNOME privacy settings, location services, and Flatpak per-app permission overrides. Use when the user asks for a security check, privacy check, hardening review, or "what can see my camera/mic/location."
---

Run `scripts/security-privacy-check.sh` from the repo root and show its
output as-is.

It's report-only and side-effect-free — never installs anything, changes a
setting, or revokes a permission. Every run also writes a timestamped copy
of its full output to `.claude/security-reports/` (gitignored — machine
state, not project narrative, same reasoning as `.claude/audit/`). The
script prints the exact path at the end; mention it so the user knows where
to find it for comparison against a later run.

Two independent halves:

1. **Lynis** — a layered package (see `scripts/PACKAGES.md`), reused rather
   than hand-rolled per CLAUDE.md's prior-art rule. Covers general OS
   hardening: boot/kernel, SELinux, SSH, cron, file integrity. If `rpm -q
   lynis` reports it missing, point at `rpm-ostree install lynis` (from
   `scripts/layer-packages.sh`) rather than improvising the install command.
   Needs root, via `pkexec` (not `sudo` — the script has no TTY to prompt
   against when run non-interactively, and `pkexec` is CLAUDE.md's rule for
   root commands anyway). Expect the GNOME polkit dialog to appear on
   screen. **Its boot/filesystem checks assume a
   traditional (non-ostree) layout** — findings there can be an artifact of
   the image-based root, not a real issue. Read Lynis's own findings before
   treating any of them as actionable, and say so if one looks
   ostree-specific rather than proposing a fix for it. Known false
   positive: **AUTH-9216 / `grpck` "no matching group file entry"** for
   dozens of system groups — `/etc/group` on this host only holds local
   entries (`root`, `wheel`, the user), the rest resolve via `altfiles`/
   `systemd` NSS sources per `nsswitch.conf` (`getent group` shows the full
   merged set); `grpck` only reads the flat files directly and doesn't know
   about the merge. Confirmed 2026-08-19 — no fix needed.
2. **Native privacy checks** — GNOME privacy settings (`gsettings`),
   location services, and Flatpak permission overrides (system-wide and
   per-app). These aren't vendored from anywhere; they're the same
   thin-wrapper-over-a-native-tool pattern as `host-check.sh` and
   `update-check.sh`. There is no direct Lynis-equivalent for privacy
   auditing on Linux desktops — this is a checklist, not a scored framework,
   confirmed by search before this was written.

After showing the output, always follow it with an action plan — the report
alone isn't the deliverable, a reviewed and triaged list of what to do next
is. Don't stop at the summary numbers (hardening index / warning count /
suggestion count); go through Lynis's actual warnings and suggestions
(`pkexec lynis show report`, or re-run with `--no-colors` output already
captured in the report file) and the Flatpak/GNOME findings, and produce:

1. **Triage each finding** into: ostree-layout artifact (say so, no action),
   already-intentional (e.g. a Flatpak override the user granted on purpose
   for a reason — note it, no action), or a real candidate fix.
2. **For each real candidate fix**, treat it like any other host change
   proposal per CLAUDE.md: show the exact command, name the reversibility
   layer it falls under (`rpm-ostree rollback` / `etckeeper` / backups), and
   rank it — don't just dump all 30+ Lynis suggestions unranked. A missing
   AppArmor/SELinux boolean or an open unnecessary service is worth
   surfacing first; a coding-style nitpick in `/etc/profile` is not.
3. **Ask before running anything** — this skill itself stays report-only;
   the action plan is proposals, not auto-applied fixes.
4. If Flatpak overrides show camera/microphone/location/broad-filesystem
   access granted to an app the user doesn't recognize as needing it, flag
   it explicitly — that's the actual "what can see my camera" answer this
   skill exists to give.
5. Suggest `/etc-drift` alongside this if it hasn't run recently — polkit
   rules and unit files are a security-relevant surface this script doesn't
   see, since it only reads Lynis's and GNOME's own state, not `/etc`'s git
   history.

If a run turns up nothing beyond ostree artifacts and already-intentional
overrides, say that plainly instead of manufacturing an action plan where
there isn't one.

## Already resolved (2026-08-19)

A future run may re-flag these as suggestions/warnings — check the full
narrative in the vault decision (`_inbox` capture referencing etckeeper
commit `5dc4784` in `/etc`) before treating any of them as new:

- **FILE-7524** cron permissions — fixed (`cron.deny`/`crontab` → 600,
  `cron.d`/`cron.daily`/`cron.hourly`/`cron.weekly`/`cron.monthly` → 700).
  Lynis re-scanning after this should show these as resolved, but note git
  only tracks the executable bit, never full permission bits — `etckeeper`'s
  diff will never show this change even though it's real and applied.
- **KRNL-5820** core dumps — fixed via `* hard core 0` in
  `/etc/security/limits.conf`.
- **NETW-3200** unused protocols — fixed via
  `/etc/modprobe.d/blacklist-unused-protocols.conf` (dccp/sctp/rds/tipc).
- **KRNL-6000** sysctl deltas — fixed via `/etc/sysctl.d/99-hardening.conf`,
  except three deliberately left alone (see below).
- **Deliberately left alone, do not propose changing without asking first**:
  `kernel.sysrq` (crash-forensics baseline, D33), `kernel.modules_disabled`
  (would break the pinned NVIDIA kmod / any layered module),
  `kernel.unprivileged_bpf_disabled` (Fedora's CAP_BPF-gated default is
  already better than Lynis's older binary-flag expectation).
- **`kernel.yama.ptrace_scope=1`** was applied — a deliberate trade-off,
  user-confirmed: `gdb -p <pid>` on an unrelated running process now needs
  sudo/pkexec. If a debugging workflow breaks and this setting is the
  reason, that's expected, not a regression to silently revert.

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
   ostree-specific rather than proposing a fix for it.
2. **Native privacy checks** — GNOME privacy settings (`gsettings`),
   location services, and Flatpak permission overrides (system-wide and
   per-app). These aren't vendored from anywhere; they're the same
   thin-wrapper-over-a-native-tool pattern as `host-check.sh` and
   `update-check.sh`. There is no direct Lynis-equivalent for privacy
   auditing on Linux desktops — this is a checklist, not a scored framework,
   confirmed by search before this was written.

After showing the output:
- For anything Lynis flags as a real (non-ostree-artifact) suggestion, treat
  it like any other host change proposal — show the exact command, explain
  the reversibility layer it falls under, and ask before running it.
- If Flatpak overrides show camera/microphone/location/broad-filesystem
  access granted to an app the user doesn't recognize as needing it, flag it
  — that's the actual "what can see my camera" answer this skill exists to
  give.
- Suggest `/etc-drift` alongside this if it hasn't run recently — polkit
  rules and unit files are a security-relevant surface this script doesn't
  see, since it only reads Lynis's and GNOME's own state, not `/etc`'s git
  history.

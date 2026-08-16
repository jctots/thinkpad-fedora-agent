---
name: host-check
description: Run every report-only script in the base layer and host profile (scripts/install-flatpaks.sh, install-gnome-extensions.sh, layer-packages.sh, tpm2-luks-unlock.sh, hosts/<slug>/quirks.sh) and summarize ok/missing across all of them. Use when the user asks for a general status sweep of the machine, "what's missing", or a health check that isn't specifically about updates.
---

Run `scripts/host-check.sh` from the repo root and show its output as-is.

It's read-only and freely agent-runnable — every script it wraps is already
guaranteed idempotent and side-effect-free by its own header comment, same
contract as `install-flatpaks.sh`. `host-check.sh` uses an explicit include
list, not a blind glob over `scripts/*.sh` — it deliberately skips
`install-hooks.sh` (mutates git config directly) and
`build-bitwarden-polkit-policy.sh` (builds a local RPM), since running those
would be a side effect disguised as a status check.

This is a different question from `/update-check`: `host-check` answers "is
X installed / present," `update-check` answers "is X out of date." They're
complementary, not overlapping — run both for a full picture.

After showing the output, for anything reported missing, point at the exact
command the script already printed rather than improvising one — same rule
as every report-only script in this repo. Some entries (like
`tpm2-luks-unlock.sh`'s enrollment step) explicitly require an interactive
terminal and can't be run non-interactively; say so rather than attempting
it as a background command.

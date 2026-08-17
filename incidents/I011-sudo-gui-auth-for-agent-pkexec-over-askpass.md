<!--
Template: incidents/I{nnn}-{slug}.md
Use: one file per incident. I### increments from incidents/index.md; slug is kebab-case.
After writing: add a row to incidents/index.md (newest first).
-->

## I011 — 2026-08-17 — Agent-run sudo needed GUI auth; openssh-askpass worked but dropped fingerprint

**Area:** agent

**Symptom:** The agent's Bash tool subprocess has no controlling TTY, so
plain `sudo <cmd>` from Claude Code fails silently or hangs — no password
prompt ever appears, no fingerprint prompt either. User wanted a way for
the agent to run `sudo` under explicit per-call human authentication (the
Bash tool's own approval prompt), authenticated via whatever GUI dialog
was already on screen, without weakening auth to a NOPASSWD rule or a
cached `sudo -v` timestamp.

**Cause:** `sudo` prompts on the controlling TTY by default; a headless
subprocess has none. `SUDO_ASKPASS` + `sudo -A` redirects the *password*
prompt to a GUI helper, but `openssh-askpass` (classic GTK askpass) only
renders `PAM_PROMPT_ECHO_OFF` (password) requests as a dialog. The
`pam_fprintd` step in `/etc/pam.d/system-auth` (`auth sufficient
pam_fprintd.so`, tried before `pam_unix`) sends a `PAM_TEXT_INFO` message
("Place your finger on the fingerprint reader") that `sudo`/askpass just
prints to stderr — invisible to the human, since that stderr lands in the
agent's tool output, not the screen. With no visible cue to touch the
sensor in time, `pam_fprintd` always times out and falls through to the
password step, which the GUI dialog does handle.

**Fix:** Use `pkexec <cmd>` instead of `sudo -A <cmd>`. `pkexec` invokes
the GNOME polkit authentication agent — the same dialog that already
authenticates `rpm-ostree` operations — which natively supports both
fingerprint and password. No extra package needed; `pkexec` ships in the
base image already. Verified end-to-end: `pkexec whoami` returned `root`,
GUI dialog appeared, fingerprint was offered and used successfully.

**Tried first:** `openssh-askpass` (`SUDO_ASKPASS=/usr/libexec/openssh/ssh-askpass
sudo -A <cmd>`). This was a reasonable first proposal — it's the standard
mechanism for GUI-driven `sudo`, it's a small layered package, and it did
work end-to-end for password auth (confirmed: real GUI dialog, real `root`
stdout back). It just didn't surface fingerprint, which turned out to be
the actual requirement (user has a long password and wants fingerprint for
convenience) rather than "any GUI auth." Once `pkexec` was tried as an
alternative it satisfied the requirement directly with no new package.
`openssh-askpass` was then uninstalled (`rpm-ostree uninstall
openssh-askpass`, staged, needs a reboot to clear from the booted
deployment) and the manifest entry in `scripts/layer-packages.sh` reverted
— it added no value once `pkexec` was in play.

**Reversibility:** `rpm-ostree` layer — the `openssh-askpass` install and
its later uninstall both roll back cleanly via `rpm-ostree rollback` if
needed. No `/etc` changes were made (PAM config was only read, not
edited).

**Captured in:** not yet — still a one-off; `pkexec <cmd>` is the pattern
to reach for going forward whenever the agent needs a privileged command
run under explicit human GUI authentication with fingerprint support.

**Tally:** time-to-fix ~45m (spanning two sessions, including reboot wait)
· first proposal: right

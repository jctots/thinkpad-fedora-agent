## I038 — 2026-08-29 — `login.keyring` corrupted (unparseable), fingerprint-only login can never unlock a password-protected keyring

**Area:** gnome

**Symptom:** `~/.local/share/keyrings/login.keyring` was in an unparseable
format (corrupted, broken since roughly 2026-08-18). Symptoms included
repeated stray `login_1.keyring` through `login_5.keyring` conflict-rename
artifacts appearing in `~/.local/share/keyrings/` (dated Aug 19, 21, 26, 28,
29 — gnome-keyring-daemon's own leftovers from repeated failed unlock
attempts), and Bitwarden's flatpak losing its "Unlock with system
authentication" toggle again (same journal signature as I037:
`[Credential Storage Listener] getPassword/setPassword failed Error: File
backend error Incorrect secret`).

**Cause:** Two compounding facts:
1. `gdm-password`'s PAM stack has `pam_gnome_keyring.so` wired into
   auth/password/session — a typed password becomes the login keyring's
   unlock/creation secret automatically, transparently, no prompt.
   `gdm-fingerprint` has **no** `pam_gnome_keyring.so` lines at all, and
   fundamentally can't: `pam_fprintd` never populates `PAM_AUTHTOK` (no
   password-shaped secret exists from a biometric match), so there is
   nothing for gnome-keyring to unlock or create a password-protected
   keyring with. This machine logs in via fingerprint only, never
   password — so a `login.keyring` that expects a real unlock password can
   never be created or repaired through normal login, only diverge further
   every boot.
2. I037's mitigation (pointing the `default` secrets alias at a
   working blank-password collection) was the right instinct but the
   specific target chosen there — re-pointing `default` back at `login` —
   was wrong for a fingerprint-only machine, since `login` inherently wants
   a real password. Any app relying on `default` (Bitwarden's flatpak
   credential cache included) kept re-desyncing against it.

**Fix:**
```
mkdir -p ~/.local/share/keyrings-corrupted-backup-20260829
mv ~/.local/share/keyrings/login.keyring \
   ~/.local/share/keyrings-corrupted-backup-20260829/login.keyring
```
Reboot so PAM/gnome-keyring re-evaluates cleanly. Confirmed post-reboot:
`busctl --user call org.freedesktop.secrets /org/freedesktop/secrets
org.freedesktop.Secret.Service ReadAlias s "default"` still resolves to
`Default_5fKeyring` (the existing blank-password collection from I037) — no
new "create keyring" prompt appeared at login, which is correct: nothing
needed creating since `default` was never pointed at `login` in the first
place after this correction.

Bitwarden's flatpak credential cache
(`~/.var/app/com.bitwarden.desktop/data/keyrings/default.keyring`)
went stale again post-reboot regardless (same I037 failure class — any
identity change on the secret-service side orphans this per-app cache).
Same fix applied, incrementing the backup suffix each recurrence:
```
flatpak kill com.bitwarden.desktop   # or Bitwarden tray → Quit
mv ~/.var/app/com.bitwarden.desktop/data/keyrings/default.keyring \
   ~/.var/app/com.bitwarden.desktop/data/keyrings/default.keyring.bak-20260829-3
flatpak run com.bitwarden.desktop
```
Confirmed via fresh journal lines (new PID after relaunch) showing zero
`Credential Storage Listener` errors, and fingerprint unlock working again
in the desktop app.

**Tried first:** Nothing wrong this time — the corrupted-file diagnosis and
blank-password requirement were already understood going into this session
from I037's mechanism research; the only correction was **not** repeating
I037's specific "point `default` at `login`" step, since `login` can't work
password-less-ly under a fingerprint-only PAM stack. That correction was
made before the reboot, so this incident is the confirmation, not the
discovery.

**Reversibility:** `/var/home` only — the corrupted keyring file was moved
aside, not deleted (`~/.local/share/keyrings-corrupted-backup-20260829/`),
and Bitwarden's stale cache likewise (`default.keyring.bak-20260829-3`,
prior backups `-2` and unsuffixed also retained). No `/etc` or OS-image
state touched. Threat-model note: the blank-password collection is an
intentional, understood tradeoff for a fingerprint-only machine — disk is
already LUKS+TPM2 encrypted, so a blank keyring's weaker at-rest protection
is acceptable here. Do not re-attempt pointing `default` at a
password-protected `login` keyring going forward.

**Captured in:** `scripts/health-checks/credential-storage.sh` (built for
I037, exercised and confirmed working end-to-end by this incident's
recurrence). Its `journalctl --user --since "15 min ago"` query, with no
boot filter, turned out to have a real false-positive bug rather than just
lag: it searches the *whole persistent journal*, not just the current
boot, and this machine's known s2idle-resume clock-jump bug (see
`thinkpad-fedora-extras` I003/I010) can leave old log lines timestamped
*ahead* of real time — so a dead process from a boot before this one kept
matching the "last 15m" window and alerting on an already-fixed problem,
observed directly: PID 356299 (the alerting log lines) no longer existed
as a process at all when checked. Fixed by adding `-b 0` (current boot
only) to the query — a process from a prior boot can never be the live
thing this check cares about anyway. No dedicated fix-script for the
keyring-move-aside step itself — low enough frequency (twice in the
project's history) that a one-off procedure, documented here, is
proportionate over a script.

**Tally:** time-to-fix ~20m (post-reboot verification only; the
move-aside-and-reboot decision itself was made earlier in the same session,
before this incident file was written) · first proposal: ✓ — the
fingerprint-only mechanism understanding and corrected `default`-alias
target from earlier in this session held up; verification surfaced no new
issues.

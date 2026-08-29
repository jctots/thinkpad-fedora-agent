## I037 — 2026-08-29 — Bitwarden flatpak "Unlock with system authentication" option missing entirely — orphaned local secret cache, not fprintd

**Area:** flatpak

**Symptom:** Bitwarden desktop (flatpak) Settings → Security showed no
"Unlock with system authentication" option at all — not greyed out, just
absent. User had just updated the Vaultwarden server and the Bitwarden
client, expecting that to have fixed it. `journalctl --user` showed
constant `[Credential Storage Listener] getPassword failed Error: File
backend error Incorrect secret` (and the same on `setPassword`) every time
the app touched its credential store.

**Cause:** Bitwarden's Linux client keeps a local encrypted secret-cache
file at `~/.var/app/com.bitwarden.desktop/data/keyrings/default.keyring`,
encrypted with a master key it fetches once per session from GNOME
Keyring via the `org.freedesktop.portal.Secret` portal (the key is stored
as an item literally named "Application key for com.bitwarden.desktop"
inside whichever collection is the desktop's *default* keyring). That file
was last written 2026-08-18 13:18 — alongside 39 abandoned
`.tmpkeyring*` atomic-write leftovers from that same session, meaning the
write path had already been flaky that day. Sometime after that date the
user cleared the password on the "Default keyring" collection via
Seahorse, which regenerated the portal-backed master key. Every read
thereafter decrypted `default.keyring`'s old ciphertext with the new key
and failed with "Incorrect secret" — permanently, since nothing ever
triggered a clean rewrite. Bitwarden's v2 Linux-biometrics capability
probe depends on this store working; when it fails, the client hides the
toggle outright rather than showing it disabled.

This is a different failure mode from I036 (fprintd/Goodix driver
segfaulting) despite an identical user-facing symptom — the two can be
confused because both make the same Bitwarden setting vanish.

**Fix:**
```
flatpak kill com.bitwarden.desktop
mkdir -p ~/.var/app/com.bitwarden.desktop/data/keyrings.bak-20260829
shopt -s dotglob
mv ~/.var/app/com.bitwarden.desktop/data/keyrings/* \
   ~/.var/app/com.bitwarden.desktop/data/keyrings.bak-20260829/
flatpak run com.bitwarden.desktop
```
Then log in with the master password — Bitwarden regenerates a clean
`default.keyring` under the *current* portal key on first successful
login. Verified: new file written cleanly (no orphaned tmp files this
time), "Unlock with system authentication" appeared in Settings and
worked.

**Tried first:** Assumed this was I036 recurring (fprintd/Goodix driver
crash-loop) since the symptom looks identical — option missing entirely
from Bitwarden's Security settings. Live-checked `fprintd.service`,
`coredumpctl` (no crashes in the relevant window), and confirmed via
`pkexec whoami` that system-level fingerprint auth worked fine at the
user's prompting — ruling out I036 before looking anywhere else. Then
spent time researching whether the Bitwarden flatpak's D-Bus sandbox
permissions were missing a `--system-talk-name=net.reactivated.Fprint`
entry (they weren't — confirmed against upstream's own flathub manifest,
which also only grants `PolicyKit1`/`login1`, by design: Bitwarden talks
to polkit, not fprintd directly). The actual cause was found only after
grepping `journalctl --user` for the app's own log lines and inspecting
GNOME Keyring's live collections/items via
`Gio.Secret`/`busctl --user tree`, which surfaced the stale-dated
`default.keyring` and the portal-secret item sitting in the
password-cleared "Default keyring" collection.

**Reversibility:** `/var/home` — the stale files were moved, not deleted,
to `~/.var/app/com.bitwarden.desktop/data/keyrings.bak-20260829/`. No
`/etc` or OS-image state touched. The deleted cache held only OS-level
convenience secrets (Chrome/Obsidian/Brave "safe storage" tokens,
Bitwarden's own portal-wrapped biometric-unlock key) — never the vault
itself, which is protected by the master password and lives
server-side/in Bitwarden's own encrypted blobs, so there was no data-loss
exposure even if the fix hadn't worked.

**Captured in:** `scripts/health-checks/credential-storage.sh` — greps
`journalctl --user` for the `Credential Storage Listener` failure signature
on a 15-minute rolling window, wired into `scripts/system-health-check.sh`.
Recurred once already (see I038) and the check caught it correctly.
Pattern worth remembering generally, not just for Bitwarden: **removing a
keyring's password in Seahorse (or any other event that changes what a
secrets alias resolves to) can silently orphan any sandboxed app's
portal-backed secret cache.**

**Tally:** time-to-fix ~50m · first proposal: ✗ (assumed I036's
fprintd crash-loop was recurring; user had to redirect with "fingerprint
is working fine, try pkexec" before the actual cause — an orphaned
portal-backed secret cache from a Seahorse password-clear — was found)

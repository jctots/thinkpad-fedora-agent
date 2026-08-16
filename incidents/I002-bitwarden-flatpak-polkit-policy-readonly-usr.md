## I002 — 2026-08-16 — Bitwarden Flatpak biometric-unlock setup fails: read-only /usr

**Area:** rpm-ostree

**Symptom:** Following Bitwarden's own docs
(https://bitwarden.com/help/biometrics/, Linux → Flatpak tab) to enable
fingerprint unlock for the desktop app: the documented
`sudo wget -O /usr/share/polkit-1/actions/com.bitwarden.Bitwarden.policy ...`
fails with `Read-only file system`.

**Cause:** Fedora Silverblue mounts `/usr` read-only (composefs overlay on
`/`, confirmed via `mount` and a failed `touch` test). Bitwarden's Flatpak
biometrics instructions assume a traditional package-managed Linux where
`/usr` is writable. There is no `/etc` override for polkit action files —
`man polkit` states action XML must live under
`/usr/share/polkit-1/actions`, and `polkitd.conf` has no directory-override
setting.

**Fix:** Package the single policy file as a local RPM and layer it with
`rpm-ostree install`, so the change lands in the OS-image reversibility
layer instead of a live write. Concretely:

```
scripts/build-bitwarden-polkit-policy.sh   # builds the rpm inside toolbox, prints the install command
rpm-ostree install <path it prints>
systemctl reboot                            # new layer only applies on next boot
```

The spec and the vendored policy XML (from Bitwarden's own repo, so it
matches their app's expectations exactly) live in
`scripts/bitwarden-polkit-policy/`. SELinux: no manual `chown`/`chcon`
needed here — the existing `org.freedesktop.policykit.policy` file was
already labelled `usr_t`, and files landing under `/usr/share` via a
properly layered RPM inherit that label automatically, unlike the docs'
raw-write path which required setting it by hand.

After reboot: Bitwarden desktop → File → Settings → Security → check
"Unlock with system authentication".

**Tried first:** The literal command from Bitwarden's docs, which is correct
for Snap/AppImage/deb/rpm/traditional-Flatpak installs but assumes a
writable `/usr`. Worth flagging for future incidents: any vendor doc that
says "copy a file into `/usr/share/...`" needs the same read-only-`/usr`
translation on this machine — this is a Silverblue-general problem
(applies to any Flatpak needing a host-side polkit action), not specific to
Bitwarden or to this host's hardware.

**Reversibility:** `rpm-ostree` rollback covers the layered RPM fully.

**Captured in:** `scripts/build-bitwarden-polkit-policy.sh`,
`scripts/bitwarden-polkit-policy/`

**Tally:** time-to-fix ~30m · first proposal: ✗ (vendor docs' raw-write path doesn't work on this OS; the toolbox-build-and-layer approach was the correct fix)

**Follow-up — "Unlock with system authentication" greyed out (not a setup bug):**
After the reboot above, the policy file, `fprintd` enrollment, and PAM were
all already correct — Fedora's `authselect` profile already had
`with-fingerprint` enabled and `/etc/pam.d/system-auth` already carried
`pam_fprintd.so sufficient`, unlike Arch-based guides which need that PAM
line added by hand. The toggle still appeared unclickable twice, both times
for reasons that are Bitwarden app behavior, not host config:

1. **First open of a session:** the toggle stays greyed out until the vault
   has been unlocked at least once with the master password/PIN in that
   app process. This is documented behavior
   (https://bitwarden.com/help/biometrics/), easy to mistake for a broken
   polkit/fprintd setup.
2. **Full quit + relaunch** (as opposed to just locking the vault) resets
   session state, so the same master-password gate reappears every cold
   start — because Settings → Security → **"Require master password or PIN
   on app restart"** is checked by default. Locking the vault without
   quitting the process doesn't hit this, which is why the two looked like
   different bugs at first. Unchecking that setting lets biometrics unlock
   a freshly-launched app directly; master password remains the fallback if
   fingerprint/polkit ever fails.

No config change was needed for either — both resolved by using the app the
way it expects to be used. Recorded here so a future "fingerprint isn't
working" report starts from "did you unlock once this session / is
restart-gating on" before re-diagnosing the polkit layer.

**Tally (follow-up):** time-to-fix ~15m · first proposal: ✗ (assumed the
grey-out was a leftover setup gap — checked polkit policy, `fprintd`
enrollment, PAM/`authselect` config, journalctl for polkit errors, all of
which were already fine; the actual cause was app session-state UX, found
via Bitwarden's own docs and GitHub issues, not host inspection).

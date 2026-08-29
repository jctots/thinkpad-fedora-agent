## I036 — 2026-08-28 — Bitwarden flatpak lost its "unlock with fingerprint / system authentication" option; root cause is fprintd itself crash-looping

**Area:** hardware

**Symptom:** Bitwarden desktop (flatpak, `com.bitwarden.desktop`) no longer offers
"Unlock with system authentication" at all — previously it was visible but
greyed out on the lock screen, now the option is gone from Settings entirely.
`sudo`/`pkexec` fingerprint auth (`authselect`'s `with-fingerprint` PAM stack)
still worked fine throughout, so this looked at first like a Bitwarden-side
bug, not a system one.

**Cause:** `fprintd.service` (D-Bus activated, `net.reactivated.Fprint`) has
been intermittently segfaulting — confirmed via `coredumpctl list`, at least
since 2026-08-19, and repeatedly in the hours before this session (21:00,
21:06, 21:20, 21:47 on 2026-08-28 alone; some `SIGSEGV`, one `SIGABRT`).
Backtrace of the most recent core:

```
libusb_bulk_transfer (libusb-1.0.so.0)
  → libfprint-tod-goodix-550a-0.0.9.so (+0x534cc)
    → SIGSEGV, in a USB transfer worker thread
```

`libfprint-tod-goodix` (installed via a third-party COPR,
`antiderivative/libfprint-tod-goodix-0.0.9`) is a closed/reverse-engineered
TOD plugin for the Goodix 550A sensor — there is no mainline libfprint driver
for this sensor. The crash is inside that plugin's USB handling, not in
`fprintd` itself, not in PAM, and not in polkit.

Because `fprintd.service` is D-Bus-activated and restarts cleanly on the next
call, `pkexec`/`sudo` fingerprint auth mostly still works (each invocation
gets a fresh daemon instance). But any app — like Bitwarden — that queries
fingerprint *availability* at a moment when the daemon has just crashed and
not yet been re-activated gets a negative/failed capability check, and
correctly hides the option. That capability check happening to land during
one of the crash windows explains why the symptom went from "visible but
disabled" to "gone entirely" as the crashes became more frequent tonight —
it's a flaky daemon, not a regression in Bitwarden.

**Fix:** None yet. Checked for a driver update two ways:
- `rpm-ostree upgrade --check` against all enabled repos (including the COPR
  itself): "No updates available."
- COPR API (`copr.fedorainfracloud.org/api_3/package/list/...` for
  `antiderivative/libfprint-tod-goodix-0.0.9`): no newer build than the
  installed `0.0.9-1.fc44` exists; the COPR's source rpm is still built
  against `fc39` and the project metadata was last generated 2026-03-19.

So the crashing binary is the newest one available — nothing to layer/update
to. This is an open upstream bug in a third-party driver with no current fix;
recorded here so the next occurrence isn't re-diagnosed from scratch.

**Tried first:** Assumed the problem was in Bitwarden's own Linux biometric
support (a documented, real bug — see below) and tried to bisect it by
rolling the Bitwarden flatpak back to an older cached commit
(`flatpak update --commit=... com.bitwarden.desktop`, system install, via
`pkexec`). The oldest cached commit (2026-07-02) failed to pull at all —
Flathub's CDN returned `404` on one `.dirtree` object, i.e. that history has
already been partially pruned server-side; the install was left untouched by
the failed pull. The next commit (2026-07-24, v2026.7.0) pulled cleanly but
then **crashed on launch with exit code 132 (SIGILL)** before drawing a
window — a dead end unrelated to the actual bug, and it left Bitwarden
unusable until reverted. Restored with a plain `pkexec flatpak update -y
com.bitwarden.desktop` back to 2026.8.0, confirmed working.

Bitwarden does have a real, separate, already-reported Linux UI bug in this
area — [clients#17292](https://github.com/bitwarden/clients/issues/17292),
the lock-screen system-auth button not polling PAM/polkit status on load —
closed upstream 2025-11-08 with no linked fix commit found.

That v1 bug (greyed-out-until-PIN) is not actually what's live on this
machine, though. `~/.var/app/com.bitwarden.desktop/config/Bitwarden/data.json`
shows the server-advertised feature flag
`pm-26340-linux-biometrics-v2 = True` for this account — Bitwarden shipped a
rewritten Linux biometrics implementation gated behind this LaunchDarkly flag
(desktop v2025.11.0+; self-hosted/Vaultwarden users have to force it on via
`EXPERIMENTAL_CLIENT_FEATURE_FLAGS`, but bitwarden.com already advertises it
for this account). So this install is on the **v2** biometrics path, not v1.

That reconciles the "greyed out" → "gone entirely" progression cleanly: v1's
bug left a visibly-disabled button; v2 apparently just hides the option
outright when its own runtime capability probe fails, rather than rendering
it disabled. A flaky `fprintd`/Goodix driver failing that probe at the moment
Bitwarden checks is consistent with both symptoms being the same underlying
cause, observed through two different UI versions as Bitwarden updated
mid-investigation. (`biometrics-sdk-ipc = False` was also seen in the same
config dump, but that flag maps to a separate, unrelated PR about CLI/SDK-IPC
biometrics, not desktop-app rendering — not implicated here.)

**Reversibility:** n/a — no fix applied. The Bitwarden downgrade/restore was
fully reversible via `flatpak update` (system flatpak, `pkexec`-gated); no
`/etc` or OS-image state was touched.

**Captured in:** not yet — still a one-off. No mitigation exists to script;
next step if this keeps recurring is either pinning `fprintd` to auto-restart
faster (it already is systemd-managed and does restart on next D-Bus call)
or filing/tracking an upstream bug against the `antiderivative` COPR, since
there's no other source for a Goodix 550A TOD driver on Fedora.

**Tally:** time-to-fix ~1h · first proposal: ✗ (assumed the bug was in
Bitwarden and chased a flatpak-version bisection; the actual cause was found
by checking `coredumpctl` after the downgrade attempt itself crashed)

## I001 — 2026-08-16 — `rpm-ostree override replace` fails with a hardlink checkout error when the replacement package ships a file the base package also ships

**Area:** rpm-ostree

**Symptom:** Replacing the base `libfprint` package with the Goodix-TOD-enabled
`libfprint-tod` build (from the `antiderivative/libfprint-tod-goodix-0.0.9`
Copr, needed for the Goodix `27c6:550a` fingerprint reader on this machine —
see `hosts/thinkpad-e14-gen5/README.md`) failed at the checkout stage:

```
error: Checkout libfprint-tod-1.94.5-2.fc44.x86_64: Hardlinking 3d/20420cdba8cf5545cc3fa85cb82bf2d46cd0144fede57cda27533f72811495.file to 60-autosuspend-libfprint-2.hwdb: File exists
```

Reproduced identically across three attempts, including after
`rpm-ostree cleanup -m` (repo metadata cache) and `rpm-ostree cleanup -b`
(checkout scratch trees) — ruling out stale cache as the cause.

**Cause:** Both the base `libfprint` package and the replacement
`libfprint-tod` package ship a file at the same path
(`/usr/lib/udev/hwdb.d/60-autosuspend-libfprint-2.hwdb`) with different
content. `rpm-ostree override replace` tries to remove the old package and
check out the new one's files into the assembled tree in a single pass, and
when a destination path is still occupied by the base tree's copy at
checkout time, the hardlink step fails outright instead of replacing it. This
is a known upstream limitation, not specific to this package — see
[coreos/rpm-ostree#4116](https://github.com/coreos/rpm-ostree/issues/4116)
and [#1255](https://github.com/coreos/rpm-ostree/issues/1255) for the same
failure mode against unrelated packages (`docker-current`, `alsa-lib`).

**Fix:** Split the replace into two separate `rpm-ostree` invocations instead
of one combined `override replace`, so the base package is fully removed from
the tree in its own deployment-assembly pass before the replacement's files
are checked out into a tree that no longer has anything at that path:

```bash
sudo rpm-ostree override remove libfprint
sudo rpm-ostree install libfprint-tod libfprint-tod-goodix
```

`fprintd`'s dependency on `libfprint` was satisfied by `libfprint-tod`'s
`Provides: libfprint = 1.94.5` in the second step — no cascade removal, no
manual reinstall needed.

**Tried first:**
1. `rpm-ostree override replace --experimental --from repo=copr:... libfprint --install libfprint-tod-goodix` — wrong argument. `override replace`'s package argument must be the *replacement* package name as it exists in the target repo (`libfprint-tod`), not the base package name being replaced (`libfprint`). Failed immediately with "No matches for 'libfprint' in repo ...", before ever reaching the real bug. Seemed plausible because the base-package name is the more intuitive thing to name when you're describing "replace X".
2. Corrected to `... libfprint-tod --install libfprint-tod-goodix` — this is what hit the hardlink checkout error above.
3. `rpm-ostree cleanup -m` then retry — no effect, same error. Seemed plausible because a corrupted/stale cache producing a bogus "file exists" is a common class of ostree issue.
4. `rpm-ostree cleanup -b` then retry — no effect, same error. Next most plausible cache-adjacent cause (checkout scratch trees specifically, per `cleanup --help`'s description) after `-m` didn't help.
5. `rpm-ostree install --force-replacefiles libfprint-tod libfprint-tod-goodix` (dropping `override` entirely, per the documented workaround for this exact error class) — failed differently: `error: Non-local fileoverrides not implemented`. `--force-replacefiles` only resolves conflicts between packages being layered together in the *same* transaction; it does not apply to a conflict against a file owned by the base image itself, which is what this actually was. This is the step that revealed the real fix: the base package has to be gone from the tree *before* the new file is checked out, not fought with in the same pass.

**Reversibility:** `rpm-ostree rollback` covers this fully — every attempt
above only ever produced a *staged* deployment; the currently booted
deployment (`44.20260816.0`, stock `libfprint`) was untouched throughout, and
the pre-existing deployment underneath it remains available regardless of how
this one boots.

**Captured in:** `hosts/thinkpad-e14-gen5/quirks.sh` (script prints the
corrected two-step commands, not the single `override replace` that fails)

**Tally:** time-to-fix ~25m · first proposal: wrong

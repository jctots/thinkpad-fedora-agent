## I022 — 2026-08-23 — /update-check never actually checked the extras flatpak manifest

**Area:** agent

**Symptom:** `scripts/update-check.sh` only ever printed a `-- public --`
Flatpaks section, never `-- extras --`, across every run this session —
even though `EXTRAS_DIR` was confirmed set (non-placeholder) in
`local/secrets.env` and the extras repo's `scripts/flatpaks.sh` exists and
is fully wired (writable by this session, run directly, documented in
`PACKAGES.md`). All 12 apps in the extras manifest (Betterbird, OnlyOffice,
RcloneUI, Steam, ProtonVPN, Mullvad Browser, Brave, SimpleScan, ScanTailor
Advanced, OBS Studio, VLC, Obsidian) had silently never been update-checked.

**Cause:** `update-check.sh` looked for the extras manifest at
`$EXTRAS_DIR/flatpaks.sh` (repo root) — correct for the extras repo's
*original*, flat layout. The extras repo was later restructured into a
`scripts/`/`docs/`/`hosts/` split (see that repo's "Restructure extras
convention" commit), moving `flatpaks.sh` to `scripts/flatpaks.sh`.
`update-check.sh` was never updated to match — a cross-repo reference that
silently went stale at the restructure, rather than a bug that was always
there. The existence check (`[ -f "$EXTRAS_DIR/flatpaks.sh" ]`) just failed
after that and the whole `sources["extras"]` branch was skipped, with no
warning path for "extras configured but manifest not found at the expected
path" — so this had no visible symptom other than a section that quietly
stopped appearing.

Separately (same investigation, lower severity): the extras manifest
declares `com.rcloneui.RcloneUI` and `com.valvesoftware.Steam` twice each —
once in its `apps` install array, again in a separate `overrides` array
(same app ID, extra `flatpak override` flags) — and `extract_ids`'s plain
grep can't tell those apart, so even once the path is fixed, those two IDs
would get checked (and printed) twice.

**Fix:**
- `scripts/update-check.sh`: `$EXTRAS_DIR/flatpaks.sh` → `$EXTRAS_DIR/scripts/flatpaks.sh`
  in both the existence check and the `sources["extras"]` assignment,
  matching the extras repo's current layout.
- `extract_ids()`: pipe through `awk '!seen[$0]++'` to de-duplicate IDs
  before the check loop runs, so an ID declared in both an `apps` and an
  `overrides` array (or any future manifest doing the same) is only checked
  once.
- Verified end-to-end: all 12 extras apps now appear under `-- extras --`,
  each exactly once, all reporting `current`.

**Tried first:** Assumed a `local/secrets.env` misconfiguration first (the
more common failure mode for this mechanism) — asked the user to confirm
`EXTRAS_DIR` was set. It was. Rather than reading `local/secrets.env`
directly to debug further (denied to this agent, correctly, per this repo's
own rule), verified indirectly: sourced it in a throwaway subshell and
tested only derived booleans (`EXTRAS_DIR` non-empty/non-placeholder, and
whether it matched the known extras repo path) without ever printing its
contents — isolated the bug to the hardcoded path inside `update-check.sh`
itself, not the user's config. The actual root cause (a stale reference
surviving a layout change in a *different* repo) only came out when the
user pointed out the extras restructure directly — worth remembering that a
script referencing another repo's paths can go stale silently when that
other repo reorganizes, with nothing on either side to catch it.

**Reversibility:** `/var/home` (this repo is a git working tree; the fix is
a plain code change, trivially revertible via git). No system-level change
involved.

**Captured in:** `scripts/update-check.sh`

**Tally:** time-to-fix ~10m · first proposal: partial (correctly isolated
the failure to a path problem in `update-check.sh` without needing to read
the gitignored config, but didn't independently connect it to the extras
restructure — the user supplied that link)

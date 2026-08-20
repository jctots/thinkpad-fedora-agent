## I018 — 2026-08-20 — reset-triage skill missed a real crash (crash marker on wrong `last -x` line)

**Area:** agent

**Symptom:** User reported "there is a crash, I just recovered from it" after
an "I'm back" session already ran the `reset-triage` skill and reported
nothing — its detection command `last -x reboot | head -1` showed
`still running` for the crashed boot, not `crash`. `last -x` (unfiltered)
did show `crash`, but on the login-session line, not the `reboot` line:

```
jcdedios tty2         local            Thu Aug 20 11:37 - crash  (03:39)
reboot   system boot  7.1.8-200.fc44.* Thu Aug 20 11:37   still running
```

The underlying crash itself was a suspend hang: kernel log for the crashed
boot (`journalctl -b -1 -k`) ends abruptly at `PM: suspend entry (s2idle)`
immediately followed by `NVRM: nvCheckOkFailedNoLog: Check failed: Out of
memory [NV_ERR_NO_MEMORY]` — a recurrence of the open s2idle resume-hang
investigation (project memory), now with a specific NVIDIA-driver OOM
signature at suspend entry. `pm_trace`'s hash-matches line on the next boot
pointed to `acpi PNP0C04:00`, consistent with a suspend-path hang but not
more specific than the NVRM line.

**Cause:** `last -x`'s `crash` annotation on this system is only ever
written on the tty/login-session record, never on the `reboot` record — a
`reboot` line just perpetually reads `still running` once no shutdown
record follows it, whether that's because the boot is genuinely current or
because a prior boot crashed and no closing shutdown record was ever
written. The skill's original detection command filtered specifically to
`reboot` lines, so it could structurally never see the tag.

**Fix:** Replaced the detection command in
`.claude/skills/reset-triage/SKILL.md` with an awk one-liner that scans
`last -x` (unfiltered, most-recent-first) for a `crash` line, bounded to
stop at the second `reboot` line encountered (the boundary where the
boot-before-last starts), so only the current + immediately-prior boot are
considered:

```
last -x | awk '
  /^reboot/ { n++; if (n==2) exit }
  /crash/ { print; exit }
'
```

**Tried first:** Nothing — the bug was in the skill from its original
design (confirmed against boot `711aacda` per the skill's own rationale
section, but that confirmation only checked that `crash` appeared
*somewhere* in `last -x` output for that boot, not that the `reboot`-only
filter would actually surface it — the filter itself was never
individually exercised against a real crash until this one).

**Reversibility:** `/var/home` — plain repo edit, covered by normal git
history in this repo.

**Captured in:** `.claude/skills/reset-triage/SKILL.md` (fixed in place;
rationale section updated to record the correction).

**Tally:** time-to-fix ~15m · first proposal: right

---

## Follow-up: NVRM-OOM suspend hang isolation and mitigation (same session)

Investigating the crash itself (not the detection bug above) turned up
more than the skill's own scope covers, so recording it here rather than
opening a separate incident for a fix that isn't fully confirmed yet.

**Isolation:** the same `nvCheckOkFailedNoLog ... NV_ERR_NO_MEMORY
(_memdescAllocInternal)` signature appears 5x across the last several
boots (`journalctl -b {0,-1,-2,-7}`), but was only fatal once (this crash).
Boot `-1` (the crash) had 2 suspend cycles — 1st succeeded, 2nd hung and
never resumed. Boot `-2` (clean shutdown) hit the same NVRM-OOM message 3
times across 3 suspend cycles without crashing. So the OOM message alone
isn't sufficient to explain the hang; `last -x` shows 8 total crashes in
the last 5 days, all in this cluster.

**Cause (partial):** driver 610.57.04 uses
`NVreg_UseKernelSuspendNotifiers=1` (confirmed via
`/proc/driver/nvidia/params`), the modern kernel-PM-notifier suspend path
that superseded the old `/proc/driver/nvidia/suspend` +
`nvidia-suspend.service` mechanism (that service's "Skipped due to
exec-condition" in the crashed boot's log is expected behavior on this
driver version, not a bug). With `PreserveVideoMemoryAllocations: 2`
("auto"), the driver backs up VRAM into a pinned kernel allocation at
suspend entry; that allocation failed with `NV_ERR_NO_MEMORY` despite ~5GB
free system RAM — consistent with community reports (Arch/Gentoo forums)
of this failing under memory fragmentation even when `free -h` looks fine.
Root cause of *why this one hung fatally* while 4 other occurrences didn't
is still unconfirmed.

**Mitigation applied:** `/etc/modprobe.d/nvidia-suspend-fix.conf`:
```
options nvidia NVreg_TemporaryFilePath=/var/tmp
```
Redirects the VRAM backup to a file instead of a pinned allocation,
targeting the specific allocation path that failed. Community-reported fix
for this exact signature (see sources below). `nvidia` is not baked into
the initramfs on this host (`lsinitrd -m` shows no nvidia module), so no
`dracut` regen was needed — a reboot alone reloads the module with the new
param. Committed via `pkexec etckeeper commit` (commit `1302acc`).
**Unverified** — needs a reboot and enough suspend/resume cycles to know if
it actually prevents a recurrence; the open s2idle investigation (project
memory) stays open until then.

**Reversibility:** `/etc` — `etckeeper`, commit `1302acc`. To roll back:
`pkexec rm /etc/modprobe.d/nvidia-suspend-fix.conf && pkexec etckeeper commit "revert I018 mitigation"`, reboot.

**Sources:**
- [NV_ERR_NO_MEMORY after some time — Arch Linux Forums](https://bbs.archlinux.org/viewtopic.php?id=307380)
- [System fails to suspend: NVIDIA GPU PM error -5 — Arch Linux Forums](https://bbs.archlinux.org/viewtopic.php?pid=2300838#p2300838)
- [NVIDIA cannot resume from suspend with PreserveVideoMemoryAllocations — Arch Linux Forums](https://bbs.archlinux.org/viewtopic.php?id=290126)

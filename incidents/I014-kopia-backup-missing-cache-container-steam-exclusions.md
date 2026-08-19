## I014 — 2026-08-19 — kopia-backup.sh exclusion list missed .cache, containers, and Steam

**Area:** backup

**Symptom:** First real `scripts/kopia-backup.sh` run (see I013 for the connect step that preceded it) ran far longer than the file count in `$HOME` would suggest — the user, watching for a stuck loop/recursion, flagged it as taking too long for "not a lot of files." Inspecting the running process (`lsof -p <pid>`) showed it walking `~/.var/app/com.valvesoftware.Steam/` — game library cache, userdata, browser cache under Steam's flatpak data dir.

**Cause:** The script's original ignore list (`data/google-drive`, `data/one-drive`, `data/syno-drive`) only covered the three rclone cloud-mount FUSE views, which was the one exclusion category anyone had reasoned about when the script was written. It never considered locally-generated disposable/reproducible data: `~/.cache` (7.1G), `~/.local/share/containers` (1.1G toolbox/podman images), and `~/.var/app/com.valvesoftware.Steam` (33G — game library + userdata + browser cache). None of this is irreplaceable: caches regenerate, container images are re-pullable, Steam's library reinstalls from Steam itself. Backing it up daily would have made every snapshot slow and bloated the shared repository for zero recovery value.

**Fix:** Added four more `--add-ignore` rules to `scripts/kopia-backup.sh`:
```bash
--add-ignore ".cache" \
--add-ignore ".local/share/containers" \
--add-ignore ".var/app/com.valvesoftware.Steam" \
```
(plus `.SynologyDrive`, added separately in the same session after finding and deleting an unused, unmanaged Synology Drive Client install — see the working tree diff in the same commit as this incident). Cancelled the in-flight snapshot (`kill -9` on the `kopia snapshot create` process — no partial-snapshot state to clean up, kopia only commits a snapshot manifest on completion), re-ran with the corrected policy. Second run: 14 GB, 24,272 files, 18m24s — down from an open-ended first run that was still walking Steam data after several minutes.

**Tried first:** The script as originally written was treated as complete because it explicitly reasoned about *one* category of large local data (cloud-mount FUSE views) — that reasoning read as thorough at the time it was written, but nobody had checked what else lived under `$HOME` at actual backup time. The size breakdown (`du -sh ~/.var ~/.cache ~/.local/share/containers`) that would have caught this wasn't run until the user's live "is this stuck" question prompted it.

**Reversibility:** `/var/home` backup layer itself — the script this incident is about. No prior snapshot existed yet to lose; the in-flight one was killed before it committed, so nothing to roll back.

**Captured in:** `scripts/kopia-backup.sh` (same commit as I013's docs/recovery.md fix).

**Tally:** time-to-fix ~15m · first proposal: wrong

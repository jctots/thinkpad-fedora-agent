## I013 — 2026-08-19 — kopia SFTP connect needs auth flags and a multi-algorithm known_hosts file

**Area:** backup

**Symptom:** `kopia repository connect sftp --host ... --path ... --username ...` (the command as documented in `docs/recovery.md` Card 3 before this session) failed in stages:

```
can't connect to storage: must provide either --sftp-password, --keyfile or --key-data
```

then, after adding `--sftp-password`/`--password`:

```
can't connect to storage: must provide either --known-hosts or --known-hosts-data
```

then, after pointing `--known-hosts` at a file containing only the host's `ssh-ed25519` line (captured from `ssh-keygen -F <host>`):

```
ssh: handshake failed: knownhosts: key mismatch
```

despite that being the exact key `ssh` itself already trusted and connected with on the same host/port.

**Cause:** Two separate gaps. First, the repo's shared kopia server (a private home-lab host, same one other private infra there uses) authenticates SFTP by password, not key — the recovery.md command never had auth flags at all, because it was written before the connection had actually been exercised. Second, kopia's Go SSH client negotiates a host-key algorithm independently of whatever the system `ssh` client last used, and a `known_hosts` file with only one algorithm's line causes `knownhosts: key mismatch` if kopia's client happens to pick RSA (which was present on the server) instead of ed25519. The single-algorithm file was a false lead — it looked complete because `ssh-keygen -F` and a plain `ssh` connection both used ed25519 successfully against the same host.

**Fix:**
```bash
. local/secrets.env
ssh-keyscan -p 22 "$KOPIA_SFTP_HOST" > ~/.config/kopia/known_hosts   # all algorithms, not just one
kopia repository connect sftp \
  --host "$KOPIA_SFTP_HOST" --path "$KOPIA_SFTP_PATH" \
  --username "$KOPIA_SFTP_USER" \
  --sftp-password "$KOPIA_REPO_PASSWORD" --password "$KOPIA_REPO_PASSWORD" \
  --known-hosts ~/.config/kopia/known_hosts
```
`KOPIA_REPO_PASSWORD` doubles as both the SFTP login password and the kopia repository encryption password — confirmed against that private infra's own kopia docs, which document the same convention. `--known-hosts` must point at a path that survives reboot (`~/.config/kopia/known_hosts`), not `/tmp` — the repository config stores that path literally and re-reads it on every connect.

**Tried first:** Ran the recovery.md command as documented (no auth flags at all) — failed immediately, expected once the missing-flag error appeared. Then tried `--known-hosts /tmp/kopia_known_hosts` containing just the single matching `ssh-ed25519` line, reasoning that since `ssh-keygen -F` and a direct `ssh` test both confirmed that exact key was already trusted, one line should be sufficient — this looked right and still failed with `key mismatch`, which was the confusing part. Also separately tried `~/.ssh/known_hosts` unfiltered, which has a mix of bracketed `[host]:2022` and plain `host` entries from other tools' historical connections at different ports — still mismatched, because it lacked a plain-hostname ecdsa line. The fix that worked was `ssh-keyscan` capturing all three algorithms (ed25519, rsa, ecdsa) as plain `host key` lines into one dedicated file.

**Reversibility:** none at the connect-attempt layer — this is talking to an external shared repository, not writing local state that needed rollback. The one local write, `~/.config/kopia/known_hosts`, is trivially regenerable via `ssh-keyscan`.

**Captured in:** `docs/recovery.md` Card 3 (updated with the working command and the known_hosts caveat, same commit as the kopia scripts). `scripts/kopia-backup.sh` / `scripts/install-kopia-backup.sh` don't call `connect` themselves — this remains a one-time manual step per machine.

**Tally:** time-to-fix ~25m · first proposal: wrong

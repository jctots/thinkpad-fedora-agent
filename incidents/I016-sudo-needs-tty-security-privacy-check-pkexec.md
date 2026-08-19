## I016 — 2026-08-19 — `security-privacy-check.sh`'s Lynis section fails with `sudo -v` on first real run

**Area:** agent

**Symptom:** First real run (post-`lynis` install, post-reboot) produced:
```
Place your finger on the fingerprint reader
Verification timed out
sudo: a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper
sudo: a password is required
error   sudo authentication failed — lynis needs root for a full scan
```
`scripts/etc-drift.sh` had the identical pattern latent in it (`sudo -v`
against `/etc`'s git state), confirmed once the fix for the first script
prompted a check of the other one.

**Cause:** Both scripts called `sudo -v` (or `sudo git ...`) to get root.
When Claude Code runs a script via the Bash tool, there is no controlling
TTY — `sudo` has nothing to prompt against, and even fingerprint auth
(which also goes through PAM) times out with nowhere to display its own
prompt.

**Fix:** Replaced every `sudo` call in both scripts with a single
`pkexec bash -c '...'` wrapping the whole root-needing sequence. `pkexec`
pops GNOME's own polkit dialog — a real on-screen window independent of
the invoking process's TTY — so it works identically whether a human or
the agent invokes it. This was already CLAUDE.md's stated rule for root
commands (`pkexec`, not plain `sudo`); the first version of these two
scripts had drifted from it. Diff of the actual change: `sudo -v` +
`sudo lynis ...` / `sudo git -C /etc ...` → `pkexec bash -c '...'`, output
captured and parsed from the single call instead of chained separate
`sudo` invocations.

**Tried first:** Nothing — the scripts were originally written with
`sudo`, on the (wrong) assumption that an interactive `sudo -v` up front
would be enough, same pattern as several other read-mostly scripts in this
repo that do prompt correctly when a human runs them in a real terminal.
It wasn't caught in review because both scripts' happy-path (missing-lynis
branch, or a clean `/etc`) never actually exercised the `sudo` call during
earlier testing — only this session's first *real* audit run against an
installed `lynis` actually hit the code path. Separately, while verifying
that `NETW-3200`'s protocol blacklist worked, ran `pkexec modprobe
sctp/rds/tipc` to test it — this was itself a mistake: explicit `modprobe`
bypasses a blacklist entirely (a blacklist only blocks *automatic*
alias-triggered loading), so the "test" actually loaded three modules into
the live kernel. `tipc`/`rds` unloaded cleanly afterward; `sctp` wouldn't
unload (refcount held by what looks like per-namespace protocol
registration, not active traffic) and was left in place — harmless, and
self-clears on the next reboot since the blacklist prevents it reloading.

**Reversibility:** `etckeeper` — both script fixes are `/etc`-external
(the scripts live in this git repo, not `/etc`), so ordinary `git revert`
covers them. The incidental `sctp` module load has no persistent-config
exposure (not written anywhere, doesn't survive reboot); the real fixes
applied via this session's Lynis hardening pass are separately committed
to `/etc` via `etckeeper` (commits `5dc4784`, `469f9c5`).

**Captured in:** `scripts/security-privacy-check.sh`,
`scripts/etc-drift.sh` — both fixed and verified end-to-end this session.

**Tally:** time-to-fix ~10m · first proposal: right

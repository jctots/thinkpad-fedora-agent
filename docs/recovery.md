# Recovery without the agent

**Export this to your phone or print it, alongside `bootstrap.md`, before the
wipe.** If you are reading it on the machine it describes, it is already the
wrong copy.

Everything here is a human at a keyboard. No network, no Claude, no agent
session, no login flow. That is the point of the document: this project claims
the machine is reversible, and a reversibility that requires an LLM to be
reachable is not reversibility. It is a subscription.

The agent's failure modes and the machine's are also correlated. A broken
GNOME, a dead NIC or a firmware problem is a plausible reason you *cannot* open
a session — which is exactly when you need to roll back.

> **Verification status.** The commands below are written from the documented
> behaviour of `rpm-ostree`, `ostree` and `etckeeper`. `bootstrap.md` §3.8
> requires walking this card once on a working system before the agent is
> given work. Correct anything here that turns out to be wrong, at that
> point, and record the walk-through in `incidents/` once it happens.

---

## Card 0 — Before you start

- **The LUKS passphrase is in Bitwarden**, reachable from the phone. If the
  machine will not boot far enough to decrypt, nothing else on this card
  matters. Confirm you can reach it from a second device.
- **Work out which layer broke** before touching anything:

| Symptom | Card |
|---|---|
| Broke after a package install, rebase, or kernel argument change | 1 — OS image |
| Broke after a config, unit file, or polkit change | 2 — `/etc` |
| Files under your home directory are gone or wrong | 3 — `/var/home` |
| Will not boot at all, or the disk is unreadable | 4 — total loss |

If you cannot tell, work down the list in order. Card 1 is the cheapest and the
most likely.

## Card 1 — Roll back the OS image

The previous deployment stays on disk until something explicitly cleans it up.
This is the layer that covers everything `rpm-ostree` did.

**If the machine boots:**

```bash
rpm-ostree status          # which deployment is running (●), which is pinned
rpm-ostree rollback        # swap to the other one
systemctl reboot
```

**If the machine does not boot far enough to get a shell:**

1. Reboot and hold <kbd>Esc</kbd> (or <kbd>Shift</kbd>) to bring up the GRUB
   menu.
2. Pick the **second** Fedora entry. The list is newest-first, so the second
   one is the previous deployment.
3. That boots you into the old deployment for one boot only. Once you have a
   shell, make it permanent with `rpm-ostree rollback` and reboot again.

**Verify you actually moved:**

```bash
rpm-ostree status          # the ● should be on a different commit than before
ostree admin status
```

**If there is only one deployment**, this layer is empty and cannot help — that
is the state a fresh install is in until its first layered change. Go to Card 4.

## Card 2 — Revert an `/etc` change

`etckeeper` makes `/etc` a git repository. Every change since the baseline
commit is a diff, including changes made by `rpm-ostree`.

```bash
sudo git -C /etc log --oneline -20        # what changed, most recent first
sudo git -C /etc show <commit>            # read it before reverting it
```

**Revert one file** — the usual case, and the one to prefer:

```bash
sudo git -C /etc checkout <commit>^ -- path/to/file
```

**Revert an entire commit:**

```bash
sudo git -C /etc revert --no-edit <commit>
```

Then restart whatever consumes the file — `systemctl daemon-reload` for unit
files, a service restart, or a reboot if you are not sure.

**If `git -C /etc log` reports "not a git repository"**, `etckeeper` was never
initialised and this layer does not exist. Nothing here will work; you are on
Card 4 for anything you cannot reconstruct by hand. Set it up before the next
time (`bootstrap.md` §3.8).

**If there are uncommitted changes in `/etc`**, someone changed a file without
`etckeeper` committing it. Look at `sudo git -C /etc status` first — the change
you want to undo may simply not be recorded, in which case the diff in the
working tree *is* the record and `git -C /etc checkout -- <file>` undoes it.

## Card 3 — Restore `/var/home`

Nothing else covers your home directory. This layer is exactly as good as the
last time the backup ran.

> **Verified end-to-end** (2026-08-19, see `incidents/`). kopia to the
> home-lab NAS, over Tailscale — same shared repository the `3etn-net-iac`
> VMs use (host/path/user in `local/secrets.env`, never inlined here).
> First snapshot: 14 GB, 24,272 files, 18m24s. Restore test (mount + copy
> one file out, diff against the live copy) passed.

### Check freshness before you trust it

The first thing, always. A backup that last ran nine days ago is not the layer
you think you are standing on, and this is the one card where finding that out
early changes what you do next.

```bash
scripts/backup-status.sh          # age of the last successful snapshot
kopia snapshot list "$HOME"       # the same thing, the long way
```

### The chain on a reinstalled machine

Nothing below works until all of this is true. On a fresh Silverblue that is
five steps, and it is why this card exists rather than a one-line command.

1. **Network.** Any network.
2. **Tailscale up**, so the NAS is reachable from wherever you are. The NAS is
   not on the LAN you are standing on unless you are at home.
3. **kopia installed** — layered with `rpm-ostree`, which means a reboot.
4. **The repository password**, from Bitwarden, reachable from your phone
   alone. Same bar as the LUKS passphrase; see `bootstrap.md` §1.2.
5. **Connect** to the repository, then install the daily timer.

```bash
# 3 — install (kopia isn't in Fedora's repos — add its own RPM repo first,
# same category as the fingerprint COPR in hosts/thinkpad-e14-gen5/quirks.sh;
# scripts/layer-packages.sh prints these same commands if the repo is missing)
sudo rpm --import https://kopia.io/signing-key
cat <<'EOF' | sudo tee /etc/yum.repos.d/kopia.repo
[Kopia]
name=Kopia
baseurl=https://packages.kopia.io/rpm/stable/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://kopia.io/signing-key
EOF
scripts/etc-drift.sh          # confirm etckeeper committed the new repo file
sudo rpm-ostree install kopia && systemctl reboot

# 5 — connect (host/path/user/password come from local/secrets.env, never
# inlined here — see that file's kopia section; KOPIA_REPO_PASSWORD doubles
# as both the SFTP login password and the repo encryption password, same
# convention 3etn-net-iac's VMs use)
#
# --known-hosts must point at a FILE that survives reboot, not /tmp — kopia
# rejects a partial known_hosts (e.g. only the ed25519 line) with "key
# mismatch" if it negotiates a different host-key algorithm, so capture all
# of them:
#   ssh-keyscan -p 22 "$KOPIA_SFTP_HOST" > ~/.config/kopia/known_hosts
. local/secrets.env
kopia repository connect sftp \
  --host "$KOPIA_SFTP_HOST" --path "$KOPIA_SFTP_PATH" \
  --username "$KOPIA_SFTP_USER" \
  --sftp-password "$KOPIA_REPO_PASSWORD" --password "$KOPIA_REPO_PASSWORD" \
  --known-hosts ~/.config/kopia/known_hosts
kopia repository status          # confirm before trusting anything below

# schedule the daily snapshot (persistent — catches up if the laptop was
# asleep or offline at the scheduled time)
scripts/install-kopia-backup.sh
```

### Restore one file

The common case, and the one to reach for. Mounting is friendlier than
`restore` under pressure: you browse, you copy, nothing is overwritten by
accident.

```bash
kopia snapshot list "$HOME"               # find the snapshot you want
mkdir -p /tmp/snap && kopia mount <snapshot-id> /tmp/snap
cp /tmp/snap/path/to/file ~/path/to/file
umount /tmp/snap
```

### Restore the whole home directory

Onto a fresh install, before you log into anything else that will write there.

```bash
kopia restore <snapshot-id> /var/home/jcdedios
```

Then check `~/.ssh` permissions before using the keys — a restore that
loosens them leaves you with keys `ssh` will refuse.

### What this layer does not cover

- Anything since the last snapshot. Check the age first; that is why it is the
  top of this card.
- A house-level event. The NAS is in the same building as the laptop. Whether
  there is an offsite copy is a decision that may still be open — if it is,
  this layer is single-copy and a fire is not recoverable from.
- The repository password itself. It is not in the backup, for obvious reasons.
  If it is lost, everything above is ciphertext.

## Card 4 — Total loss

The machine will not boot, the disk is unreadable, or the deployment store is
gone.

1. Write the Fedora Silverblue ISO to a USB stick from another machine.
2. Reinstall, following [`bootstrap.md`](bootstrap.md) Part 2.
3. Clone this repo and run through Part 3. The manual is inside the repo and the
   repo is on GitHub — that ordering is deliberate, and §1.3b of the manual is
   the reason. If this machine has a private extras layer, §3.7b is in that
   walk and is not optional here — skipping it leaves `install.sh` silently
   not installing anything the extras repo covers.
4. Restore `/var/home` from Card 3.

What you lose is whatever was only in `/var/home` since the last backup, and
whatever was never recorded in this repo or its extras layer. The second one
is the drift risk that `incidents/` exists to bound.

## Card 5 — Afterwards

**Write the incident anyway.**

An incident recovered by hand, because the agent was unreachable — no network,
a usage limit, a broken session, an outage — still gets a file in `incidents/`
and a row in the index, with `n/a — agent unavailable` in the first-proposal
column.

Those rows are not noise. This project's claim is that a privileged agent plus
reversibility makes a Linux desktop cheaper to live with than maintaining it
by hand. Availability is part of that cost. A tally that counts only the
sessions where the agent was working measures the arrangement on its best
days and proves nothing.

Record, at minimum: what broke, which card you used, how long it took, and why
the agent was not available.

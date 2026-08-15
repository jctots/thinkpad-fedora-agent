"""The reversibility ruleset.

This is the substance of the project. Everything else in `.claude/` is
plumbing around it.

The axis is not privilege. `sudo`, `rpm-ostree` and `systemctl` are this
machine's ordinary work — a guardrail that blocks them forbids the agent from
doing its job. What gets denied is what no layer of the reversibility triad
can undo:

    OS image     rpm-ostree rollback   — the previous deployment stays pinned
    /etc         etckeeper             — every change becomes a git diff
    /var/home    backups               — nothing else covers it

A command is DENY only if it falls outside all three. Everything privileged
but covered is ASK, which is a prompt, not a wall.

Kept as a separate module from the hook that applies it so a second machine —
the home lab, a VM — can vendor the ruleset without the harness around it.

Adding a rule: state which layer would have to undo it and why that layer
cannot. If you cannot name the layer, the rule belongs in ASK.
"""

# --- helpers ------------------------------------------------------------------
# Patterns are matched against the raw command string, anywhere in it. That is
# deliberate: the threat is the dangerous text appearing at all, including
# inside chains (`a && b`), wrappers (`timeout 30 wipefs …`), subshells and
# `toolbox run …`. Anchoring to the start of the command is exactly the
# mistake that makes `cd /x && sudo y` walk past a prefix rule.

# Paths whose loss no layer covers. /sysroot and /ostree are the deployment
# store itself — destroying them destroys the rollback target along with the
# running system. /var/home is user data, covered only by a backup that has to
# have actually run.
_UNRECOVERABLE_PATHS = r"(?:/sysroot|/ostree|/var/home|/var/lib/flatpak|/boot|/etc|/var|/home|/)"

# Block devices and the LUKS header live outside every layer. Writing to them
# is the one operation that can end the machine while it is running.
_BLOCK_DEV = r"/dev/(?:nvme\d+n\d+|sd[a-z]|vd[a-z]|mmcblk\d+|dm-\d+|mapper/\S+)"

# `rm` with a recursive flag, up to and including the opening quote of its
# first path argument. Flags may appear in any order and on either side.
_RM_R = r"\brm\s+(?:-\S+\s+)*-\S*[rR]\S*\s+(?:-\S+\s+)*['\"]?"

# End of a path token. Fussy on purpose: it must accept the path being quoted,
# trailing-slashed, or globbed — `/*` is how `rm -rf /` actually gets written —
# while still NOT matching `/home/jc/scratch`, which is backup-covered and
# belongs in ASK. All three of those forms walked past the first version of
# this rule and were caught by probing it, which is the argument for the probe.
_PATH_END = r"(?:/?\*|/?['\"]?(?:\s|$))"


# --- DENY ---------------------------------------------------------------------
# Irreversible. No rollback, no etckeeper diff, no backup brings this back.
# Each entry is (pattern, label, why-no-layer-covers-it).

DENY = [
    # -- Filesystem and partition destruction ---------------------------------
    (r"\bwipefs\b",
     "wipefs",
     "erases filesystem signatures; the partition table survives but nothing on it is mountable"),

    (r"\bmkfs(?:\.\w+)?\b",
     "mkfs.*",
     "formats a filesystem — every layer that could restore it lived on it"),

    (r"\bmkswap\s+" + _BLOCK_DEV,
     "mkswap on a block device",
     "same as mkfs if the device is not already swap"),

    (r"\bblkdiscard\b",
     "blkdiscard",
     "issues TRIM across the device; on SSDs the data is gone at the controller"),

    (rf"\bdd\b[^|;&]*?\bof=\s*{_BLOCK_DEV}",
     "dd to a block device",
     "writes past every filesystem; the running deployment included"),

    (rf">\s*['\"]?{_BLOCK_DEV}",
     "shell redirect to a block device",
     "same as dd, in the form that a deny list on `dd` alone misses"),

    (rf"\btee\b[^|;&]*?{_BLOCK_DEV}",
     "tee to a block device",
     "the third spelling of `dd`; found by probing, not by reading the list"),

    (r"\bshred\b",
     "shred",
     "overwrites in place, specifically so that recovery is impossible"),

    # -- Disk encryption -------------------------------------------------------
    # The LUKS header is the only copy of the key material. Without it the
    # passphrase in Bitwarden decrypts nothing.
    (r"\bcryptsetup\b[^|;&]*?\b(?:luksFormat|luksErase|erase)\b",
     "cryptsetup luksFormat / luksErase",
     "destroys the LUKS header — the disk becomes unrecoverable ciphertext"),

    (r"\bcryptsetup\b[^|;&]*?\bluksKillSlot\b",
     "cryptsetup luksKillSlot",
     "removes a key slot; if it is the last one the volume is unopenable"),

    # -- Partition tables ------------------------------------------------------
    (r"\bsgdisk\b[^|;&]*?(?:-Z\b|--zap-all\b|-o\b|--clear\b)",
     "sgdisk --zap-all / --clear",
     "erases the GPT; partitions are not addressable afterwards"),

    (r"\bparted\b[^|;&]*?\b(?:mklabel|mktable)\b",
     "parted mklabel",
     "writes a new partition table over the existing one"),

    (r"\b(?:parted|sfdisk|fdisk)\b[^|;&]*?\brm\b",
     "partition deletion",
     "removes a partition entry; the data is orphaned"),

    # -- LVM -------------------------------------------------------------------
    (r"\b(?:lvremove|vgremove|pvremove)\b",
     "LVM volume/group/physical-volume removal",
     "destroys the container the filesystem lives in"),

    # -- The rollback target itself -------------------------------------------
    # These are the subtle ones. They are not destructive in the usual sense —
    # they remove the thing that makes everything else reversible.
    (r"\bostree\s+admin\s+undeploy\b",
     "ostree admin undeploy",
     "removes a deployment; if it is the rollback target, the OS layer of the triad is gone"),

    (r"\brpm-ostree\s+cleanup\b[^|;&]*?(?:-r\b|--rollback\b)",
     "rpm-ostree cleanup --rollback",
     "deletes the pinned previous deployment — the entire OS-image safety net"),

    (r"\bostree\s+(?:prune|refs\s+--delete)\b",
     "ostree prune / refs --delete",
     "garbage-collects commits the rollback target may depend on"),

    # kopia holds the /var/home layer. Deleting snapshots or the blobs behind
    # them is the same class of act as `rpm-ostree cleanup --rollback`: not
    # destructive to the running system, destructive to the thing that makes
    # the running system recoverable.
    #
    # NOTE: written before kopia was installed. Verify the subcommand surface
    # against `kopia --help` on the machine and correct these — a rule that
    # names a command that does not exist protects nothing and reads as if it
    # does.
    (r"\bkopia\s+snapshot\s+delete\b",
     "kopia snapshot delete",
     "removes the restore points /var/home is classified as reversible against"),

    (r"\bkopia\s+snapshot\s+expire\b[^|;&]*?--delete\b",
     "kopia snapshot expire --delete",
     "same, in the form that looks like maintenance"),

    (r"\bkopia\s+blob\s+delete\b",
     "kopia blob delete",
     "removes repository content directly, underneath the snapshot index"),

    # -- Recursive deletion of paths no layer restores -------------------------
    (rf"{_RM_R}{_UNRECOVERABLE_PATHS}{_PATH_END}",
     "recursive rm of a system root",
     "outside every layer, or the layer's own storage"),

    (rf"{_RM_R}(?:~|\$HOME){_PATH_END}",
     "recursive rm of the home directory",
     "covered only by a backup, and only if it ran"),


    (r":\(\)\s*\{\s*:\|:&\s*\};:",
     "fork bomb",
     "not reversible so much as not survivable"),

    # -- The guardrail layer defending itself ---------------------------------
    # An agent that can edit its own ruleset has no ruleset. These are denied
    # from the shell; the Edit/Write path is denied in settings.json.
    (r"(?:>|>>|\btee\b|\bsed\b[^|;&]*?-i|\bmv\b|\brm\b)[^|;&]*?\.claude/(?:hooks|settings\.json)",
     "modification of the guardrail layer",
     "self-modification: the change that makes every later check meaningless"),

    (r"--dangerously-skip-permissions|--bypass-permissions",
     "permission-bypass flag",
     "turns the whole layer off for the session"),

    # -- Credential exfiltration ----------------------------------------------
    # Not a reversibility question — a disclosure one. A leaked key cannot be
    # un-leaked, which is the same shape, so it lives here.
    (r"\b(?:curl|wget)\b[^|;&]*?(?:--data|--upload-file|-d|-T)\s*@?\S*(?:\.env|id_(?:rsa|ed25519|ecdsa)|secrets|\.ssh/)",
     "upload of a credential file",
     "the disclosure is permanent regardless of what happens locally"),

    (r"\b(?:scp|rsync)\b[^|;&]*?(?:\.env|id_(?:rsa|ed25519|ecdsa)|local/secrets)",
     "copy of a credential file to a remote host",
     "same"),

    # -- The record ------------------------------------------------------------
    # The incident log and commit history are what make the machine
    # rebuildable. Rewriting published history destroys evidence the project's
    # own claim rests on.
    (r"\bgit\s+push\b[^|;&]*?(?:--force(?!-with-lease)|\s-f\b)",
     "git push --force",
     "overwrites pushed history — the record is the deliverable here"),

    (r"\bgit\s+filter-branch\b|\bgit-filter-repo\b",
     "history rewrite",
     "same"),
]


# --- ASK ----------------------------------------------------------------------
# Privileged, consequential, and covered by a layer. These are the job. The
# prompt is there so the command is read before it runs, not to discourage it.

ASK = [
    (r"\bsudo\b|\bpkexec\b|\bdoas\b",
     "privilege escalation",
     "the ordinary case on this machine — read the command, then approve"),

    (r"\brpm-ostree\s+(?:install|uninstall|override|rebase|upgrade|update|initramfs)\b",
     "rpm-ostree layering or rebase",
     "reversible: the previous deployment stays pinned until cleanup"),

    (r"\bsystemctl\s+(?:enable|disable|mask|unmask|start|stop|restart|set-default)\b",
     "systemctl unit change",
     "reversible by hand; unit files under /etc are an etckeeper diff"),

    (r"\bflatpak\s+(?:install|uninstall|override|remote-add|remote-delete)\b",
     "flatpak change",
     "reversible: reinstall, or reset the override"),

    (r"(?:^|[\s;&|])/etc/|\betckeeper\b",
     "touches /etc",
     "reversible as a git diff — provided etckeeper is installed and committing"),

    (r"\b(?:nmcli|firewall-cmd|nft|iptables)\b",
     "network or firewall change",
     "reversible, but can cut the machine off mid-session"),

    (r"\bgit\s+reset\s+[^|;&]*?--hard\b|\bgit\s+clean\s+-\S*f",
     "destructive git working-tree operation",
     "recoverable from the reflog for committed work; uncommitted work is not"),

    (r"\brm\s+(?:-\S+\s+)*-\S*[rR]",
     "recursive delete",
     "under /var/home this is backup-covered; the unrecoverable roots are denied above"),

    (r"\b(?:curl|wget)\b[^|;&]*?\|\s*(?:sudo\s+)?(?:sh|bash|zsh)\b",
     "piping a download to a shell",
     "how Claude Code itself installs — allowed, but the URL gets read first"),

    (r"\b(?:useradd|userdel|usermod|groupadd|passwd|chpasswd)\b",
     "account change",
     "reversible, but a mistake here can lock you out at the next boot"),

    (r"\b(?:fprintd-enroll|fprintd-delete|authselect)\b",
     "authentication stack change",
     "reversible; authselect keeps backups, but a broken PAM stack blocks login"),

    # Retention changes are destructive on a delay — a shortened policy deletes
    # at the next maintenance run, not now. A regex cannot tell a lengthened
    # policy from a shortened one, so this asks rather than denies. Read the
    # numbers.
    (r"\bkopia\s+(?:policy\s+set|maintenance\s+run)\b",
     "kopia retention or maintenance change",
     "shortening retention deletes restore points later, quietly — check the direction"),

    (r"\bkopia\s+(?:restore|repository\s+(?:create|connect|disconnect|sync-to))\b",
     "kopia restore or repository operation",
     "restore overwrites live files; repository operations decide where the layer lives"),

    (r"\bbootc\b|\bgrubby\b|\bkargs\b",
     "boot configuration change",
     "reversible by rollback, but the failure mode is an unbootable machine"),

    (r"\.env\b(?!\.example)|\bid_(?:rsa|ed25519|ecdsa)\b|local/secrets",
     "references a credential file",
     "reading these is legitimate; the prompt is so it is never done absently"),
]

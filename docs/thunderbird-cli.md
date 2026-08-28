# thunderbird-cli — the auth layer, and how to rebuild it

This doc is scoped narrowly: **the authentication layer in front of the
thunderbird-cli bridge**, and the exact steps to reach the current, patched
state on a rebuilt machine. It exists in this repo, not the extras one,
because what it protects against is an *agent-security* incident
(`incidents/I023`) — this session shelling out to `tb` and reading a full
mailbox with zero mail tools configured. Everything else about
thunderbird-cli — why it was chosen over notmuch/mbsync, the bridge's
on-demand lifecycle paired to Betterbird's own launch, the npm-prefix
workaround, the WebExtension side-load steps, the second-brain
`PreToolUse` hook that blocks `mode:"send"` and permanent-delete — is
already documented in the extras repo's
[`docs/THUNDERBIRD-CLI.md`](../../thinkpad-fedora-extras/docs/THUNDERBIRD-CLI.md)
and stays there: thunderbird-cli is a personal-app install
(`scripts/PACKAGES.md`'s "what this deliberately doesn't cover"), the auth
layer around it is not.

**Read the extras doc first for architecture and the base install.** This
doc assumes you have reached the point where `tb health` returns
`{"ok":true,"thunderbird":true}` with no auth involved yet, and picks up
from there.

## Why this exists

Binding the bridge to `127.0.0.1:7700` bounds *remote* access. It is not
access control — every process running as this user, including this
agent's own Bash tool, could call it. Restricting mail tools at the MCP
registration layer (which session's `.mcp.json` lists `tb-mcp`) does
nothing for a session that never goes through MCP at all. See
`incidents/I023` for the full incident.

## Rebuild procedure

### 1. Install thunderbird-cli — upstream if merged, fork otherwise

Check first whether the fix has landed upstream:

```bash
curl -s https://api.github.com/repos/vitalio-sh/thunderbird-cli/pulls/21 \
  | grep -o '"state": *"[a-z]*"'
```

- **If `"state": "closed"` and merged** — a plain upstream install already
  carries the auth code. Follow the extras doc's install step as written
  (`thinkpad-fedora-extras/scripts/thunderbird-cli.sh`, which does
  `npm install -g thunderbird-cli thunderbird-cli-bridge thunderbird-cli-mcp`
  from the public registry) and skip to step 2.
- **If still open** — that script currently installs the *unpatched*
  public packages and writes a unit file with no `EnvironmentFile=`, which
  reproduces the exact vulnerable state I023 fixed. Build from the fork
  instead:

  ```bash
  cd ~/code/thunderbird-cli   # clone git@github.com:jctots/thunderbird-cli.git if missing
  git fetch origin
  git checkout fix/bridge-auth-token
  git pull

  # Do NOT `npm install -g ./bridge` — that symlinks into this working
  # tree, and the running service then silently follows whatever branch
  # this clone happens to be on later. Pack a real tarball instead:
  npm pack ./bridge
  npm install -g thunderbird-cli-bridge-*.tgz

  npm pack ./cli    2>/dev/null && npm install -g thunderbird-cli-*.tgz    || true
  npm pack ./mcp    2>/dev/null && npm install -g thunderbird-cli-mcp-*.tgz || true
  ```

  (Adjust the subdirectory names to match whatever the clone's actual
  layout is at rebuild time — `bridge/`, `cli/`, `mcp/` as of 2026-08-24.)

  Verify it took: `npm ls -g --depth=0` should show no `-> ../..` arrow
  next to any `thunderbird-cli*` package — an arrow means it symlinked
  into the clone instead of installing a self-contained copy.

### 2. Generate a fresh token and the env file

Never reuse a token across rebuilds.

```bash
mkdir -p ~/.config/thunderbird-cli
umask 077
printf 'TB_AUTH_TOKEN=%s\n' "$(openssl rand -hex 32)" > ~/.config/thunderbird-cli/bridge-daemon.env
chmod 600 ~/.config/thunderbird-cli/bridge-daemon.env
```

**Do not** put this token in `~/.config/thunderbird-cli/config.json`. Both
`tb` and `tb-mcp` read that file automatically — a token there would be
picked up by *any* same-user agent's bare `tb` call and reopen exactly the
hole this closes. **Do not** pass it as a CLI argument either —
`/proc/<pid>/cmdline` is world-readable, which widens exposure past
same-UID to every local user.

### 3. Point the systemd user unit at the env file

Edit `~/.config/systemd/user/tb-bridge.service` (written by the extras
install script) to add an `EnvironmentFile=` line if it's not already
there:

```ini
[Service]
Type=simple
EnvironmentFile=%h/.config/thunderbird-cli/bridge-daemon.env
ExecStart=%h/.npm-global/bin/tb-bridge
Restart=on-failure
RestartSec=5
```

Leave the `[Unit]` section's lack of an `[Install]` block alone — the unit
stays `static`, started on demand by `betterbird-with-bridge`, not at
login. That part is unrelated to auth and already correct if the extras
install ran.

```bash
systemctl --user daemon-reload
systemctl --user restart tb-bridge.service   # only if already running
```

### 4. Wrap the credential for second-brain's MCP client

**As of D153, `tb-mcp-authed` sources `~/.config/second-brain/second-brain.env`**
(a file second-brain's own tooling manages), not
`~/.config/thunderbird-cli/bridge-daemon.env` directly — the two are
separate files that must carry the *same* `TB_AUTH_TOKEN` value. If step 2
above regenerates the token in `bridge-daemon.env` (e.g. after a rebuild or
an I029-style credential loss), `second-brain.env` needs the matching value
copied in too, or second-brain's `tb-mcp` calls will get `401`s against a
healthy bridge — see I030.

```bash
mkdir -p ~/.local/bin
umask 077
cat > ~/.local/bin/tb-mcp-authed <<'EOF'
#!/bin/sh
# Launches tb-mcp with the bridge credential loaded from the vault's shared
# secrets file, so the token never appears in a command line (/proc/<pid>/cmdline
# is world-readable). Consolidated from a dedicated bridge-daemon.env onto the
# shared file per second-brain-setup D153.
set -a
. "$HOME/.config/second-brain/second-brain.env"
set +a
exec node "$HOME/.npm-global/bin/tb-mcp" "$@"
EOF
chmod 700 ~/.local/bin/tb-mcp-authed
```

In the second-brain vault's `.mcp.json`, point the `tb-mcp` server entry's
command at `~/.local/bin/tb-mcp-authed` rather than at `tb-mcp` directly.
The vault's config file itself holds no secret — it just launches the
wrapper, which sources the 600-mode env file at exec time.

## Verification — all three must hold

```bash
# 1. No token -> refused
tb accounts
# expect: {"ok":false,"error":"...","code":"AUTH_REQUIRED"}

# 2. With token -> works
TB_AUTH_TOKEN="$(grep -o '=.*' ~/.config/thunderbird-cli/bridge-daemon.env | cut -c2-)" tb accounts
# expect: {"ok":true,"data":[...6 accounts...]}

# 3. Startup banner confirms it
journalctl --user -u tb-bridge.service | grep Auth:
# expect: [bridge] Auth: enabled (Authorization: Bearer required on all HTTP requests)
```

If (1) instead succeeds, the env file isn't wired to the unit, or the
running bridge binary predates the auth patch (check `npm ls -g` for a
symlink arrow, per step 1).

## Standing health check

`tb-bridge.service` is a `static` unit — started on demand by
`betterbird-with-bridge`, never at boot/login — so a crash-loop (I029) can
sit silent between sessions with nothing surfacing it. Since I030,
`hosts/thinkpad-e14-gen5/tb-bridge-status.sh check` runs every 15 minutes
via `tb-bridge-status.timer` and fires a GNOME notification only on a
genuine failure (unit `failed`, or Betterbird running with the bridge not
active) — silent otherwise. Re-run `tb-bridge-status.sh install` if the
timer is ever missing after a rebuild.

## This is not isolation — say so, always

Both the thinkpad agent and the second-brain agent run as the same uid
(1000). The token is recoverable by anything determined enough — reading
the 600-mode env file as this user, or `/proc/<pid>/environ` of the
running `tb-bridge` process. A shared secret cannot divide a trust domain
it lives inside. This closes the *accidental* path (a bare `tb` call with
no special effort) — see `incidents/I023`. Real separation between the two
agents' mail access would need a separate UID for the bridge or for one of
the agents; that is not what this setup does, and nothing here should be
described as isolation.

## `AUTH_REQUIRED` from this session is by design

If a future thinkpad-fedora-agent session runs `tb accounts` and gets
`AUTH_REQUIRED`, that is the fix working. **Do not add `TB_AUTH_TOKEN` to
this session's environment, do not read the second-brain wrapper's token,
and do not "fix" this.** See `CLAUDE.md` and `docs/guardrails.md` §8.

## Known gap at time of writing (2026-08-24)

`thinkpad-fedora-extras/scripts/thunderbird-cli.sh` — the extras-side
installer — still installs the unpatched public `thunderbird-cli-bridge`
package and writes a unit file with no `EnvironmentFile=`. Re-running it
on a rebuild reproduces I023's vulnerable state exactly, unless step 1
above is followed instead. That script belongs to the extras repo and
wasn't updated as part of this fix — flagging it here rather than silently
routing around it. Worth a follow-up in an extras-side session once PR #21
(or its outcome) is settled, so the installer matches whichever path
(upstream-merged vs. fork) turns out to be permanent.

## Also open, out of scope here

Issue #22 upstream: the WebSocket listener on `:7701` still has no auth
and assigns the extension socket unconditionally, so a local process can
seize the extension slot, see every forwarded request, and forge
responses. Needs extension-side changes; not fixed by anything in this
doc.

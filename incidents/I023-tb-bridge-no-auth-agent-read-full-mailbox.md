## I023 — 2026-08-23 — thunderbird-cli bridge had no auth; this agent read the full mailbox with zero mail tools configured

**Area:** agent

**Symptom:** Asked to check unread email, this session (the thinkpad agent —
no MCP wiring, no mail tools in its config) shelled out to the `tb` CLI via
Bash and got a complete, correct answer: account list, per-folder unread
counts, full message bodies. It should have had no path to any of that.
thunderbird-cli was installed and MCP-wired specifically *for the
second-brain agent* (2026-08-23, see the vault's `decisions/D38` and
`thinkpad-fedora-extras/docs/THUNDERBIRD-CLI.md`) — this session was never
supposed to be a client of it at all.

**Cause:** `tb-bridge`, the HTTP↔WebSocket proxy that `tb`/`tb-mcp` talk to
(`http://127.0.0.1:7700`), had no authentication whatsoever. Its config
schema documented an `authToken` field, the CLI already sent an
`Authorization: Bearer` header, and upstream's `SPEC.md` listed auth as a
roadmap item — but the daemon never read the corresponding env var and
never checked the header on any request. Binding to `127.0.0.1` bounds
*remote* access but is not access control: every process running as this
user (uid 1000) — any terminal, any script, any other agent session —
could reach it. Restricting a tool at the MCP-registration layer
(second-brain's `.mcp.json`) does not constrain what that same user's
*shell* can reach; the second-brain agent's careful `PreToolUse` guard
against `mode:"send"` and `permanent:true` delete (see the extras doc) was
never in this session's path to begin with, because this session was never
going through MCP.

**Fix:** Patched `tb-bridge` (`~/code/thunderbird-cli`, fork
`jctots/thunderbird-cli`, branch `fix/bridge-auth-token`, commit
`ba56442`) to require `Authorization: Bearer <token>` matching
`TB_AUTH_TOKEN` on every HTTP request, constant-time compared. An empty
`TB_AUTH_TOKEN` aborts startup rather than failing open. The startup
banner now states plainly whether auth is enabled
(`journalctl --user -u tb-bridge.service` — "Auth: enabled" vs. "Auth:
disabled — any local process can call this bridge"). The token itself:

- lives only in `~/.config/thunderbird-cli/bridge-daemon.env` (mode 600),
  loaded into `tb-bridge.service` via `EnvironmentFile=`
- deliberately **not** in `~/.config/thunderbird-cli/config.json` — both
  `tb` and `tb-mcp` read that file automatically, so a token placed there
  would be picked up by *any* same-user agent's bare `tb` call and reopen
  exactly this hole
- deliberately **not** passed as a CLI argument — `/proc/<pid>/cmdline` is
  world-readable, which would widen exposure past same-UID to every local
  user, not just this one
- reaches the second-brain side only through
  `~/.local/bin/tb-mcp-authed` (mode 700), a wrapper that sources the env
  file and execs `tb-mcp`; the vault's `.mcp.json` holds no secret, it
  just launches the wrapper

Reinstall note for whoever touches this next: the live daemon runs a
**self-contained copy** at
`~/.npm-global/lib/node_modules/thunderbird-cli-bridge/`, independent of
the git clone. A patch to the clone does not reach the running service
until reinstalled with `npm pack ./bridge && npm install -g <tarball>`.
Plain `npm install -g ./bridge` **symlinks** into the working tree instead
— hit and reverted during this fix, because it makes the running service
silently follow whatever branch the clone happens to be on. `npm ls -g`
shows a `-> ../..` arrow if this has happened; it should not.

Verified live 2026-08-24: journal shows `Auth: enabled`, extension
connected, bare `tb accounts` (no token) returns
`{"ok":false,"error":"...","code":"AUTH_REQUIRED"}`, credentialed calls via
the wrapper return all 6 accounts correctly, second-brain's MCP calls work
unchanged through `tb-mcp-authed`.

The fix was upstreamed, not kept private: PR #21 open against
`vitalio-sh/thunderbird-cli` (+258/-6, 10 files), CI gated behind
maintainer approval (first-time-contributor `action_required`, not a
failure). A related gap was filed separately and left open, deliberately
out of this PR's scope because it needs extension-side changes: issue #22
— the WebSocket listener on `:7701` still has no auth and assigns the
extension socket unconditionally, so a local process can seize the
extension slot, see every forwarded request, and forge responses.

**Tried first:** N/A — this was found, not chased. The thinkpad agent was
simply asked to summarize unread mail, used the tool it had (Bash), and
the answer it got back should not have been possible; there was no wrong
turn before the right one.

**Reversibility:** `/var/home` (systemd user unit, gitignored env file, a
wrapper script — all plain files, and the fix itself lives in a git clone
with a full commit history and an upstream PR). No system-level (`/etc` or
OS-image) change was involved anywhere in this incident or its fix.

**Scope, stated honestly — this is not isolation.** This closes the
*accidental* path: an agent shelling out to `tb` with zero special effort,
which is what actually happened here. It is not a hard trust boundary.
Both the thinkpad agent and the second-brain agent run as the same uid
(1000), and the token is recoverable by anything sufficiently determined —
reading the 600-mode env file as this user, or reading
`/proc/<pid>/environ` of the running `tb-bridge` process. A shared secret
cannot divide a trust domain it lives inside. Real isolation between the
two agents' mail access would need a separate UID for the bridge (or for
one of the agents), which is not what this fix does and is tracked as
separate, future work, not implied here.

**What this is not:** the removal of this session's ability to read mail
by shelling out is the *intended outcome* of the fix, not a regression or
a loss of capability to be restored. A future thinkpad-fedora-agent
session hitting `AUTH_REQUIRED` from `tb` should not "fix" it — see
`CLAUDE.md` and `docs/guardrails.md` §8.

**Captured in:** `docs/thunderbird-cli.md` (rebuild procedure, this repo);
`incidents/index.md` §Areas `agent`; upstream PR #21 and issue #22.

**Tally:** time-to-fix ~n/a (found and fixed entirely in a second-brain
session on 2026-08-23/24, before this repo had any record of it) · first
proposal: n/a — this incident predates this repo's involvement; recorded
here after the fact from the second-brain session's account, cross-checked
directly against live machine state (`systemctl`, `journalctl`, file
perms, `npm ls -g`, the GitHub API) rather than taken on faith.

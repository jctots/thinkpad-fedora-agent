## P006 — 2026-08-20 — ASK tier for commands that put pip on system Python

**Direction:** tighten (adds ASK prompts where the ruleset currently returns
ALLOW; not a DENY — see reversibility below, blocking outright would
overreach).

> Loosening never ships in the session that asked for it. If something
> irreversible has to run now, say so and let the human type the command.

**Motivating incident:** this conversation (no `incidents/` entry — nothing
broke, this is a preventive request). jc asked to keep system Python clean —
venv/pipx/poetry only, never a bare `pip install` against the interpreter
itself — while investigating whether adding `podman-compose` (landed via
`rpm-ostree install`, see the extras repo) had touched Python anywhere.
Verification found no prior pip install of any kind on this host, but also
found there is currently nothing that would *stop* one:

- `python3 -m ensurepip` is bundled in the base image's own interpreter — no
  package install needed to bootstrap pip.
- Fedora's usual PEP 668 `EXTERNALLY-MANAGED` guard, which normally makes a
  bare `pip install` refuse to run, isn't present on this system — it ships
  inside the `python3-pip` package, which isn't installed. So today, nothing
  blocks it.

**What happens today:**

```
$ make check CMD='python3 -m ensurepip --user'
  ALLOW   python3 -m ensurepip --user

$ make check CMD='pip install requests'
  ALLOW   pip install requests

$ make check CMD='curl https://bootstrap.pypa.io/get-pip.py | python3'
  ALLOW   curl https://bootstrap.pypa.io/get-pip.py | python3
```

**What should happen, and why:** ASK, not DENY. Either an `rpm-ostree`
layered `python3-pip` (OS-image layer, `rpm-ostree rollback` undoes it) or a
`--user`/`ensurepip` install into `~/.local/lib/python3.14/site-packages`
(`/var/home` layer, covered by the existing `kopia` backup) is reversible —
this isn't the unrecoverable-by-any-layer bar `DENY` is reserved for. But it
is exactly the kind of thing CLAUDE.md's "read the command before it runs"
prompt is for: once pip lands in the global user site-packages, every future
`pip install` (even one that looks like it's going into a venv, if run with
the venv not actually activated) silently pollutes it, and the mistake is
easy to make by accident and easy to miss until a package conflict shows up
much later.

Deliberately **not** flagging bare `pip install X` (no `--user`, no
`ensurepip`, no override flag) — that pattern is indistinguishable at the
command-string level from a legitimate venv-activated install
(`source .venv/bin/activate && pip install -r requirements.txt`), and
`bash-guard.py` only sees the command text, not `$VIRTUAL_ENV`. Flagging it
would nag on the exact venv/pipx/poetry workflow this proposal exists to
protect. The four patterns below target only the unambiguous
system/user-site bypass routes.

**Proposed diff:**

```diff
--- a/.claude/hooks/_ruleset.py
+++ b/.claude/hooks/_ruleset.py
@@ ASK = [
+    (r"\bpython3?\s+-m\s+ensurepip\b",
+     "ensurepip bootstrap",
+     "bundled in the interpreter itself, no package needed — writes pip into "
+     "system or user site-packages depending on flags; reversible (OS image "
+     "or /var/home backup) but should be read, not silent"),
+
+    (r"get-pip\.py\b",
+     "get-pip.py bootstrap",
+     "same bypass as ensurepip via the classic curl-pipe pattern — /var/home "
+     "backup covers the user-site result, but read the command first"),
+
+    (r"\bpip3?\s+install\b[^|;&]*--user\b|\bpython3?\s+-m\s+pip\s+install\b[^|;&]*--user\b",
+     "pip install --user",
+     "writes into ~/.local, bypassing venv/pipx isolation deliberately — "
+     "covered by the kopia /var/home backup, but the point of --user is "
+     "exactly to dodge the isolation this project wants kept"),
+
+    (r"--break-system-packages\b",
+     "pip override of PEP 668 protection",
+     "explicitly disables the one guard that would otherwise stop a bare "
+     "system-wide install — if this flag is being typed, read why"),
 ]
```

**Probe case that fails today:**

```bash
make check CMD='python3 -m ensurepip --user' EXPECT=ask
make check CMD='curl https://bootstrap.pypa.io/get-pip.py | python3' EXPECT=ask
make check CMD='pip install --user requests' EXPECT=ask
make check CMD='python3 -m pip install --user requests' EXPECT=ask
make check CMD='pip install --break-system-packages requests' EXPECT=ask
```

All five currently print `ALLOW`; each should print `ASK` after the patch.

**Blast radius:** hand-simulated the four new patterns against the
venv/pipx/poetry cases they must *not* touch, before proposing this diff:

```
no-match   pip install requests
no-match   python3 -m venv .venv
no-match   source .venv/bin/activate && pip install -r requirements.txt
no-match   pipx install podman-compose
no-match   poetry install
```

None of the four new patterns overlap any existing `DENY` or `ASK` entry
(none of the current rules mention `pip`, `ensurepip`, or `venv` at all —
confirmed via `grep -n "pip\|ensurepip" _ruleset.py` before writing this).
Run `make probe` after applying to confirm the full suite still passes with
no case moving between tiers unexpectedly.

**Outcome:** open

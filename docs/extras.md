# extras — a private layer on top of this repo

This repo is public and meant to be forked. Not every app or config belongs
in its manifest: things that are personal (a specific streaming client), tied
to an employer, or just not worth another forker's review attention. `extras`
is the supported way to keep those out of the public tree without hiding them
from the machine that runs them.

## The shape

A second, private repo — anywhere you like (a private GitHub repo, a private
Gitea instance, a plain directory with its own git history). It is never
referenced from this repo by path, URL, or submodule.

There are two separate mechanisms here, easy to conflate because they take
the same path as input — set one and assume the other follows. It doesn't:

- **`install.sh` running the scripts** — the machine-level connection. One
  line in your own gitignored `local/secrets.env`:
  ```bash
  EXTRAS_DIR="/home/you/code/thinkpad-extras"
  ```
  `install.sh` sources `local/secrets.env`, and if `EXTRAS_DIR` is set to a
  real directory, it runs every `*.sh` in `EXTRAS_DIR/scripts/` — flat,
  alphabetical — after the base layer and host profile. If a directory
  matching the detected host slug exists at `EXTRAS_DIR/hosts/<slug>/`
  (same slug this repo's own `hosts/<slug>/` uses), its scripts run too,
  same base-then-host-profile order as this repo. That split only matters
  once the private repo runs on more than one machine — a single-machine
  extras repo can leave `hosts/` empty or absent. If `EXTRAS_DIR` is unset,
  `PLACEHOLDER`, missing, or `local/secrets.env`
  itself doesn't exist yet, this is a silent no-op — `install.sh` warns and
  skips it, same as it does for every other authenticated step. Every fork
  behaves identically until its owner opts in. **This file is off-limits to
  the agent** — it holds real credentials, so `local/secrets.env` is denied
  even for writes; you create and edit it yourself
  (`cp local/secrets.env.example local/secrets.env`).
- **The agent being able to read/write the private repo's files** — a
  session-level permission, unrelated to `install.sh`. Add the private
  repo's absolute path to `additionalDirectories` in your gitignored
  `.claude/settings.local.json`. Without this, the agent can still tell you
  what to run, but can't create or edit scripts/incidents there itself.

Neither one implies the other. It's entirely possible — and was, for a
while, on this project — to have agent write access to the private repo
while `install.sh` still silently skips it because `local/secrets.env`
hadn't been created yet.

Why not a submodule: a `.gitmodules` entry in a public repo names the private
remote's URL in plain text, and it breaks the clone for anyone forking this
who doesn't have access to that remote. A path read from a gitignored file
has neither problem.

## Setting up your own

1. **Create the private repo.** Anywhere with git and, ideally, SSH access:
   a private GitHub/GitLab repo, a self-hosted Gitea/Forgejo instance, even a
   bare local repo with no remote yet. Nothing about `install.sh` cares where
   it lives.
2. **Clone it** somewhere under your own `~/code/` (or wherever), sibling to
   this repo, not inside it.
3. **Give it the same shape this repo uses**, scaled down to what a private
   layer actually needs:
   ```
   README.md
   incidents/            same convention as this repo's incidents/, own index.md
   incidents/_template.md
   docs/                 procedure/narrative docs (not manifest companions)
   scripts/
     PACKAGES.md         narrated companion to the flatpak/package scripts, if any
     *.sh                flat, idempotent, report-only — same contract as scripts/
   hosts/<slug>/         only once this repo runs on more than one machine —
                         same slug as this repo's own hosts/<slug>/. Most
                         personal app/config choices travel with the person,
                         not the hardware, so this stays empty until
                         something genuinely differs machine-to-machine.
   ```
   The one thing intentionally still skipped: no `local/` in the private
   repo — secrets stay in *this* repo's gitignored `local/secrets.env`,
   which `install.sh` already sources before running extras' scripts.
4. **Point this repo at it**: add `EXTRAS_DIR="/abs/path/to/your-extras"` to
   your gitignored `local/secrets.env` (copy from
   `local/secrets.env.example` if you haven't already).
5. **If you want the agent to write there too** — scripts, incidents, the
   manifest — add the absolute path to `additionalDirectories` in your
   gitignored `.claude/settings.local.json`. This takes effect on the *next*
   session start, not the running one (see CLAUDE.md's "Session shape").
6. Run `./install.sh` — it now runs the base layer, your host profile, then
   every `*.sh` in `EXTRAS_DIR/scripts/`, then (if it exists)
   `EXTRAS_DIR/hosts/<slug>/`, in that order.

## What goes where

Default: **a new app request goes to the private repo**, not this one. This
repo's scope is the harness/infrastructure (`scripts/`, `hosts/`,
`.claude/`) plus the small foundational app set already in
`scripts/install-flatpaks.sh` — things bootstrap or recovery themselves lean
on, or that near enough any fork of this specific project would also want
(currently: an editor, a password manager). Everything else — a specific
app, a personal preference, anything employer-specific — defaults private.
Say "public" explicitly to override; the agent should ask rather than guess
on a genuinely unclear case, not default to the public repo because that's
the one it's sitting in.

## Writing an extras script

Same contract `run_script` enforces on everything else in this repo:

- Idempotent — safe to run on every `install.sh` invocation, changes nothing
  if the desired state already holds.
- Executable (`chmod +x`) or `install.sh` refuses to run it, loudly, rather
  than silently skipping a broken script.
- Report-only where it's installing something reviewable — print what's
  missing and the command to fix it, don't run the mutating command yourself.
  See `scripts/install-flatpaks.sh` for the pattern (an `app-id|reason` array,
  `flatpak info` to check, printed `flatpak install` lines to run by hand).

Copying that pattern means your private script reads and behaves exactly
like the public ones, which matters more than it sounds: it's the difference
between "check before acting" being a repo convention and being a rule you
have to remember to re-apply for the one part of your setup nobody else can
see.

## Guardrails still apply

Extras scripts run inside the same `install.sh` invocation, in the same
Claude Code session, under the same `.claude/hooks/` guardrail layer as
everything else in this repo — the hooks watch the commands the agent
proposes and runs, not which repo a script came from. A private extras repo
is not a way to bypass CLAUDE.md's rules; it's a way to keep a fork's public
manifest relevant to the next forker.

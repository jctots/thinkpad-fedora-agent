---
name: end-session
description: Wrap up a session — decide whether a reboot is actually pending and delegate to the handover skill if so, save anything memory-worthy that hasn't been captured yet, and report usage stats. Use whenever the user says they're done, wrapping up, or closing the session — this is the one command to reach for at session end, not `/handover` directly; it decides which mechanism applies instead of making the user track that.
---

The two continuity mechanisms this project has — `.claude/handover.md` and
the auto-memory system — solve different problems and neither replaces the
other:

- **Handover** is ephemeral, task-in-flight state: what's staged but
  unverified, the exact next step, uncommitted git state. It exists only to
  give a resumed session the same continuity as `claude -c` without
  replaying the whole prior transcript (and its token cost) on every turn
  after. It's overwritten each time, gitignored, and only useful right
  before something reboots the session.
- **Memory** is durable, cross-session narrative — decisions, feedback,
  ongoing project facts. It's meant to accumulate over months, not describe
  what to do the moment the session resumes. The auto-memory system's own
  rules already exclude ephemeral task state from it, so this is not
  duplicate coverage — dumping handover-shaped content into memory would
  violate its scope, same as leaving durable narrative in a file that gets
  overwritten next time.

`end-session` exists so the user doesn't have to decide which applies —
run this at the end of every session, reboot-pending or not.

## Steps

1. **Decide if a reboot is actually pending.**
   - Run `rpm-ostree status` — a staged deployment not yet booted is the
     primary signal on this Silverblue machine.
   - Also weigh anything this session proposed but hasn't yet executed that
     needs a restart to take effect (kernel module changes, certain
     `systemctl` unit changes) — judgment call, not just the one command.
   - If pending: invoke the `handover` skill in write mode
     (`Skill(handover, "write")`) rather than duplicating its steps here —
     it owns the actual snapshot logic (what's confirmed done, staged
     git state, the exact next step).
   - If not pending: skip handover entirely. Writing one anyway leaves
     stale state for a future session to trip over — the handover skill's
     own read-mode guidance says to flag a handover file that looks stale
     against current `git log` / `rpm-ostree status`; don't create that
     problem by writing one with nothing to describe.

2. **Capture anything memory-worthy that isn't saved yet.** Review the
   session against the auto-memory system's four types (user, feedback,
   project, reference) per the main memory instructions already in context.
   This is not a new mechanism — just making sure nothing surfaced this
   session is left uncaptured before it closes. Do not put task-in-flight
   state here; that's step 1's job when it applies.

3. **Report usage.** Tell the user to run the built-in `/cost` command for
   authoritative token and dollar usage — never fabricate a dollar figure.
   `/cost` is intercepted client-side by the CLI before it reaches the
   model, so it costs nothing to run and can't be triggered from inside a
   skill; it has to be the user typing it. If a quick sanity check is
   useful in the meantime, this project's `scripts/session-token-check.sh`
   reads the last assistant turn's usage from the transcript for a fast
   context-size read — clearly label that as context size, not cumulative
   session cost, since it isn't the same number `/cost` reports.

4. **Close with a short summary**, mirroring what a resumed session (via
   handover's read mode, or just memory) would need: what changed, what's
   committed vs. pending, and the single next step — surfaced directly in
   chat here since this is the same session ending, not a fresh resume
   reading it back from a file.

5. **End the summary by prompting `/cost` then `/clear`** (or `/exit` if
   the user wants to leave the terminal entirely) as the two things to type
   next. Both are CLI-level commands, same as `/cost` — a skill has no tool
   that can invoke either, so this is a prompt for the user to act on, not
   something the skill executes itself.

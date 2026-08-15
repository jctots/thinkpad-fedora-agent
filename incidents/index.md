# Incidents — index

The why behind every non-obvious thing on this machine, written when it happens
rather than reconstructed later. One file per incident, newest first.

An incident is something that broke and this fixed it. A choice with
alternatives that were weighed is a decision, not an incident, and lives in the
vault. A fact about this particular machine — firmware strings, device IDs,
hardware support — belongs in `hosts/<slug>/`.

This index leads and `scripts/` follows. A script is what a set of incidents
becomes once the same problem has come up enough times to be worth automating.

## The tally

The columns below are the evidence for this project's central claim: that a
privileged agent plus reversibility makes a Linux desktop cheaper to live with
than Windows. The claim is only falsifiable if the misses are recorded as
faithfully as the hits. **An index with no `✗` in the last column is evidence
of nothing except selective writing.**

An incident fixed by hand because the agent was unreachable — no network, a
usage limit, a broken session, an outage — still gets a row, with
`n/a — agent unavailable` in the first-proposal column. Those rows are not
noise. Availability is part of the cost being compared against Windows, and a
tally that silently drops the times the agent could not help is measuring the
arrangement on its best days. `docs/recovery.md` is the path those entries come
from.

| # | Date | Area | Symptom | Time to fix | 1st proposal right? | Captured in |
|---|---|---|---|---|---|---|

_No entries yet. The machine still runs Windows 11._

## Adding an entry

1. Create `incidents/I{nnn}-{slug}.md` from `incidents/_template.md`,
   incrementing from the top row.
2. Add a row here.

Write the entry when the problem is fixed, not at the end of the session — the
failed attempts are the part that is gone forever if it is left until later.

## Areas

Keep the `Area` column to a small vocabulary so the table stays sortable:
`rpm-ostree`, `flatpak`, `toolbox`, `gnome`, `hardware`, `network`, `etc`,
`backup`, `agent`, `boot`.

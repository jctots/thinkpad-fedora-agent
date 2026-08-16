# thinkpad-e14-gen5 — host profile

Everything here is about *this device*, not about the software stack around it.
The test for whether something belongs in this directory rather than in
`scripts/`: would it be identical on a different laptop? If yes, it is base
layer. Most apparent hardware quirks are — the Bitwarden → polkit → `fprintd`
chain is the same everywhere; only reader support and driver choice are not.

Contents, as they get written:

- `packages.txt` — additive, on top of the base list
- `quirks.sh` — fingerprint reader *driver and configuration*, GPU, power
  management, firmware quirks, function keys. Not enrolment — that needs a
  finger, and stays on the manual list in `docs/bootstrap.md` § Part 4

## Pinned: DMI detection strings

Read 2026-08-16 off this machine:

```
sys_vendor:   LENOVO
product_name: 21JKCTO1WW
```

`install.sh`'s `detect_host_profile` matches `LENOVO|21JK*` — prefix match on
the MTM code (`21JK` = E14 Gen 5), not the full CTO suffix, so other
configurations of the same model still resolve to this profile.

## Fingerprint reader: Goodix, supported via third-party driver

```
lsusb: Bus 003 Device 002: ID 27c6:550a Shenzhen Goodix Technology Co.,Ltd. FingerPrint
```

Confirmed 2026-08-16: this is the Goodix variant, not Synaptics. `27c6:550a`
is **not supported by upstream libfprint** — Goodix's driver is proprietary
and ships as a "Touch-Only Device" (TOD) shim, `libfprint-tod-goodix`, not
present in Fedora's official repos. The only known working package is a
third-party COPR: `antiderivative/libfprint-tod-goodix-0.0.9`, which upstream
reports as tested specifically on a ThinkPad E14 Gen5 — matches this profile.

This is a **third-party, prebuilt binary driver from an unaudited COPR**, not
a source build — a different trust category from anything else layered so
far in this repo (`rpm-ostree install <pkg>` from Fedora's own repos). Adding
the COPR itself is an `/etc` change (a `.repo` file under `/etc/yum.repos.d/`)
and therefore ASK-tier, covered by `etckeeper`, but the *contents* of what it
installs are opaque. Enrolment quirks/config for this driver belong in
`quirks.sh` per this directory's layout; do not add the COPR without saying
so out loud first, separately from the rest of the fingerprint setup.

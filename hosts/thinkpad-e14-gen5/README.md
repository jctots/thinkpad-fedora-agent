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

## Unpinned: DMI detection strings

`install.sh` selects this profile by matching `/sys/class/dmi/id/sys_vendor`
and `product_name`. The current match is a guess and detection fails loudly
rather than guessing wrong. Read the real values off the machine and pin them:

```bash
cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name
```

## Unverified: fingerprint reader

E14 Gen 5 ships either a Synaptics or a Goodix reader depending on variant, and
`libfprint` coverage across those is uneven — some have no working Linux driver
at all. Get the vendor:product ID and check it before planning anything that
depends on biometrics:

```bash
lsusb | grep -iE 'synaptics|goodix|fingerprint'
```

If it is unsupported, that is a fact about this machine — record the ID and the
verdict here in this file, not as an incident, and move on.

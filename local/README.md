# local/ — never committed

Everything in this directory is gitignored except this file and `*.example`
files. It holds the values that would turn a public repo into a leak: Wi-Fi
PSKs, kickstart passwords, LUKS passphrases, tokens, registry logins, and
home-lab hostnames and endpoints.

## The rule

Scripts **source** from here. They never inline.

```bash
# wrong — the action is the secret, and it is now in git history forever
nmcli connection add type wifi ssid HomeNet wifi-sec.psk 'hunter2'

# right
. "${REPO_ROOT}/local/secrets.env"
nmcli connection add type wifi ssid "$WIFI_SSID" wifi-sec.psk "$WIFI_PSK"
```

This matters more than it looks. Most of this repo is inert — package lists,
`gsettings` lines, an orchestrator. The leak paths all share one mechanism:
*an action that configures something authenticated carries the credential as
an argument.*

## Setting up a fresh clone

```bash
cp local/secrets.env.example local/secrets.env
$EDITOR local/secrets.env          # fill from Bitwarden
scripts/install-hooks.sh           # enables the gitleaks pre-commit scan
```

## For the agent

If a command you are about to propose contains a credential, a PSK, a
passphrase, a token or an internal hostname, stop. Add the value to
`local/secrets.env` and reference the variable instead. Say that you are doing
this and why — do not silently substitute a placeholder and leave a script that
does not work.

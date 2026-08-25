#!/usr/bin/env bash
# Stages a copy of the enrolled MOK signing key (used by
# scripts/build-signed-kmod.sh) into a location a toolbox container can
# read directly, without sudo.
#
# Why this exists (incidents/I008): toolbox containers are rootless —
# "root" inside one maps to a host subuid range, not real UID 0 — so even
# a bind-mounted /run/host/etc/pki/akmods/private (root:958, mode 0750) is
# unreadable from inside a toolbox no matter what. The only privileged
# process that can actually read that directory is a real host process,
# so the read has to happen here, before the toolbox build ever starts.
#
# Run this ON THE HOST, not inside a toolbox. It uses pkexec (real root)
# to copy the private key + cert out of /etc/pki/akmods into
# ~/kmod-builds/.keystage, owned by the invoking user — a location every
# toolbox container already sees via its default $HOME bind mount, no
# extra wiring needed. build-signed-kmod.sh then reads from there as a
# plain user-owned file, no sudo required on that side.
#
# The staged copy is deliberately short-lived but not auto-deleted here
# (unlike build-signed-kmod.sh's own /var/cache/akmods copy) — a single
# staging may cover several kmod builds back to back (nvidia, xpadneo,
# ...). Remove it explicitly with --cleanup once done.
#
# Usage: scripts/stage-mok-key.sh [--cleanup]

set -euo pipefail

if [ -f /run/.toolboxenv ]; then
  echo "error   this must run on the bare host, not inside a toolbox" >&2
  echo "        (the whole point is doing the privileged read outside" >&2
  echo "        the toolbox's rootless mapping — see incidents/I008)" >&2
  exit 1
fi

stage_dir="$HOME/kmod-builds/.keystage"

if [ "${1:-}" = "--cleanup" ]; then
  if [ -d "$stage_dir" ]; then
    rm -f "$stage_dir/private_key.priv" "$stage_dir/public_key.der"
    rmdir --ignore-fail-on-non-empty "$stage_dir" 2>/dev/null || true
    echo "ok      staged key material removed from $stage_dir"
  else
    echo "ok      nothing staged"
  fi
  exit 0
fi

if [ -f "$stage_dir/private_key.priv" ] && [ -f "$stage_dir/public_key.der" ]; then
  echo "ok      already staged at $stage_dir (run with --cleanup to remove when done)"
  exit 0
fi

mkdir -p "$stage_dir"
chmod 0700 "$stage_dir"

user="$(id -un)"
group="$(id -gn)"

echo "==> staging MOK key material to $stage_dir (pkexec — one polkit prompt)"
pkexec sh -c '
  set -eu
  install -o "$1" -g "$2" -m 0600 /etc/pki/akmods/private/private_key.priv "$3/private_key.priv"
  install -o "$1" -g "$2" -m 0644 /etc/pki/akmods/certs/public_key.der "$3/public_key.der"
' _ "$user" "$group" "$stage_dir"

echo "ok      staged. Run build-signed-kmod.sh inside the toolbox now."
echo "        When done with all builds for this session:"
echo "        scripts/stage-mok-key.sh --cleanup"

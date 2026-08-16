#!/usr/bin/env bash
# Fingerprint reader driver for this host's Goodix 27c6:550a sensor.
# Report-only, idempotent, same pattern as scripts/layer-packages.sh — this
# script never installs or overrides anything itself, only prints what's
# missing and the exact commands to run.
#
# Why an override, not a plain layer: 27c6:550a has no upstream libfprint
# support. The working driver is Lenovo's own proprietary TOD blob,
# repackaged (not authored) by the antiderivative Copr — see this
# directory's README.md § Fingerprint reader for the trust reasoning.
# Installing it replaces the base libfprint package.
#
# It has to be two separate `rpm-ostree` invocations, not one
# `override replace` — see incidents/I001-libfprint-tod-override-hardlink-checkout.md.
# `override replace` in one pass hits a real upstream hardlink-checkout bug
# (coreos/rpm-ostree#4116) when the base and replacement packages both ship
# a file at the same path with different content, which is exactly this
# case (/usr/lib/udev/hwdb.d/60-autosuspend-libfprint-2.hwdb). Removing the
# base package in its own pass first, then installing the replacement in a
# second pass, avoids it.

set -euo pipefail

COPR_REPOID="copr.fedorainfracloud.org:antiderivative:libfprint-tod-goodix-0.0.9"
REPO_FILE="/etc/yum.repos.d/_copr_antiderivative-libfprint-tod-goodix-0.0.9.repo"
REPO_URL="https://copr.fedorainfracloud.org/coprs/antiderivative/libfprint-tod-goodix-0.0.9/repo/fedora-\$(rpm -E %fedora)/antiderivative-libfprint-tod-goodix-0.0.9-fedora-\$(rpm -E %fedora).repo"

steps_needed=0

if [ -f "$REPO_FILE" ]; then
  echo "ok      copr repo file present ($REPO_FILE)"
else
  echo "missing copr repo file"
  steps_needed=1
fi

if rpm -q libfprint-tod-goodix >/dev/null 2>&1; then
  echo "ok      libfprint-tod-goodix installed"
else
  echo "missing libfprint-tod-goodix"
  steps_needed=1
fi

if rpm -q libfprint-tod >/dev/null 2>&1; then
  echo "ok      libfprint overridden with libfprint-tod (TOD-enabled build)"
else
  echo "missing libfprint override (still on stock libfprint, TOD sensors won't work)"
  steps_needed=1
fi

if rpm -q fprintd >/dev/null 2>&1; then
  echo "ok      fprintd"
else
  echo "missing fprintd"
  steps_needed=1
fi

if [ "$steps_needed" -eq 0 ]; then
  echo
  echo "all fingerprint driver components present — enrolment is still manual"
  echo "(fprintd-enroll), see docs/bootstrap.md Part 4"
  exit 0
fi

echo
echo "Run (as separate, reviewable commands — do not chain):"
echo "  sudo curl -Lo $REPO_FILE \"$REPO_URL\""
echo "  sudo rpm-ostree override remove libfprint"
echo "  sudo rpm-ostree install libfprint-tod libfprint-tod-goodix"
echo "  # ^ must be two separate invocations, not one 'override replace' —"
echo "  #   see incidents/I001-libfprint-tod-override-hardlink-checkout.md"
echo "  systemctl reboot"
echo "  # after reboot: fprintd-enroll   (manual, needs a finger — not scripted)"
exit 1

#!/usr/bin/env bash
# Builds the local RPM that carries scripts/bitwarden-polkit-policy/
# com.bitwarden.Bitwarden.policy into /usr/share/polkit-1/actions.
#
# Why a local RPM instead of the raw `sudo wget` Bitwarden's own Flatpak
# biometrics docs give: /usr is a read-only ostree overlay on this machine,
# so a live write there fails outright. Packaging the file and layering it
# with rpm-ostree puts the change in the OS-image reversibility layer
# (rpm-ostree rollback undoes it) instead of leaving it unreversible.
# See incidents/I002-bitwarden-flatpak-polkit-policy-readonly-usr.md.
#
# Idempotent: safe to re-run. Builds inside toolbox (host has no rpmbuild)
# and, like layer-packages.sh, never calls rpm-ostree itself — it prints the
# install command and stops, so the change still goes through the normal
# ask-tier prompt.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src_dir="$here/bitwarden-polkit-policy"
rpm_name="bitwarden-polkit-policy"

if rpm -q "$rpm_name" >/dev/null 2>&1; then
  echo "ok      $rpm_name already layered"
  exit 0
fi

toolbox run bash -c "
  set -euo pipefail
  mkdir -p ~/rpmbuild/{SOURCES,SPECS}
  cp '$src_dir/com.bitwarden.Bitwarden.policy' ~/rpmbuild/SOURCES/
  cp '$src_dir/bitwarden-polkit-policy.spec' ~/rpmbuild/SPECS/
  rpmbuild -bb ~/rpmbuild/SPECS/bitwarden-polkit-policy.spec
"

rpm_path="$(ls -t "$HOME"/rpmbuild/RPMS/noarch/${rpm_name}-*.rpm | head -1)"

echo
echo "built: $rpm_path"
echo
echo "Run (as a separate, reviewable command):"
echo "  rpm-ostree install $rpm_path"

#!/usr/bin/env bash
# Generic replacement for the toolbox-signed-kmod recipe that was pasted
# near-verbatim twice in hosts/thinkpad-e14-gen5/quirks.sh: kmod-nvidia
# (incidents/I004) and kmod-xpadneo (incidents/I006) hit the identical bug
# — rpm-ostree's `%post` akmods build sandbox can't see
# /etc/pki/akmods/private at build time, so akmod-* packages build
# unsigned even with a correctly enrolled MOK. The fix both times was:
# build + sign in a toolbox container (which isn't inside that sandbox),
# then pin the resulting kmod to the exact running kernel as an
# rpm-ostree LocalPackage.
#
# Run this INSIDE a toolbox container (fedora-toolbox-44 or matching the
# host release), not on the bare host. It builds and signs the module and
# stops there — like this repo's other scripts (layer-packages.sh,
# install-flatpaks.sh), it never calls rpm-ostree itself. The host-side
# swap needs sudo rpm-ostree, which is ask-tier under this repo's own
# guardrail; printing the exact commands instead of running them keeps
# that "show the command before running it" property intact across the
# toolbox/host boundary too.
#
# Prerequisite: scripts/stage-mok-key.sh, run on the HOST first (not in
# this toolbox). This script reads the MOK key from that staged location
# rather than /etc/pki/akmods directly — a toolbox's "root" is a host
# subuid mapping, not real UID 0, so it can never read the host's
# root:958-owned, mode-0750 key directory even via sudo or the
# /run/host bind mount. See incidents/I008 for the full diagnosis.
#
# Usage: scripts/build-signed-kmod.sh <kmod-name> <kmodsrc-package>
#   kmod-name        e.g. nvidia, xpadneo — passed to `akmods --kmod`
#   kmodsrc-package   the actual `akmod-<name>` package (NOT a `-kmodsrc`
#                     package — that only ships driver sources, and never
#                     registers with `akmods` at all: only a real
#                     `akmod-*` package drops a src.rpm into
#                     /usr/src/akmods for it to find). e.g. akmod-nvidia,
#                     akmod-xpadneo. Confirmed the hard way 2026-08-25:
#                     xorg-x11-drv-nvidia-kmodsrc (I004's original choice)
#                     installs fine but `akmods --kmod nvidia` then fails
#                     with "Could not find akmod nvidia".
#
# See incidents/I004, I006, I008 for the full diagnosis and reproduction.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <kmod-name> <kmodsrc-package>" >&2
  echo "e.g.:  $0 nvidia akmod-nvidia" >&2
  echo "       $0 xpadneo akmod-xpadneo" >&2
  exit 1
fi

kmod_name="$1"
kmodsrc_package="$2"

if [ ! -f /run/.toolboxenv ]; then
  echo "error   this must run inside a toolbox container, not the bare host" >&2
  echo "        (the whole point is building outside the rpm-ostree %post" >&2
  echo "        sandbox — see incidents/I004 for why)" >&2
  exit 1
fi

running_kernel="$(uname -r)"
build_root="$HOME/kmod-builds/${kmod_name}"
mkdir -p "$build_root"

echo "==> installing build dependencies (toolbox)"
sudo dnf install -y \
  rpmfusion-free-release rpmfusion-nonfree-release \
  "kernel-devel-${running_kernel}" akmods gcc make elfutils-libelf-devel \
  "${kmodsrc_package}"

# kernel-devel only populates /usr/src/kernels/<ver> — the
# /usr/lib/modules/<ver>/build symlink akmods actually looks for is
# normally created by the kernel-core/kernel package's %post, which this
# toolbox never installs (it only needs headers, not a bootable kernel).
# Not owned by any package here; this step went undocumented in the
# original I004/I006 manual builds and only surfaced on the first re-run
# against a new kernel version (2026-08-25).
module_dir="/usr/lib/modules/${running_kernel}"
if [ ! -e "$module_dir/build" ]; then
  echo "==> creating $module_dir/build -> /usr/src/kernels/${running_kernel}"
  sudo mkdir -p "$module_dir"
  sudo ln -s "/usr/src/kernels/${running_kernel}" "$module_dir/build"
fi

staged_dir="$HOME/kmod-builds/.keystage"
if [ ! -f "$staged_dir/private_key.priv" ] || [ ! -f "$staged_dir/public_key.der" ]; then
  echo "error   no staged MOK key at $staged_dir" >&2
  echo "        run scripts/stage-mok-key.sh on the HOST first (I008)" >&2
  exit 1
fi

echo "==> copying staged MOK key into /var/cache/akmods (akmods system user)"
# akmodsbuild compiles+signs as the 'akmods' system user via runuser, not
# root or the invoking user — .rpmmacros and the key copies have to live
# in /var/cache/akmods, not ~/.rpmmacros or /root/.rpmmacros (I006 finding,
# silently true of I004's build too). Source is the staged copy from
# stage-mok-key.sh, not /etc/pki/akmods directly — see I008.
key_dir="/var/cache/akmods"
sudo install -d -o akmods -g akmods -m 0750 "$key_dir"
sudo install -o akmods -g akmods -m 0600 "$staged_dir/private_key.priv" "$key_dir/private_key.priv"
sudo install -o akmods -g akmods -m 0644 "$staged_dir/public_key.der" "$key_dir/public_key.der"
sudo tee "$key_dir/.rpmmacros" >/dev/null <<EOF
%_kmodtool_signmodules_privkey $key_dir/private_key.priv
%_kmodtool_signmodules_pubkey $key_dir/public_key.der
EOF
sudo chown akmods:akmods "$key_dir/.rpmmacros"
sudo chmod 0600 "$key_dir/.rpmmacros"

cleanup() {
  echo "==> deleting copied signing key material from $key_dir"
  sudo rm -f "$key_dir/private_key.priv" "$key_dir/public_key.der" "$key_dir/.rpmmacros"
}
trap cleanup EXIT

echo "==> building + signing kmod-${kmod_name} for kernel ${running_kernel}"
# akmods also tries to self-install the built RPM into this toolbox, which
# fails here because the container deliberately has no matching `kernel`
# package (headers-only, via kernel-devel) — that failure is expected and
# does not mean the build/sign itself failed, so don't let `set -e` abort
# on it; check for the actual RPM below instead.
sudo akmods --kernels "$running_kernel" --kmod "$kmod_name" || true

# /var/cache/akmods is akmods:akmods, mode 0750 — the invoking user can't
# traverse it directly, so every read here needs sudo (I008: this whole
# tail of the script was never actually exercised end-to-end before).
built_rpm="$(sudo find /var/cache/akmods -name "kmod-${kmod_name}-${running_kernel}-*.rpm" -newer "$key_dir/.rpmmacros" 2>/dev/null | head -n1 || true)"
if [ -z "$built_rpm" ]; then
  built_rpm="$(sudo find /var/cache/akmods -name "kmod-${kmod_name}-${running_kernel}-*.rpm" 2>/dev/null | sort | tail -n1)"
fi
if [ -z "$built_rpm" ]; then
  echo "error   no kmod-${kmod_name}-${running_kernel}-*.rpm found under /var/cache/akmods after build" >&2
  exit 1
fi

final_rpm="$build_root/$(basename "$built_rpm")"
sudo install -m 0644 "$built_rpm" "$final_rpm"
sudo chown "$(id -u):$(id -g)" "$final_rpm"

echo "==> verifying signature"
extract_dir="$(mktemp -d)"
(cd "$extract_dir" && rpm2cpio "$final_rpm" | cpio -idm --quiet)
ko_file="$(find "$extract_dir" -name '*.ko*' | head -n1 || true)"
if [ -z "$ko_file" ]; then
  echo "error   couldn't find a .ko file inside $final_rpm to verify" >&2
  exit 1
fi
modinfo_out="$(modinfo "$ko_file" 2>/dev/null || true)"
sig_id_line="$(grep -i '^sig_id:' <<<"$modinfo_out" || true)"
signer_line="$(grep -i '^signer:' <<<"$modinfo_out" || true)"
# The signer CN is whatever was set when the MOK key was generated (e.g.
# fedora_<timestamp>_<hash>) — it never literally contains "akmods", so
# check for the presence of a signature block, not a specific name.
# Confirmed 2026-08-25 by comparing modinfo's signer CN against
# `mokutil --list-enrolled`'s subject line — they match.
if [ -z "$sig_id_line" ] || [ -z "$signer_line" ]; then
  echo "error   built module does not look signed — modinfo output:" >&2
  modinfo "$ko_file" >&2
  exit 1
fi
echo "$sig_id_line"
echo "$signer_line"
echo "ok      module is signed"

rm -rf "$extract_dir"
echo "==> copied to $final_rpm (host-shared \$HOME path)"

cat <<EOF

Build complete. Run these on the HOST (not in this toolbox) to install:

  sudo rpm-ostree uninstall akmod-${kmod_name}   # if present
  sudo rpm-ostree install ${final_rpm}
  sudo systemctl reboot

After reboot, confirm with the relevant quirks.sh check block.
EOF

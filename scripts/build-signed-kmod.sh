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
# Usage: scripts/build-signed-kmod.sh <kmod-name> <kmodsrc-package>
#   kmod-name        e.g. nvidia, xpadneo — passed to `akmods --kmod`
#   kmodsrc-package   the source/akmod package that provides the spec, e.g.
#                     xorg-x11-drv-nvidia-kmodsrc (nvidia), akmod-xpadneo
#                     (xpadneo) — this varies per project, so it's an arg,
#                     not derived from kmod-name.
#
# See incidents/I004 and I006 for the full diagnosis and reproduction.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <kmod-name> <kmodsrc-package>" >&2
  echo "e.g.:  $0 nvidia xorg-x11-drv-nvidia-kmodsrc" >&2
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

echo "==> copying MOK signing key into /var/cache/akmods (akmods system user)"
# akmodsbuild compiles+signs as the 'akmods' system user via runuser, not
# root or the invoking user — .rpmmacros and the key copies have to live
# in /var/cache/akmods, not ~/.rpmmacros or /root/.rpmmacros (I006 finding,
# silently true of I004's build too).
key_dir="/var/cache/akmods"
sudo install -d -o akmods -g akmods -m 0750 "$key_dir"
sudo install -o akmods -g akmods -m 0600 /etc/pki/akmods/private/private_key.priv "$key_dir/private_key.priv"
sudo install -o akmods -g akmods -m 0644 /etc/pki/akmods/certs/public_key.der "$key_dir/public_key.der"
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
akmods --kernels "$running_kernel" --kmod "$kmod_name"

built_rpm="$(find /var/cache/akmods -name "kmod-${kmod_name}-${running_kernel}-*.rpm" -newer "$key_dir/.rpmmacros" 2>/dev/null | head -n1)"
if [ -z "$built_rpm" ]; then
  built_rpm="$(find /var/cache/akmods -name "kmod-${kmod_name}-${running_kernel}-*.rpm" 2>/dev/null | sort | tail -n1)"
fi
if [ -z "$built_rpm" ]; then
  echo "error   no kmod-${kmod_name}-${running_kernel}-*.rpm found under /var/cache/akmods after build" >&2
  exit 1
fi

echo "==> verifying signature"
extract_dir="$(mktemp -d)"
(cd "$extract_dir" && rpm2cpio "$built_rpm" | cpio -idm --quiet)
ko_file="$(find "$extract_dir" -name '*.ko*' | head -n1)"
if [ -z "$ko_file" ]; then
  echo "error   couldn't find a .ko file inside $built_rpm to verify" >&2
  exit 1
fi
if ! modinfo "$ko_file" | grep -qi "signer.*akmods\|module signature appended"; then
  echo "error   built module does not look signed — modinfo output:" >&2
  modinfo "$ko_file" >&2
  exit 1
fi
modinfo "$ko_file" | grep -i "sig_id\|signer"
echo "ok      module is signed"

cp "$built_rpm" "$build_root/"
rm -rf "$extract_dir"
final_rpm="$build_root/$(basename "$built_rpm")"
echo "==> copied to $final_rpm (host-shared \$HOME path)"

cat <<EOF

Build complete. Run these on the HOST (not in this toolbox) to install:

  sudo rpm-ostree uninstall akmod-${kmod_name}   # if present
  sudo rpm-ostree install ${final_rpm}
  sudo systemctl reboot

After reboot, confirm with the relevant quirks.sh check block.
EOF

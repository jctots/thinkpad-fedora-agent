#!/usr/bin/env bash
# One-time host setup so flatpak VSCode's Dev Containers extension can
# attach to rootless Podman. See docs/devcontainers.md for why each step
# is needed — the flatpak sandbox does not see the host's container
# socket by default, even with filesystems=host already in the app
# manifest.
#
# All three steps are user-level (systemd --user, flatpak --user,
# ~/.local/bin) — no pkexec, nothing under /etc.
#
# Idempotent: safe to re-run — `systemctl enable --now` and
# `flatpak override` are themselves idempotent, and the wrapper scripts
# are just overwritten with the same content.
#
# Usage: scripts/install-devcontainers-host.sh

set -euo pipefail

echo "== podman.socket =="
systemctl --user enable --now podman.socket
systemctl --user is-active podman.socket
systemctl --user is-enabled podman.socket

sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
if [ -S "$sock" ]; then
  echo "ok      $sock"
else
  echo "missing $sock — podman.socket is enabled but the socket file isn't there yet"
  exit 1
fi

echo
echo "== flatpak override (com.visualstudio.code) =="
flatpak override --user --filesystem=xdg-run/podman com.visualstudio.code
flatpak override --user --show com.visualstudio.code

echo
echo "== wrapper scripts (~/.local/bin) =="
mkdir -p "${HOME}/.local/bin"

cat > "${HOME}/.local/bin/podman-host" <<'EOF'
#!/bin/sh
exec flatpak-spawn --host podman "$@"
EOF
chmod 755 "${HOME}/.local/bin/podman-host"
echo "wrote   ${HOME}/.local/bin/podman-host"

if command -v podman-compose >/dev/null 2>&1; then
  cat > "${HOME}/.local/bin/podman-compose-host" <<'EOF'
#!/bin/sh
exec flatpak-spawn --host podman-compose "$@"
EOF
  chmod 755 "${HOME}/.local/bin/podman-compose-host"
  echo "wrote   ${HOME}/.local/bin/podman-compose-host"
else
  echo "skip    podman-compose-host — podman-compose not installed on host (not installing it here)"
fi

echo
echo "Restart VSCode, then confirm from its integrated terminal:"
echo "  ls -la ${sock}"
echo "  podman-host --version"

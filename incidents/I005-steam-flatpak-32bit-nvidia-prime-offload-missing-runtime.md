## I005 — 2026-08-17 — Steam-wide PRIME offload env vars set but 32-bit games still rendered on iGPU

**Area:** flatpak

**Symptom:** `__NV_PRIME_RENDER_OFFLOAD=1` and `__GLX_VENDOR_LIBRARY_NAME=nvidia`
were correctly applied Steam-wide via `flatpak override --user --env=...` on
`com.valvesoftware.Steam` (see `hosts/thinkpad-e14-gen5/README.md`), and
confirmed present in the running game process's environment via
`/proc/<pid>/environ`. Despite that, `nvidia-smi` showed the MX550 idle at 0%
utilization with no game process listed while Portal 2 was running, and
nvtop showed GPU0 unused.

**Cause:** Portal 2 (`portal2_linux`) is a 32-bit (i386) Source engine binary.
`/proc/<pid>/maps` showed it had loaded `libGLX_mesa.so` — GLVND was silently
falling back to Mesa/Intel because no 32-bit NVIDIA GLX vendor library was
available inside the Steam Flatpak's sandboxed runtime. Flatpak apps need a
matching `org.freedesktop.Platform.GL.nvidia-<version>` runtime extension
installed (and the `GL32.nvidia-<version>` variant for 32-bit apps),
version-matched exactly to the host driver (`610.57.04`, confirmed via
`nvidia-smi --query-gpu=driver_version`). Flatpak normally auto-installs this
when it detects the host NVIDIA driver, but that hook never fired here —
almost certainly because the driver is a manually built and pinned
`kmod-nvidia` package (see [I004](I004-nvidia-akmod-unsigned-in-rpm-ostree-post-sandbox.md))
rather than a package form Flatpak's driver-detection recognizes.
`__GLX_VENDOR_LIBRARY_NAME=nvidia` being set with the matching vendor library
absent produces no error — GLVND just silently picks the other available
vendor (Mesa).

**Fix:**
```
sudo flatpak install --system -y flathub \
  org.freedesktop.Platform.GL.nvidia-610-57-04 \
  org.freedesktop.Platform.GL32.nvidia-610-57-04
```
Then fully quit and relaunch the game — GLVND vendor selection happens once
at process start, so a running instance doesn't pick up a newly installed
extension.

Verified via `nvidia-smi` listing `portal2_linux` at 793MiB / 6% util, and
`/proc/<pid>/maps` showing `libGLX_nvidia.so.610.57.04` and
`libnvidia-glcore.so.610.57.04` loaded from the new extension.

**Tried first:** `flatpak install --user -y flathub ...` — failed with "No
remote refs found for 'flathub'". `flathub` was only configured as a system
remote, not a user one (Steam itself is installed system-wide, so its
overrides and matching GL runtime extensions need to live at the system
level too). Re-ran with `--system`, which then needed interactive `sudo`
(fingerprint auth) that the agent's Bash tool can't satisfy — the user ran
the final install command directly via the `!` prefix.

**Reversibility:** flatpak — `sudo flatpak uninstall --system
org.freedesktop.Platform.GL.nvidia-610-57-04
org.freedesktop.Platform.GL32.nvidia-610-57-04`. No `/etc` or OS-image layer
touched.

**Captured in:** `hosts/thinkpad-e14-gen5/quirks.sh` and `README.md` (this
session)

**Tally:** time-to-fix ~20m · first proposal: right

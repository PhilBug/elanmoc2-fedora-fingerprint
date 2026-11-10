#!/usr/bin/env bash
# Uninstall the elanmoc2 libfprint driver and restore the stock state.
#
# Removes:
# - /usr/local/lib64/libfprint-2* (custom library)
# - /etc/systemd/system/fprintd.service.d/90-elanmoc2.conf (systemd drop-in)
# - legacy files left by older versions of this script
#
# The Fedora libfprint package itself is never modified.
#
# Usage: ./uninstall.sh
set -euo pipefail

LIBDIR="/usr/local/lib64"
DROPIN_DIR="/etc/systemd/system/fprintd.service.d"
DROPIN="${DROPIN_DIR}/90-elanmoc2.conf"
LEGACY_DROPIN="${DROPIN_DIR}/elanmoc2.conf"
LEGACY_LIBCONF="/etc/ld.so.conf.d/libfprint-elanmoc2.conf"

say()  { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if ((EUID == 0)); then
    die "Run this script as a normal user, not root. It calls sudo itself."
fi

command -v sudo >/dev/null 2>&1 \
    || die "sudo was not found."

say "Removing the custom libfprint library"
sudo rm -f "${LIBDIR}/libfprint-2.so" \
           "${LIBDIR}/libfprint-2.so.2" \
           "${LIBDIR}/libfprint-2.so.2.0.0"

# Files installed by older versions of install.sh (full `ninja install`).
say "Removing legacy files (if present)"
sudo rm -rf /usr/local/include/libfprint-2
sudo rm -f  /usr/local/lib64/pkgconfig/libfprint-2.pc
sudo rm -f  /usr/local/share/metainfo/org.freedesktop.libfprint.metainfo.xml

say "Removing the systemd drop-in"
sudo rm -f "${DROPIN}" "${LEGACY_DROPIN}"
sudo rmdir --ignore-fail-on-non-empty "${DROPIN_DIR}" 2>/dev/null || true

if [[ -f "${LEGACY_LIBCONF}" ]]; then
    say "Removing the legacy global ldconfig entry"
    sudo rm -f "${LEGACY_LIBCONF}"
fi

sudo ldconfig
sudo systemctl daemon-reload
sudo systemctl restart fprintd 2>/dev/null || true

say "Verifying that the stock library is active again"
fprintd_pid="$(systemctl show fprintd -p MainPID --value 2>/dev/null || true)"
if [[ -n "${fprintd_pid}" && "${fprintd_pid}" != "0" \
      && -r "/proc/${fprintd_pid}/maps" ]] \
   && grep -q "${LIBDIR}/libfprint-2.so" "/proc/${fprintd_pid}/maps"; then
    warn "fprintd still has the custom library mapped."
    echo "    Reboot or run: sudo systemctl restart fprintd"
    exit 1
fi

echo ""
echo "OK - the stock Fedora libfprint is active again."
echo "The ELAN 04f3:0c5e sensor will no longer be visible to fprintd."
echo "Your enrolled fingerprint templates stay in the sensor and will be"
echo "usable again if you reinstall the driver."

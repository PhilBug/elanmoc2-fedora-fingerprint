#!/usr/bin/env bash
# Install the elanmoc2 libfprint driver for the ELAN 04f3:0c5e fingerprint
# sensor (HP ProBook 440/450/455 G8) on Fedora.
#
# - Installs build dependencies via dnf (requires sudo)
# - Fetches the elanmoc2 branch of depau/libfprint at a pinned commit
# - Builds a minimal libfprint with only the elanmoc2 driver
# - Installs just the shared library to /usr/local/lib64
# - Adds a systemd drop-in so only fprintd loads it
#
# The Fedora libfprint package is not modified. Run ./uninstall.sh to undo.
#
# Usage: ./install.sh
set -euo pipefail

REPO_URL="https://gitlab.freedesktop.org/depau/libfprint.git"
PINNED_COMMIT="11f0316d069cc90c154c8cb0e46478388c5e2a74"
BUILD_DIR="${ELANMOC2_BUILD_DIR:-${HOME}/elanmoc2-build}"
SRC_DIR="${BUILD_DIR}/libfprint"
MESON_BUILD="${SRC_DIR}/builddir"
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

command -v dnf >/dev/null 2>&1 \
    || die "This script is for Fedora (dnf was not found)."
command -v sudo >/dev/null 2>&1 \
    || die "sudo was not found."

say "Checking sensor (expected: 04f3:0c5e)"
if command -v lsusb >/dev/null 2>&1; then
    sensor_line="$(lsusb | grep -i '04f3:0c5e' | head -n1 || true)"
    if [[ -n "${sensor_line}" ]]; then
        echo "    Sensor found: ${sensor_line}"
    else
        warn "sensor 04f3:0c5e not found in lsusb output."
        echo "    Other ELAN MOC2 IDs (0c00, 0c4c, 0c7c, 0c90) use the same driver."
        echo "    Continuing anyway; the device may still work."
    fi
else
    warn "usbutils is not installed yet; skipping the sensor check."
fi

say "Installing build dependencies (sudo)"
sudo dnf install -y --setopt=install_weak_deps=False \
    meson ninja-build gcc gcc-c++ git pkgconf-pkg-config \
    glib2-devel libgusb-devel libusb1-devel systemd-devel cairo-devel \
    usbutils fprintd fprintd-pam

say "Fetching ${REPO_URL}"
say "  commit: ${PINNED_COMMIT}"

if [[ -d "${SRC_DIR}/.git" ]]; then
    current_origin="$(git -C "${SRC_DIR}" remote get-url origin 2>/dev/null || true)"
    if [[ "${current_origin}" != "${REPO_URL}" ]]; then
        warn "existing checkout has a different origin (${current_origin}); re-cloning"
        rm -rf "${SRC_DIR}"
    fi
fi

if [[ ! -d "${SRC_DIR}/.git" ]]; then
    rm -rf "${SRC_DIR}"
    mkdir -p "${SRC_DIR}"
    git init -q "${SRC_DIR}"
    git -C "${SRC_DIR}" remote add origin "${REPO_URL}"
fi

GIT_TERMINAL_PROMPT=0 git -C "${SRC_DIR}" fetch --depth 1 origin "${PINNED_COMMIT}"
git -C "${SRC_DIR}" checkout -q --detach FETCH_HEAD

fetched_commit="$(git -C "${SRC_DIR}" rev-parse HEAD)"
if [[ "${fetched_commit}" != "${PINNED_COMMIT}" ]]; then
    die "expected commit ${PINNED_COMMIT}, got ${fetched_commit}"
fi
echo "    checked out ${fetched_commit}"

say "Configuring build (driver: elanmoc2, prefix: /usr/local)"
if [[ -d "${MESON_BUILD}" ]]; then
    meson setup --reconfigure "${MESON_BUILD}" "${SRC_DIR}" \
        -Ddrivers=elanmoc2 \
        -Dintrospection=false \
        -Ddoc=false \
        -Dinstalled-tests=false \
        -Dudev_rules=disabled \
        -Dudev_hwdb=disabled \
        --prefix=/usr/local
else
    meson setup "${MESON_BUILD}" "${SRC_DIR}" \
        -Ddrivers=elanmoc2 \
        -Dintrospection=false \
        -Ddoc=false \
        -Dinstalled-tests=false \
        -Dudev_rules=disabled \
        -Dudev_hwdb=disabled \
        --prefix=/usr/local
fi

say "Building"
ninja -C "${MESON_BUILD}"

say "Installing library to ${LIBDIR} (sudo)"
sudo install -d -m755 "${LIBDIR}"
sudo install -m755 "${MESON_BUILD}/libfprint/libfprint-2.so.2.0.0" \
    "${LIBDIR}/libfprint-2.so.2.0.0"
sudo ln -sfn libfprint-2.so.2.0.0 "${LIBDIR}/libfprint-2.so.2"
sudo ln -sfn libfprint-2.so.2.0.0 "${LIBDIR}/libfprint-2.so"

say "Creating fprintd systemd drop-in"
sudo install -d -m755 "${DROPIN_DIR}"
printf '[Service]\nEnvironment="LD_LIBRARY_PATH=%s"\n' "${LIBDIR}" \
    | sudo tee "${DROPIN}" >/dev/null

# Clean up files left by older versions of this script.
if [[ -f "${LEGACY_DROPIN}" ]]; then
    sudo rm -f "${LEGACY_DROPIN}"
fi
if [[ -f "${LEGACY_LIBCONF}" ]]; then
    say "Removing the old global ldconfig entry"
    sudo rm -f "${LEGACY_LIBCONF}"
    sudo ldconfig
fi

if command -v restorecon >/dev/null 2>&1; then
    sudo restorecon "${LIBDIR}/libfprint-2.so.2.0.0" "${LIBDIR}/libfprint-2.so.2" \
        2>/dev/null || true
fi

say "Restarting fprintd"
sudo systemctl daemon-reload
sudo systemctl restart fprintd

say "Verifying installation"
if ! systemctl is-active --quiet fprintd; then
    warn "fprintd is not running."
    echo "    Check: systemctl status fprintd"
    exit 1
fi

fprintd_env="$(systemctl show fprintd -p Environment --value 2>/dev/null || true)"
if ! printf '%s\n' "${fprintd_env}" | grep -q "LD_LIBRARY_PATH=${LIBDIR}"; then
    warn "fprintd does not have LD_LIBRARY_PATH=${LIBDIR} in its environment."
    echo "    Check: systemctl show fprintd -p Environment --value"
    exit 1
fi

fprintd_pid="$(systemctl show fprintd -p MainPID --value 2>/dev/null || true)"
if [[ -n "${fprintd_pid}" && "${fprintd_pid}" != "0" \
      && -r "/proc/${fprintd_pid}/maps" ]]; then
    if grep -q "${LIBDIR}/libfprint-2.so" "/proc/${fprintd_pid}/maps"; then
        echo "    fprintd loaded ${LIBDIR}/libfprint-2.so.2"
    else
        warn "fprintd is not using the library from ${LIBDIR}."
        echo "    Check: sudo grep libfprint /proc/${fprintd_pid}/maps"
    fi
fi

if LC_ALL=C fprintd-list "${USER}" 2>/dev/null | grep -qi 'ELAN Match-on-Chip'; then
    echo ""
    echo "=== SUCCESS: fingerprint reader is ready ==="
    echo ""
    echo "Enroll a finger:"
    echo "    fprintd-enroll -f right-index-finger"
    echo "Then test with:"
    echo "    fprintd-verify"
else
    echo ""
    echo "=== WARNING: the ELAN device was not detected ==="
    echo "Check the drop-in, restart fprintd and try again:"
    echo "    systemctl cat fprintd"
    echo "    sudo systemctl restart fprintd"
    echo "    fprintd-list \$USER"
    echo "If it still fails, run ./doctor.sh and attach its output to an issue."
    exit 1
fi

if command -v authselect >/dev/null 2>&1; then
    if authselect current 2>/dev/null | grep -q 'with-fingerprint'; then
        echo "PAM fingerprint support is enabled (authselect: with-fingerprint)."
    else
        warn "PAM feature 'with-fingerprint' is not enabled."
        echo "    Enable it with: sudo authselect enable-feature with-fingerprint"
    fi
fi

echo ""
echo "NOTE: keep password login enabled. This driver is experimental."

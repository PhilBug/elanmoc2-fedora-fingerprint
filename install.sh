#!/usr/bin/env bash
# Install the elanmoc2 libfprint driver for the ELAN 04f3:0c5e fingerprint
# sensor (HP ProBook 440/450/455 G8) on Fedora.
#
# - Installs build dependencies via dnf (requires sudo)
# - Clones the elanmoc2 branch of depau/libfprint (pinned commit)
# - Builds a minimal libfprint with only the elanmoc2 driver
# - Installs it to /usr/local/lib64 without touching the Fedora package
# - Adds an ldconfig entry and a systemd drop-in for fprintd
#
# Usage: ./install.sh
set -euo pipefail

REPO_URL="https://gitlab.freedesktop.org/depau/libfprint.git"
BRANCH="elanmoc2"
PINNED_COMMIT="11f0316"
BUILD_DIR="$HOME/elanmoc2-build"
LIBCONF="/etc/ld.so.conf.d/libfprint-elanmoc2.conf"
DROPIN_DIR="/etc/systemd/system/fprintd.service.d"
DROPIN="$DROPIN_DIR/elanmoc2.conf"

echo "==> Checking sensor (expected: 04f3:0c5e)"
if lsusb | grep -qi "04f3:0c5e"; then
    echo "    Sensor found: $(lsusb | grep -i '04f3:0c5e')"
else
    echo "    WARNING: sensor 04f3:0c5e not found in lsusb output."
    echo "    Other ELAN MOC2 IDs (0c00, 0c4c, 0c7c, 0c90) are supported by"
    echo "    the same driver, continuing anyway..."
fi

echo "==> Installing build dependencies (sudo)"
sudo dnf install -y meson ninja-build libgusb-devel git

echo "==> Cloning $REPO_URL (branch $BRANCH)"
mkdir -p "$BUILD_DIR"
if [ -d "$BUILD_DIR/libfprint/.git" ]; then
    git -C "$BUILD_DIR/libfprint" fetch origin "$BRANCH"
    git -C "$BUILD_DIR/libfprint" checkout "FETCH_HEAD"
else
    git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$BUILD_DIR/libfprint"
fi
git -C "$BUILD_DIR/libfprint" checkout "$PINNED_COMMIT" 2>/dev/null \
    || echo "    NOTE: commit $PINNED_COMMIT not found, using branch HEAD"

echo "==> Configuring build (driver: elanmoc2, prefix: /usr/local)"
meson setup "$BUILD_DIR/libfprint/builddir" \
    -Ddrivers=elanmoc2 \
    -Dintrospection=false \
    -Ddoc=false \
    -Dinstalled-tests=false \
    -Dudev_rules=disabled \
    -Dudev_hwdb=disabled \
    --prefix=/usr/local \
    --reconfigure 2>/dev/null || \
meson setup "$BUILD_DIR/libfprint/builddir" \
    -Ddrivers=elanmoc2 \
    -Dintrospection=false \
    -Ddoc=false \
    -Dinstalled-tests=false \
    -Dudev_rules=disabled \
    -Dudev_hwdb=disabled \
    --prefix=/usr/local

echo "==> Building"
ninja -C "$BUILD_DIR/libfprint/builddir"

echo "==> Installing to /usr/local (sudo)"
sudo ninja -C "$BUILD_DIR/libfprint/builddir" install

echo "==> Registering library path (ldconfig)"
echo /usr/local/lib64 | sudo tee "$LIBCONF" >/dev/null

echo "==> Creating fprintd systemd drop-in"
sudo mkdir -p "$DROPIN_DIR"
printf '[Service]\nEnvironment=LD_LIBRARY_PATH=/usr/local/lib64\n' | sudo tee "$DROPIN" >/dev/null

sudo ldconfig
sudo systemctl daemon-reload
sudo systemctl stop fprintd.service 2>/dev/null || true

echo "==> Verifying that fprintd sees the device"
sleep 1
if fprintd-list "$USER" 2>&1 | grep -qi "found 1 devices"; then
    echo ""
    echo "=== SUCCESS: fingerprint reader is ready ==="
    echo ""
    echo "Enroll a finger:"
    echo "    fprintd-enroll -f right-index-finger"
    echo "Then test with:"
    echo "    fprintd-verify"
else
    echo ""
    echo "=== WARNING: device not detected yet ==="
    echo "Run 'fprintd-list \$USER' to check. If it still says 'No devices available',"
    echo "reboot and try again."
fi

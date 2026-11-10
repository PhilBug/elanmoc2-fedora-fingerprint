#!/usr/bin/env bash
# Diagnose the elanmoc2 fingerprint setup.
#
# Prints the state of the sensor, the custom library, the fprintd drop-in and
# the PAM configuration, then a short summary. Safe to run at any time.
#
# Usage: ./doctor.sh
set -uo pipefail

LIBDIR="/usr/local/lib64"
DROPIN_DIR="/etc/systemd/system/fprintd.service.d"
DROPIN="${DROPIN_DIR}/90-elanmoc2.conf"
LEGACY_DROPIN="${DROPIN_DIR}/elanmoc2.conf"
LEGACY_LIBCONF="/etc/ld.so.conf.d/libfprint-elanmoc2.conf"

failures=0
warnings=0

section() { printf '\n== %s ==\n' "$*"; }
ok()      { printf '  [ OK ] %s\n' "$*"; }
fail()    { printf '  [FAIL] %s\n' "$*"; failures=$((failures + 1)); }
warn()    { printf '  [WARN] %s\n' "$*"; warnings=$((warnings + 1)); }
info()    { printf '         %s\n' "$*"; }

section "Sensor"
if command -v lsusb >/dev/null 2>&1; then
    sensor_line="$(lsusb | grep -i '04f3:0c5e' | head -n1 || true)"
    if [[ -n "${sensor_line}" ]]; then
        ok "found ${sensor_line}"
    else
        warn "04f3:0c5e not present (device unplugged, or a different ELAN model)"
    fi
else
    warn "lsusb is missing; install usbutils"
fi

section "Packages"
if rpm -q libfprint fprintd >/dev/null 2>&1; then
    pkg_list="$(rpm -q libfprint fprintd | tr '\n' ' ' || true)"
    ok "${pkg_list}"
else
    fail "libfprint or fprintd is not installed"
fi
if rpm -V libfprint >/dev/null 2>&1; then
    ok "stock libfprint package files are unmodified"
else
    warn "stock libfprint package files differ from the RPM (rpm -V libfprint)"
fi

section "Custom library"
if [[ -f "${LIBDIR}/libfprint-2.so.2.0.0" ]]; then
    ok "${LIBDIR}/libfprint-2.so.2.0.0 exists"
    if grep -aq elanmoc2 "${LIBDIR}/libfprint-2.so.2.0.0" 2>/dev/null; then
        ok "library contains the elanmoc2 driver"
    else
        fail "library does not look like an elanmoc2 build"
    fi
else
    fail "custom library is missing; run ./install.sh"
fi

section "systemd drop-in"
if [[ -f "${DROPIN}" ]]; then
    ok "${DROPIN}"
    sed 's/^/         /' "${DROPIN}"
else
    fail "missing ${DROPIN}; run ./install.sh"
fi
if [[ -f "${LEGACY_DROPIN}" ]]; then
    warn "legacy drop-in still present: ${LEGACY_DROPIN}"
fi
if [[ -f "${LEGACY_LIBCONF}" ]]; then
    warn "legacy global ldconfig entry still present: ${LEGACY_LIBCONF}"
fi

section "fprintd"
if systemctl is-active --quiet fprintd 2>/dev/null; then
    ok "fprintd is running"
else
    fail "fprintd is not running (systemctl status fprintd)"
fi

fprintd_env="$(systemctl show fprintd -p Environment --value 2>/dev/null || true)"
if printf '%s\n' "${fprintd_env}" | grep -q "LD_LIBRARY_PATH=${LIBDIR}"; then
    ok "fprintd environment: ${fprintd_env}"
else
    warn "LD_LIBRARY_PATH=${LIBDIR} is missing from fprintd's environment"
fi

fprintd_pid="$(systemctl show fprintd -p MainPID --value 2>/dev/null || true)"
if [[ -n "${fprintd_pid}" && "${fprintd_pid}" != "0" \
      && -r "/proc/${fprintd_pid}/maps" ]]; then
    if grep -q "${LIBDIR}/libfprint-2.so" "/proc/${fprintd_pid}/maps"; then
        ok "fprintd (pid ${fprintd_pid}) loaded the custom library"
    else
        fail "fprintd (pid ${fprintd_pid}) did not load the custom library"
        info "sudo grep libfprint /proc/${fprintd_pid}/maps"
    fi
else
    warn "cannot inspect fprintd's memory map (service not running?)"
fi

section "Device"
devices="$(LC_ALL=C fprintd-list "${USER}" 2>&1 || true)"
printf '%s\n' "${devices}" | sed 's/^/         /'
if printf '%s\n' "${devices}" | grep -qi 'ELAN Match-on-Chip'; then
    ok "fprintd sees the ELAN device"
else
    fail "fprintd does not see an ELAN Match-on-Chip device"
fi

section "PAM"
if command -v authselect >/dev/null 2>&1; then
    if authselect current 2>/dev/null | grep -q 'with-fingerprint'; then
        ok "authselect feature with-fingerprint is enabled"
    else
        warn "authselect feature with-fingerprint is not enabled"
        info "sudo authselect enable-feature with-fingerprint"
    fi
else
    warn "authselect not found; not a Fedora system?"
fi

section "SELinux"
if command -v getenforce >/dev/null 2>&1; then
    enforce="$(getenforce 2>/dev/null || true)"
    info "getenforce: ${enforce:-unknown}"
    if [[ -f "${LIBDIR}/libfprint-2.so.2.0.0" ]]; then
        context="$(ls -Z "${LIBDIR}/libfprint-2.so.2.0.0" 2>/dev/null || true)"
        info "context: ${context:-unknown}"
    fi
    info "recent denials: sudo ausearch -m avc -ts recent"
else
    info "SELinux tools not installed"
fi

section "Recent fprintd log"
if command -v journalctl >/dev/null 2>&1; then
    journalctl -u fprintd -n 15 --no-pager -o cat 2>/dev/null \
        | sed 's/^/         /' || info "journal not available"
else
    info "journalctl not available"
fi

printf '\n== Summary ==\n'
if [[ "${failures}" -eq 0 ]]; then
    echo "  No critical problems found (${warnings} warning(s))."
    echo "  If authentication still fails, re-enroll:"
    echo "      fprintd-delete \"\$USER\" -f right-index-finger"
    echo "      fprintd-enroll -f right-index-finger"
    exit 0
else
    echo "  ${failures} critical problem(s), ${warnings} warning(s)."
    echo "  Start with the [FAIL] lines above."
    exit 1
fi

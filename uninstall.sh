#!/usr/bin/env bash
# Uninstall the elanmoc2 libfprint driver and restore the stock state.
#
# Removes:
# - /usr/local/lib64/libfprint-2* (custom library)
# - /usr/local/include/libfprint-2 (headers)
# - /etc/ld.so.conf.d/libfprint-elanmoc2.conf (ldconfig entry)
# - /etc/systemd/system/fprintd.service.d/elanmoc2.conf (systemd drop-in)
#
# Usage: ./uninstall.sh
set -e
sudo rm -f /usr/local/lib64/libfprint-2.so \
           /usr/local/lib64/libfprint-2.so.2 \
           /usr/local/lib64/libfprint-2.so.2.0.0
sudo rm -rf /usr/local/include/libfprint-2
sudo rm -f  /etc/ld.so.conf.d/libfprint-elanmoc2.conf
sudo rm -f  /etc/systemd/system/fprintd.service.d/elanmoc2.conf
sudo rmdir --ignore-fail-on-non-empty /etc/systemd/system/fprintd.service.d 2>/dev/null || true
sudo ldconfig
sudo systemctl daemon-reload
sudo systemctl stop fprintd.service 2>/dev/null || true
echo "OK - stock libfprint (Fedora package) is active again."
echo "Note: the 04f3:0c5e sensor will no longer be visible to fprintd."

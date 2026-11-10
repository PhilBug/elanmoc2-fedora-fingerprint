# ELAN fingerprint reader fix for Fedora (elanmoc2)

Makes the **ELAN `04f3:0c5e` (ELAN:ARM-M4, match-on-chip)** fingerprint reader
work on **Fedora Linux**. This sensor ships in HP ProBook 440/450/455 G8
laptops (and possibly others) and is **not supported by the official
`libfprint` package** — it is on the upstream
[unsupported devices list](https://fprint.freedesktop.org/supported-devices.html),
so `fprintd` reports `No devices available`.

The fix builds the community [`elanmoc2`](https://gitlab.freedesktop.org/depau/libfprint/-/tree/elanmoc2)
driver branch (by Davide Depau), which has native, dedicated support for
`04f3:0c5e` (`ELANMOC2_DEV_0C5E`), and installs it alongside the stock
package without overwriting it.

> **Experimental.** The driver is a community fork that is not merged upstream.
> Keep password login enabled and make sure you can always get back into your
> account.

## Tested setup

| Component | Value |
|-----------|-------|
| Laptop | HP ProBook 455 G8 (likely works on 440/450 G8 too — same sensor) |
| Sensor | ELAN `04f3:0c5e` (check with `lsusb \| grep -i elan`) |
| OS | Fedora 44 Workstation (tested) |
| libfprint (stock) | 1.94.100 |
| fprintd | 1.94.5 |
| Driver branch | depau/libfprint `elanmoc2` @ `11f0316d069cc90c154c8cb0e46478388c5e2a74` |

Fedora 41–43 will most likely work too, but they are untested with this exact
script. Other distributions have confirmed this sensor working via the same
driver (Ubuntu 24.04, Manjaro, Arch AUR `libfprint-elanmoc2-git`, Mint, Zorin).

The same driver also lists `04f3:0c00`, `04f3:0c4c`, `04f3:0c7c` and
`04f3:0c90`. Those IDs are untested here, but the script should work for them.

## Requirements

- Fedora Workstation (or another dnf-based Fedora edition)
- `sudo` access
- Network access during installation (packages + git clone)
- About 1 GB of free disk space for the build

## Install

```bash
git clone https://github.com/PhilBug/elanmoc2-fedora-fingerprint.git
cd elanmoc2-fedora-fingerprint
./install.sh
```

The script:

1. checks for the sensor (a warning is fine if `lsusb` does not show it yet),
2. installs the build dependencies with `dnf`,
3. fetches the pinned commit from `depau/libfprint`,
4. builds a minimal libfprint with only the `elanmoc2` driver,
5. installs **only** `libfprint-2.so.*` to `/usr/local/lib64`,
6. adds a systemd drop-in so only `fprintd` loads that library,
7. restarts `fprintd` and verifies that the ELAN device appears.

The Fedora `libfprint` package is not modified. Everything can be removed with
`./uninstall.sh`.

## Enroll and verify

Enroll a finger (default: right index finger). Touch the sensor several times
when prompted and lift your finger between reads:

```bash
fprintd-enroll -f right-index-finger
```

Test it:

```bash
fprintd-verify
```

List enrolled prints:

```bash
fprintd-list "$USER"
```

Screen unlock and `sudo`/polkit authentication use the fingerprint
automatically if the `with-fingerprint` PAM feature is enabled. Check with:

```bash
authselect current
```

Fedora Workstation enables it by default. If it is missing:

```bash
sudo authselect enable-feature with-fingerprint
```

## How it works

- The custom library lives in `/usr/local/lib64` and is **not** registered
  globally with `ldconfig`, so other applications keep using the stock
  libfprint from the RPM.
- `/etc/systemd/system/fprintd.service.d/90-elanmoc2.conf` sets
  `LD_LIBRARY_PATH=/usr/local/lib64` for `fprintd` only. This is enough for
  the daemon (and therefore for PAM/GNOME) to use the new driver.
- The library filename and ABI match the stock package, so no rebuild of
  `fprintd` is needed.

## Troubleshooting

Run the built-in diagnostic first:

```bash
./doctor.sh
```

It checks the sensor, packages, custom library, drop-in, loaded library,
device list, PAM and SELinux, and prints recent `fprintd` log lines.

### `fprintd-list` says `No devices available`

```bash
systemctl cat fprintd            # drop-in present?
systemctl show fprintd -p Environment --value
sudo systemctl restart fprintd
fprintd-list "$USER"
```

The environment must contain `LD_LIBRARY_PATH=/usr/local/lib64`. If the
drop-in is missing, rerun `./install.sh`.

### `Failed to open device: Access denied`

Usually SELinux or a stale daemon. Try:

```bash
sudo restorecon -R /usr/local/lib64/libfprint-2*
sudo systemctl restart fprintd
sudo ausearch -m avc -ts recent
```

### Enrollment fails or verification never matches

Remove the old print and enroll again:

```bash
fprintd-delete "$USER" -f right-index-finger
fprintd-enroll -f right-index-finger
```

If fingerprints were previously enrolled **under Windows**, the sensor may
contain foreign templates. Wipe the on-sensor storage once:

```bash
sudo ~/elanmoc2-build/libfprint/builddir/examples/clear-storage
```

> Warning: this erases every template stored in the sensor, including the ones
> used by Windows.

### After a Fedora upgrade

If `fprintd` or `libfprint` changes ABI, rebuild and reinstall:

```bash
./install.sh
```

The script always fetches the same pinned commit, so a rebuild is
reproducible.

## Known limitations

- **GDM login screen** (after boot/reboot) may not offer fingerprint
  authentication. Depending on the GDM/PAM version it can work, but it is not
  guaranteed. Screen unlock generally works.
- Fingerprint authentication is a convenience, not a replacement for the
  password. Keep password login enabled.
- The sensor is match-on-chip: fingerprints are matched on the device itself,
  and no fingerprint images leave the sensor.
- This is not an official Fedora or libfprint package, and the driver is not
  merged upstream.

## Uninstall

```bash
./uninstall.sh
```

This removes the custom library, the systemd drop-in and any files left by
older versions of the script (headers, pkg-config file, metainfo, global
`ldconfig` entry). The stock Fedora package becomes active again. Enrolled
templates stay in the sensor and become usable again if you reinstall.

## Credits

- Driver: [depau/libfprint `elanmoc2` branch](https://gitlab.freedesktop.org/depau/libfprint/-/tree/elanmoc2)
  — reverse engineering and implementation by Davide Depau
- Upstream libfprint: [fprint project](https://fprint.freedesktop.org/)
- Related discussions:
  [iafilatov/libfprint#56](https://github.com/iafilatov/libfprint/issues/56)
  (04f3:0c5e support request),
  [libfprint MR !330](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/330)

## Disclaimer

Community solution, not an official Fedora or libfprint package. Use at your
own risk.

## License

MIT — see [LICENSE](LICENSE).

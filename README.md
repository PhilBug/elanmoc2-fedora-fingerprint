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

## Tested setup

| Component | Value |
|-----------|-------|
| Laptop | HP ProBook 455 G8 (likely works on 440/450 G8 too — same sensor) |
| Sensor | ELAN `04f3:0c5e` (check with `lsusb \| grep -i elan`) |
| OS | Fedora 44 Workstation (should work on 41+) |
| libfprint (stock) | 1.94.100 |
| Driver branch | depau/libfprint `elanmoc2` @ `11f0316` |

Other distributions have confirmed this sensor working via the same driver
(Ubuntu 24.04, Manjaro, Arch AUR `libfprint-elanmoc2-git`, Mint, Zorin).

## How it works

1. Clones the `elanmoc2` branch of `depau/libfprint` (pinned commit).
2. Builds a minimal `libfprint` with only the `elanmoc2` driver (meson/ninja).
3. Installs it to `/usr/local/lib64` — **the Fedora package is not touched**.
4. Registers the path in `ldconfig` and adds a systemd drop-in so `fprintd`
   loads the custom library first:
   `/etc/systemd/system/fprintd.service.d/elanmoc2.conf`
   → `Environment=LD_LIBRARY_PATH=/usr/local/lib64`
5. Restarts `fprintd`. Enrollment then works via `fprintd-enroll` and GNOME
   Settings.

## Install

```bash
git clone https://github.com/PhilBug/elanmoc2-fedora-fingerprint.git
cd elanmoc2-fedora-fingerprint
./install.sh
```

The script asks for the sudo password when installing packages and files.

Then enroll a finger (default: right index finger) and press your finger on
the sensor when prompted:

```bash
fprintd-enroll -f right-index-finger
```

Test it:

```bash
fprintd-verify
```

Screen unlock and `sudo`/polkit authentication use the fingerprint
automatically if the `with-fingerprint` PAM feature is enabled
(`authselect current` — enabled by default on Fedora Workstation).

## Known limitations

- **GDM login screen** (login after boot/reboot) usually does *not* offer
  fingerprint authentication — a known Linux limitation, unrelated to this
  driver. Screen unlock works.
- If fingerprints were previously enrolled **under Windows**, the sensor
  contains foreign templates. The driver skips/wipes them during enrollment;
  if enrollment misbehaves, wipe the on-sensor storage once:
  ```bash
  ~/elanmoc2-build/libfprint/builddir/examples/clear-storage
  ```
  Warning: this erases every template stored *in the sensor*, including ones
  used by Windows.

## Uninstall

```bash
./uninstall.sh
```

Restores the stock state: removes `/usr/local/lib64/libfprint-2*`, the
ldconfig entry and the systemd drop-in.

## Notes

- After major Fedora upgrades that change `fprintd`/`libfprint` ABI, rebuild:
  `cd ~/elanmoc2-build/libfprint && git pull && ninja -C builddir`, then rerun
  the install section of `install.sh`.
- The sensor is match-on-chip: fingerprints are matched on the device itself,
  no fingerprint images ever leave the sensor.

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

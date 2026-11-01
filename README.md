# PLF110 Touch Rate Sync

[English](README.md) | [简体中文](README.zh-CN.md)

Systemless touch report-rate sync module for OnePlus PLF110 / Synaptics S3910.
It uses the existing Binder touch interface and does not modify partitions or
files under `/system`, `/vendor`, or `/odm`.

## Device requirement

The service validates `ro.product.model`, `ro.product.vendor.model`,
`ro.product.device`, and `ro.boot.prjname` before starting. The defaults are
`ALLOWED_MODELS="PLF110"` and `ALLOWED_PROJECTS="24825"`. A mismatched device
causes the service to exit without writing the touch node.

## Features

- Polls display refresh rate every 3 seconds; foreground queries run only in
  listed-app mode (`ONLY_FOR_LISTED_APPS=1`).
- Writes the touch report rate when the live value differs from the target.
- Reads the live report rate every 1.5 seconds and reapplies the target if it
  is replaced by another service.
- Runs with KernelSU's BusyBox standalone shell and uses built-in rate parsing
  to reduce short-lived subprocesses.
- Verifies every write by reading the value back.
- Restores the default value when the screen is off, the package is not listed,
  the module is disabled, or the daemon exits.

## v1.0.7 implementation and validation

The optimization targets subprocess creation rather than hiding activity by
extending polling intervals. The daemon uses KernelSU's BusyBox standalone shell,
parses the HIDL readback and first display record with shell built-ins, and skips
foreground queries when all apps are eligible (`foreground=all`). Existing write
verification, retry, device gating, single-instance locking and exit restoration
remain in place. `/system/bin/timeout` is explicit to preserve timeout behavior.

On 2026-11-01, short consecutive samples on the same PLF110 setup measured daemon
CPU time including reaped children at approximately **17.9% → 2.22% of one core**
(12.57s before, 12.59s after, about 88% lower). Both samples used 3s display polling
and 1.5s readback, matching the installed configuration; the older repository
v1.0.5 default was 10s readback. This is not a universal performance guarantee or
proof that every CPU 0–3 `cycles` fluctuation comes from this module.

Validation covered 66 fixture assertions, actual-shell syntax checks, live
120Hz/raw 288 readback, single-instance startup and graceful exit restoring raw 0.
Fixtures also covered 144/90/60Hz mapping, listed-app filtering and off-screen
restore targets. Live 144Hz gaming, screen-off transitions, ZIP reinstall and
reboot persistence have not been tested for this release. `effective_target` is a
configured label, not a physical touch-sampling-rate measurement.

## Rate map

| Display refresh | Touch report rate | Notes |
|---:|---:|---|
| 30Hz | 120Hz | Lowest available rate |
| 60Hz | 120Hz | |
| 90Hz | 180Hz | |
| 120Hz | 300Hz | Writes raw value 288; platform maps 288 to 300 |
| 144Hz | 320Hz | Writes raw value 360; effective label is 320Hz |

The S3910 driver accepts `120/180/240/288/360` only. Edit `RATE_MAP` in
`config.conf` to change the mapping. `EFFECTIVE_RATE_MAP` supplies display
labels for raw controller values, such as `120:288:300` and `144:360:320`.

## Install

Version `v1.0.7` is a **KernelSU-only** release. It requires an executable
`/data/adb/ksu/bin/busybox`; missing BusyBox causes startup to fail explicitly.
Magisk is not supported by this release.

Install the release zip with KernelSU and reboot. The module ID is
`plf110_touch_rate_sync`, matching the currently tested module.

**Do not keep the old `touch_rate_sync` module installed alongside this one.**
Its ID differs, so this release does not automatically replace it. Back up any
custom configuration, uninstall the old module in your manager and reboot before
installing this release. Both IDs use the same runtime PID/lock directory.

Manual start and stop:

```sh
sh /data/adb/modules/plf110_touch_rate_sync/service.sh
kill "$(cat /data/adb/touch_rate_sync/pid)"
```

## Configuration

Edit `/data/adb/modules/plf110_touch_rate_sync/config.conf`:

- `POLL_INTERVAL`: refresh-rate and foreground polling interval, integer seconds.
- `WATCHDOG_INTERVAL`: report-rate readback interval, default 1.5 seconds.
- `RATE_MAP`: refresh-rate to report-rate mapping.
- `FALLBACK`: fallback for unmapped refresh rates.
- `ONLY_FOR_LISTED_APPS=1`: apply only to packages in `apps.txt`.
- `DRY_RUN=1`: log intended changes without writing.
- `RESTORE_RATE`: value used when inactive, default `0`.
- `ALLOWED_MODELS`: accepted device model names, default `PLF110`.
- `ALLOWED_PROJECTS`: accepted project ids, default `24825`.

## Runtime files

- Status: `/data/adb/touch_rate_sync/status`
- Log: `/data/adb/touch_rate_sync/daemon.log`
- PID: `/data/adb/touch_rate_sync/pid`

The module Action button shows the current status and creates a read-only diagnostic archive,
preferably under `/sdcard/Download`. It collects module, touch, display, and relevant log
information without writing the touch node or collecting account tokens/full system properties.

## Build

```sh
./build.sh
```

The script creates `PLF110-Touch-Rate-Sync-<version>.zip` from the module files.

## Notes

- Higher touch report rates can increase touch-controller power use and heat.
- Set `ONLY_FOR_LISTED_APPS=1` to limit enforcement to selected packages.
- The module is device-specific to PLF110 / S3910.

## License

MIT


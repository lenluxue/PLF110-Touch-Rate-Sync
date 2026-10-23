# PLF110 Touch Rate Sync

Systemless touch report-rate sync module for OnePlus PLF110 / Synaptics S3910.
It uses the existing Binder touch interface and does not modify partitions or
files under `/system`, `/vendor`, or `/odm`.

## Device requirement

The service validates `ro.product.model`, `ro.product.vendor.model`,
`ro.product.device`, and `ro.boot.prjname` before starting. The defaults are
`ALLOWED_MODELS="PLF110"` and `ALLOWED_PROJECTS="24825"`. A mismatched device
causes the service to exit without writing the touch node.

## Features

- Polls display refresh rate and the foreground package every 3 seconds.
- Writes the touch report rate only when the desired value changes.
- Reads the live report rate every 1.5 seconds and reapplies the target if it
  is replaced by another service.
- Verifies every write by reading the value back.
- Restores the default value when the screen is off, the package is not listed,
  the module is disabled, or the daemon exits.

## Rate map

| Display refresh | Touch report rate | Notes |
|---:|---:|---|
| 30Hz | 120Hz | Lowest available rate |
| 60Hz | 120Hz | |
| 90Hz | 180Hz | 200Hz is not accepted by this controller |
| 120Hz | 300Hz | Writes raw value 288; platform maps 288 to 300 |
| 144Hz | 360Hz | |

The S3910 driver accepts `120/180/240/288/360` only. Edit `RATE_MAP` in
`config.conf` to change the mapping.

## Install

Install the release zip with KernelSU or Magisk and reboot. The module entry is
`touch_rate_sync`.

Manual start and stop:

```sh
sh /data/adb/modules/touch_rate_sync/service.sh
kill "$(cat /data/adb/touch_rate_sync/pid)"
```

## Configuration

Edit `/data/adb/modules/touch_rate_sync/config.conf`:

- `POLL_INTERVAL`: refresh-rate and foreground polling interval, integer seconds.
- `WATCHDOG_INTERVAL`: report-rate readback interval.
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

The module Action button shows the current status and recent log lines.

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


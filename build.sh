#!/usr/bin/env sh

set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
VERSION=$(sed -n 's/^version=//p' "$ROOT/module.prop" | head -n 1)
OUT=${1:-"$ROOT/PLF110-Touch-Rate-Sync-${VERSION}.zip"}

cd "$ROOT"
zip -r9 "$OUT" \
    module.prop \
    config.conf \
    apps.txt \
    service.sh \
    action.sh \
    uninstall.sh \
    README.md \
    bin/collect_diag.sh \
    bin/touch_rate_daemon.sh \
    bin/device_check.sh


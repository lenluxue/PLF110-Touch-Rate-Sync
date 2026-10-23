#!/system/bin/sh

MODDIR=${0%/*}
STATE_DIR=/data/adb/touch_rate_sync
DAEMON=$MODDIR/bin/touch_rate_daemon.sh

[ -e "$MODDIR/disable" ] && exit 0
[ -x "$DAEMON" ] || chmod 0755 "$DAEMON" 2>/dev/null
mkdir -p "$STATE_DIR" 2>/dev/null
chmod 0700 "$STATE_DIR" 2>/dev/null

i=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$i" -lt 120 ]; do
    sleep 2
    i=$((i + 1))
done

i=0
while [ "$i" -lt 60 ]; do
    if /odm/bin/touchHidlTest -c ab 0 182 2>&1 | grep -q 'binder: support'; then
        break
    fi
    sleep 1
    i=$((i + 1))
done

if command -v setsid >/dev/null 2>&1; then
    setsid /system/bin/sh "$DAEMON" </dev/null >/dev/null 2>&1 &
else
    /system/bin/sh "$DAEMON" </dev/null >/dev/null 2>&1 &
fi


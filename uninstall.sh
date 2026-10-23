#!/system/bin/sh

STATE_DIR=/data/adb/touch_rate_sync

if [ -f "$STATE_DIR/pid" ]; then
    pid=$(cat "$STATE_DIR/pid" 2>/dev/null)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
    sleep 1
fi

/odm/bin/touchHidlTest -c wb 0 182 0 >/dev/null 2>&1
rm -rf "$STATE_DIR"


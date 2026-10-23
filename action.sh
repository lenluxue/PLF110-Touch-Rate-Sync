#!/system/bin/sh

STATE_DIR=/data/adb/touch_rate_sync

echo "Touch Rate Sync"
echo "==============="
if [ -r "$STATE_DIR/status" ]; then
    cat "$STATE_DIR/status"
else
    echo "status: not started"
fi
echo
echo "Recent log:"
tail -n 30 "$STATE_DIR/daemon.log" 2>/dev/null || true


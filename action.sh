#!/system/bin/sh

MODDIR=${0%/*}
STATE_DIR=/data/adb/touch_rate_sync
DIAG="$MODDIR/bin/collect_diag.sh"

echo 'PLF110 触控采样率模块'
echo '===================='
echo '感谢慕容提供诊断思路'
if [ -r "$STATE_DIR/status" ]; then
    cat "$STATE_DIR/status"
else
    echo '运行状态：未发现状态文件'
fi

echo
echo '正在收集只读诊断信息……'
if [ -x "$DIAG" ]; then
    "$DIAG"
elif [ -r "$DIAG" ]; then
    /system/bin/sh "$DIAG"
else
    echo "诊断失败：找不到采集脚本 $DIAG"
fi

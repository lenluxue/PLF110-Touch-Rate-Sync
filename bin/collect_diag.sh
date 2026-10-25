#!/system/bin/sh

MODDIR=${0%/*}
MODDIR=${MODDIR%/*}
STATE_DIR=/data/adb/touch_rate_sync
TS=$(date +%Y%m%d_%H%M%S)
NAME="touch_rate_sync_diag_$TS"
TMP="/data/local/tmp/$NAME"
OUT=

say() { printf '%s\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }
run_to() { "$@" > "$1" 2>&1; }

if [ ! -d "$MODDIR" ]; then
    say "诊断失败：模块目录不存在：$MODDIR"
    exit 1
fi
if ! mkdir -p "$TMP" 2>/dev/null; then
    say "诊断失败：无法创建临时目录。"
    exit 1
fi

mkdir -p "$TMP/模块" "$TMP/触控" "$TMP/显示" "$TMP/系统" "$TMP/日志" "$TMP/工具"

{
    echo '慕容触控采样率模块 · PLF110 诊断报告'
    echo "采集时间：$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null)"
    echo "模块目录：$MODDIR"
    echo "设备型号：$(getprop ro.product.model 2>/dev/null)"
    echo "产品型号：$(getprop ro.product.vendor.model 2>/dev/null)"
    echo "设备代号：$(getprop ro.product.device 2>/dev/null)"
    echo "项目号：$(getprop ro.boot.prjname 2>/dev/null)"
    echo "品牌：$(getprop ro.product.brand 2>/dev/null)"
    echo "Android：$(getprop ro.build.version.release 2>/dev/null)（SDK $(getprop ro.build.version.sdk 2>/dev/null)）"
    echo "系统版本：$(getprop ro.build.version.incremental 2>/dev/null)"
    echo "内核：$(uname -a 2>/dev/null)"
    echo "SELinux：$(getenforce 2>/dev/null)"
    echo "启动管理器：KSU $(getprop ro.kernelsu.version 2>/dev/null)，Magisk $(getprop ro.magisk.version 2>/dev/null)"
    echo "运行身份：$(id 2>/dev/null)"
    echo
    echo '===== 模块信息 ====='
    cat "$MODDIR/module.prop" 2>/dev/null
    echo
    echo '===== 模块文件及权限 ====='
    ls -laR "$MODDIR" 2>/dev/null
    echo
    echo '===== 运行进程 ====='
    ps -A 2>/dev/null | grep -E 'touch_rate_daemon|touch_rate_sync' | grep -v grep
    echo
    echo '===== 状态文件 ====='
    cat "$STATE_DIR/status" 2>/dev/null || echo '状态文件不存在'
    echo
    echo '===== 配置文件 ====='
    cat "$MODDIR/config.conf" 2>/dev/null
    echo
    echo '===== PID 文件 ====='
    cat "$STATE_DIR/pid" 2>/dev/null
    echo
    echo '===== 存储空间 ====='
    df -h /data /sdcard 2>/dev/null
} > "$TMP/基础信息.txt" 2>&1

{
    echo '===== 当前触控上报率（只读） ====='
    if [ -x /odm/bin/touchHidlTest ]; then
        timeout 5 /odm/bin/touchHidlTest -c rb 0 182 2>&1
    else
        echo '未找到 /odm/bin/touchHidlTest'
    fi
    echo
    echo '===== 触控相关节点 ====='
    ls -la /proc/touchpanel /dev/tcm_hbp\* /dev/input 2>&1
    for f in /proc/touchpanel/report_rate /proc/touchpanel/rate_white_list /proc/touchpanel/debug_info/main_register; do
        if [ -r "$f" ]; then
            echo "===== $f ====="
            timeout 5 cat "$f" 2>&1 | head -n 120
        fi
    done
    echo
    echo '===== 触控控制服务 ====='
    service list 2>/dev/null | grep -iE 'touch|hbp|syna' | head -n 80
    echo
    echo '===== 输入设备摘要 ====='
    getevent -lp 2>/dev/null | head -n 160
} > "$TMP/触控/触控信息.txt" 2>&1

{
    echo '===== 当前显示模式与刷新率 ====='
    timeout 8 cmd display get-displays 2>&1
    echo
    echo '===== dumpsys display 摘要 ====='
    timeout 10 dumpsys display 2>/dev/null | grep -iE 'mActiveModeId|renderFrameRate|DisplayDeviceInfo|supportedModes|refreshRateOverride' | head -n 80
    echo
    echo '===== SurfaceFlinger 刷新率摘要 ====='
    timeout 10 dumpsys SurfaceFlinger 2>/dev/null | grep -iE 'RefreshRateSelector|activeMode=|DisplayMode' | tail -n 60
    echo
    echo '===== 刷新率相关设置 ====='
    for key in system/peak_refresh_rate system/min_refresh_rate system/user_refresh_rate system/default_refresh_rate; do
        printf '%s=' "$key"
        settings get $key 2>/dev/null
    done
} > "$TMP/显示/刷新率.txt" 2>&1

{
    echo '===== 触控模块 daemon 日志（最近 500 行） ====='
    tail -n 500 "$STATE_DIR/daemon.log" 2>/dev/null
    echo
    echo '===== 触控模块 service 日志（最近 200 行） ====='
    tail -n 200 "$STATE_DIR/service.log" 2>/dev/null
    echo
    echo '===== 相关 logcat（最近 1200 行匹配） ====='
    timeout 15 logcat -d -v threadtime -t 2500 2>/dev/null | grep -iE 'touch|tcm|hbp|syna|touch_rate_sync' | tail -n 1200
} > "$TMP/日志/触控日志.txt" 2>&1

{
    echo '===== 已安装模块 ====='
    ls -la /data/adb/modules 2>/dev/null
    echo
    echo '===== 相关系统属性 ====='
    getprop 2>/dev/null | grep -iE 'touch|hbp|syna|kernel.?su|magisk|prjname|oplusrom'
    echo
    echo '===== 相关内核日志（最近 400 行匹配） ====='
    dmesg 2>/dev/null | grep -iE 'synaptics|syna|tcm|hbp|touchpanel|touch' | tail -n 400
} > "$TMP/系统/系统摘要.txt" 2>&1

{
    echo "tar=$(command -v tar 2>/dev/null)"
    echo "timeout=$(command -v timeout 2>/dev/null)"
    echo "sha256sum=$(command -v sha256sum 2>/dev/null)"
    echo "logcat=$(command -v logcat 2>/dev/null)"
    echo "toybox=$(command -v toybox 2>/dev/null)"
    echo "busybox=$(command -v busybox 2>/dev/null)"
} > "$TMP/工具/工具信息.txt" 2>&1

for dir in /sdcard/Download /storage/emulated/0/Download /data/local/tmp "$MODDIR"; do
    [ -d "$dir" ] || continue
    probe="$dir/.touch_diag_write_test_$$"
    if ( : > "$probe" ) 2>/dev/null; then
        rm -f "$probe"
        OUT=$dir
        break
    fi
done

if [ -z "$OUT" ]; then
    rm -rf "$TMP"
    say '诊断失败：没有可写入的输出目录。'
    exit 1
fi

ARCHIVE="$OUT/$NAME.tar.gz"
if ! ( cd "$TMP" && tar -czf "$ARCHIVE" . ) >/dev/null 2>&1 || [ ! -s "$ARCHIVE" ]; then
    rm -f "$ARCHIVE"
    if has zip && ( cd "$TMP" && zip -qr "$OUT/$NAME.zip" . ) >/dev/null 2>&1; then
        ARCHIVE="$OUT/$NAME.zip"
    else
        rm -rf "$TMP"
        say '诊断失败：压缩打包失败。'
        exit 1
    fi
fi

SIZE=$(wc -c < "$ARCHIVE" 2>/dev/null | tr -d ' \n')
rm -rf "$TMP"
say "诊断完成：$ARCHIVE（${SIZE:-未知} 字节）"
say '报告包含设备/模块/触控/刷新率/日志摘要；不包含账户令牌或完整系统属性。'

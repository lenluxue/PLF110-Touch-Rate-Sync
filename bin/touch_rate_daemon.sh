#!/system/bin/sh

set -u

SELF=$0
MODDIR=$(cd "${SELF%/*}/.." 2>/dev/null && pwd) || exit 1
STATE_DIR=${TRS_STATE_DIR:-/data/adb/touch_rate_sync}
PIDFILE=$STATE_DIR/pid
LOCKDIR=$STATE_DIR/lock
STATUS=$STATE_DIR/status
LOG=$STATE_DIR/daemon.log

POLL_INTERVAL=3
WATCHDOG_INTERVAL=1.5
RATE_MAP="30:120 60:120 90:180 120:288 144:360"
EFFECTIVE_RATE_MAP="120:300"
SUPPORTED_RATES="120 180 240 288 360"
FALLBACK=nearest_high
SCALE_NUM=5
SCALE_DEN=2
ONLY_FOR_LISTED_APPS=0
APP_LIST_FILE=apps.txt
RESTORE_RATE=0
RESTORE_ON_EXIT=1
DRY_RUN=0
LOG_MAX_BYTES=131072
TOUCH_HIDL=/odm/bin/touchHidlTest
TOUCH_NODE=182
HIDL_DEVICE=0
ALLOWED_MODELS=PLF110
ALLOWED_PROJECTS=24825

CONFIG_FILE=${TRS_CONFIG:-$MODDIR/config.conf}
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

case "$APP_LIST_FILE" in
    /*) ;;
    *) APP_LIST_FILE=$MODDIR/$APP_LIST_FILE ;;
esac

mkdir -p "$STATE_DIR" 2>/dev/null || exit 1
chmod 0700 "$STATE_DIR" 2>/dev/null || true

log() {
    if [ -f "$LOG" ]; then
        size=$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')
        case "$size" in
            ''|*[!0-9]*) size=0 ;;
        esac
        if [ "$size" -gt "$LOG_MAX_BYTES" ]; then
            mv -f "$LOG" "$LOG.1" 2>/dev/null || true
        fi
    fi
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null || true
}

if [ ! -r "$MODDIR/bin/device_check.sh" ]; then
    log "ERROR missing device_check.sh"
    exit 1
fi
. "$MODDIR/bin/device_check.sh"
if ! device_check; then
    log "device check failed: $DEVICE_SUMMARY"
    exit 1
fi

log_limited() {
    now=$(date +%s)
    if [ $((now - LAST_LOG_ERR)) -ge 60 ]; then
        log "$*"
        LAST_LOG_ERR=$now
    fi
}

read_rate() {
    out=$(timeout 2 "$TOUCH_HIDL" -c rb "$HIDL_DEVICE" "$TOUCH_NODE" 2>&1) || return 1
    value=$(printf '%s\n' "$out" | tail -n 1 | tr -cd '0-9')
    case "$value" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s\n' "$value"
}

write_rate() {
    want=$1
    reason=$2
    LAST_REASON=$reason

    if [ "$DRY_RUN" = 1 ]; then
        log "DRY-RUN target=$want reason=$reason"
        return 0
    fi

    log "write rate=$want reason=$reason"
    timeout 2 "$TOUCH_HIDL" -c wb "$HIDL_DEVICE" "$TOUCH_NODE" "$want" >/dev/null 2>&1 || true
    sleep 0.12
    got=$(read_rate 2>/dev/null) || got=
    if [ "$got" = "$want" ]; then
        CURRENT=$got
        log "verified rate=$want"
        return 0
    fi

    sleep 0.25
    timeout 2 "$TOUCH_HIDL" -c wb "$HIDL_DEVICE" "$TOUCH_NODE" "$want" >/dev/null 2>&1 || true
    sleep 0.12
    got=$(read_rate 2>/dev/null) || got=
    if [ "$got" = "$want" ]; then
        CURRENT=$got
        log "verified rate=$want after retry"
        return 0
    fi

    CURRENT=${got:--}
    log "ERROR rate=$want readback=${got:-unknown}"
    return 1
}

read_display() {
    out=$(timeout 4 cmd display get-displays 2>/dev/null) || return 1
    [ -n "$out" ] || return 1

    state=$(printf '%s\n' "$out" | sed -n 's/.*state \([A-Z_][A-Z_]*\).*/\1/p' | head -n 1)
    render=$(printf '%s\n' "$out" | sed -n 's/.*renderFrameRate \([0-9][0-9.]*\).*/\1/p' | head -n 1)
    case "$render" in
        ''|*[!0-9.]*) return 1 ;;
    esac

    rounded=$(awk -v r="$render" 'BEGIN { printf "%d", int(r + 0.5) }' 2>/dev/null)
    case "$rounded" in
        ''|*[!0-9]*) return 1 ;;
    esac

    SCREEN_STATE=${state:-UNKNOWN}
    REFRESH=$rounded
    return 0
}

read_screen_fallback() {
    wake=$(timeout 3 dumpsys power 2>/dev/null | sed -n 's/.*mWakefulness=\([A-Za-z_]*\).*/\1/p' | head -n 1)
    case "$wake" in
        Awake) SCREEN_STATE=ON ;;
        '') return 1 ;;
        *) SCREEN_STATE=OFF ;;
    esac
    return 0
}

read_foreground() {
    pkg=$(timeout 4 dumpsys window 2>/dev/null | sed -n 's/.*mFocusedApp=ActivityRecord{[^ ]* u[0-9][0-9]* \([^ /]*\)\/.*/\1/p' | head -n 1)

    if [ -z "$pkg" ]; then
        pkg=$(timeout 4 dumpsys activity activities 2>/dev/null | sed -n 's/.*topResumedActivity=ActivityRecord{[^ ]* u[0-9][0-9]* \([^ /]*\)\/.*/\1/p' | head -n 1)
    fi

    FOREGROUND=${pkg:-?}
}

check_app_allowed() {
    if [ "$ONLY_FOR_LISTED_APPS" != 1 ]; then
        APP_ALLOWED=1
        return 0
    fi

    APP_ALLOWED=0
    [ -r "$APP_LIST_FILE" ] || return 0

    while IFS= read -r line; do
        line=${line%%#*}
        line=$(printf '%s' "$line" | tr -d '[:space:]')
        [ -n "$line" ] || continue
        if [ "$line" = "$FOREGROUND" ]; then
            APP_ALLOWED=1
            return 0
        fi
    done < "$APP_LIST_FILE"
}

target_from_map() {
    refresh=$1
    for pair in $RATE_MAP; do
        case "$pair" in
            *:*) ;;
            *) continue ;;
        esac
        key=${pair%%:*}
        value=${pair#*:}
        if [ "$key" = "$refresh" ]; then
            printf '%s\n' "$value"
            return 0
        fi
    done
    return 1
}

choose_closest() {
    wanted=$1
    best=

    case "$FALLBACK" in
        floor)
            for rate in $SUPPORTED_RATES; do
                if [ "$rate" -le "$wanted" ]; then
                    if [ -z "$best" ] || [ "$rate" -gt "$best" ]; then
                        best=$rate
                    fi
                fi
            done
            ;;
        ceil)
            for rate in $SUPPORTED_RATES; do
                if [ "$rate" -ge "$wanted" ]; then
                    if [ -z "$best" ] || [ "$rate" -lt "$best" ]; then
                        best=$rate
                    fi
                fi
            done
            ;;
        *)
            best_delta=
            for rate in $SUPPORTED_RATES; do
                delta=$((rate - wanted))
                [ "$delta" -lt 0 ] && delta=$((-delta))
                if [ -z "$best" ] || [ "$delta" -lt "$best_delta" ]; then
                    best=$rate
                    best_delta=$delta
                elif [ "$delta" -eq "$best_delta" ] && [ "$rate" -gt "$best" ]; then
                    best=$rate
                fi
            done
            ;;
    esac

    [ -n "$best" ] || best=$wanted
    printf '%s\n' "$best"
}

target_for_refresh() {
    refresh=$1
    mapped=$(target_from_map "$refresh" 2>/dev/null) || mapped=
    if [ -n "$mapped" ]; then
        printf '%s\n' "$mapped"
        return 0
    fi

    if [ "$SCALE_DEN" -le 0 ]; then
        printf '0\n'
        return 0
    fi

    wanted=$((refresh * SCALE_NUM / SCALE_DEN))
    choose_closest "$wanted"
}

effective_for_target() {
    refresh=$1
    rate=$2
    for pair in ${EFFECTIVE_RATE_MAP:-}; do
        case "$pair" in
            *:*) ;;
            *) continue ;;
        esac
        key=${pair%%:*}
        value=${pair#*:}
        if [ "$key" = "$refresh" ] && [ "$rate" = "288" ]; then
            printf '%s\n' "$value"
            return 0
        fi
    done
    printf '%s\n' "$rate"
}

status_write() {
    {
        printf 'time=%s\n' "$(date '+%F %T')"
        printf 'screen=%s\n' "$SCREEN_STATE"
        printf 'refresh=%s\n' "$REFRESH"
        printf 'foreground=%s\n' "$FOREGROUND"
        printf 'app_allowed=%s\n' "$APP_ALLOWED"
        printf 'node_target=%s\n' "$TARGET"
        printf 'effective_target=%s\n' "$EFFECTIVE_TARGET"
        printf 'node_current=%s\n' "$CURRENT"
        printf 'last_reason=%s\n' "$LAST_REASON"
        printf 'dry_run=%s\n' "$DRY_RUN"
        printf 'device=%s\n' "$DEVICE_SUMMARY"
        printf 'pid=%s\n' "$$"
    } > "$STATUS.tmp" 2>/dev/null && mv -f "$STATUS.tmp" "$STATUS" 2>/dev/null || rm -f "$STATUS.tmp"
}

is_running_daemon() {
    pid=$1
    [ -n "$pid" ] || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'touch_rate_daemon.sh'
}

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null || true)
    if is_running_daemon "$oldpid"; then
        exit 0
    fi
    rm -rf "$LOCKDIR"
    mkdir "$LOCKDIR" 2>/dev/null || exit 1
fi
echo $$ > "$PIDFILE"

cleanup() {
    trap - EXIT INT TERM HUP
    if [ "${RESTORE_ON_EXIT:-1}" = 1 ] && [ "${DRY_RUN:-0}" != 1 ]; then
        timeout 2 "$TOUCH_HIDL" -c wb "$HIDL_DEVICE" "$TOUCH_NODE" "$RESTORE_RATE" >/dev/null 2>&1 || true
        log "exit restore rate=$RESTORE_RATE"
    fi
    rm -f "$PIDFILE"
    rmdir "$LOCKDIR" 2>/dev/null || true
}

on_signal() {
    cleanup
    exit 0
}

trap cleanup EXIT
trap on_signal INT TERM HUP

if [ ! -x "$TOUCH_HIDL" ]; then
    log "ERROR missing touch control binary: $TOUCH_HIDL"
    exit 1
fi

NEXT_POLL=0
LAST_LOG_ERR=0
HAVE_DISPLAY=0
SCREEN_STATE=UNKNOWN
REFRESH=0
FOREGROUND=-
TARGET=$RESTORE_RATE
EFFECTIVE_TARGET=$RESTORE_RATE
CURRENT=-
APP_ALLOWED=1
LAST_APPLIED=-
LAST_REASON=startup

log "start pid=$$ config=$CONFIG_FILE dry_run=$DRY_RUN device=$DEVICE_SUMMARY"
status_write

while :; do
    if [ -e "$MODDIR/disable" ]; then
        log "disable file found, exiting"
        break
    fi
    if [ -e "$MODDIR/remove" ]; then
        log "remove file found, exiting"
        break
    fi

    now=$(date +%s)
    if [ "$now" -ge "$NEXT_POLL" ]; then
        if read_display; then
            HAVE_DISPLAY=1
            if [ "$SCREEN_STATE" = ON ]; then
                read_foreground
            else
                FOREGROUND=off
            fi
        else
            log_limited "display read failed"
            if read_screen_fallback && [ "$SCREEN_STATE" != ON ]; then
                FOREGROUND=off
            fi
        fi

        if [ "$HAVE_DISPLAY" = 1 ] && [ "$SCREEN_STATE" = ON ]; then
            check_app_allowed
            if [ "$APP_ALLOWED" = 1 ] && [ "$REFRESH" -gt 0 ]; then
                TARGET=$(target_for_refresh "$REFRESH")
                EFFECTIVE_TARGET=$(effective_for_target "$REFRESH" "$TARGET")
            else
                TARGET=$RESTORE_RATE
                EFFECTIVE_TARGET=$TARGET
            fi
        else
            TARGET=$RESTORE_RATE
            EFFECTIVE_TARGET=$TARGET
        fi

        NEXT_POLL=$((now + POLL_INTERVAL))
        status_write
    fi

    if [ "$DRY_RUN" = 1 ]; then
        if [ "$TARGET" != "$LAST_APPLIED" ]; then
            log "DRY-RUN target=$TARGET refresh=$REFRESH screen=$SCREEN_STATE app=$FOREGROUND"
            LAST_APPLIED=$TARGET
            status_write
        fi
        sleep "$WATCHDOG_INTERVAL"
        continue
    fi

    if [ "$HAVE_DISPLAY" = 1 ] && [ "$SCREEN_STATE" = ON ] && [ "$APP_ALLOWED" = 1 ] && [ "$TARGET" -gt 0 ]; then
        CURRENT=$(read_rate 2>/dev/null) || CURRENT=
        if [ "$CURRENT" != "$TARGET" ]; then
            write_rate "$TARGET" "sync refresh=$REFRESH app=$FOREGROUND current=${CURRENT:-unknown} effective=$EFFECTIVE_TARGET"
            LAST_APPLIED=$TARGET
            status_write
        fi
    else
        if [ "$LAST_APPLIED" != "$RESTORE_RATE" ]; then
            CURRENT=$(read_rate 2>/dev/null) || CURRENT=
            if [ "$CURRENT" != "$RESTORE_RATE" ]; then
                write_rate "$RESTORE_RATE" "inactive screen=$SCREEN_STATE app=$FOREGROUND"
            fi
            LAST_APPLIED=$RESTORE_RATE
            status_write
        fi
    fi

    sleep "$WATCHDOG_INTERVAL"
done


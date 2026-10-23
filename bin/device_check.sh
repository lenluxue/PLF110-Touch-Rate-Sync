#!/system/bin/sh

# Source this file after ALLOWED_MODELS and ALLOWED_PROJECTS are defined.
device_check() {
    DEV_MODEL=$(getprop ro.product.model 2>/dev/null || true)
    DEV_VENDOR_MODEL=$(getprop ro.product.vendor.model 2>/dev/null || true)
    DEV_DEVICE=$(getprop ro.product.device 2>/dev/null || true)
    DEV_PROJECT=$(getprop ro.boot.prjname 2>/dev/null || true)

    DEVICE_SUMMARY="model=${DEV_MODEL:-?} vendor_model=${DEV_VENDOR_MODEL:-?} device=${DEV_DEVICE:-?} project=${DEV_PROJECT:-?}"

    matched=0
    for allowed in ${ALLOWED_MODELS:-}; do
        if [ "$DEV_MODEL" = "$allowed" ] || [ "$DEV_VENDOR_MODEL" = "$allowed" ] || [ "$DEV_DEVICE" = "$allowed" ]; then
            matched=1
        fi
    done
    [ "$matched" = 1 ] || return 1

    if [ -n "${ALLOWED_PROJECTS:-}" ]; then
        matched=0
        for allowed in $ALLOWED_PROJECTS; do
            if [ "$DEV_PROJECT" = "$allowed" ]; then
                matched=1
            fi
        done
        [ "$matched" = 1 ] || return 1
    fi

    return 0
}


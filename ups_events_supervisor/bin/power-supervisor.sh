#!/usr/bin/env bash
#
# power-supervisor.sh
# Main UPS power supervisor daemon
#

set -euo pipefail
IFS=$'\n\t'

LOCK_FILE="/run/powerctl/power-supervisor.lock"
exec 9>"$LOCK_FILE" || exit 1
flock -n 9 || exit 0

# --- Imports --------------------------------------------------
source /usr/local/powerctl/common/lib/log.sh
source /usr/local/powerctl/bin/state-lib.sh
source /usr/local/powerctl/bin/device-lib.sh

# --- Configs --------------------------------------------------
source /usr/local/powerctl/conf/power.conf
source /usr/local/powerctl/conf/device.conf
source /usr/local/powerctl/conf/schedule.conf

log_info "Power Supervisor started"

# --- Helpers --------------------------------------------------
shutdown_devices_if_needed() {
    for entry in "${DEVICES[@]}"; do
        device_parse "$entry"

        if [[ "$DEVICE_ROLE" == "critical" ]] && device_is_reachable "$DEVICE_HOST"; then
            device_shutdown_graceful "$DEVICE_NAME" "$DEVICE_HOST"
        fi
    done
}

wake_devices_if_allowed() {
    for entry in "${DEVICES[@]}"; do
        device_parse "$entry"

        [[ "$DEVICE_AUTOSTART" != "yes" ]] && continue
        device_wake "$DEVICE_NAME" "$DEVICE_MAC"
    done
}

# --- Main loop -----------------------------------------------
while true; do
    power_status="$(state_get power_status || echo unknown)"

    case "$power_status" in
        on_battery)
            since="$(state_get on_battery_since || echo 0)"
            elapsed=$(( $(state_timestamp) - since ))

            if (( elapsed > BATTERY_GRACE_PERIOD )); then
                log_warn "Battery grace period exceeded (${elapsed}s)"
                shutdown_devices_if_needed
            fi
            ;;
        online)
            restored="$(state_get power_restored_at || echo 0)"
            stable=$(( $(state_timestamp) - restored ))

            if (( stable > POWER_STABLE_TIME )); then
                log_info "Power stable for ${stable}s, waking devices"
                wake_devices_if_allowed
                state_unset "power_restored_at"
            fi
            ;;
        *)
            log_debug "Power state unknown or not yet initialized"
            ;;
    esac

    sleep "$CHECK_INTERVAL"
done

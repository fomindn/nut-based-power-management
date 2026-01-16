#!/usr/bin/env bash
#
# power-supervisor.sh
#
# Main UPS power supervisor FSM.
#

set -euo pipefail
IFS=$'\n\t'

LOGGER_TAG="power-supervisor"

source /usr/local/powerctl/common/lib/log.sh
source /usr/local/powerctl/bin/ups-lib.sh
source /usr/local/powerctl/bin/device-lib.sh

STATE_FILE="/run/powerctl/state"
CHECK_INTERVAL=10

# ------------------------------------------------------------
# Configuration (loaded from conf/)
# ------------------------------------------------------------

source /usr/local/powerctl/conf/power.conf
source /usr/local/powerctl/conf/device.conf
source /usr/local/powerctl/conf/schedule.conf

set_state() {
    echo "$1" >"$STATE_FILE"
    log_info "FSM state changed to: $1"
}

get_state() {
    [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo "INIT"
}

# ------------------------------------------------------------
# FSM handlers
# ------------------------------------------------------------

handle_on_line() {
    if ups_on_battery; then
        log_warn "Power lost, switching to battery"
        set_state "ON_BATTERY"
    fi
}

handle_on_battery() {
    if ups_on_line; then
        log_info "Power restored"
        set_state "WAIT_RESTORE"
        return
    fi

    if ups_low_battery; then
        log_error "Low battery, forcing shutdown"
        set_state "SHUTTING_DOWN"
        return
    fi

    log_info "On battery, waiting before shutdown"
    sleep "$BATTERY_GRACE_PERIOD"
    set_state "SHUTTING_DOWN"
}

handle_shutting_down() {
    for device in "${DEVICES[@]}"; do
        device_shutdown_graceful "${device[name]}" "${device[host]}"
    done

    sleep "$FORCE_TIMEOUT"

    for device in "${DEVICES[@]}"; do
        device_shutdown_forced "${device[name]}" "${device[host]}"
    done

    log_warn "All devices shutdown sequence completed"
}

handle_wait_restore() {
    sleep "$POWER_STABLE_TIME"

    if ups_on_line && [[ "$(ups_battery_charge)" -ge "$MIN_START_BATTERY" ]]; then
        log_info "Power stable, waking devices"
        for device in "${DEVICES[@]}"; do
            device_wake "${device[name]}" "${device[mac]}"
        done
        set_state "ON_LINE"
    fi
}

# ------------------------------------------------------------
# Main loop
# ------------------------------------------------------------

main() {
    log_info "Power supervisor started"

    while true; do
        case "$(get_state)" in
            INIT|ON_LINE)       handle_on_line ;;
            ON_BATTERY)        handle_on_battery ;;
            SHUTTING_DOWN)     handle_shutting_down ;;
            WAIT_RESTORE)      handle_wait_restore ;;
            *) log_error "Unknown FSM state" ;;
        esac
        sleep "$CHECK_INTERVAL"
    done
}

main

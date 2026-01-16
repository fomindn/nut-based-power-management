#!/usr/bin/env bash
#
# power-supervisor.sh
# Main UPS power supervisor daemon
#
# This supervisor is a long-running FSM that reacts to state flags
# written by ups-event-writer.sh. It avoids deep nesting and keeps
# the shutdown and auto-wake logic deterministic and safe.
#

set -euo pipefail
IFS=$'\n\t'

LOGGER_TAG="power-supervisor"

# --- Imports --------------------------------------------------
source /usr/local/powerctl/common/lib/log.sh
source /usr/local/powerctl/bin/state-lib.sh
source /usr/local/powerctl/bin/device-lib.sh
source /usr/local/powerctl/bin/time-lib.sh
source /usr/local/powerctl/bin/ups-lib.sh

# --- Configs --------------------------------------------------
source /usr/local/powerctl/conf/power.conf
source /usr/local/powerctl/conf/device.conf
source /usr/local/powerctl/conf/schedule.conf

# Safe defaults for optional settings
POWER_STABLE_TIME_LOW="${POWER_STABLE_TIME_LOW:-120}"
POWER_STABLE_TIME_HIGH="${POWER_STABLE_TIME_HIGH:-60}"

# --- Lock -----------------------------------------------------
LOCK_FILE="/run/powerctl/power-supervisor.lock"
exec 9>"$LOCK_FILE" || exit 1
flock -n 9 || {
    log_error "Another instance is already running"
    exit 0
}

log_info "Power Supervisor started"

# --- Helpers --------------------------------------------------

# Validate timestamp is a non-zero integer
is_valid_ts() {
    local ts="$1"
    [[ -n "$ts" ]] && [[ "$ts" =~ ^[0-9]+$ ]] && [[ "$ts" != "0" ]]
}

# Read a timestamp from state, return empty if invalid
get_state_ts() {
    local key="$1"
    local ts

    ts="$(state_get "$key" || true)"
    if is_valid_ts "$ts"; then
        echo "$ts"
    else
        echo ""
    fi
}

# Ensure timestamp exists in state, otherwise set to now
ensure_state_ts() {
    local key="$1"
    local ts

    ts="$(get_state_ts "$key")"
    if [[ -z "$ts" ]]; then
        ts="$(state_timestamp)"
        state_set "$key" "$ts"
    fi

    echo "$ts"
}

# Read battery charge safely
get_battery_charge() {
    local charge

    charge="$(ups_battery_charge)"
    if [[ -n "$charge" ]] && [[ "$charge" =~ ^[0-9]+$ ]]; then
        echo "$charge"
    else
        echo ""
    fi
}

# Determine stability wait time based on battery charge
get_stable_time() {
    local charge

    charge="$(get_battery_charge)"
    if [[ -z "$charge" ]]; then
        log_warn "Battery charge unavailable; using conservative stability time"
        echo "$POWER_STABLE_TIME_LOW"
        return
    fi

    if (( charge < MIN_START_BATTERY )); then
        echo "$POWER_STABLE_TIME_LOW"
    else
        echo "$POWER_STABLE_TIME_HIGH"
    fi
}

# Count reachable devices
count_active_devices() {
    local count=0
    local entry

    for entry in "${DEVICES[@]}"; do
        device_parse "$entry"
        if device_is_reachable "$DEVICE_HOST"; then
            ((count++))
        fi
    done

    echo "$count"
}

# Collect active critical devices (name|host)
collect_active_critical_devices() {
    ACTIVE_DEVICES=()
    local entry

    for entry in "${DEVICES[@]}"; do
        device_parse "$entry"
        if [[ "$DEVICE_ROLE" == "critical" ]] && device_is_reachable "$DEVICE_HOST"; then
            ACTIVE_DEVICES+=("${DEVICE_NAME}|${DEVICE_HOST}")
        fi
    done
}

# Send graceful shutdown; build PENDING_DEVICES list
send_graceful_shutdown() {
    PENDING_DEVICES=()
    local device_info name host old_ifs

    for device_info in "${ACTIVE_DEVICES[@]}"; do
        old_ifs="$IFS"
        IFS='|' read -r name host <<< "$device_info"
        IFS="$old_ifs"

        log_info "Sending graceful shutdown to ${name} (${host})"
        if device_shutdown_graceful "$name" "$host"; then
            PENDING_DEVICES+=("${name}|${host}")
        else
            log_warn "Graceful shutdown failed for ${name}; forcing immediately"
            device_shutdown_forced "$name" "$host"
        fi
    done
}

# Wait for devices to shutdown, then force remaining
wait_and_force_shutdown() {
    local timeout="$1"
    local start_ts elapsed
    local pending new_pending
    local device_info name host old_ifs

    if (( ${#PENDING_DEVICES[@]} == 0 )); then
        return 0
    fi

    start_ts="$(state_timestamp)"
    pending=("${PENDING_DEVICES[@]}")

    while true; do
        new_pending=()

        for device_info in "${pending[@]}"; do
            old_ifs="$IFS"
            IFS='|' read -r name host <<< "$device_info"
            IFS="$old_ifs"

            if device_is_reachable "$host"; then
                new_pending+=("${name}|${host}")
            else
                log_info "Device ${name} is now down"
            fi
        done

        pending=("${new_pending[@]}")

        if (( ${#pending[@]} == 0 )); then
            return 0
        fi

        elapsed=$(( $(state_timestamp) - start_ts ))
        if (( elapsed >= timeout )); then
            break
        fi

        sleep "$CHECK_INTERVAL"
    done

    for device_info in "${pending[@]}"; do
        old_ifs="$IFS"
        IFS='|' read -r name host <<< "$device_info"
        IFS="$old_ifs"

        log_warn "Forcing shutdown for ${name} after timeout"
        device_shutdown_forced "$name" "$host"
    done
}

# Mark shutdown started to avoid duplicates and keep audit context
mark_shutdown_started() {
    local ts
    ts="$(state_timestamp)"
    state_set "shutdown_started" "$ts"
    state_set "shutdown_started_at" "$ts"
}

is_shutdown_started() {
    state_exists "shutdown_started"
}

# Shutdown Raspberry Pi via NUT
shutdown_raspberry_pi() {
    log_warn "Shutting down Raspberry Pi via NUT (upsmon -c fsd)"
    if /usr/sbin/upsmon -c fsd 2>/dev/null; then
        log_info "Raspberry Pi shutdown initiated"
    else
        log_error "Failed to initiate shutdown via NUT; trying system shutdown"
        shutdown -h now || true
    fi
}

# Execute full shutdown sequence
shutdown_sequence() {
    local reason="$1"

    if is_shutdown_started; then
        log_warn "Shutdown already started; skipping duplicate request (${reason})"
        return
    fi

    log_warn "Shutdown sequence started: ${reason}"
    mark_shutdown_started
    state_set "shutdown_reason" "$reason"

    collect_active_critical_devices
    log_info "Active critical devices: ${#ACTIVE_DEVICES[@]}"

    if (( ${#ACTIVE_DEVICES[@]} > 0 )); then
        send_graceful_shutdown
        wait_and_force_shutdown "$FORCE_SHUTDOWN_TIMEOUT"
    else
        log_info "No active critical devices detected"
    fi

    shutdown_raspberry_pi
}

# --- State Handlers ------------------------------------------

handle_low_battery() {
    if [[ "$(state_get "battery_status" || true)" == "low" ]]; then
        shutdown_sequence "low_battery"
    fi
}

handle_on_battery() {
    local since elapsed active_count

    if is_shutdown_started; then
        return
    fi

    # Clear any stale online marker
    state_unset "power_restored_at"

    since="$(ensure_state_ts "on_battery_since")"
    elapsed=$(( $(state_timestamp) - since ))

    if is_night_time; then
        active_count="$(count_active_devices)"
        if (( active_count == 0 )); then
            shutdown_sequence "night_no_active_devices"
            return
        fi
    fi

    if (( elapsed >= BATTERY_GRACE_PERIOD )); then
        shutdown_sequence "battery_grace_exceeded"
    else
        log_debug "On battery for ${elapsed}s (grace: ${BATTERY_GRACE_PERIOD}s)"
    fi
}

handle_power_restored() {
    local restored stable stable_time current_time charge entry

    if is_shutdown_started; then
        return
    fi

    # Clear any stale on_battery marker
    state_unset "on_battery_since"
    state_unset "battery_status"

    restored="$(get_state_ts "power_restored_at")"
    if [[ -z "$restored" ]]; then
        return
    fi

    stable_time="$(get_stable_time)"
    stable=$(( $(state_timestamp) - restored ))
    if (( stable < stable_time )); then
        log_debug "Power restored ${stable}s ago; waiting ${stable_time}s"
        return
    fi

    # Night time: never auto-wake
    current_time=$(date +%H:%M)
    if ! is_day_time; then
        log_info "Current time (${current_time}) is outside day window (${DAY_START}-${DAY_END}); skipping auto-wake"
        return
    fi

    charge="$(get_battery_charge)"
    if [[ -z "$charge" ]] || (( charge < MIN_START_BATTERY )); then
        log_warn "Battery charge (${charge:-unknown}%) below MIN_START_BATTERY (${MIN_START_BATTERY}%)"
        return
    fi

    log_info "Auto-wake conditions met: time=${current_time}, charge=${charge}%, stable=${stable}s"

    for entry in "${DEVICES[@]}"; do
        device_parse "$entry"
        if [[ "$DEVICE_AUTOSTART" != "yes" ]]; then
            continue
        fi

        if device_is_reachable "$DEVICE_HOST"; then
            log_info "Device ${DEVICE_NAME} already up; skipping WOL"
            continue
        fi

        device_wake "$DEVICE_NAME" "$DEVICE_MAC"
    done

    # Clear restoration markers only after auto-wake attempt
    state_unset "power_restored_at"
}

# --- Main loop -----------------------------------------------
while true; do
    power_status="$(state_get power_status || echo unknown)"

    # Highest priority: low battery
    handle_low_battery

    case "$power_status" in
        on_battery)
            handle_on_battery
            ;;
        online)
            handle_power_restored
            ;;
        *)
            log_debug "Power state: ${power_status} (idle)"
            ;;
    esac

    sleep "$CHECK_INTERVAL"
done

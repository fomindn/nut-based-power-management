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
ONLINE_STABLE_MIN="${ONLINE_STABLE_MIN:-30}"
ONBATT_STABLE_MIN="${ONBATT_STABLE_MIN:-10}"
AUTO_WAKE_MAX_ATTEMPTS="${AUTO_WAKE_MAX_ATTEMPTS:-3}"
SHUTDOWN_COOLDOWN="${SHUTDOWN_COOLDOWN:-30}"
AUTO_WAKE_COOLDOWN="${AUTO_WAKE_COOLDOWN:-30}"
POWER_RESTORED_TTL="${POWER_RESTORED_TTL:-0}"
STATUS_LOG_INTERVAL="${STATUS_LOG_INTERVAL:-0}"

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

# Sanitize a string to a safe state key suffix
sanitize_key() {
    local raw="$1"
    echo "${raw//[^a-zA-Z0-9_]/_}"
}

# Build a per-device state key
device_state_key() {
    local device_name="$1"
    local suffix="$2"
    local safe_name

    safe_name="$(sanitize_key "$device_name")"
    echo "${suffix}_${safe_name}"
}

# Read an integer from state, return 0 if invalid
get_state_int() {
    local key="$1"
    local value

    value="$(state_get "$key" || true)"
    if [[ -n "$value" ]] && [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    else
        echo "0"
    fi
}

# Clear stale power_restored_at if TTL is configured
maybe_clear_stale_power_restored() {
    local restored age

    if (( POWER_RESTORED_TTL <= 0 )); then
        return
    fi

    restored="$(get_state_ts "power_restored_at")"
    if [[ -z "$restored" ]]; then
        return
    fi

    age=$(( $(state_timestamp) - restored ))
    if (( age >= POWER_RESTORED_TTL )); then
        log_warn "power_restored_at is stale (${age}s); clearing"
        state_unset "power_restored_at"
        state_unset "auto_wake_for_restored_at"
    fi
}

# Periodic status log to help diagnostics without excessive noise
log_status_summary() {
    local last_ts now_ts elapsed power_status charge active_count

    if (( STATUS_LOG_INTERVAL <= 0 )); then
        return
    fi

    last_ts="$(get_state_ts "status_last_log")"
    now_ts="$(state_timestamp)"
    elapsed=$(( now_ts - ${last_ts:-0} ))
    if (( elapsed < STATUS_LOG_INTERVAL )); then
        return
    fi

    power_status="$(state_get power_status || echo unknown)"
    charge="$(get_battery_charge)"
    active_count="$(count_active_devices)"

    log_info "Status: power=${power_status}, battery=${charge:-unknown}%, active=${active_count}"
    state_set "status_last_log" "$now_ts"
}

# Determine per-device auto-wake limit
get_device_auto_wake_limit() {
    local device_limit="$1"

    if [[ -n "$device_limit" ]] && [[ "$device_limit" =~ ^[0-9]+$ ]] && (( device_limit > 0 )); then
        echo "$device_limit"
    else
        echo "$AUTO_WAKE_MAX_ATTEMPTS"
    fi
}

# Initialize auto-wake session counters for a new ONLINE event
init_auto_wake_session() {
    local restored_ts="$1"
    local current_session
    local entry attempts_key exhausted_key

    current_session="$(state_get "auto_wake_for_restored_at" || true)"
    if [[ "$current_session" != "$restored_ts" ]]; then
        state_set "auto_wake_for_restored_at" "$restored_ts"
        for entry in "${DEVICES[@]}"; do
            device_parse "$entry"
            if [[ "$DEVICE_AUTOSTART" != "yes" ]]; then
                continue
            fi

            attempts_key="$(device_state_key "$DEVICE_NAME" "auto_wake_attempts")"
            exhausted_key="$(device_state_key "$DEVICE_NAME" "auto_wake_exhausted")"
            state_set "$attempts_key" "0"
            state_unset "$exhausted_key"
        done
    fi
}

# Reconcile conflicting power state markers and return effective state
# This prevents flapping from leaving both on_battery_since and power_restored_at set.
resolve_power_state() {
    local onbatt_ts online_ts

    onbatt_ts="$(get_state_ts "on_battery_since")"
    online_ts="$(get_state_ts "power_restored_at")"

    if [[ -n "$onbatt_ts" && -n "$online_ts" ]]; then
        if (( onbatt_ts > online_ts )); then
            log_warn "State conflict detected; keeping on_battery and clearing power_restored_at"
            state_unset "power_restored_at"
            echo "on_battery"
            return
        fi

        log_warn "State conflict detected; keeping online and clearing on_battery_since"
        state_unset "on_battery_since"
        echo "online"
        return
    fi

    if [[ -n "$onbatt_ts" ]]; then
        echo "on_battery"
        return
    fi

    if [[ -n "$online_ts" ]]; then
        echo "online"
        return
    fi

    echo ""
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

# Count active devices (ping + ports if configured)
count_active_devices() {
    local count=0
    local entry

    for entry in "${DEVICES[@]}"; do
        device_parse "$entry"
        if device_is_active "$DEVICE_HOST" "$DEVICE_PORTS"; then
            ((count++))
        fi
    done

    echo "$count"
}

# Collect active critical devices (name|host|ports)
collect_active_critical_devices() {
    ACTIVE_DEVICES=()
    local entry

    for entry in "${DEVICES[@]}"; do
        device_parse "$entry"
        if [[ "$DEVICE_ROLE" == "critical" ]] && device_is_active "$DEVICE_HOST" "$DEVICE_PORTS"; then
            ACTIVE_DEVICES+=("${DEVICE_NAME}|${DEVICE_HOST}|${DEVICE_PORTS}")
        fi
    done
}

# Send graceful shutdown; build PENDING_DEVICES list
send_graceful_shutdown() {
    PENDING_DEVICES=()
    local device_info name host ports old_ifs

    for device_info in "${ACTIVE_DEVICES[@]}"; do
        old_ifs="$IFS"
        IFS='|' read -r name host ports <<< "$device_info"
        IFS="$old_ifs"

        log_info "Sending graceful shutdown to ${name} (${host})"
        if device_shutdown_graceful "$name" "$host"; then
            PENDING_DEVICES+=("${name}|${host}|${ports}")
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
    local device_info name host ports old_ifs

    if (( ${#PENDING_DEVICES[@]} == 0 )); then
        return 0
    fi

    start_ts="$(state_timestamp)"
    pending=("${PENDING_DEVICES[@]}")

    while true; do
        new_pending=()

        for device_info in "${pending[@]}"; do
            old_ifs="$IFS"
            IFS='|' read -r name host ports <<< "$device_info"
            IFS="$old_ifs"

            if device_is_active "$host" "$ports"; then
                new_pending+=("${name}|${host}|${ports}")
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
        IFS='|' read -r name host ports <<< "$device_info"
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
    local last_request_ts now_ts elapsed

    if is_shutdown_started; then
        log_warn "Shutdown already started; skipping duplicate request (${reason})"
        return
    fi

    last_request_ts="$(get_state_ts "shutdown_last_request")"
    if [[ -n "$last_request_ts" ]]; then
        now_ts="$(state_timestamp)"
        elapsed=$(( now_ts - last_request_ts ))
        if (( elapsed < SHUTDOWN_COOLDOWN )); then
            log_warn "Shutdown request suppressed by cooldown (${elapsed}s < ${SHUTDOWN_COOLDOWN}s)"
            return
        fi
    fi

    log_warn "Shutdown sequence started: ${reason}"
    state_set "shutdown_last_request" "$(state_timestamp)"
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

    since="$(ensure_state_ts "on_battery_since")"
    elapsed=$(( $(state_timestamp) - since ))

    if (( elapsed < ONBATT_STABLE_MIN )); then
        log_debug "On battery for ${elapsed}s (debounce: ${ONBATT_STABLE_MIN}s)"
        return
    fi

    # Clear any stale online marker after debounce
    state_unset "power_restored_at"

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
    local attempts attempts_key exhausted_key limit
    local wol_attempted_any wol_success autostart_total autostart_active autostart_exhausted
    local last_attempt now_ts elapsed cooldown_key

    if is_shutdown_started; then
        return
    fi

    restored="$(get_state_ts "power_restored_at")"
    if [[ -z "$restored" ]]; then
        return
    fi

    stable=$(( $(state_timestamp) - restored ))
    if (( stable < ONLINE_STABLE_MIN )); then
        log_debug "Power restored ${stable}s ago (debounce: ${ONLINE_STABLE_MIN}s)"
        return
    fi

    # Clear any stale on_battery marker after debounce
    state_unset "on_battery_since"
    state_unset "battery_status"

    stable_time="$(get_stable_time)"
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

    init_auto_wake_session "$restored"

    log_info "Auto-wake conditions met: time=${current_time}, charge=${charge}%, stable=${stable}s"

    wol_attempted_any=0
    wol_success=0
    autostart_total=0
    autostart_active=0
    autostart_exhausted=0

    for entry in "${DEVICES[@]}"; do
        device_parse "$entry"
        if [[ "$DEVICE_AUTOSTART" != "yes" ]]; then
            continue
        fi

        ((autostart_total++))

        if device_is_active "$DEVICE_HOST" "$DEVICE_PORTS"; then
            ((autostart_active++))
            log_info "Device ${DEVICE_NAME} already up; skipping WOL"
            continue
        fi

        attempts_key="$(device_state_key "$DEVICE_NAME" "auto_wake_attempts")"
        exhausted_key="$(device_state_key "$DEVICE_NAME" "auto_wake_exhausted")"
        cooldown_key="$(device_state_key "$DEVICE_NAME" "auto_wake_last_attempt")"
        limit="$(get_device_auto_wake_limit "$DEVICE_AUTO_WAKE_MAX")"
        attempts="$(get_state_int "$attempts_key")"

        if (( attempts >= limit )); then
            if [[ -z "$(state_get "$exhausted_key" || true)" ]]; then
                log_warn "Auto-wake exhausted for ${DEVICE_NAME} (${attempts}/${limit}); skipping"
                state_set "$exhausted_key" "1"
            fi
            ((autostart_exhausted++))
            continue
        fi

        last_attempt="$(get_state_ts "$cooldown_key")"
        if [[ -n "$last_attempt" ]]; then
            now_ts="$(state_timestamp)"
            elapsed=$(( now_ts - last_attempt ))
            if (( elapsed < AUTO_WAKE_COOLDOWN )); then
                log_info "Auto-wake cooldown for ${DEVICE_NAME} (${elapsed}s < ${AUTO_WAKE_COOLDOWN}s); skipping"
                continue
            fi
        fi

        wol_attempted_any=1
        attempts=$(( attempts + 1 ))
        state_set "$attempts_key" "$attempts"
        state_set "$cooldown_key" "$(state_timestamp)"

        if device_wake "$DEVICE_NAME" "$DEVICE_MAC"; then
            wol_success=1
        fi
    done

    if (( autostart_total == 0 )); then
        log_info "No auto-start devices configured; clearing restoration marker"
        state_unset "power_restored_at"
        return
    fi

    if (( autostart_active == autostart_total )); then
        log_info "All auto-start devices already active; clearing restoration marker"
        state_unset "power_restored_at"
        return
    fi

    if (( (autostart_active + autostart_exhausted) == autostart_total )); then
        log_warn "Auto-wake exhausted for remaining devices; clearing restoration marker"
        state_unset "power_restored_at"
        return
    fi

    if (( wol_attempted_any == 0 )); then
        log_info "No auto-wake attempts executed; keeping restoration marker"
        return
    fi

    if (( wol_success == 1 )); then
        log_info "Auto-wake command succeeded; waiting for devices to become active"
    fi
}

# --- Main loop -----------------------------------------------
while true; do
    power_status="$(state_get power_status || echo unknown)"
    resolved_status="$(resolve_power_state)"
    if [[ -n "$resolved_status" ]]; then
        power_status="$resolved_status"
    fi

    # Highest priority: low battery
    handle_low_battery

    maybe_clear_stale_power_restored
    log_status_summary

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

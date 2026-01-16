#!/usr/bin/env bash
#
# power-supervisor.sh
#
# Long-running power orchestration supervisor for NUT-based environments.
# This service is responsible for:
#  - reacting to UPS state changes (ONLINE / ONBATT / LOWBATT)
#  - coordinating graceful and emergency shutdown of network devices
#  - handling power restoration logic (delayed WOL, battery checks, night mode)
#
# IMPORTANT:
#  - This script is STATE-driven, not EVENT-driven.
#  - It must be the ONLY component making power-related decisions.
#

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------
# 1. Load environment and shared libraries
# ------------------------------------------------------------

ENV_FILE="/etc/powerctl/powerctl.env"

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/etc/powerctl/powerctl.env
    source "$ENV_FILE"
else
    echo "FATAL: Environment file $ENV_FILE not found"
    exit 1
fi

# Default paths (can be overridden via env)
: "${POWERCTL_ROOT:=/usr/local/powerctl}"
: "${POWERCTL_STATE_DIR:=/run/powerctl/state}"
: "${POWERCTL_LOCK_DIR:=/run/powerctl/lock}"
: "${POWERCTL_LOOP_INTERVAL:=10}"

# Logging setup
export POWERCTL_LOG_TAG="${POWERCTL_LOG_TAG:-power-supervisor}"

# Load shared logging helpers
# shellcheck source=common/lib/log.sh
source "$POWERCTL_ROOT/../common/lib/log.sh"

# Load internal libraries
# shellcheck source=ups-lib.sh
source "$POWERCTL_ROOT/bin/ups-lib.sh"
# shellcheck source=device-lib.sh
source "$POWERCTL_ROOT/bin/device-lib.sh"
# shellcheck source=time-lib.sh
source "$POWERCTL_ROOT/bin/time-lib.sh"
# shellcheck source=wol-lib.sh
source "$POWERCTL_ROOT/bin/wol-lib.sh"
# shellcheck source=ssh-lib.sh
source "$POWERCTL_ROOT/bin/ssh-lib.sh"

# ------------------------------------------------------------
# 2. Sanity checks
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    log_fatal "power-supervisor must run as root"
fi

mkdir -p "$POWERCTL_STATE_DIR" "$POWERCTL_LOCK_DIR"

# ------------------------------------------------------------
# 3. Acquire singleton lock
# ------------------------------------------------------------
#
# Ensures that only ONE instance of supervisor is running.
# This prevents race conditions and duplicated actions.
#

LOCK_FILE="$POWERCTL_LOCK_DIR/supervisor.lock"
exec 200>"$LOCK_FILE"

if ! flock -n 200; then
    log_warn "Another instance of power-supervisor is already running. Exiting."
    exit 0
fi

log_info "Power supervisor started"

# ------------------------------------------------------------
# 4. Helper functions (high-level FSM actions)
# ------------------------------------------------------------

handle_online_state() {
    # Called when UPS is ONLINE (utility power present)
    #
    # IMPORTANT:
    # - ONLINE does NOT mean "turn everything on immediately"
    # - Decisions are made based on:
    #     * battery charge
    #     * time of day
    #     * actual device state
    #

    log_debug "Handling ONLINE state"

    # Placeholder:
    #  - check stability timers
    #  - evaluate WOL conditions
    :
}

handle_on_battery_state() {
    # Called when UPS is running on battery (ONBATT)
    #
    # Responsibilities:
    #  - wait grace period (day/night dependent)
    #  - monitor device shutdown progress
    #  - prepare for possible escalation
    #

    log_debug "Handling ONBATT state"
    :
}

handle_low_battery_state() {
    # Called when UPS battery is critically low (LOWBATT)
    #
    # This path has the HIGHEST priority.
    # All graceful logic is bypassed.
    #

    log_warn "LOWBATT detected — initiating emergency shutdown sequence"
    :
}

# ------------------------------------------------------------
# 5. Main supervisor loop
# ------------------------------------------------------------

while true; do
    # --------------------------------------------------------
    # 5.1 Read current UPS state
    # --------------------------------------------------------

    UPS_STATE="$(get_ups_state || echo UNKNOWN)"
    BATTERY_CHARGE="$(get_battery_charge || echo 0)"

    # --------------------------------------------------------
    # 5.2 Determine time context
    # --------------------------------------------------------

    if is_night_time; then
        TIME_CONTEXT="NIGHT"
    else
        TIME_CONTEXT="DAY"
    fi

    log_debug "UPS_STATE=$UPS_STATE BATTERY=${BATTERY_CHARGE}% TIME=$TIME_CONTEXT"

    # --------------------------------------------------------
    # 5.3 Update device states
    # --------------------------------------------------------
    #
    # Device state is determined by:
    #  - network reachability
    #  - service availability
    #
    # Device-lib is responsible for maintaining per-device state files.
    #

    update_all_device_states

    # --------------------------------------------------------
    # 5.4 FSM decision logic
    # --------------------------------------------------------

    case "$UPS_STATE" in
        ONLINE)
            handle_online_state
            ;;
        ONBATT)
            handle_on_battery_state
            ;;
        LOWBATT)
            handle_low_battery_state
            ;;
        *)
            log_warn "Unknown UPS state: $UPS_STATE"
            ;;
    esac

    # --------------------------------------------------------
    # 5.5 Loop sleep
    # --------------------------------------------------------

    sleep "$POWERCTL_LOOP_INTERVAL"
done

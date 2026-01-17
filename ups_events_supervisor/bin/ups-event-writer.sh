#!/usr/bin/env bash
#
# ups-event-writer.sh
# Called by NUT upssched or NOTIFYCMD
#
# This script MUST be extremely simple and fast.
# It only writes power state markers for standard NUT events.
#

set -euo pipefail
IFS=$'\n\t'

source /usr/local/powerctl/bin/state-lib.sh
source /usr/local/powerctl/common/lib/log.sh

EVENT="${1:-}"

# Only standard NUT event names are accepted:
# onbatt, online, lowbatt, commbad, commfault, commok (lowercase from upssched)
case "$EVENT" in
    onbatt)
        log_warn "UPS event: ON BATTERY"
        state_set "power_status" "on_battery"
        state_set "on_battery_since" "$(state_timestamp)"
        ;;
    online)
        log_info "UPS event: POWER RESTORED"
        state_set "power_status" "online"
        state_set "power_restored_at" "$(state_timestamp)"
        ;;
    lowbatt)
        log_error "UPS event: LOW BATTERY"
        state_set "battery_status" "low"
        ;;
    commbad|commfault)
        log_error "UPS event: COMMUNICATION LOST (${EVENT})"
        state_set "comm_status" "bad"
        if [[ -z "$(state_get "comm_bad_since" || true)" ]]; then
            state_set "comm_bad_since" "$(state_timestamp)"
        fi
        ;;
    commok)
        log_info "UPS event: COMMUNICATION OK"
        state_set "comm_status" "ok"
        state_unset "comm_bad_since"
        state_unset "comm_last_log"
        state_unset "comm_last_wall"
        ;;
    *)
        log_warn "UPS event: UNKNOWN (${EVENT})"
        ;;
esac

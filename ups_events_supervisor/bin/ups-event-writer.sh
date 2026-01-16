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
# onbatt, online, lowbatt (lowercase from upssched)
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
    *)
        log_warn "UPS event: UNKNOWN (${EVENT})"
        ;;
esac

#!/usr/bin/env bash
#
# ups_event.sh
# NUT server event handler
#
# This script logs UPS events and, if the supervisor is installed,
# forwards the event to ups-event-writer.sh to update state files.
#

set -euo pipefail
IFS=$'\n\t'

LOG_TAG="nut-server-event"
SUPERVISOR_EVENT_WRITER="/usr/local/powerctl/bin/ups-event-writer.sh"

log_info() { logger -t "$LOG_TAG" -p user.info -- "$*"; }
log_warn() { logger -t "$LOG_TAG" -p user.warn -- "$*"; }
log_error() { logger -t "$LOG_TAG" -p user.err -- "$*"; }

event="${1:-}"

case "$event" in
    onbatt)
        log_warn "UPS event: ON BATTERY"
        ;;
    online)
        log_info "UPS event: ONLINE"
        ;;
    lowbatt)
        log_error "UPS event: LOW BATTERY"
        ;;
    commbad|commfault)
        log_error "UPS event: COMMUNICATION LOST (${event})"
        ;;
    commok)
        log_info "UPS event: COMMUNICATION OK"
        ;;
    shutdown)
        log_warn "UPS event: SHUTDOWN"
        ;;
    *)
        log_warn "UPS event: UNKNOWN (${event})"
        ;;
esac

if [[ -x "$SUPERVISOR_EVENT_WRITER" ]]; then
    "$SUPERVISOR_EVENT_WRITER" "$event" || true
fi

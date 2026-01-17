#!/usr/bin/env bash
#
# ups_event.sh
# NUT server event handler
#
# This script stays NUT-native and always works even without the supervisor.
# It logs UPS events and, if the supervisor is installed, forwards the event
# to ups-event-writer.sh to update state files.
#

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"
LOG_TAG="nut-server-event"
SUPERVISOR_EVENT_WRITER="/usr/local/powerctl/bin/ups-event-writer.sh"

# Log helper that mirrors the style used in the legacy scripts.
log() {
    local level="$1"
    local message="$2"
    local current_time

    current_time="$(date +'%Y-%m-%d %H:%M:%S')"
    case "$level" in
        "INFO") level="info" ;;
        "NOTICE") level="notice" ;;
        "WARN") level="warning" ;;
        "ERROR") level="err" ;;
        "DEBUG") level="debug" ;;
        *) level="info" ;;
    esac

    logger -p "daemon.${level}" -i -t "$SCRIPT_NAME" -- "${current_time} ${message}"
}

event="${1:-}"
timer="${2:-}"

if [[ -z "$event" ]]; then
    log "ERROR" "Missing event argument"
    exit 0
fi

case "$event" in
    TIMEREXPIRED)
        log "WARN" "UPS event: TIMEREXPIRED (${timer:-unknown})"
        ;;
    onbatt)
        log "WARN" "UPS event: ON BATTERY"
        ;;
    online)
        log "INFO" "UPS event: ONLINE"
        ;;
    lowbatt)
        log "ERROR" "UPS event: LOW BATTERY"
        ;;
    commbad|commfault)
        log "ERROR" "UPS event: COMMUNICATION LOST (${event})"
        ;;
    commok)
        log "INFO" "UPS event: COMMUNICATION OK"
        ;;
    shutdown)
        log "WARN" "UPS event: SHUTDOWN"
        ;;
    *)
        log "WARN" "UPS event: UNKNOWN (${event})"
        ;;
esac

if [[ -x "$SUPERVISOR_EVENT_WRITER" ]]; then
    "$SUPERVISOR_EVENT_WRITER" "$event" || true
fi

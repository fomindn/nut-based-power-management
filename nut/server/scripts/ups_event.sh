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

    logger -p "daemon.${level}" -i -t "$LOG_TAG" -- "${current_time} ${message}"
}

event="${1:-}"
timer="${2:-}"

if [[ -z "$event" ]]; then
    log "ERROR" "Missing event argument"
    exit 0
fi

case "$event" in
    TIMEREXPIRED)
        log "WARN" "event=timer_expired timer=${timer:-unknown}"
        ;;
    onbatt)
        log "WARN" "event=onbatt"
        ;;
    online)
        log "INFO" "event=online"
        ;;
    lowbatt)
        log "ERROR" "event=lowbatt"
        ;;
    commbad|commfault)
        log "ERROR" "event=${event} comm=lost"
        ;;
    commok)
        log "INFO" "event=commok"
        ;;
    shutdown)
        log "WARN" "event=shutdown"
        ;;
    *)
        log "WARN" "event=unknown name=${event}"
        ;;
esac

if [[ -x "$SUPERVISOR_EVENT_WRITER" ]]; then
    "$SUPERVISOR_EVENT_WRITER" "$event" || true
fi

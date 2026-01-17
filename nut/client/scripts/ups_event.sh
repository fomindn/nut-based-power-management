#!/usr/bin/env bash
#
# ups_event.sh
# NUT client fallback event handler
#
# This script is intentionally simple and fast. It handles:
# - Basic logging for NUT events
# - Fallback shutdown timers triggered by upssched
#

set -euo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.0.0"
LOG_TAG="nut-client-event"

# Load centralized environment configuration if available
POWERCTL_ENV_FILE="${POWERCTL_ENV_FILE:-/usr/local/powerctl/common/env}"
if [[ -f "$POWERCTL_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$POWERCTL_ENV_FILE"
fi

# Grace periods (seconds) - must match values in upssched.conf
ONBATT_GRACE="${NUT_CLIENT_ONBATT_GRACE:-300}"      # Shutdown after ONBATT
COMMFAULT_GRACE="${NUT_CLIENT_COMMFAULT_GRACE:-1800}" # Shutdown after COMMFAULT

# Shutdown command (local)
SHUTDOWN_CMD="${SHUTDOWN_CMD:-/sbin/shutdown -h now}"

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
        case "$timer" in
            onbatt_shutdown)
                log "WARN" "event=timer_expired timer=onbatt_shutdown grace=${ONBATT_GRACE} action=shutdown"
                $SHUTDOWN_CMD || true
                ;;
            commfault_shutdown)
                log "ERROR" "event=timer_expired timer=commfault_shutdown grace=${COMMFAULT_GRACE} action=shutdown"
                $SHUTDOWN_CMD || true
                ;;
            *)
                log "WARN" "event=timer_expired timer=${timer}"
                ;;
        esac
        ;;
    onbatt)
        log "WARN" "event=onbatt action=start_timer"
        ;;
    online)
        log "INFO" "event=online action=cancel_timer"
        ;;
    lowbatt)
        log "ERROR" "event=lowbatt action=shutdown"
        $SHUTDOWN_CMD || true
        ;;
    commbad)
        log "WARN" "event=commbad action=start_timer"
        ;;
    commfault)
        log "ERROR" "event=commfault action=start_timer"
        ;;
    commok)
        log "INFO" "event=commok action=cancel_timer"
        ;;
    shutdown)
        log "WARN" "event=shutdown"
        ;;
    *)
        log "WARN" "event=unknown name=${event}"
        ;;
esac

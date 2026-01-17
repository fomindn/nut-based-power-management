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

log_info() { logger -t "$LOG_TAG" -p user.info -- "$*"; }
log_warn() { logger -t "$LOG_TAG" -p user.warn -- "$*"; }
log_error() { logger -t "$LOG_TAG" -p user.err -- "$*"; }

event="${1:-}"
timer="${2:-}"

case "$event" in
    TIMEREXPIRED)
        case "$timer" in
            onbatt_shutdown)
                log_warn "Timer expired: onbatt_shutdown (${ONBATT_GRACE}s); shutting down"
                $SHUTDOWN_CMD || true
                ;;
            commfault_shutdown)
                log_error "Timer expired: commfault_shutdown (${COMMFAULT_GRACE}s); shutting down"
                $SHUTDOWN_CMD || true
                ;;
            *)
                log_warn "Unknown timer expired: ${timer}"
                ;;
        esac
        ;;
    onbatt)
        log_warn "UPS event: ON BATTERY (local fallback timer started)"
        ;;
    online)
        log_info "UPS event: ONLINE (local fallback timer cancelled)"
        ;;
    lowbatt)
        log_error "UPS event: LOW BATTERY; immediate shutdown"
        $SHUTDOWN_CMD || true
        ;;
    commbad)
        log_warn "UPS event: COMMBAD (starting commfault timer)"
        ;;
    commfault)
        log_error "UPS event: COMMFAULT (starting commfault timer)"
        ;;
    commok)
        log_info "UPS event: COMMOK (commfault timer cancelled)"
        ;;
    shutdown)
        log_warn "UPS event: SHUTDOWN (system shutdown initiated)"
        ;;
    *)
        log_warn "UPS event: UNKNOWN (${event})"
        ;;
esac

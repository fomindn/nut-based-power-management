#!/usr/bin/env bash
#
# common/lib/log.sh
#
# Unified logging library.
# All logs go to journald.
#

set -euo pipefail
IFS=$'\n\t'

# Load centralized environment configuration if available
POWERCTL_ENV_FILE="${POWERCTL_ENV_FILE:-/usr/local/powerctl/common/env}"
if [[ -f "$POWERCTL_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$POWERCTL_ENV_FILE"
fi

LOGGER_TAG="${LOGGER_TAG:-powerctl}"
LOGGER_BIN="${LOGGER_BIN:-logger}"
LOG_FORMAT="${LOG_FORMAT:-kv}"

_log() {
    local level="$1"
    shift
    if [[ "$LOG_FORMAT" == "kv" ]]; then
        "$LOGGER_BIN" -t "$LOGGER_TAG" -p "user.${level}" -- "src=${LOGGER_TAG} level=${level} msg=\"$*\""
    else
        "$LOGGER_BIN" -t "$LOGGER_TAG" -p "user.${level}" -- "$*"
    fi
}

log_debug() { _log debug "$*"; }
log_info()  { _log info  "$*"; }
log_warn()  { _log warn  "$*"; }
log_error() { _log err   "$*"; }
log_crit()  { _log crit  "$*"; }

#!/usr/bin/env bash
# common/lib/log.sh
# Unified logging helpers for power orchestration stack

set -euo pipefail

# Default values (can be overridden by env)
: "${POWERCTL_LOG_TAG:=powerctl}"
: "${POWERCTL_LOG_STDERR:=0}"

_log() {
    local level="$1"
    shift
    local msg="$*"

    logger -t "$POWERCTL_LOG_TAG" "[$level] $msg"

    if [[ "$POWERCTL_LOG_STDERR" -eq 1 ]]; then
        >&2 echo "[$level] $msg"
    fi
}

log_debug() { _log DEBUG "$@"; }
log_info()  { _log INFO  "$@"; }
log_warn()  { _log WARN  "$@"; }
log_error() { _log ERROR "$@"; }
log_fatal() { _log FATAL "$@"; exit 1; }

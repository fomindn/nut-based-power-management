#!/usr/bin/env bash
#
# common/lib/log.sh
#
# Unified logging library.
# All logs go to journald.
#

set -euo pipefail
IFS=$'\n\t'

LOGGER_TAG="${LOGGER_TAG:-powerctl}"

_log() {
    local level="$1"
    shift
    logger -t "$LOGGER_TAG" -p "user.${level}" -- "$*"
}

log_debug() { _log debug "$*"; }
log_info()  { _log info  "$*"; }
log_warn()  { _log warn  "$*"; }
log_error() { _log err   "$*"; }

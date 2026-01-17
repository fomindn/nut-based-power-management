#!/usr/bin/env bash
#
# state-lib.sh
# Persistent state handling for UPS power events
#
# State is stored in tmpfs (/run/powerctl/state) to survive
# service restarts but not system reboots.
#

set -euo pipefail
IFS=$'\n\t'

source /usr/local/powerctl/common/lib/log.sh

STATE_DIR="${STATE_DIR:-/run/powerctl/state}"
mkdir -p "$STATE_DIR"

state_set() {
    local key="$1"
    local value="$2"

    echo "$value" > "${STATE_DIR}/${key}"
    log_debug "STATE set: ${key}=${value}"
}

state_get() {
    local key="$1"
    [[ -f "${STATE_DIR}/${key}" ]] && cat "${STATE_DIR}/${key}" || true
}

state_unset() {
    local key="$1"
    rm -f "${STATE_DIR}/${key}"
    log_debug "STATE unset: ${key}"
}

state_exists() {
    [[ -f "${STATE_DIR}/$1" ]]
}

state_timestamp() {
    date +%s
}

#!/usr/bin/env bash
#
# device-lib.sh
#
# Device state management library.
# Responsibilities:
#  - Track reachability and availability of managed devices
#  - Maintain per-device state files
#
# This library MUST NOT:
#  - decide WHEN to shutdown
#  - interact with UPS directly
#

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

: "${POWERCTL_STATE_DIR:?POWERCTL_STATE_DIR not set}"
: "${DEVICE_CONF:?DEVICE_CONF not set}"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

_device_state_file() {
    local name="$1"
    echo "$POWERCTL_STATE_DIR/device_${name}.state"
}

_ping_device() {
    local host="$1"
    ping -c1 -W1 "$host" &>/dev/null
}

# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------

update_all_device_states() {
    #
    # Reads device.conf and updates state files.
    # device.conf format:
    #   name host role
    #
    while read -r name host role; do
        [[ -z "$name" || "$name" =~ ^# ]] && continue
        update_device_state "$name" "$host" "$role"
    done <"$DEVICE_CONF"
}

update_device_state() {
    local name="$1"
    local host="$2"
    local role="$3"

    local state_file reachable

    state_file="$(_device_state_file "$name")"

    if _ping_device "$host"; then
        reachable="ONLINE"
    else
        reachable="OFFLINE"
    fi

    cat >"$state_file" <<EOF
NAME=$name
HOST=$host
ROLE=$role
STATE=$reachable
UPDATED_AT=$(date +%s)
EOF
}

get_device_state() {
    local name="$1"
    local state_file

    state_file="$(_device_state_file "$name")"
    [[ -f "$state_file" ]] || return 1

    # shellcheck disable=SC1090
    source "$state_file"
    echo "$STATE"
}

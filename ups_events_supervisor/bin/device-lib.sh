#!/usr/bin/env bash
#
# device-lib.sh
#
# Network device abstraction layer.
#

set -euo pipefail
IFS=$'\n\t'

source /usr/local/powerctl/bin/ssh-lib.sh
source /usr/local/powerctl/bin/wol-lib.sh

device_is_reachable() {
    local host="$1"
    ping -c1 -W1 "$host" >/dev/null 2>&1
}

device_shutdown_graceful() {
    local name="$1"
    local host="$2"

    log_info "Requesting graceful shutdown for ${name}"
    ssh_graceful_shutdown "$host" || return 1
}

device_shutdown_forced() {
    local name="$1"
    local host="$2"

    log_warn "Requesting FORCED shutdown for ${name}"
    ssh_forced_shutdown "$host"
}

device_wake() {
    local name="$1"
    local mac="$2"
    wol_device "$name" "$mac"
}

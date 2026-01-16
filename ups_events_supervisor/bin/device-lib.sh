#!/usr/bin/env bash
#
# device-lib.sh
# Network device abstraction layer
#

set -euo pipefail
IFS=$'\n\t'

source /usr/local/powerctl/common/lib/log.sh
source /usr/local/powerctl/bin/ssh-lib.sh
source /usr/local/powerctl/bin/wol-lib.sh

# Parse a device entry from device.conf
# Format: name|host|mac|role|auto_start
device_parse() {
    local entry="$1"
    local old_ifs="$IFS"

    IFS='|' read -r DEVICE_NAME DEVICE_HOST DEVICE_MAC DEVICE_ROLE DEVICE_AUTOSTART <<< "$entry"
    IFS="$old_ifs"
}

# Check if a device responds to ping
# Returns 0 if reachable, 1 otherwise
device_is_reachable() {
    local host="$1"
    ping -c1 -W1 "$host" >/dev/null 2>&1
}

# Request graceful shutdown over SSH
# Returns 0 if command sent, 1 otherwise
device_shutdown_graceful() {
    local name="$1"
    local host="$2"

    log_info "Requesting graceful shutdown for ${name}"
    ssh_graceful_shutdown "$host"
}

# Force shutdown over SSH (last resort)
# Returns 0 on success, 1 on failure
device_shutdown_forced() {
    local name="$1"
    local host="$2"

    log_warn "Requesting FORCED shutdown for ${name}"
    ssh_forced_shutdown "$host"
}

# Wake device via WOL
device_wake() {
    local name="$1"
    local mac="$2"

    log_info "Sending WOL packet to ${name}"
    wol_device "$mac"
}

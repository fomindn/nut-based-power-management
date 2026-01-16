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
# Format: name|host|mac|role|auto_start|ports
# ports: comma-separated TCP ports used to detect "active" services.
# Use "-" or empty to treat ping as the only activity signal.
device_parse() {
    local entry="$1"
    local old_ifs="$IFS"

    IFS='|' read -r DEVICE_NAME DEVICE_HOST DEVICE_MAC DEVICE_ROLE DEVICE_AUTOSTART DEVICE_PORTS <<< "$entry"
    IFS="$old_ifs"
}

# Check if a device responds to ping
# Returns 0 if reachable, 1 otherwise
# Check if a device responds to ping
# Returns 0 if reachable, 1 otherwise
device_is_reachable() {
    local host="$1"
    ping -c1 -W1 "$host" >/dev/null 2>&1
}

# Check if a TCP port is open using best available method
# Returns 0 if port is open, 1 otherwise
port_is_open() {
    local host="$1"
    local port="$2"

    if command -v nc >/dev/null 2>&1; then
        nc -z -w1 "$host" "$port" >/dev/null 2>&1
        return $?
    fi

    # Fallback to /dev/tcp when nc is unavailable (bash feature)
    timeout 1 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" >/dev/null 2>&1
}

# Determine if a device is "active"
# - Ping must succeed
# - If ports are specified, at least one port must be open
# Returns 0 if active, 1 otherwise
device_is_active() {
    local host="$1"
    local ports_csv="$2"
    local old_ifs ports port

    if ! device_is_reachable "$host"; then
        return 1
    fi

    if [[ -z "$ports_csv" ]] || [[ "$ports_csv" == "-" ]]; then
        return 0
    fi

    old_ifs="$IFS"
    IFS=',' read -r -a ports <<< "$ports_csv"
    IFS="$old_ifs"

    for port in "${ports[@]}"; do
        if [[ "$port" =~ ^[0-9]+$ ]] && port_is_open "$host" "$port"; then
            return 0
        fi
    done

    return 1
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

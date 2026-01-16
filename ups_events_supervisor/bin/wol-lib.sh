#!/usr/bin/env bash
#
# wol-lib.sh
#
# Wake-on-LAN utilities.
#

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------
# Dependencies check
# ------------------------------------------------------------

command -v wakeonlan >/dev/null || {
    echo "wakeonlan utility is required"
    exit 1
}

# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------

wol_device() {
    #
    # Sends WOL magic packet
    #
    local name="$1"
    local mac="$2"
    local broadcast="${3:-255.255.255.255}"

    if [[ ! "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        log_error "Invalid MAC address for ${name}: ${mac}"
        return 1
    fi

    log_info "Sending WOL packet to ${name} (${mac})"

    wakeonlan -i "$broadcast" "$mac" \
        && log_info "WOL packet sent to ${name}" \
        || log_error "WOL failed for ${name}"
}

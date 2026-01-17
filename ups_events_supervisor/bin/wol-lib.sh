#!/usr/bin/env bash
#
# wol-lib.sh
# Wake-on-LAN helper
#

set -euo pipefail
IFS=$'\n\t'

source /usr/local/powerctl/common/lib/log.sh

WOL_RETRIES="${WOL_RETRIES:-3}"
WOL_INTERVAL="${WOL_INTERVAL:-15}"
WAKEONLAN_BIN="${WAKEONLAN_BIN:-wakeonlan}"

wol_device() {
    local mac="$1"

    for ((i=1; i<=WOL_RETRIES; i++)); do
        log_info "WOL attempt ${i} for ${mac}"
        "$WAKEONLAN_BIN" "$mac" && return 0
        sleep "$WOL_INTERVAL"
    done

    log_error "WOL failed for ${mac}"
    return 1
}

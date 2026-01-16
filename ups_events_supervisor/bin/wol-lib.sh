#!/usr/bin/env bash
#
# wol-lib.sh
# Wake-on-LAN helper
#

set -euo pipefail
IFS=$'\n\t'

source /usr/local/powerctl/common/lib/log.sh

WOL_RETRIES=3
WOL_INTERVAL=15

wol_device() {
    local mac="$1"

    for ((i=1; i<=WOL_RETRIES; i++)); do
        log_info "WOL attempt ${i} for ${mac}"
        wakeonlan "$mac" && return 0
        sleep "$WOL_INTERVAL"
    done

    log_error "WOL failed for ${mac}"
    return 1
}

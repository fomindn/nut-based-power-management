#!/usr/bin/env bash
#
# time-lib.sh
# Time-related helpers
#

set -euo pipefail
IFS=$'\n\t'

source /usr/local/powerctl/common/lib/log.sh

is_night_time() {
    local now
    now=$(date +%H:%M)

    [[ "$now" < "$DAY_START" || "$now" >= "$DAY_END" ]]
}

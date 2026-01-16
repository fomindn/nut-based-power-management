#!/usr/bin/env bash
#
# time-lib.sh
# Time-related helpers
#

set -euo pipefail
IFS=$'\n\t'

source /usr/local/powerctl/common/lib/log.sh

# Convert HH:MM to minutes since midnight
_time_to_minutes() {
    local time_str="$1"
    local hours minutes
    local old_ifs="$IFS"

    IFS=':' read -r hours minutes <<< "$time_str"
    IFS="$old_ifs"

    echo $((10#$hours * 60 + 10#$minutes))
}

# Returns 0 if night, 1 if day
is_night_time() {
    local now now_minutes day_start day_end

    now=$(date +%H:%M)
    now_minutes=$(_time_to_minutes "$now")
    day_start=$(_time_to_minutes "${DAY_START:-09:00}")
    day_end=$(_time_to_minutes "${DAY_END:-23:59}")

    (( now_minutes < day_start || now_minutes >= day_end ))
}

# Returns 0 if day, 1 if night
is_day_time() {
    ! is_night_time
}

#!/usr/bin/env bash
#
# time-lib.sh
#
# Time and schedule logic for power supervisor.
# All time-based decisions MUST be centralized here.
#

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------
# Configuration (from env or power.conf)
# ------------------------------------------------------------

: "${DAY_START:=07:00}"
: "${NIGHT_START:=22:00}"
: "${TIMEZONE:=UTC}"

export TZ="$TIMEZONE"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

_time_to_minutes() {
    local t="$1"
    IFS=: read -r h m <<<"$t"
    echo $((10#$h * 60 + 10#$m))
}

_current_minutes() {
    date +%H:%M | _time_to_minutes
}

# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------

is_night_time() {
    #
    # Returns 0 if current time is considered NIGHT
    #
    local now day_start night_start

    now="$(_current_minutes)"
    day_start="$(_time_to_minutes "$DAY_START")"
    night_start="$(_time_to_minutes "$NIGHT_START")"

    if (( night_start > day_start )); then
        # Normal day (e.g. 07:00–22:00)
        (( now >= night_start || now < day_start ))
    else
        # Overnight window crosses midnight
        (( now >= night_start && now < day_start ))
    fi
}

is_day_time() {
    ! is_night_time
}

current_time_human() {
    date "+%Y-%m-%d %H:%M:%S %Z"
}

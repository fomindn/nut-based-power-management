#!/usr/bin/env bash
#
# ups-lib.sh
#
# UPS state abstraction via NUT.
#

set -euo pipefail
IFS=$'\n\t'

# Load centralized environment configuration if available
POWERCTL_ENV_FILE="${POWERCTL_ENV_FILE:-/usr/local/powerctl/common/env}"
if [[ -f "$POWERCTL_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$POWERCTL_ENV_FILE"
fi

UPS_NAME="${UPS_NAME:-ups}"
UPS_HOST="${UPS_HOST:-127.0.0.1}"
UPSC_BIN="${UPSC_BIN:-upsc}"

ups_query() {
    "$UPSC_BIN" "${UPS_NAME}@${UPS_HOST}"
}

ups_battery_charge() {
    ups_query | awk -F': ' '/battery.charge:/ {print $2}'
}

ups_on_battery() {
    ups_query | grep -q "ups.status: OB"
}

ups_on_line() {
    ups_query | grep -q "ups.status: OL"
}

ups_low_battery() {
    ups_query | grep -q "ups.status:.*LB"
}

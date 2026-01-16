#!/usr/bin/env bash
#
# ups-lib.sh
#
# UPS state abstraction via NUT.
#

set -euo pipefail
IFS=$'\n\t'

UPS_NAME="${UPS_NAME:-ups}"
UPS_HOST="${UPS_HOST:-127.0.0.1}"

ups_query() {
    upsc "${UPS_NAME}@${UPS_HOST}"
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

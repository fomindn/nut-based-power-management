#!/usr/bin/env bash
#
# ups-lib.sh
#
# Low-level UPS interaction library for NUT.
# Responsibilities:
#  - Query UPS state via upsc
#  - Normalize output for supervisor FSM
#
# This library MUST NOT:
#  - initiate shutdowns
#  - write state files
#  - make decisions
#

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------
# Configuration (from env)
# ------------------------------------------------------------

: "${NUT_UPS_NAME:?NUT_UPS_NAME is not set}"
: "${NUT_UPS_HOST:=localhost}"
: "${NUT_UPS_PORT:=3493}"

UPS_TARGET="${NUT_UPS_NAME}@${NUT_UPS_HOST}"

# ------------------------------------------------------------
# Internal helper
# ------------------------------------------------------------

_upsc_query() {
    local key="$1"

    upsc "$UPS_TARGET" "$key" 2>/dev/null || return 1
}

# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------

get_ups_state() {
    #
    # Returns normalized UPS state:
    #   ONLINE | ONBATT | LOWBATT
    #
    local status raw

    raw="$(_upsc_query ups.status)" || {
        log_error "Unable to query ups.status"
        return 1
    }

    # Example values:
    #  OL
    #  OB
    #  OB LB
    #  OL CHRG
    #
    if [[ "$raw" =~ LB ]]; then
        echo "LOWBATT"
    elif [[ "$raw" =~ OB ]]; then
        echo "ONBATT"
    elif [[ "$raw" =~ OL ]]; then
        echo "ONLINE"
    else
        log_warn "Unknown ups.status value: $raw"
        echo "UNKNOWN"
    fi
}

get_battery_charge() {
    #
    # Returns battery charge percentage (integer)
    #
    local charge

    charge="$(_upsc_query battery.charge)" || {
        log_error "Unable to query battery.charge"
        return 1
    }

    # Defensive: ensure integer output
    if [[ "$charge" =~ ^[0-9]+$ ]]; then
        echo "$charge"
    else
        log_warn "Invalid battery.charge value: $charge"
        echo 0
    fi
}

#!/usr/bin/env bash
#
# ssh-lib.sh
#
# Remote shutdown control via SSH.
# Provides escalation: graceful → forced.
#

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

: "${SSH_USER:=powerctl}"
: "${SSH_OPTS:=-o BatchMode=yes -o ConnectTimeout=5}"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

_ssh() {
    local host="$1"
    shift
    ssh $SSH_OPTS "${SSH_USER}@${host}" "$@"
}

# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------

ssh_graceful_shutdown() {
    #
    # Attempts clean OS shutdown via systemd
    #
    local host="$1"

    log_info "Attempting graceful shutdown on ${host}"

    _ssh "$host" "systemctl poweroff" \
        && log_info "Graceful shutdown command sent to ${host}" \
        || {
            log_warn "Graceful shutdown failed on ${host}"
            return 1
        }
}

ssh_forced_shutdown() {
    #
    # Forced shutdown (last resort)
    #
    local host="$1"

    log_warn "Attempting FORCED shutdown on ${host}"

    _ssh "$host" "sync; echo o > /proc/sysrq-trigger" \
        && log_warn "Forced shutdown triggered on ${host}" \
        || log_error "Forced shutdown FAILED on ${host}"
}

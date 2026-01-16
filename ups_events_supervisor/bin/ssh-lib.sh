#!/usr/bin/env bash
#
# ssh-lib.sh
# SSH-based power control
#

set -euo pipefail
IFS=$'\n\t'

source /usr/local/powerctl/common/lib/log.sh

SSH_TIMEOUT=5

ssh_available() {
    local host="$1"
    timeout "$SSH_TIMEOUT" ssh -o BatchMode=yes -o ConnectTimeout=3 "$host" true >/dev/null 2>&1
}

ssh_graceful_shutdown() {
    local host="$1"

    if ssh_available "$host"; then
        log_info "Graceful shutdown via SSH on ${host}"
        ssh "$host" "shutdown -h now" || return 1
    else
        log_warn "SSH not available on ${host}"
        return 1
    fi
}

ssh_forced_shutdown() {
    local host="$1"

    if ssh_available "$host"; then
        log_warn "Forced poweroff via SSH on ${host}"
        ssh "$host" "poweroff -f" || true
    else
        log_error "SSH unreachable, cannot force shutdown on ${host}"
    fi
}

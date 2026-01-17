#!/usr/bin/env bash
#
# nut/client/install.sh
#
# Installs or removes NUT client configuration and fallback script.
#

set -euo pipefail
IFS=$'\n\t'

ACTION="${1:---install}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NUT_CONF_DIR="${NUT_CONF_DIR:-/etc/nut}"
NUT_SCRIPTS_DIR="/etc/nut/bash-scr"
NUT_RUN_DIR="/etc/nut/upssched"
NUT_SERVER_IP=""

DRY_RUN=false

log() {
    local level="$1"
    shift
    logger -t nut-client-install -p "user.${level}" -- "$*"
}

info()  { log info  "$*"; }
warn()  { log warn  "$*"; }
error() { log err   "$*"; }

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error "This installer must be run as root"
        exit 1
    fi
}

run() {
    if $DRY_RUN; then
        info "[dry-run] $*"
    else
        "$@"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install)
                ACTION="--install"
                shift
                ;;
            --nut-server-ip)
                NUT_SERVER_IP="${2:-}"
                shift 2
                ;;
            --delete)
                ACTION="--delete"
                shift
                ;;
            --status)
                ACTION="--status"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                ACTION="--install"
                shift
                ;;
            *)
                echo "Usage: $0 [--install|--delete|--status|--dry-run] [--nut-server-ip <ip>]"
                exit 1
                ;;
        esac
    done
}

install_all() {
    require_root
    info "Installing NUT client configuration"

    run mkdir -p "$NUT_CONF_DIR" "$NUT_SCRIPTS_DIR" "$NUT_RUN_DIR"

    run cp -f "$PROJECT_ROOT/conf/nut.conf" "$NUT_CONF_DIR/nut.conf"
    run cp -f "$PROJECT_ROOT/conf/upsmon.conf" "$NUT_CONF_DIR/upsmon.conf"
    run cp -f "$PROJECT_ROOT/conf/upssched.conf" "$NUT_CONF_DIR/upssched.conf"

    if [[ -z "$NUT_SERVER_IP" ]]; then
        if grep -q "<NUT_SERVER_IP>" "$NUT_CONF_DIR/upsmon.conf"; then
            error "Missing --nut-server-ip (placeholder <NUT_SERVER_IP> is still present)"
            exit 1
        fi
    else
        run sed -i "s/<NUT_SERVER_IP>/${NUT_SERVER_IP}/g" "$NUT_CONF_DIR/upsmon.conf"
    fi

    run install -m 0755 "$PROJECT_ROOT/scripts/ups_event.sh" "$NUT_SCRIPTS_DIR/ups_event.sh"

    run systemctl restart nut-monitor || true
    info "NUT client configuration installed"
}

delete_all() {
    require_root
    info "Removing NUT client configuration"
    run rm -f "${NUT_CONF_DIR}/nut.conf" \
       "${NUT_CONF_DIR}/upsmon.conf" \
       "${NUT_CONF_DIR}/upssched.conf"
    run rm -f "${NUT_SCRIPTS_DIR}/ups_event.sh"
    run systemctl restart nut-monitor || true
}

status() {
    echo "NUT_CONF_DIR: ${NUT_CONF_DIR}"
    systemctl status nut-monitor --no-pager || true
}

parse_args "$@"

case "$ACTION" in
    --install)
        install_all
        ;;
    --delete)
        delete_all
        ;;
    --status)
        status
        ;;
    --dry-run)
        DRY_RUN=true
        install_all
        ;;
    *)
        echo "Usage: $0 [--install|--delete|--status|--dry-run]"
        exit 1
        ;;
esac

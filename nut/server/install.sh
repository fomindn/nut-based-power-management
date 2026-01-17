#!/usr/bin/env bash
#
# nut/server/install.sh
#
# Installs or removes NUT server configuration.
# This script is idempotent and uses env configuration.
#

set -euo pipefail
IFS=$'\n\t'

ACTION="${1:---install}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NUT_CONF_DIR="${NUT_CONF_DIR:-/etc/nut}"
NUT_SCRIPTS_DIR="/etc/nut/bash-scr"
NUT_RUN_DIR="/etc/nut/upssched"

DRY_RUN=false

log() {
    local level="$1"
    shift
    logger -t nut-server-install -p "user.${level}" -- "$*"
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

install_all() {
    require_root
    info "Installing NUT server configuration"

    run mkdir -p "$NUT_CONF_DIR" "$NUT_SCRIPTS_DIR" "$NUT_RUN_DIR"

    run cp -f "$PROJECT_ROOT/conf/nut.conf" "$NUT_CONF_DIR/nut.conf"
    run cp -f "$PROJECT_ROOT/conf/ups.conf" "$NUT_CONF_DIR/ups.conf"
    run cp -f "$PROJECT_ROOT/conf/upsd.conf" "$NUT_CONF_DIR/upsd.conf"
    run cp -f "$PROJECT_ROOT/conf/upsd.users" "$NUT_CONF_DIR/upsd.users"
    run cp -f "$PROJECT_ROOT/conf/upsmon.conf" "$NUT_CONF_DIR/upsmon.conf"
    run cp -f "$PROJECT_ROOT/conf/upssched.conf" "$NUT_CONF_DIR/upssched.conf"

    run install -m 0755 "$PROJECT_ROOT/scripts/ups_event.sh" "$NUT_SCRIPTS_DIR/ups_event.sh"
    run chmod 640 "$NUT_CONF_DIR/upsd.users"

    run systemctl restart nut-server || true
    run systemctl restart nut-monitor || true
    info "NUT server configuration installed"
}

delete_all() {
    require_root
    info "Removing NUT server configuration"
    run rm -f "${NUT_CONF_DIR}/nut.conf" \
       "${NUT_CONF_DIR}/ups.conf" \
       "${NUT_CONF_DIR}/upsd.conf" \
       "${NUT_CONF_DIR}/upsd.users" \
       "${NUT_CONF_DIR}/upsmon.conf" \
       "${NUT_CONF_DIR}/upssched.conf"
    run rm -f "${NUT_SCRIPTS_DIR}/ups_event.sh"
    run systemctl restart nut-server || true
    run systemctl restart nut-monitor || true
}

status() {
    echo "NUT_CONF_DIR: ${NUT_CONF_DIR}"
    systemctl status nut-server --no-pager || true
    systemctl status nut-monitor --no-pager || true
}

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

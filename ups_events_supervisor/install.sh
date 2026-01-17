#!/usr/bin/env bash
#
# ups_events_supervisor/install.sh
#
# Installs or removes UPS Power Supervisor service.
#
# Supported actions:
#   --install (default)
#   --delete
#   --status
#   --dry-run
#
# Design goals:
# - Idempotent
# - Journald-only logging
# - Explicit MANIFEST for clean removal
# - FHS-compliant paths
# - systemd-native
#

set -euo pipefail
IFS=$'\n\t'

# ------------------------------------------------------------
# Runtime parameters
# ------------------------------------------------------------

ACTION="${1:---install}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INSTALL_ROOT="/usr/local/powerctl"
BIN_ROOT="$INSTALL_ROOT/bin"
CONF_ROOT="$INSTALL_ROOT/conf"
COMMON_ROOT="$INSTALL_ROOT/common"

STATE_ROOT="/run/powerctl"          # tmpfs runtime state
SYSTEMD_UNIT_NAME="power-supervisor.service"
SYSTEMD_UNIT_PATH="/etc/systemd/system/${SYSTEMD_UNIT_NAME}"
TMPFILES_CONF_NAME="powerctl-tmpfiles.conf"
TMPFILES_CONF_PATH="/etc/tmpfiles.d/${TMPFILES_CONF_NAME}"

MANIFEST_PATH="${INSTALL_ROOT}/MANIFEST"

DRY_RUN=false

# ------------------------------------------------------------
# Logging (journald)
# ------------------------------------------------------------

log() {
    local level="$1"
    shift
    logger -t power-supervisor-install -p "user.${level}" -- "$*"
}

info()  { log info  "$*"; }
warn()  { log warn  "$*"; }
error() { log err   "$*"; }

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

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

record_manifest() {
    echo "$1" >>"$MANIFEST_PATH"
}

# ------------------------------------------------------------
# Install logic
# ------------------------------------------------------------

install_files() {
    info "Installing supervisor files"

    run mkdir -p "$BIN_ROOT" "$CONF_ROOT" "$COMMON_ROOT"
    run cp -r "$PROJECT_ROOT/bin/." "$BIN_ROOT/"
    run cp -r "$PROJECT_ROOT/conf/." "$CONF_ROOT/"
    run cp -r "$PROJECT_ROOT/../common/lib" "$COMMON_ROOT/"

    # Install env template if env file does not exist
    if [[ ! -f "$COMMON_ROOT/env" ]]; then
        run cp "$PROJECT_ROOT/../common/env.example" "$COMMON_ROOT/env"
    fi

    record_manifest "$INSTALL_ROOT"
}

install_runtime_state() {
    info "Preparing runtime state directory"

    run mkdir -p "$STATE_ROOT"
    record_manifest "$STATE_ROOT"
}

install_systemd_unit() {
    info "Installing systemd unit"

    run cp "$PROJECT_ROOT/systemd/${SYSTEMD_UNIT_NAME}" "$SYSTEMD_UNIT_PATH"
    run cp "$PROJECT_ROOT/systemd/${TMPFILES_CONF_NAME}" "$TMPFILES_CONF_PATH"
    record_manifest "$SYSTEMD_UNIT_PATH"
    record_manifest "$TMPFILES_CONF_PATH"

    run systemctl daemon-reexec
    run systemctl daemon-reload
    run systemctl enable "$SYSTEMD_UNIT_NAME"
    run systemd-tmpfiles --create "$TMPFILES_CONF_PATH" || true
}

install_all() {
    require_root

    run mkdir -p "$INSTALL_ROOT"
    run : >"$MANIFEST_PATH"

    install_files
    install_runtime_state
    install_systemd_unit

    info "UPS Power Supervisor installed successfully"
}

# ------------------------------------------------------------
# Delete logic
# ------------------------------------------------------------

delete_all() {
    require_root

    if [[ ! -f "$MANIFEST_PATH" ]]; then
        warn "MANIFEST not found, nothing to delete"
        exit 0
    fi

    info "Stopping and disabling service"
    run systemctl stop "$SYSTEMD_UNIT_NAME" || true
    run systemctl disable "$SYSTEMD_UNIT_NAME" || true

    info "Removing installed files"
    tac "$MANIFEST_PATH" | while read -r path; do
        run rm -rf "$path"
    done

    run systemctl daemon-reload
    info "UPS Power Supervisor removed"
}

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

status() {
    echo "Install root:  $INSTALL_ROOT"
    echo "State dir:     $STATE_ROOT"
    echo "Systemd unit:  $SYSTEMD_UNIT_PATH"
    echo
    systemctl status "$SYSTEMD_UNIT_NAME" --no-pager || true
}

# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------

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

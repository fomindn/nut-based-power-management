#!/usr/bin/env bash
# ups_events_supervisor/install.sh

set -euo pipefail
IFS=$'\n\t'

ACTION="${1:---install}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT="/usr/local/powerctl"
CONF_ROOT="$INSTALL_ROOT/conf"
BIN_ROOT="$INSTALL_ROOT/bin"
SYSTEMD_UNIT="/etc/systemd/system/power-supervisor.service"
ENV_DIR="/etc/powerctl"
ENV_FILE="$ENV_DIR/powerctl.env"
MANIFEST="$PROJECT_ROOT/MANIFEST"
INSTALL_LOG="/var/log/powerctl-install.log"

export POWERCTL_LOG_TAG="powerctl-install"
export POWERCTL_LOG_STDERR=1

source "$PROJECT_ROOT/../common/lib/log.sh"

require_root() {
    [[ $EUID -eq 0 ]] || log_fatal "This script must be run as root"
}

log_install() {
    echo "$(date '+%F %T') $*" >> "$INSTALL_LOG"
}

install_files() {
    log_info "Installing supervisor files"

    install -d -m 0755 "$INSTALL_ROOT" "$BIN_ROOT" "$CONF_ROOT"
    install -d -m 0755 "$ENV_DIR"

    for f in "$PROJECT_ROOT/bin/"*.sh; do
        install -m 0755 "$f" "$BIN_ROOT/"
        log_install "INSTALL $(basename "$f") -> $BIN_ROOT"
    done

    for f in "$PROJECT_ROOT/conf/"*.conf; do
        dest="$CONF_ROOT/$(basename "$f")"
        if [[ -f "$dest" ]]; then
            log_warn "Config $(basename "$f") exists, skipping"
            log_install "SKIP existing config $dest"
        else
            install -m 0644 "$f" "$CONF_ROOT/"
            log_install "INSTALL config $(basename "$f")"
        fi
    done

    install -m 0644 "$PROJECT_ROOT/systemd/power-supervisor.service" "$SYSTEMD_UNIT"
    log_install "INSTALL systemd unit $SYSTEMD_UNIT"
}

setup_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        cp "$PROJECT_ROOT/../common/env.example" "$ENV_FILE"
        chmod 0644 "$ENV_FILE"
        log_install "CREATE env file $ENV_FILE"
        log_warn "Created $ENV_FILE from env.example — review before use"
    else
        log_info "Env file exists, skipping"
    fi
}

enable_service() {
    systemctl daemon-reload
    systemctl enable power-supervisor.service
    systemctl restart power-supervisor.service
    log_install "ENABLE and START power-supervisor.service"
}

uninstall() {
    log_warn "Uninstalling power supervisor"

    systemctl stop power-supervisor.service || true
    systemctl disable power-supervisor.service || true

    while read -r file; do
        rm -f "$file"
        log_install "REMOVE $file"
    done < "$MANIFEST"

    systemctl daemon-reload
    log_install "UNINSTALL complete"
}

status() {
    systemctl status power-supervisor.service --no-pager || true
}

case "$ACTION" in
    --install)
        require_root
        install_files
        setup_env
        enable_service
        log_info "Installation complete"
        ;;
    --delete)
        require_root
        uninstall
        ;;
    --status)
        status
        ;;
    --dry-run)
        log_info "Dry-run mode not yet implemented"
        ;;
    *)
        log_fatal "Unknown action: $ACTION"
        ;;
esac

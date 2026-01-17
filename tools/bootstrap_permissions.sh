#!/usr/bin/env bash
#
# bootstrap_permissions.sh
# Ensure executable permissions for project scripts after git clone.
#
# This script is safe to run multiple times. It only sets +x on known scripts.
#

set -euo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# List of scripts that must be executable.
SCRIPTS=(
  "${ROOT_DIR}/nut/server/install.sh"
  "${ROOT_DIR}/nut/client/install.sh"
  "${ROOT_DIR}/ups_events_supervisor/install.sh"
  "${ROOT_DIR}/nut/server/scripts/ups_event.sh"
  "${ROOT_DIR}/nut/client/scripts/ups_event.sh"
  "${ROOT_DIR}/tools/setup_ssh_user.sh"
  "${ROOT_DIR}/tools/bootstrap_permissions.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [[ -f "$script" ]]; then
        chmod 755 "$script"
    else
        echo "WARNING: missing script: $script"
    fi
done

echo "Script permissions updated."

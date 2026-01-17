#!/usr/bin/env bash
#
# setup_ssh_user.sh
# Create a restricted SSH user for remote shutdown operations.
#
# This script:
# - Creates a dedicated user (default: powerctl)
# - Installs a public SSH key into authorized_keys
# - Applies secure file permissions
# - Optionally adds the user to the nut group
# - Installs a sudoers rule for shutdown commands only
#
# Usage:
#   sudo ./setup_ssh_user.sh \
#     --user powerctl \
#     --pubkey-file /path/to/key.pub \
#     --add-to-nut-group
#
# Notes:
# - The public key must be generated on the Raspberry Pi (private key stays there).
# - The user should have no interactive shell by default.
#

set -euo pipefail
IFS=$'\n\t'

USER_NAME="powerctl"
PUBKEY_FILE=""
PUBKEY_VALUE=""
ADD_NUT_GROUP=false
SUDO_CMDS=(
  "/sbin/shutdown"
  "/sbin/poweroff"
  "/usr/bin/systemctl shutdown"
  "/usr/bin/systemctl poweroff"
)

usage() {
    echo "Usage: $0 --pubkey-file <file> [--user <name>] [--add-to-nut-group]"
    echo "       $0 --pubkey '<key>' [--user <name>] [--add-to-nut-group]"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            USER_NAME="${2:-}"
            shift 2
            ;;
        --pubkey-file)
            PUBKEY_FILE="${2:-}"
            shift 2
            ;;
        --pubkey)
            PUBKEY_VALUE="${2:-}"
            shift 2
            ;;
        --add-to-nut-group)
            ADD_NUT_GROUP=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$PUBKEY_FILE" && -z "$PUBKEY_VALUE" ]]; then
    echo "ERROR: public key is required"
    usage
    exit 1
fi

if [[ -n "$PUBKEY_FILE" ]]; then
    if [[ ! -f "$PUBKEY_FILE" ]]; then
        echo "ERROR: public key file not found: $PUBKEY_FILE"
        exit 1
    fi
    PUBKEY_VALUE="$(cat "$PUBKEY_FILE")"
fi

if ! id "$USER_NAME" >/dev/null 2>&1; then
    # Create a non-interactive user with a home directory.
    useradd -m -s /usr/sbin/nologin "$USER_NAME"
fi

USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
SSH_DIR="${USER_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

# Create SSH directory with strict permissions.
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$SSH_DIR"

# Append the key if it's not already present.
if [[ ! -f "$AUTH_KEYS" ]] || ! grep -qxF "$PUBKEY_VALUE" "$AUTH_KEYS"; then
    echo "$PUBKEY_VALUE" >> "$AUTH_KEYS"
fi

chown "$USER_NAME:$USER_NAME" "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

# Optional: add user to nut group if requested and group exists.
if $ADD_NUT_GROUP; then
    if getent group nut >/dev/null 2>&1; then
        usermod -a -G nut "$USER_NAME"
    else
        echo "WARNING: group 'nut' does not exist, skipping"
    fi
fi

# Install sudoers rule for shutdown commands only.
SUDOERS_FILE="/etc/sudoers.d/${USER_NAME}-powerctl"
{
    echo "# Restricted shutdown permissions for ${USER_NAME}"
    printf "%s ALL=(root) NOPASSWD: %s\n" "$USER_NAME" "$(IFS=','; echo "${SUDO_CMDS[*]}")"
} > "$SUDOERS_FILE"

chmod 440 "$SUDOERS_FILE"

echo "SSH user '${USER_NAME}' configured successfully."

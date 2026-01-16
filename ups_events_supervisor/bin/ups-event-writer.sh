#!/usr/bin/env bash
#
# ups-event-writer.sh
#
# Minimal NUT event recorder.
# NO logic allowed here.
#

set -euo pipefail
IFS=$'\n\t'

EVENT="$1"

STATE_DIR="/run/powerctl"
EVENT_FILE="${STATE_DIR}/ups.event"
TS_FILE="${STATE_DIR}/ups.event.ts"

LOGGER_TAG="ups-event-writer"
source /usr/local/powerctl/common/lib/log.sh

mkdir -p "$STATE_DIR"

echo "$EVENT" >"$EVENT_FILE"
date +%s >"$TS_FILE"

log_info "UPS event recorded: $EVENT"

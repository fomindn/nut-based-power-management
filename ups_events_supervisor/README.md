# UPS Events Supervisor

The supervisor is the core decision engine. It reads UPS events written to
state files by `ups-event-writer.sh` and applies a deterministic FSM to decide
when to shut down devices or wake them via WOL.

## What It Does

- Handles day/night logic and grace periods
- Shuts down critical devices gracefully, then forces if needed
- Shuts down Raspberry Pi last via `upsmon -c fsd`
- Auto-wakes devices when power is stable and conditions are met
- Protects against flapping and duplicate shutdowns

## Installation

1. Copy supervisor files (or run `install.sh` as root):
   - `/usr/local/powerctl/bin/*`
   - `/usr/local/powerctl/conf/*`
2. Ensure runtime state directory exists:
   - `/run/powerctl/state`
3. Enable and start systemd unit:
   - `systemctl enable --now power-supervisor.service`

## Configuration Files

### `conf/power.conf`

- `BATTERY_GRACE_PERIOD`: Wait time after power loss before shutdown
- `FORCE_SHUTDOWN_TIMEOUT`: Max wait for graceful shutdown
- `POWER_STABLE_TIME_LOW/HIGH`: Stability before auto-wake
- `ONLINE_STABLE_MIN`: Debounce time for ONLINE
- `ONBATT_STABLE_MIN`: Debounce time for ONBATT
- `AUTO_WAKE_MAX_ATTEMPTS`: Default auto-wake attempts per device
- `SHUTDOWN_COOLDOWN`: Minimum time between shutdown requests

### `conf/device.conf`

Each device line has:

```
name|host|mac|role|auto_start|ports|auto_wake_max
```

- `role`: `critical` or `user`
- `auto_start`: `yes` or `no`
- `ports`: comma-separated TCP ports for activity detection
- `auto_wake_max`: optional per-device override

### `conf/schedule.conf`

Defines day/night windows for auto-wake:

```
DAY_START="09:00"
DAY_END="23:59"
```

## State Files

State is stored in `/run/powerctl/state`. Key files include:

- `power_status`
- `on_battery_since`
- `power_restored_at`
- `battery_status`
- `shutdown_started` / `shutdown_reason`

## Logging

All logs go to `journald` with tag `power-supervisor`.

Example:
```
journalctl -u power-supervisor.service -f
```

## Troubleshooting

- If no actions occur, check:
  - `upssched` calls to `ups-event-writer.sh`
  - Supervisor state files in `/run/powerctl/state`
  - `power-supervisor.service` status

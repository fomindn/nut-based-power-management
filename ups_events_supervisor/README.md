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

### `/usr/local/powerctl/common/env`

Centralized configuration file used by all scripts. This is the single source
of truth for paths, timeouts, and thresholds. Use `common/env.example` as a
template and adjust values before installation.

### `conf/power.conf`

Deprecated. All values are now stored in `/usr/local/powerctl/common/env`.

### `conf/device.conf`

Each device line has:

```
name|host|mac|role|auto_start|ports|auto_wake_max|auto_wake_cooldown
```

- `role`: `critical` or `user`
- `auto_start`: `yes` or `no`
- `ports`: comma-separated TCP ports for activity detection
- `auto_wake_max`: optional per-device override
- `auto_wake_cooldown`: optional per-device WOL cooldown override

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

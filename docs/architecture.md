# Architecture

This project is a state-driven UPS power management system built on top of NUT.
All decision logic is centralized in a single supervisor running on the
Raspberry Pi (NUT server). Clients run NUT only, plus a minimal fallback script.

## Design Goals

- **Deterministic behavior**: decisions are based on persisted state, not event timing.
- **Fail-safe priority**: protect data and gracefully shut down devices before UPS cutoff.
- **Single authority**: one supervisor process, one FSM, no split-brain logic.
- **Debounce and anti-flap**: power transitions must be stable before actions.
- **Centralized config**: all tunables live in `/usr/local/powerctl/common/env`.

## High-Level Components

1. **NUT Server (Raspberry Pi)**
   - `upsd` exposes UPS state to the network
   - `upsmon` monitors UPS and emits events
   - `upssched` executes `/etc/nut/bash-scr/ups_event.sh`

2. **Supervisor (Raspberry Pi)**
   - `power-supervisor.sh` reads state and applies FSM rules
   - Acts on devices via SSH and Wake-on-LAN
   - Tracks shutdown sessions and auto-wake attempts
   - Optional: receives events forwarded by NUT server handler

3. **NUT Clients (NAS, Proxmox, PC)**
   - `upsmon` monitors remote UPS
   - `upssched` executes `ups_event.sh` for fallback shutdown

## Event Flow (Server)

```
UPS -> usbhid-ups -> upsd -> upsmon -> upssched -> /etc/nut/bash-scr/ups_event.sh
                                                    |
                                                    v
                                  (optional) ups-event-writer.sh -> state/*
                                                    |
                                                    v
                                           power-supervisor.sh
```

The supervisor never sleeps for long or blocks on events; it polls state with a
small interval, ensuring resilience after restarts.

## State Storage

State is stored in `/run/powerctl/state`:

- `power_status`: `on_battery` or `online`
- `on_battery_since`: timestamp when power loss occurred
- `power_restored_at`: timestamp when power was restored
- `battery_status`: `low` when LOWBATT occurs
- `shutdown_started`, `shutdown_reason`
- per-device auto-wake attempts and exhaustion flags

This state is transient (tmpfs), but survives service restarts.

## Device Control

Device definitions live in `ups_events_supervisor/conf/device.conf`. Each device
has:

- Hostname/IP
- MAC for WOL
- Role (critical/user)
- Auto-start flag
- Optional TCP ports to detect activity
- Optional per-device auto-wake attempt limit

## Day/Night Logic

`time-lib.sh` defines day/night windows. At night:

- No automatic WOL
- If no active devices on battery: shutdown immediately

## Auto-Wake Policy

Auto-wake is only allowed if:

- Power is stable (time-based)
- Battery charge is above `MIN_START_BATTERY`
- Time is within day window
- Auto-wake attempts have not exceeded limits
- Per-device WOL cooldown has elapsed
- Optional TTL has not expired for `power_restored_at`

## Client Fallback

Clients do not make decisions. They only:

- Shutdown locally after a grace period (ONBATT)
- Shutdown if communication with server fails

This ensures the system remains safe even if the server becomes unreachable.

# nut-based-power-management

Production-grade UPS power management based on NUT (Network UPS Tools) with a
state-driven supervisor running on Raspberry Pi. The supervisor coordinates
graceful shutdowns, forced shutdowns, and auto-wake behavior for network devices
based on UPS events, battery charge, and day/night rules.

## Quick Summary

- **Supervisor runs only on Raspberry Pi (NUT server)** and makes decisions.
- **Clients run NUT upsmon + upssched** with a minimal fallback shutdown script.
- **Events are standardized** (onbatt/online/lowbatt).
- **State-driven** logic prevents missed events and handles flapping safely.

## Repository Layout

- `nut/server/` — NUT server configuration templates
- `nut/client/` — NUT client configuration templates + fallback script
- `ups_events_supervisor/` — supervisor service, config, and systemd unit
- `docs/` — architecture, state machine, recovery scenarios
- `common/` — shared logging utilities

## Core Components

- **NUT server (Raspberry Pi)**
  - `upsd` exposes UPS status
  - `upsmon` monitors UPS and triggers `upssched`
  - `upssched` executes `ups-event-writer.sh`
- **Supervisor**
  - `power-supervisor.sh` reads state and makes decisions
  - Shutdowns are graceful first, then forced via SSH if needed
  - Auto-wake uses WOL with configurable stability and retries
- **NUT clients**
  - `upsmon` monitors remote UPS
  - `upssched` runs `ups_event.sh` for fallback shutdown

## Where to Start

1. Read `docs/architecture.md` and `docs/state-machine.md`.
2. Configure server configs in `nut/server/conf/` (standalone NUT configs).
3. Configure client configs in `nut/client/conf/` (standalone NUT configs).
4. Configure supervisor in `ups_events_supervisor/conf/`.
5. Install the supervisor service on Raspberry Pi.

## Central Configuration

All tunable parameters (paths, timeouts, thresholds) are centralized in
`/usr/local/powerctl/common/env`. Use `common/env.example` as a template.

## SSH Setup (Recommended)

Use a dedicated SSH user for remote shutdowns. A helper script is provided:

```
sudo tools/setup_ssh_user.sh --user powerctl --pubkey-file /path/to/key.pub
```

## Security Notes

- Use unique, strong passwords in `upsd.users`.
- Restrict `upsd.conf` listen IPs to your LAN only.
- Use SSH keys with limited privileges for forced shutdowns.

## Documentation

- `docs/architecture.md`
- `docs/state-machine.md`
- `docs/recovery-scenarios.md`
- `ups_events_supervisor/README.md`
- `nut/server/README.md`
- `nut/client/README.md`

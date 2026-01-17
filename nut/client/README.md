# NUT Client (NAS / Proxmox / PC)

Clients run `upsmon` to monitor the UPS status from the server. They do not
make policy decisions; the supervisor on Raspberry Pi does that. Clients only
run a minimal fallback shutdown handler to protect data if the server becomes
unreachable. These configs remain fully functional without the supervisor.

## Files

- `conf/nut.conf` — client mode (`netclient`)
- `conf/upsmon.conf` — client monitor configuration
- `conf/upssched.conf` — local fallback timers
- `scripts/ups_event.sh` — local fallback shutdown handler

## Installation (Manual)

1. Copy configs to `/etc/nut/`:
   - `nut.conf`
   - `upsmon.conf`
   - `upssched.conf`
2. Install the fallback script:
   - `install -m 0755 scripts/ups_event.sh /usr/local/nut/bin/ups_event.sh`
3. Create runtime directory:
   - `mkdir -p /run/nut`
4. Restart NUT monitor:
   - `systemctl restart nut-monitor`

## Installation (Scripted)

Use `install.sh` to copy configs as-is:

- `sudo ./install.sh --install`

## Fallback Behavior

- **ONBATT**: start a local shutdown timer (default 300s)
- **ONLINE**: cancel the local shutdown timer
- **LOWBATT**: immediate shutdown
- **COMMBAD/COMMFAULT**: start a communication-loss timer (default 1800s)
- **COMMOK**: cancel communication-loss timer

These are last-resort safety measures and do not replace the supervisor logic.

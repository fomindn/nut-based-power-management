# NUT Server (Raspberry Pi)

This directory contains server-side NUT configuration templates. The server
hosts `upsd` and `upsmon`, and triggers `upssched` events for the supervisor.

## Files

- `conf/nut.conf` — server mode (`netserver`)
- `conf/ups.conf` — UPS driver configuration
- `conf/upsd.conf` — network listener configuration
- `conf/upsd.users` — NUT users (monitor/admin)
- `conf/upsmon.conf` — server-side upsmon config
- `conf/upssched.conf` — event mapping to `ups-event-writer.sh`

## Installation (Manual)

1. Copy configs to `/etc/nut/`:
   - `nut.conf`
   - `ups.conf`
   - `upsd.conf`
   - `upsd.users`
   - `upsmon.conf`
   - `upssched.conf`
2. Ensure correct ownership and permissions:
   - `chmod 640 /etc/nut/upsd.users`
3. Create runtime directory:
   - `mkdir -p /run/powerctl`
4. Restart NUT services:
   - `systemctl restart nut-server`
   - `systemctl restart nut-monitor`

## Notes

- Set strong passwords in `upsd.users`.
- Restrict `LISTEN` addresses in `upsd.conf` to your LAN.
- `upssched.conf` must point to `/usr/local/powerctl/bin/ups-event-writer.sh`.

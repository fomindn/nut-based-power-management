# NUT Server (Raspberry Pi)

This directory contains server-side NUT configuration files. The server hosts
`upsd` and `upsmon`, and triggers `upssched` events. These configs remain fully
functional even without the supervisor installed.

## Files

- `conf/nut.conf` — server mode (`netserver`)
- `conf/ups.conf` — UPS driver configuration
- `conf/upsd.conf` — network listener configuration
- `conf/upsd.users` — NUT users (monitor/admin)
- `conf/upsmon.conf` — server-side upsmon config
- `conf/upssched.conf` — event mapping to `/usr/local/nut/bin/ups_event.sh`
- `scripts/ups_event.sh` — server event handler (optional supervisor forward)

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
3. Install event handler:
   - `install -m 0755 scripts/ups_event.sh /usr/local/nut/bin/ups_event.sh`
4. Create runtime directory:
   - `mkdir -p /run/nut`
5. Restart NUT services:
   - `systemctl restart nut-server`
   - `systemctl restart nut-monitor`

## Notes

- Set strong passwords in `upsd.users`.
- Restrict `LISTEN` addresses in `upsd.conf` to your LAN.
- `upssched.conf` must point to `/usr/local/nut/bin/ups_event.sh`.

## Installation (Scripted)

Use `install.sh` to copy configs as-is:

- `sudo ./install.sh --install`

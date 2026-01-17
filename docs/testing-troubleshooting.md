# Testing and Troubleshooting

This document provides a **manual test checklist** and a **troubleshooting guide**
for the NUT + Supervisor stack. The focus is on verifying real behavior after
installation and enabling quick diagnosis in production.

---

# 1) Manual Test Checklist

All steps below assume:
- NUT server is running on Raspberry Pi.
- Supervisor service is installed and running.
- Clients are configured and `nut-monitor` is running.
- Logging uses the tags:
  - `power-supervisor`
  - `nut-server-event`
  - `nut-client-event`

Recommended log view:
```
journalctl -t power-supervisor -t nut-server-event -t nut-client-event -o cat
```

---

## A) ONBATT (Day)

**Goal:** Graceful → forced shutdown sequence starts after grace period.

1. Simulate power loss (pull UPS power or use test mode).
2. Verify log sequence:
   - `nut-server-event`: `event=onbatt`
   - `power-supervisor`: `event=on_battery_debounce`
   - After `BATTERY_GRACE_PERIOD`: `event=shutdown_start`
3. Verify:
   - SSH graceful shutdown attempts are logged.
   - After `FORCE_SHUTDOWN_TIMEOUT`, forced shutdown logs appear.
4. Verify Raspberry Pi shutdown:
   - `event=shutdown_pi action=upsmon_fsd`

**Expected outcome:** controlled devices go down, Pi shuts down last.

---

## B) ONBATT (Night, No Active Devices)

**Goal:** Immediate shutdown when no active devices are detected.

1. Ensure no active monitored devices.
2. Trigger ONBATT at night.
3. Verify logs:
   - `event=on_battery night=1 active=0 action=shutdown`
4. Verify Pi shutdown is initiated.

**Expected outcome:** immediate shutdown without waiting grace period.

---

## C) LOWBATT

**Goal:** Immediate shutdown sequence.

1. Trigger LOWBATT event from UPS.
2. Verify logs:
   - `event=low_battery action=shutdown` (critical)
3. Verify forced shutdown triggers if devices are still active.

**Expected outcome:** immediate shutdown of all critical devices and Pi.

---

## D) ONLINE → WOL

**Goal:** Auto‑wake after stability checks.

1. Trigger ONLINE event.
2. Verify logs:
   - `event=online_debounce`
   - `event=online_stable_wait`
   - `event=auto_wake_ready`
3. Verify WOL attempts:
   - `event=auto_wake_sent`
4. Verify `power_restored_at` cleared when conditions met.

**Expected outcome:** eligible devices are woken after stable power window.

---

## E) COMMBAD / COMMFAULT (Server)

**Goal:** Log + wall + block WOL, no shutdown.

1. Disconnect UPS USB or simulate COMMBAD.
2. Verify logs:
   - `event=comm_loss status=bad action=log`
3. Verify wall messages appear (throttled).
4. Trigger ONLINE while comm_status=bad.
5. Verify:
   - `event=auto_wake_skip reason=comm_bad`

**Expected outcome:** WOL blocked until COMMOK.

---

## F) Client Fallback (COMMBAD / COMMFAULT)

**Goal:** Local shutdown after long comm loss.

1. Disconnect client from NUT server.
2. Verify client logs:
   - `event=commbad action=start_timer`
3. Wait `NUT_CLIENT_COMMFAULT_GRACE` (default 1800s).
4. Verify:
   - `event=timer_expired timer=commfault_shutdown action=shutdown`

**Expected outcome:** client shuts down after grace timeout.

---

# 2) Troubleshooting Guide

## A) No events reaching supervisor

Check:
- `/etc/nut/upssched.conf` points to `/etc/nut/bash-scr/ups_event.sh`
- NUT handler exists:
  - `/etc/nut/bash-scr/ups_event.sh`
- Forwarding to:
  - `/usr/local/powerctl/bin/ups-event-writer.sh`

## B) No state changes

Check:
- `/run/powerctl/state/` files exist
- `ups-event-writer.sh` logs show events

## C) WOL does not trigger

Check:
- device is marked `auto_start=yes`
- `MIN_START_BATTERY` satisfied
- `comm_status` is not `bad`
- device not already active (ping/port checks)

## D) Forced shutdown does not work

Check:
- SSH connectivity to devices
- sudoers permissions for `powerctl` user

## E) No logs

Check:
- `journalctl -t power-supervisor`
- `journalctl -t nut-server-event`
- `journalctl -t nut-client-event`

---

If you want to enable **plain logs**, set:
```
LOG_FORMAT="plain"
```

If you want structured logs, keep:
```
LOG_FORMAT="kv"
```

# State Machine

The supervisor acts as a finite-state machine (FSM) driven by persisted state.
It does not process events directly; it reads state markers written by NUT.

## Core Power States

| State Marker | Meaning |
| --- | --- |
| `power_status=on_battery` | UPS switched to battery |
| `power_status=online` | Utility power restored |
| `battery_status=low` | Battery is critically low |
| `comm_status=bad` | UPS communication lost |

## Internal Supervisor Flags

| Flag | Purpose |
| --- | --- |
| `shutdown_started` | Prevents duplicate shutdown sequences |
| `shutdown_reason` | Audit of why shutdown began |
| `shutdown_last_request` | Cooldown for repeated shutdown triggers |
| `on_battery_since` | Timestamp for grace period tracking |
| `power_restored_at` | Timestamp for power-stability tracking |

## Main Loop (Simplified)

```
read power_status
if battery_status == low -> emergency shutdown
if power_status == on_battery -> on-battery handler
if power_status == online -> power-restored handler
sleep CHECK_INTERVAL
```

## On-Battery Handler

1. Ensure `on_battery_since` exists
2. Debounce ONBATT (`ONBATT_STABLE_MIN`)
3. At night:
   - If no active devices -> shutdown immediately
4. If grace period exceeded -> shutdown sequence

## Power-Restored Handler

1. Debounce ONLINE (`ONLINE_STABLE_MIN`)
2. Verify stability window based on battery charge
3. Day window only (no night auto-wake)
4. Auto-wake only for eligible devices
5. Limit attempts per device per ONLINE session
6. Clear `power_restored_at` only when:
   - All auto-start devices are active, or
   - All remaining devices have exhausted auto-wake attempts
7. Enforce per-device WOL cooldown and optional TTL for stale ONLINE markers

## Low-Battery Handler

- Immediate shutdown of all critical devices
- Forced shutdown of Raspberry Pi via `upsmon -c fsd`

## Communication Loss Handling

- COMMBAD/COMMFAULT updates `comm_status=bad`
- Supervisor logs warnings and throttled wall alerts
- Auto-wake is blocked until COMMOK clears the condition
- Events are received via `/etc/nut/bash-scr/ups_event.sh` (forwarded if supervisor is installed)
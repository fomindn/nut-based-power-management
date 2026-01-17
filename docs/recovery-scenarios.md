# Recovery Scenarios

This document summarizes typical failure and recovery paths and the expected
behavior of the system.

## Scenario 1: Power Loss (Day)

1. UPS switches to battery (`onbatt`)
2. Supervisor debounces ONBATT
3. Waits `BATTERY_GRACE_PERIOD`
4. If still on battery:
   - Graceful shutdown of critical devices
   - Forced shutdown after timeout if still active
   - Raspberry Pi shuts down last

## Scenario 2: Power Loss (Night)

1. UPS switches to battery
2. If no active devices -> immediate shutdown
3. If active devices exist:
   - Wait grace period
   - Perform shutdown sequence
4. No auto-wake during night window

## Scenario 3: Low Battery

1. UPS reports LOWBATT
2. Immediate shutdown of all critical devices
3. Raspberry Pi triggers `upsmon -c fsd`

## Scenario 4: Power Restored (Stable)

1. UPS goes ONLINE
2. Supervisor waits `ONLINE_STABLE_MIN` and power-stability window
3. If day time and battery >= `MIN_START_BATTERY`:
   - Auto-wake eligible devices
   - Limit per-device attempts
4. Clear restoration marker only when:
   - Devices are active, or
   - Attempts are exhausted
5. Optional TTL may clear stale ONLINE markers after a long delay

## Scenario 5: Power Flapping

1. Alternating ONBATT/ONLINE events are recorded
2. Supervisor resolves conflicts via timestamps
3. Actions are delayed until stable windows pass

## Scenario 6: NUT Server Communication Loss (Client)

1. Client receives COMMBAD/COMMFAULT
2. Fallback timer starts (client-only)
3. If COMMOK is not received in time:
   - Client performs local shutdown

This ensures safety even if the server becomes unreachable.

## Scenario 7: UPS Communication Loss (Server)

1. Server receives COMMBAD/COMMFAULT
2. Supervisor logs warning and sends throttled wall alerts
3. Auto-wake is blocked until COMMOK is received

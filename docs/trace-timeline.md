# Trace Timeline (Detailed Execution)

This document provides a step‑by‑step timeline for the most important power
events. Each step shows **who acts**, **what is evaluated**, **what is written**,
and **what is forwarded**. All timings use the defaults from `common/env.example`.

## Defaults used in examples

| Variable | Value |
| --- | --- |
| `CHECK_INTERVAL` | 10s |
| `ONBATT_STABLE_MIN` | 10s |
| `ONLINE_STABLE_MIN` | 30s |
| `BATTERY_GRACE_PERIOD` | 180s |
| `FORCE_SHUTDOWN_TIMEOUT` | 180s |
| `SHUTDOWN_COOLDOWN` | 30s |
| `POWER_STABLE_TIME_LOW` | 120s |
| `POWER_STABLE_TIME_HIGH` | 60s |
| `MIN_START_BATTERY` | 30% |
| `NUT_CLIENT_COMMFAULT_GRACE` | 1800s |

---

# Scenario A — ONBATT (Day, power does not return)

**Goal:** Graceful shutdown of critical devices, then force shutdown, then Pi.

| Time | Actor / File | Evaluates | Writes / Forwards | Action |
| --- | --- | --- | --- | --- |
| T+0 | `upssched.conf` (server) | `ONBATT` event | → `/etc/nut/bash-scr/ups_event.sh` | Execute handler |
| T+0 | `/etc/nut/bash-scr/ups_event.sh` | event type | → journald (`nut-server-event`) | Log event |
| T+0 | `/etc/nut/bash-scr/ups_event.sh` | supervisor exists? | → `/usr/local/powerctl/bin/ups-event-writer.sh` | Forward event |
| T+0 | `ups-event-writer.sh` | `onbatt` | `power_status=on_battery`, `on_battery_since=now` | Persist state |
| T+0…10 | `power-supervisor.sh` | `elapsed < ONBATT_STABLE_MIN` | — | Debounce (wait) |
| T+10…180 | `power-supervisor.sh` | `elapsed < BATTERY_GRACE_PERIOD` | — | Grace wait |
| T+180 | `power-supervisor.sh` | cooldown check | `shutdown_last_request` | Start shutdown |
| T+180 | `power-supervisor.sh` | active devices list | `ACTIVE_DEVICES` | Build list |
| T+180 | `power-supervisor.sh` | per device | — | Send graceful SSH shutdown |
| T+180…360 | `power-supervisor.sh` | device active? | — | Wait up to `FORCE_SHUTDOWN_TIMEOUT` |
| T+360 | `power-supervisor.sh` | still active? | — | Forced SSH shutdown |
| T+360 | `power-supervisor.sh` | — | — | `upsmon -c fsd` (Pi shutdown) |

---

# Scenario B — ONBATT (Night, no active devices)

**Goal:** Immediate shutdown of Pi to preserve battery.

| Time | Actor / File | Evaluates | Writes / Forwards | Action |
| --- | --- | --- | --- | --- |
| T+0 | `upssched.conf` | `ONBATT` event | → `/etc/nut/bash-scr/ups_event.sh` | Execute handler |
| T+0 | `/etc/nut/bash-scr/ups_event.sh` | event type | → journald | Log event |
| T+0 | `/etc/nut/bash-scr/ups_event.sh` | supervisor exists? | → writer | Forward |
| T+0 | `ups-event-writer.sh` | `onbatt` | `power_status=on_battery`, `on_battery_since=now` | Persist |
| T+0…10 | `power-supervisor.sh` | debounce | — | Wait |
| T+10 | `power-supervisor.sh` | `is_night_time && active_count=0` | — | Start shutdown |
| T+10 | `power-supervisor.sh` | — | — | `upsmon -c fsd` |

---

# Scenario C — LOWBATT (critical battery)

**Goal:** Immediate shutdown of all critical devices and Pi.

| Time | Actor / File | Evaluates | Writes / Forwards | Action |
| --- | --- | --- | --- | --- |
| T+0 | `upssched.conf` | `LOWBATT` event | → handler | Execute handler |
| T+0 | `/etc/nut/bash-scr/ups_event.sh` | event type | → journald | Log event |
| T+0 | `/etc/nut/bash-scr/ups_event.sh` | supervisor exists? | → writer | Forward |
| T+0 | `ups-event-writer.sh` | `lowbatt` | `battery_status=low` | Persist |
| T+0 | `power-supervisor.sh` | `battery_status=low` | — | `shutdown_sequence` |
| T+0… | `power-supervisor.sh` | device active? | — | graceful → force |
| T+… | `power-supervisor.sh` | — | — | `upsmon -c fsd` |

---

# Scenario D — ONLINE (power restored, day)

**Goal:** Auto‑wake eligible devices when power is stable.

| Time | Actor / File | Evaluates | Writes / Forwards | Action |
| --- | --- | --- | --- | --- |
| T+0 | `upssched.conf` | `ONLINE` event | → handler | Execute handler |
| T+0 | `/etc/nut/bash-scr/ups_event.sh` | event type | → journald | Log event |
| T+0 | `/etc/nut/bash-scr/ups_event.sh` | supervisor exists? | → writer | Forward |
| T+0 | `ups-event-writer.sh` | `online` | `power_status=online`, `power_restored_at=now` | Persist |
| T+0…30 | `power-supervisor.sh` | `elapsed < ONLINE_STABLE_MIN` | — | Debounce |
| T+30…90 | `power-supervisor.sh` | `elapsed < POWER_STABLE_TIME_HIGH` | — | Stability wait |
| T+90 | `power-supervisor.sh` | `is_day_time` | — | Continue |
| T+90 | `power-supervisor.sh` | `charge >= MIN_START_BATTERY` | — | Continue |
| T+90 | `power-supervisor.sh` | `comm_status != bad` | — | Continue |
| T+90 | `power-supervisor.sh` | device active? attempts? cooldown? | — | Send WOL |
| T+90+ | `power-supervisor.sh` | all active? exhausted? | clear `power_restored_at` | Close session |

---

# Scenario E — ONLINE (night)

**Goal:** Never auto‑wake at night.

| Time | Actor / File | Evaluates | Writes / Forwards | Action |
| --- | --- | --- | --- | --- |
| T+0 | `ups-event-writer.sh` | `online` | `power_restored_at=now` | Persist |
| T+30… | `power-supervisor.sh` | `!is_day_time` | — | Skip auto‑wake |

---

# Scenario F — COMMBAD / COMMFAULT (server)

**Goal:** Log + wall + block auto‑wake.

| Time | Actor / File | Evaluates | Writes / Forwards | Action |
| --- | --- | --- | --- | --- |
| T+0 | `ups-event-writer.sh` | commbad/commfault | `comm_status=bad` | Persist |
| T+0… | `power-supervisor.sh` | `comm_status=bad` | — | Log WARN (throttled) |
| T+0… | `power-supervisor.sh` | `COMM_WALL_INTERVAL` | — | `wall` (throttled) |
| any | `power-supervisor.sh` | `comm_status=bad` | — | Block auto‑wake |

---

# Scenario G — COMMBAD / COMMFAULT (client)

**Goal:** Safety shutdown if comm loss persists.

| Time | Actor / File | Evaluates | Writes / Forwards | Action |
| --- | --- | --- | --- | --- |
| T+0 | `upssched.conf` (client) | `COMMBAD` | start timer | start `commfault_shutdown` |
| T+0…1800 | `ups_event.sh` | timer expired? | — | wait |
| T+1800 | `ups_event.sh` | `TIMEREXPIRED` | — | `shutdown -h now` |
| T+any | `COMMOK` | — | cancel timer | abort shutdown |

---

# Scenario H — COOL DOWN & DUPLICATES

**Goal:** Avoid repeated shutdown / wake attempts.

| Condition | Where | Effect |
| --- | --- | --- |
| Shutdown requested too soon | `shutdown_sequence()` | Blocked by `SHUTDOWN_COOLDOWN` |
| WOL attempt too soon | `handle_power_restored()` | Blocked by per‑device cooldown |
| Power events flap | `resolve_power_state()` | Resolved by timestamp |


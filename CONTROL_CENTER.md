# MAGMA Control Center

## Scope

Internal technical backoffice for MAGMA/Foresight. It is not the customer admin
dashboard. Route root: `/control-center`.

MVP pages:

- Overview
- Devices
- Device Detail
- Events
- Diagnostics

Future navigation slots: Test Center, Configuration, Firmware, Analytics.

## Authorization

The Control Center uses the existing Supabase Auth flow and the existing
`public.profiles.role` authorization model. The role `internal_admin` is added
to `profiles.role`.

The account `foresightmem@gmail.com` is assigned to `internal_admin` by the
migration only if the Supabase Auth user already exists. No password is stored
in code, migrations, Edge Functions, or env files.

If the Auth user does not exist yet, create it from Supabase Auth admin tools,
set its password there, then insert/update the matching profile:

```sql
update public.profiles
set role = 'internal_admin'
where id = (
  select id from auth.users where lower(email) = 'foresightmem@gmail.com'
);
```

Frontend guard:

- login redirects `internal_admin` to `/control-center`;
- direct `/control-center` access checks the DB-backed role;
- internal admins are redirected away from legacy operator/admin areas.

Backend guard:

- Control Center tables have RLS enabled;
- direct reads are only visible to `internal_admin`;
- command creation is only available through
  `create_control_center_device_command`;
- RPCs re-check `control_center_is_internal_admin()`;
- client-provided roles are never trusted.

## Data Model

Reused existing core tables:

- `profiles`
- `clients`
- `sites`
- `machines`
- `machine_consumables`
- `refills`
- `tickets`
- `ticket_events`

Control Center/device tables:

- `devices`: physical device identity and machine link.
- `device_status`: latest observed status, firmware/app versions, sensor JSON.
- `device_counters_bucket`: telemetry buckets used by device telemetry.
- `device_events`: technical events/logs for device/backend/app correlation.
- `ble_sessions`: observed BLE sessions from app/backend flows.
- `device_commands`: asynchronous command queue and audit trail.

Important indexes cover device/time, event type/time, severity/time,
BLE device/time, and command device/status.

## Device Health

Device health is centralized in both:

- DB function `control_center_device_health`;
- Dart domain helper `calculateDeviceHealth`.

States:

- `healthy`
- `warning`
- `degraded`
- `offline`
- `never_connected`

Default MVP thresholds:

- never connected: no observed contact/event/BLE session;
- offline: last observed contact older than 7 days;
- degraded: `health_hint = degraded` or at least 3 error/critical events in
  the last 24 hours;
- warning: `health_hint = warning`, warning events, or missing/invalid/required
  calibration;
- healthy: no previous condition.

Cloud online state is never inferred as a direct connection. MAGMA devices are
treated as observed through app/device syncs.

## Event Model

`device_events` stores technical events with:

- timestamp;
- severity: `info`, `warning`, `error`, `critical`;
- device/machine/operator correlation;
- source;
- firmware/app version;
- JSON payload.

The Event Explorer currently reads through `get_control_center_events` with a
bounded limit. Future server-side pagination can extend the same RPC surface.

## Commands

Command architecture is asynchronous:

```text
Control Center
  -> Supabase device_commands
  -> operator app or device poll
  -> ESP32
  -> app/device acknowledgement
  -> Supabase
  -> Control Center
```

The UI must display queued states as waiting for app/device poll, not as direct
sending.

Current supported firmware downlink:

- `set_products`

This is a configuration write, not a read-only diagnostic. It is exposed with a
fixed payload from the Diagnostics page and is created only through the
allowlisted RPC. Unsupported commands are displayed as unsupported and are not
sent arbitrarily.

## Firmware Analysis

Firmware repository: `ic-01-firwmare`.

Current firmware:

- ESP32 Arduino/PlatformIO;
- firmware version: `0.1.0`;
- sensors: LDR, INMP441 I2S microphone, MPU6050 accelerometer/gyroscope;
- Wi-Fi telemetry with HMAC headers;
- manual serial commands for calibration/status;
- HTTP command polling via `device_commands`;
- supported downlink command: `set_products`.

BLE diagnostics are not implemented in the firmware source currently checked
in. Flutter has calibration BLE protocol scaffolding, but the Control Center
does not assume direct browser/desktop BLE access.

## Development

Apply migration locally:

```sh
supabase migration up
```

Run Flutter checks:

```sh
flutter analyze
flutter test
```

Manual route smoke test:

1. Sign in through `/login` with a Supabase Auth user whose profile role is
   `internal_admin`.
2. Confirm redirect to `/control-center`.
3. Open Devices, Device Detail, Events, Diagnostics.
4. Confirm a normal `admin`, `technician`, or `refill_operator` cannot open
   `/control-center`.
5. In Diagnostics, create only the supported `set_products` command and verify
   it appears as queued/waiting.

## Future Work

- Add app-side BLE session logging into `ble_sessions`.
- Add structured calibration session sync.
- Add firmware read-only diagnostic commands.
- Add firmware version catalog for outdated firmware KPI.
- Add Edge Function health instrumentation.
- Add server-side cursor pagination to events/devices when fleet size grows.

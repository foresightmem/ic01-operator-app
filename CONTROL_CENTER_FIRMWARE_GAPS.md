# Control Center Firmware Gaps

## GAP-001 - BLE diagnostic service

Current state:
The checked firmware does not implement BLE advertising, GATT services,
characteristics, pairing, or command handling.

Required behavior:
Expose a secure maintenance BLE service only when a physical or local
maintenance condition is active.

Suggested BLE command:
Use the existing Flutter IC01 service UUIDs if confirmed:
`9B7E0001-5A3C-4F3B-9D0E-1C0100000001`.

Expected request:
JSON command messages with request IDs.

Expected response:
Machine-readable event/status JSON with sequence and terminal states.

Priority:
High

## GAP-002 - Read-only device info command

Current state:
Firmware exposes `kDeviceId` and `kFirmwareVersion` internally and in
telemetry, but not through a local diagnostic command usable by Control Center.

Required behavior:
Support `get_device_info` with device ID, firmware version, hardware revision,
protocol version, supported sensors, and supported commands.

Suggested BLE command:
`get_device_info`

Expected request:
`{"command":"get_device_info","request_id":"uuid"}`

Expected response:
`{"type":"device.info","device_id":"...","fw_version":"0.1.0","protocol_version":1,"supported_commands":[...]}`

Priority:
High

## GAP-003 - Read sensor snapshot commands

Current state:
Firmware reads LDR, microphone features, accelerometer, and gyroscope, but does
not expose raw/processed snapshots through a supported remote diagnostic
command.

Required behavior:
Expose read-only commands for accelerometer/gyro, light sensor, and microphone
level/features.

Suggested BLE commands:
`read_accelerometer`, `read_light_sensor`, `read_microphone_level`

Expected request:
`{"command":"read_accelerometer","request_id":"uuid"}`

Expected response:
Include processed values. Include raw values only where firmware really has
them available.

Priority:
High

## GAP-004 - Calibration state query

Current state:
Calibration exists via serial commands and NVS, but status/result is not exposed
as a structured diagnostic response.

Required behavior:
Expose `get_calibration` with profile validity, timestamps if available,
mode/profile coverage, and LDR calibration state.

Suggested BLE command:
`get_calibration`

Expected request:
`{"command":"get_calibration","request_id":"uuid"}`

Expected response:
Structured JSON for mic, vibration, threshold, and LDR calibration.

Priority:
High

## GAP-005 - Self-test command

Current state:
There is no structured `run_self_test` command.

Required behavior:
Run bounded read-only checks for sensor availability, NVS profile validity,
door state, and telemetry configuration without changing calibration.

Suggested BLE command:
`run_self_test`

Expected request:
`{"command":"run_self_test","request_id":"uuid"}`

Expected response:
`{"type":"self_test.result","status":"ok|warning|failed","checks":[...]}`

Priority:
Medium

## GAP-006 - Command status vocabulary alignment

Current state:
Firmware sends `ack` or `failed` to the HTTP command function. The Control
Center queue uses richer states such as `queued`, `delivered_to_app`,
`completed`, and `unsupported`.

Required behavior:
Adopt or document a versioned status mapping in firmware/app protocol.

Suggested BLE command:
Not a device command; protocol contract update.

Expected request:
N/A

Expected response:
N/A

Priority:
Medium

## GAP-007 - Secure provisioning and secrets

Current state:
Wi-Fi SSID/password and `kDeviceSecret` are hardcoded in firmware config.

Required behavior:
Provision secrets outside source control and support rotation without firmware
edits.

Suggested BLE command:
Do not implement arbitrary config writes in the MVP. Design a separate secure
provisioning flow.

Expected request:
N/A

Expected response:
N/A

Priority:
High

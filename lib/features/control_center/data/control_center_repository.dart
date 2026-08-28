import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/device_health.dart';

class ControlCenterRepository {
  ControlCenterRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<ControlCenterOverview> loadOverview() async {
    final data = await _client.rpc('get_control_center_overview');
    return ControlCenterOverview.fromMap(_asMap(data));
  }

  Future<List<ControlCenterDevice>> loadDevices() async {
    final data = await _client.rpc('get_control_center_devices');
    return _asList(data)
        .map((row) => ControlCenterDevice.fromMap(_asMap(row)))
        .toList(growable: false);
  }

  Future<ControlCenterDeviceDetail> loadDeviceDetail(String deviceId) async {
    final data = await _client.rpc(
      'get_control_center_device_detail',
      params: {'p_device_id': deviceId},
    );
    return ControlCenterDeviceDetail.fromMap(_asMap(data));
  }

  Future<List<ControlCenterEvent>> loadEvents({
    String? deviceId,
    String? severity,
    String? eventType,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final data = await _client.rpc(
      'get_control_center_events',
      params: {
        'p_limit': limit,
        'p_device_id': _blankToNull(deviceId),
        'p_severity': _blankToNull(severity),
        'p_event_type': _blankToNull(eventType),
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
      },
    );
    return _asList(data)
        .map((row) => ControlCenterEvent.fromMap(_asMap(row)))
        .toList(growable: false);
  }

  Future<List<SupportedCommand>> loadSupportedCommands() async {
    final data = await _client.rpc('control_center_supported_commands');
    return _asList(data)
        .map((row) => SupportedCommand.fromMap(_asMap(row)))
        .toList(growable: false);
  }

  Future<CommandJob> createSetProductsCommand(String deviceId) async {
    final data = await _client.rpc(
      'create_control_center_device_command',
      params: {
        'p_device_id': deviceId,
        'p_command': 'set_products',
        'p_payload': {
          'count': 3,
          'names': ['coffee', 'cappuccino', 'powder_drink'],
        },
      },
    );
    return CommandJob.fromMap(_asMap(data));
  }
}

class ControlCenterOverview {
  const ControlCenterOverview({
    required this.fleetHealth,
    required this.systemHealth,
    required this.attentionRequired,
    required this.latestEvents,
    required this.notAvailable,
  });

  final FleetHealth fleetHealth;
  final Map<String, dynamic> systemHealth;
  final List<ControlCenterDevice> attentionRequired;
  final List<ControlCenterEvent> latestEvents;
  final List<String> notAvailable;

  factory ControlCenterOverview.fromMap(Map<String, dynamic> map) {
    return ControlCenterOverview(
      fleetHealth: FleetHealth.fromMap(_asMap(map['fleet_health'])),
      systemHealth: _asMap(map['system_health']),
      attentionRequired: _asList(map['attention_required'])
          .map((row) => ControlCenterDevice.fromMap(_asMap(row)))
          .toList(growable: false),
      latestEvents: _asList(map['latest_events'])
          .map((row) => ControlCenterEvent.fromMap(_asMap(row)))
          .toList(growable: false),
      notAvailable: _asList(
        map['not_available'],
      ).map((value) => value.toString()).toList(growable: false),
    );
  }
}

class FleetHealth {
  const FleetHealth({
    required this.total,
    required this.healthy,
    required this.warning,
    required this.degraded,
    required this.offline,
    required this.neverConnected,
    required this.calibrationMissing,
    required this.firmwareOutdated,
  });

  final int total;
  final int healthy;
  final int warning;
  final int degraded;
  final int offline;
  final int neverConnected;
  final int calibrationMissing;
  final int? firmwareOutdated;

  factory FleetHealth.fromMap(Map<String, dynamic> map) {
    return FleetHealth(
      total: _asInt(map['total']),
      healthy: _asInt(map['healthy']),
      warning: _asInt(map['warning']),
      degraded: _asInt(map['degraded']),
      offline: _asInt(map['offline']),
      neverConnected: _asInt(map['never_connected']),
      calibrationMissing: _asInt(map['calibration_missing']),
      firmwareOutdated: _asNullableInt(map['firmware_outdated']),
    );
  }
}

class ControlCenterDevice {
  const ControlCenterDevice({
    required this.id,
    required this.deviceId,
    required this.serialNumber,
    required this.hardwareRevision,
    required this.machineId,
    required this.machineCode,
    required this.clientName,
    required this.siteName,
    required this.siteCity,
    required this.firmwareVersion,
    required this.appVersion,
    required this.calibrationState,
    required this.lastOperatorName,
    required this.lastContactAt,
    required this.lastEventAt,
    required this.errorCount,
    required this.warningCount,
    required this.bleAttempts24h,
    required this.bleSuccess24h,
    required this.health,
  });

  final String id;
  final String deviceId;
  final String? serialNumber;
  final String? hardwareRevision;
  final String? machineId;
  final String? machineCode;
  final String? clientName;
  final String? siteName;
  final String? siteCity;
  final String? firmwareVersion;
  final String? appVersion;
  final String? calibrationState;
  final String? lastOperatorName;
  final DateTime? lastContactAt;
  final DateTime? lastEventAt;
  final int errorCount;
  final int warningCount;
  final int bleAttempts24h;
  final int bleSuccess24h;
  final DeviceHealth health;

  bool get calibrationMissing {
    final value = calibrationState?.trim().toLowerCase();
    return value == 'missing' || value == 'invalid' || value == 'required';
  }

  factory ControlCenterDevice.fromMap(Map<String, dynamic> map) {
    return ControlCenterDevice(
      id: _asString(map['id']),
      deviceId: _asString(map['device_id']),
      serialNumber: _asNullableString(map['serial_number']),
      hardwareRevision: _asNullableString(map['hardware_revision']),
      machineId: _asNullableString(map['machine_id']),
      machineCode: _asNullableString(map['machine_code']),
      clientName: _asNullableString(map['client_name']),
      siteName: _asNullableString(map['site_name']),
      siteCity: _asNullableString(map['site_city']),
      firmwareVersion: _asNullableString(map['fw_version']),
      appVersion: _asNullableString(map['app_version']),
      calibrationState: _asNullableString(map['calibration_state']),
      lastOperatorName: _asNullableString(map['last_operator_name']),
      lastContactAt: _asDate(map['last_contact_at']),
      lastEventAt: _asDate(map['last_event_at']),
      errorCount: _asInt(map['error_count']),
      warningCount: _asInt(map['warning_count']),
      bleAttempts24h: _asInt(map['ble_attempts_24h']),
      bleSuccess24h: _asInt(map['ble_success_24h']),
      health: DeviceHealth.fromValue(map['health'] as String?),
    );
  }
}

class ControlCenterDeviceDetail {
  const ControlCenterDeviceDetail({
    required this.device,
    required this.status,
    required this.latestSensorData,
    required this.bleSessions,
    required this.events,
    required this.commands,
    required this.error,
  });

  final ControlCenterDevice? device;
  final Map<String, dynamic> status;
  final Map<String, dynamic> latestSensorData;
  final List<BleSession> bleSessions;
  final List<ControlCenterEvent> events;
  final List<CommandJob> commands;
  final String? error;

  factory ControlCenterDeviceDetail.fromMap(Map<String, dynamic> map) {
    final error = map['error'] as String?;
    return ControlCenterDeviceDetail(
      error: error,
      device: error == null
          ? ControlCenterDevice.fromMap(_asMap(map['device']))
          : null,
      status: _asMap(map['status']),
      latestSensorData: _asMap(map['latest_sensor_data']),
      bleSessions: _asList(
        map['ble_sessions'],
      ).map((row) => BleSession.fromMap(_asMap(row))).toList(growable: false),
      events: _asList(map['events'])
          .map((row) => ControlCenterEvent.fromMap(_asMap(row)))
          .toList(growable: false),
      commands: _asList(
        map['commands'],
      ).map((row) => CommandJob.fromMap(_asMap(row))).toList(growable: false),
    );
  }
}

class ControlCenterEvent {
  const ControlCenterEvent({
    required this.id,
    required this.createdAt,
    required this.severity,
    required this.eventType,
    required this.summary,
    required this.source,
    required this.deviceId,
    required this.machineCode,
    required this.clientName,
    required this.operatorName,
    required this.firmwareVersion,
    required this.appVersion,
    required this.payload,
  });

  final String id;
  final DateTime? createdAt;
  final String severity;
  final String eventType;
  final String? summary;
  final String source;
  final String? deviceId;
  final String? machineCode;
  final String? clientName;
  final String? operatorName;
  final String? firmwareVersion;
  final String? appVersion;
  final Map<String, dynamic> payload;

  factory ControlCenterEvent.fromMap(Map<String, dynamic> map) {
    return ControlCenterEvent(
      id: _asString(map['id']),
      createdAt: _asDate(map['created_at']),
      severity: _asString(map['severity'], fallback: 'info'),
      eventType: _asString(map['event_type'], fallback: 'event'),
      summary: _asNullableString(map['summary']),
      source: _asString(map['source'], fallback: 'backend'),
      deviceId: _asNullableString(map['device_id']),
      machineCode: _asNullableString(map['machine_code']),
      clientName: _asNullableString(map['client_name']),
      operatorName: _asNullableString(map['operator_name']),
      firmwareVersion: _asNullableString(map['firmware_version']),
      appVersion: _asNullableString(map['app_version']),
      payload: _asMap(map['payload']),
    );
  }
}

class BleSession {
  const BleSession({
    required this.startedAt,
    required this.completedAt,
    required this.disconnectedAt,
    required this.result,
    required this.disconnectReason,
    required this.errorCode,
    required this.durationMs,
    required this.appVersion,
    required this.operatorName,
  });

  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? disconnectedAt;
  final String result;
  final String? disconnectReason;
  final String? errorCode;
  final int? durationMs;
  final String? appVersion;
  final String? operatorName;

  factory BleSession.fromMap(Map<String, dynamic> map) {
    return BleSession(
      startedAt: _asDate(map['started_at']),
      completedAt: _asDate(map['completed_at']),
      disconnectedAt: _asDate(map['disconnected_at']),
      result: _asString(map['result'], fallback: 'unknown'),
      disconnectReason: _asNullableString(map['disconnect_reason']),
      errorCode: _asNullableString(map['error_code']),
      durationMs: _asNullableInt(map['duration_ms']),
      appVersion: _asNullableString(map['app_version']),
      operatorName: _asNullableString(map['operator_name']),
    );
  }
}

class SupportedCommand {
  const SupportedCommand({
    required this.command,
    required this.label,
    required this.supported,
    required this.readOnly,
    required this.requiresPayload,
    required this.description,
  });

  final String command;
  final String label;
  final bool supported;
  final bool readOnly;
  final bool requiresPayload;
  final String? description;

  factory SupportedCommand.fromMap(Map<String, dynamic> map) {
    return SupportedCommand(
      command: _asString(map['command']),
      label: _asString(map['label'], fallback: _asString(map['command'])),
      supported: map['supported'] == true,
      readOnly: map['read_only'] == true,
      requiresPayload: map['requires_payload'] == true,
      description: _asNullableString(map['description']),
    );
  }
}

class CommandJob {
  const CommandJob({
    required this.id,
    required this.command,
    required this.status,
    required this.requestedAt,
    required this.deliveredAt,
    required this.completedAt,
    required this.error,
    required this.payload,
  });

  final String id;
  final String command;
  final String status;
  final DateTime? requestedAt;
  final DateTime? deliveredAt;
  final DateTime? completedAt;
  final String? error;
  final Map<String, dynamic> payload;

  factory CommandJob.fromMap(Map<String, dynamic> map) {
    return CommandJob(
      id: _asString(map['id']),
      command: _asString(map['command']),
      status: _asString(map['status'], fallback: 'queued'),
      requestedAt: _asDate(map['requested_at']),
      deliveredAt: _asDate(map['delivered_at']),
      completedAt: _asDate(map['completed_at']),
      error: _asNullableString(map['error']),
      payload: _asMap(map['payload']),
    );
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, val) => MapEntry('$key', val));
  return <String, dynamic>{};
}

List<dynamic> _asList(Object? value) {
  if (value is List) return value;
  return const <dynamic>[];
}

String _asString(Object? value, {String fallback = ''}) {
  final string = value?.toString() ?? '';
  return string.isEmpty ? fallback : string;
}

String? _asNullableString(Object? value) {
  final string = value?.toString().trim() ?? '';
  return string.isEmpty ? null : string;
}

int _asInt(Object? value) => _asNullableInt(value) ?? 0;

int? _asNullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _asDate(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  return null;
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

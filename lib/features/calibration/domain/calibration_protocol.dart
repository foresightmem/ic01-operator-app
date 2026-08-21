import 'dart:convert';

enum CalibrationMode {
  hot('hot', 'coffee', 'Caldo'),
  cold('cold', 'idle', 'Freddo');

  const CalibrationMode(this.commandValue, this.profileSet, this.label);

  final String commandValue;
  final String profileSet;
  final String label;

  static CalibrationMode fromDb(String? value) {
    switch (value) {
      case 'cold':
        return CalibrationMode.cold;
      case 'hot':
      default:
        return CalibrationMode.hot;
    }
  }
}

enum CalibrationBleEventType { status, result, error, unknown }

enum CalibrationErrorCode {
  maintenanceRequired('maintenance_required'),
  unsupportedMode('unsupported_mode'),
  doorOpen('door_open'),
  busy('busy'),
  timeout('timeout'),
  storageError('storage_error'),
  invalidProfile('invalid_profile'),
  unsupportedCommand('unsupported_command'),
  invalidJson('invalid_json'),
  unknown('unknown');

  const CalibrationErrorCode(this.wireValue);

  final String wireValue;

  static CalibrationErrorCode fromWire(String? value) {
    for (final code in CalibrationErrorCode.values) {
      if (code.wireValue == value) return code;
    }
    return CalibrationErrorCode.unknown;
  }
}

class Ic01DeviceInfo {
  const Ic01DeviceInfo({
    required this.deviceId,
    required this.fwVersion,
    required this.protocolVersion,
    required this.maintenanceEnabled,
    required this.raw,
  });

  final String deviceId;
  final String? fwVersion;
  final int? protocolVersion;
  final bool maintenanceEnabled;
  final Map<String, dynamic> raw;

  factory Ic01DeviceInfo.fromJsonString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Device info JSON must be an object.');
    }
    return Ic01DeviceInfo.fromMap(decoded);
  }

  factory Ic01DeviceInfo.fromMap(Map<String, dynamic> map) {
    return Ic01DeviceInfo(
      deviceId: (map['device_id'] as String?) ?? '',
      fwVersion:
          (map['fw_version'] as String?) ??
          (map['firmware_version'] as String?),
      protocolVersion: _asInt(map['protocol_version']),
      maintenanceEnabled: (map['maintenance_enabled'] as bool?) ?? false,
      raw: Map<String, dynamic>.unmodifiable(map),
    );
  }
}

class CalibrationBleEvent {
  const CalibrationBleEvent({
    required this.type,
    required this.rawType,
    required this.rawStatus,
    required this.seq,
    required this.requestId,
    required this.sessionId,
    required this.progress,
    required this.message,
    required this.errorCode,
    required this.retryable,
    required this.recoverAction,
    required this.committed,
    required this.profileValid,
    required this.raw,
  });

  final CalibrationBleEventType type;
  final String rawType;
  final String? rawStatus;
  final int? seq;
  final String? requestId;
  final String? sessionId;
  final double progress;
  final String? message;
  final CalibrationErrorCode? errorCode;
  final bool? retryable;
  final String? recoverAction;
  final bool? committed;
  final bool? profileValid;
  final Map<String, dynamic> raw;

  bool get isTerminal =>
      type == CalibrationBleEventType.result ||
      rawStatus == 'completed' ||
      rawStatus == 'failed' ||
      rawStatus == 'cancelled';

  bool get isSuccess =>
      rawStatus == 'completed' ||
      (type == CalibrationBleEventType.result && rawStatus == 'ok');

  bool get isCancelled => rawStatus == 'cancelled';

  factory CalibrationBleEvent.fromJsonString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Calibration event JSON must be an object.');
    }
    return CalibrationBleEvent.fromMap(decoded);
  }

  factory CalibrationBleEvent.fromMap(Map<String, dynamic> map) {
    final rawType = (map['type'] as String?) ?? '';
    final eventType = switch (rawType) {
      'cal.status' => CalibrationBleEventType.status,
      'cal.result' => CalibrationBleEventType.result,
      'cal.error' => CalibrationBleEventType.error,
      _ => CalibrationBleEventType.unknown,
    };

    final errorValue = map['error'] as String?;
    return CalibrationBleEvent(
      type: eventType,
      rawType: rawType,
      rawStatus: map['status'] as String?,
      seq: _asInt(map['seq']),
      requestId: map['request_id'] as String?,
      sessionId: map['session_id'] as String?,
      progress: _asDouble(map['progress'])?.clamp(0.0, 1.0) ?? 0,
      message: map['message'] as String?,
      errorCode: errorValue == null
          ? null
          : CalibrationErrorCode.fromWire(errorValue),
      retryable: map['retryable'] as bool?,
      recoverAction: map['recover_action'] as String?,
      committed: map['committed'] as bool?,
      profileValid: map['profile_valid'] as bool?,
      raw: Map<String, dynamic>.unmodifiable(map),
    );
  }
}

class CalibrationCommandCodec {
  const CalibrationCommandCodec._();

  static String info({required String requestId}) {
    return jsonEncode({'command': 'info', 'request_id': requestId});
  }

  static String status({required String requestId, required String sessionId}) {
    return jsonEncode({
      'command': 'cal.status',
      'request_id': requestId,
      'session_id': sessionId,
    });
  }

  static String start({
    required String requestId,
    required String sessionId,
    required CalibrationMode mode,
  }) {
    return jsonEncode({
      'command': 'cal.start',
      'request_id': requestId,
      'session_id': sessionId,
      'mode': mode.commandValue,
      'profile_set': mode.profileSet,
    });
  }

  static String cancel({required String requestId, required String sessionId}) {
    return jsonEncode({
      'command': 'cal.cancel',
      'request_id': requestId,
      'session_id': sessionId,
    });
  }
}

String calibrationErrorLabel(CalibrationErrorCode? code) {
  switch (code) {
    case CalibrationErrorCode.maintenanceRequired:
      return 'Abilita la finestra maintenance e riprova.';
    case CalibrationErrorCode.unsupportedMode:
      return 'Modalita di calibrazione non supportata dal firmware.';
    case CalibrationErrorCode.doorOpen:
      return 'Chiudi la porta della macchina e riprova.';
    case CalibrationErrorCode.busy:
      return 'Il dispositivo sta gia eseguendo una calibrazione.';
    case CalibrationErrorCode.timeout:
      return 'La calibrazione e andata in timeout.';
    case CalibrationErrorCode.storageError:
      return 'Il firmware non ha salvato il profilo.';
    case CalibrationErrorCode.invalidProfile:
      return 'Profilo non valido: controlla microfono/sensori e riprova.';
    case CalibrationErrorCode.unsupportedCommand:
      return 'Comando non supportato dal firmware.';
    case CalibrationErrorCode.invalidJson:
      return 'Payload non valido inviato al firmware.';
    case CalibrationErrorCode.unknown:
    case null:
      return 'Errore di calibrazione non riconosciuto.';
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? int.tryParse(value.split('.').first);
  }
  return null;
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

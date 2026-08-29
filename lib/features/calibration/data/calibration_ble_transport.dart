import '../domain/calibration_protocol.dart';

class CalibrationBleDevice {
  const CalibrationBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;

  String get displayName => name.trim().isEmpty ? id : name;
}

enum CalibrationConnectionState { disconnected, connecting, connected }

abstract class CalibrationBleTransport {
  Stream<CalibrationBleEvent> get events;
  Stream<CalibrationConnectionState> get connectionState;

  Future<List<CalibrationBleDevice>> scan({
    Duration timeout = const Duration(seconds: 6),
  });

  Future<void> connect(CalibrationBleDevice device);

  Future<void> disconnect();

  Future<Ic01DeviceInfo> readInfo();

  Future<void> sendCommand(String commandJson);

  void dispose();
}

class CalibrationTransportException implements Exception {
  const CalibrationTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

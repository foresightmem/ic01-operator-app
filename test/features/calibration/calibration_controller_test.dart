import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ic01_operator_app/features/calibration/application/calibration_controller.dart';
import 'package:ic01_operator_app/features/calibration/application/calibration_permissions.dart';
import 'package:ic01_operator_app/features/calibration/data/calibration_ble_transport.dart';
import 'package:ic01_operator_app/features/calibration/domain/calibration_protocol.dart';

void main() {
  test(
    'blocks start when maintenance is disabled, then starts after refresh',
    () async {
      final transport = FakeCalibrationBleTransport(
        info: _info(maintenanceEnabled: false),
      );
      final controller = _controller(transport);

      await controller.scan();
      expect(controller.state.phase, CalibrationPhase.maintenanceRequired);

      transport.info = _info(maintenanceEnabled: true);
      await controller.refreshInfo();
      expect(controller.state.phase, CalibrationPhase.ready);

      await controller.start();
      expect(controller.state.phase, CalibrationPhase.running);

      final command = jsonDecode(transport.sentCommands.single);
      expect(command['command'], 'cal.start');
      expect(command['mode'], 'hot');
      expect(command['profile_set'], 'coffee');

      controller.dispose();
      transport.dispose();
    },
  );

  test(
    'continues with debug warning when backend has no device association',
    () {
      final transport = FakeCalibrationBleTransport(info: _info());
      final controller = CalibrationController(
        machine: const CalibrationMachineContext(
          machineId: 'machine-1',
          machineCode: 'IC01-1',
          mode: CalibrationMode.hot,
          expectedDeviceId: null,
        ),
        transport: transport,
        permissions: const FakePermissions(),
      );

      expect(controller.state.warningMessage, contains('Debug'));

      controller.dispose();
      transport.dispose();
    },
  );

  test('fails on device identity mismatch', () async {
    final transport = FakeCalibrationBleTransport(
      info: _info(deviceId: 'ic01-wrong'),
    );
    final controller = _controller(transport);

    await controller.scan();

    expect(controller.state.phase, CalibrationPhase.failed);
    expect(controller.state.errorMessage, contains('Device non associato'));

    controller.dispose();
    transport.dispose();
  });

  test('maps invalid_profile error to failed state', () async {
    final transport = FakeCalibrationBleTransport(info: _info());
    final controller = _controller(transport);

    await controller.scan();
    await controller.start();

    transport.emit(
      CalibrationBleEvent.fromMap({
        'type': 'cal.result',
        'status': 'failed',
        'session_id': _lastSessionId(transport),
        'progress': 0,
        'message': 'Profile validation failed',
        'error': 'invalid_profile',
        'committed': false,
        'profile_valid': false,
      }),
    );
    await _flushMicrotasks();

    expect(controller.state.phase, CalibrationPhase.failed);
    expect(controller.state.errorMessage, 'Profile validation failed');
    expect(
      controller.state.lastEvent?.errorCode,
      CalibrationErrorCode.invalidProfile,
    );

    controller.dispose();
    transport.dispose();
  });

  test('cancel command drives cancelled terminal state', () async {
    final transport = FakeCalibrationBleTransport(info: _info());
    final controller = _controller(transport);

    await controller.scan();
    await controller.start();
    await controller.cancel();

    expect(jsonDecode(transport.sentCommands.last)['command'], 'cal.cancel');

    transport.emit(
      CalibrationBleEvent.fromMap({
        'type': 'cal.status',
        'status': 'cancelled',
        'session_id': _lastSessionId(transport),
        'progress': 0,
        'message': 'calibration_cancelled',
      }),
    );
    await _flushMicrotasks();

    expect(controller.state.phase, CalibrationPhase.cancelled);

    controller.dispose();
    transport.dispose();
  });

  test('disconnects previous GATT session before scanning again', () async {
    final transport = FakeCalibrationBleTransport(info: _info());
    final controller = _controller(transport);

    await controller.scan();
    await controller.start();

    transport.emit(
      CalibrationBleEvent.fromMap({
        'type': 'cal.result',
        'status': 'completed',
        'session_id': _lastSessionId(transport),
        'progress': 1,
      }),
    );
    await _flushMicrotasks();

    expect(controller.state.phase, CalibrationPhase.completed);

    await controller.scan();

    expect(transport.disconnectCount, 1);

    controller.dispose();
    transport.dispose();
  });

  test('can start again after terminal result while still connected', () async {
    final transport = FakeCalibrationBleTransport(info: _info());
    final controller = _controller(transport);

    await controller.scan();
    await controller.start();

    transport.emit(
      CalibrationBleEvent.fromMap({
        'type': 'cal.result',
        'status': 'completed',
        'session_id': _lastSessionId(transport),
        'progress': 1,
      }),
    );
    await _flushMicrotasks();

    expect(controller.state.phase, CalibrationPhase.completed);
    expect(controller.state.canStart, isTrue);

    await controller.start();

    final startCommands = transport.sentCommands
        .map((command) => jsonDecode(command) as Map<String, dynamic>)
        .where((command) => command['command'] == 'cal.start')
        .toList();
    expect(startCommands, hasLength(2));
    expect(transport.disconnectCount, 0);

    controller.dispose();
    transport.dispose();
  });
}

CalibrationController _controller(FakeCalibrationBleTransport transport) {
  return CalibrationController(
    machine: const CalibrationMachineContext(
      machineId: 'machine-1',
      machineCode: 'IC01-1',
      mode: CalibrationMode.hot,
      expectedDeviceId: 'ic01-dev-001',
    ),
    transport: transport,
    permissions: const FakePermissions(),
  );
}

Ic01DeviceInfo _info({
  String deviceId = 'ic01-dev-001',
  bool maintenanceEnabled = true,
}) {
  return Ic01DeviceInfo.fromMap({
    'device_id': deviceId,
    'fw_version': '0.1.0',
    'protocol_version': 1,
    'maintenance_enabled': maintenanceEnabled,
  });
}

String _lastSessionId(FakeCalibrationBleTransport transport) {
  final start = transport.sentCommands
      .map((command) => jsonDecode(command) as Map<String, dynamic>)
      .lastWhere((command) => command['command'] == 'cal.start');
  return start['session_id'] as String;
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

class FakePermissions implements CalibrationPermissionGateway {
  const FakePermissions();

  @override
  bool get isSupportedPlatform => true;

  @override
  Future<CalibrationPermissionStatus> ensurePermissions() async {
    return CalibrationPermissionStatus.granted;
  }
}

class FakeCalibrationBleTransport implements CalibrationBleTransport {
  FakeCalibrationBleTransport({required this.info});

  Ic01DeviceInfo info;
  List<CalibrationBleDevice> devices = const [
    CalibrationBleDevice(id: 'ble-1', name: 'IC01', rssi: -42),
  ];
  final sentCommands = <String>[];
  var disconnectCount = 0;

  final _events = StreamController<CalibrationBleEvent>.broadcast();
  final _connectionStates =
      StreamController<CalibrationConnectionState>.broadcast();

  @override
  Stream<CalibrationBleEvent> get events => _events.stream;

  @override
  Stream<CalibrationConnectionState> get connectionState =>
      _connectionStates.stream;

  @override
  Future<List<CalibrationBleDevice>> scan({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    return devices;
  }

  @override
  Future<void> connect(CalibrationBleDevice device) async {
    _connectionStates.add(CalibrationConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    _connectionStates.add(CalibrationConnectionState.disconnected);
  }

  @override
  Future<Ic01DeviceInfo> readInfo() async => info;

  @override
  Future<void> sendCommand(String commandJson) async {
    sentCommands.add(commandJson);
  }

  void emit(CalibrationBleEvent event) {
    _events.add(event);
  }

  @override
  void dispose() {
    _events.close();
    _connectionStates.close();
  }
}

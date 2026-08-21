import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/calibration_ble_transport.dart';
import '../domain/calibration_protocol.dart';
import '../domain/ic01_ble_constants.dart';
import 'calibration_permissions.dart';

enum CalibrationPhase {
  idle,
  unsupportedPlatform,
  permissionsRequired,
  scanning,
  noDevices,
  selectingDevice,
  connecting,
  verifyingIdentity,
  maintenanceRequired,
  ready,
  starting,
  running,
  cancelling,
  completed,
  cancelled,
  failed,
  disconnected,
}

class CalibrationMachineContext {
  const CalibrationMachineContext({
    required this.machineId,
    required this.machineCode,
    required this.mode,
    required this.expectedDeviceId,
    this.backendWarning,
  });

  final String machineId;
  final String machineCode;
  final CalibrationMode mode;
  final String? expectedDeviceId;
  final String? backendWarning;
}

class CalibrationControllerState {
  const CalibrationControllerState({
    required this.phase,
    required this.devices,
    required this.progress,
    required this.isConnected,
    this.selectedDevice,
    this.deviceInfo,
    this.lastEvent,
    this.errorMessage,
    this.warningMessage,
    this.requestId,
    this.sessionId,
  });

  const CalibrationControllerState.initial()
    : phase = CalibrationPhase.idle,
      devices = const [],
      progress = 0,
      isConnected = false,
      selectedDevice = null,
      deviceInfo = null,
      lastEvent = null,
      errorMessage = null,
      warningMessage = null,
      requestId = null,
      sessionId = null;

  final CalibrationPhase phase;
  final List<CalibrationBleDevice> devices;
  final bool isConnected;
  final CalibrationBleDevice? selectedDevice;
  final Ic01DeviceInfo? deviceInfo;
  final CalibrationBleEvent? lastEvent;
  final double progress;
  final String? errorMessage;
  final String? warningMessage;
  final String? requestId;
  final String? sessionId;

  bool get isBusy {
    return switch (phase) {
      CalibrationPhase.scanning ||
      CalibrationPhase.connecting ||
      CalibrationPhase.verifyingIdentity ||
      CalibrationPhase.starting ||
      CalibrationPhase.cancelling => true,
      _ => false,
    };
  }

  bool get canStart {
    if (phase == CalibrationPhase.ready) return true;
    final terminal = switch (phase) {
      CalibrationPhase.completed ||
      CalibrationPhase.failed ||
      CalibrationPhase.cancelled => true,
      _ => false,
    };
    return terminal && isConnected && (deviceInfo?.maintenanceEnabled ?? false);
  }

  bool get canCancel =>
      phase == CalibrationPhase.running || phase == CalibrationPhase.starting;

  CalibrationControllerState copyWith({
    CalibrationPhase? phase,
    List<CalibrationBleDevice>? devices,
    bool? isConnected,
    Object? selectedDevice = _unset,
    Object? deviceInfo = _unset,
    Object? lastEvent = _unset,
    double? progress,
    Object? errorMessage = _unset,
    Object? warningMessage = _unset,
    Object? requestId = _unset,
    Object? sessionId = _unset,
  }) {
    return CalibrationControllerState(
      phase: phase ?? this.phase,
      devices: devices ?? this.devices,
      isConnected: isConnected ?? this.isConnected,
      selectedDevice: identical(selectedDevice, _unset)
          ? this.selectedDevice
          : selectedDevice as CalibrationBleDevice?,
      deviceInfo: identical(deviceInfo, _unset)
          ? this.deviceInfo
          : deviceInfo as Ic01DeviceInfo?,
      lastEvent: identical(lastEvent, _unset)
          ? this.lastEvent
          : lastEvent as CalibrationBleEvent?,
      progress: progress ?? this.progress,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      warningMessage: identical(warningMessage, _unset)
          ? this.warningMessage
          : warningMessage as String?,
      requestId: identical(requestId, _unset)
          ? this.requestId
          : requestId as String?,
      sessionId: identical(sessionId, _unset)
          ? this.sessionId
          : sessionId as String?,
    );
  }
}

class CalibrationController extends ChangeNotifier {
  CalibrationController({
    required CalibrationMachineContext machine,
    required CalibrationBleTransport transport,
    required CalibrationPermissionGateway permissions,
    Uuid? uuid,
  }) : _machine = machine,
       _transport = transport,
       _permissions = permissions,
       _uuid = uuid ?? const Uuid() {
    _eventsSubscription = _transport.events.listen(_handleEvent);
    _connectionSubscription = _transport.connectionState.listen(
      _handleConnectionState,
    );

    final warning = machine.backendWarning ?? _debugIdentityWarning(machine);
    if (warning != null) {
      _state = _state.copyWith(warningMessage: warning);
    }
  }

  final CalibrationMachineContext _machine;
  final CalibrationBleTransport _transport;
  final CalibrationPermissionGateway _permissions;
  final Uuid _uuid;

  StreamSubscription<CalibrationBleEvent>? _eventsSubscription;
  StreamSubscription<CalibrationConnectionState>? _connectionSubscription;
  bool _disposed = false;

  CalibrationControllerState _state =
      const CalibrationControllerState.initial();

  CalibrationControllerState get state => _state;
  CalibrationMachineContext get machine => _machine;

  Future<void> scan() async {
    final permissionStatus = await _permissions.ensurePermissions();
    if (permissionStatus == CalibrationPermissionStatus.unsupportedPlatform) {
      _setState(
        _state.copyWith(
          phase: CalibrationPhase.unsupportedPlatform,
          errorMessage: 'La calibrazione BLE e disponibile solo su Android.',
        ),
      );
      return;
    }
    if (permissionStatus == CalibrationPermissionStatus.denied) {
      _setState(
        _state.copyWith(
          phase: CalibrationPhase.permissionsRequired,
          errorMessage:
              'Autorizza Bluetooth e posizione per cercare le macchine IC01.',
        ),
      );
      return;
    }

    if (_state.selectedDevice != null) {
      await _transport.disconnect();
    }

    _setState(
      _state.copyWith(
        phase: CalibrationPhase.scanning,
        devices: const [],
        selectedDevice: null,
        deviceInfo: null,
        lastEvent: null,
        progress: 0,
        errorMessage: null,
      ),
    );

    try {
      final devices = await _transport.scan();
      if (devices.isEmpty) {
        _setState(
          _state.copyWith(
            phase: CalibrationPhase.noDevices,
            devices: devices,
            errorMessage: 'Nessuna macchina IC01 trovata nelle vicinanze.',
          ),
        );
        return;
      }

      _setState(
        _state.copyWith(
          phase: devices.length == 1
              ? CalibrationPhase.scanning
              : CalibrationPhase.selectingDevice,
          devices: devices,
          errorMessage: null,
        ),
      );

      if (devices.length == 1) {
        await connect(devices.first);
      }
    } catch (error) {
      _fail('Scan BLE fallito: $error');
    }
  }

  Future<void> connect(CalibrationBleDevice device) async {
    _setState(
      _state.copyWith(
        phase: CalibrationPhase.connecting,
        selectedDevice: device,
        isConnected: false,
        errorMessage: null,
      ),
    );

    try {
      await _transport.connect(device);
      await refreshInfo();
    } catch (error) {
      _fail('Connessione BLE fallita: $error');
    }
  }

  Future<void> refreshInfo() async {
    _setState(
      _state.copyWith(
        phase: CalibrationPhase.verifyingIdentity,
        errorMessage: null,
      ),
    );

    try {
      final info = await _transport.readInfo();
      final identityError = _validateIdentity(info);
      if (identityError != null) {
        _setState(
          _state.copyWith(
            phase: CalibrationPhase.failed,
            deviceInfo: info,
            errorMessage: identityError,
          ),
        );
        return;
      }

      _setState(
        _state.copyWith(
          phase: info.maintenanceEnabled
              ? CalibrationPhase.ready
              : CalibrationPhase.maintenanceRequired,
          deviceInfo: info,
          progress: 0,
          errorMessage: info.maintenanceEnabled
              ? null
              : 'Abilita maintenance dal dispositivo e premi Rileggi.',
        ),
      );
    } catch (error) {
      _fail('Lettura info BLE fallita: $error');
    }
  }

  Future<void> start() async {
    final info = _state.deviceInfo;
    if (info == null || !info.maintenanceEnabled) {
      await refreshInfo();
      if (_state.phase != CalibrationPhase.ready) return;
    }

    final requestId = _uuid.v4();
    final sessionId = _uuid.v4();
    _setState(
      _state.copyWith(
        phase: CalibrationPhase.starting,
        requestId: requestId,
        sessionId: sessionId,
        progress: 0,
        errorMessage: null,
        lastEvent: null,
      ),
    );

    try {
      final command = CalibrationCommandCodec.start(
        requestId: requestId,
        sessionId: sessionId,
        mode: _machine.mode,
      );
      await _transport.sendCommand(command);
      _setState(_state.copyWith(phase: CalibrationPhase.running));
    } catch (error) {
      _fail('Avvio calibrazione fallito: $error');
    }
  }

  Future<void> requestStatus() async {
    final sessionId = _state.sessionId;
    if (sessionId == null) return;

    final requestId = _uuid.v4();
    try {
      await _transport.sendCommand(
        CalibrationCommandCodec.status(
          requestId: requestId,
          sessionId: sessionId,
        ),
      );
    } catch (error) {
      _fail('Richiesta stato fallita: $error');
    }
  }

  Future<void> cancel() async {
    final sessionId = _state.sessionId;
    if (sessionId == null) return;

    final requestId = _uuid.v4();
    _setState(
      _state.copyWith(
        phase: CalibrationPhase.cancelling,
        requestId: requestId,
        errorMessage: null,
      ),
    );

    try {
      await _transport.sendCommand(
        CalibrationCommandCodec.cancel(
          requestId: requestId,
          sessionId: sessionId,
        ),
      );
    } catch (error) {
      _fail('Cancel calibrazione fallito: $error');
    }
  }

  Future<void> reconnectAndRequestStatus() async {
    final selectedDevice = _state.selectedDevice;
    final sessionId = _state.sessionId;
    if (selectedDevice == null || sessionId == null) return;

    await connect(selectedDevice);
    await requestStatus();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_eventsSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());
    _transport.dispose();
    super.dispose();
  }

  void _handleEvent(CalibrationBleEvent event) {
    debugPrint(
      '[CAL event] phase=${_state.phase.name} type=${event.rawType} '
      'status=${event.rawStatus} seq=${event.seq} '
      'session=${event.sessionId} error=${event.errorCode?.wireValue}',
    );
    final activeSessionId = _state.sessionId;
    if (activeSessionId != null &&
        event.sessionId != null &&
        event.sessionId != activeSessionId) {
      debugPrint(
        '[CAL event ignored] activeSession=$activeSessionId '
        'eventSession=${event.sessionId}',
      );
      return;
    }

    if (event.type == CalibrationBleEventType.error) {
      _setState(
        _state.copyWith(
          phase: CalibrationPhase.failed,
          lastEvent: event,
          progress: event.progress,
          errorMessage: event.message ?? calibrationErrorLabel(event.errorCode),
        ),
      );
      return;
    }

    if (event.isCancelled) {
      _setState(
        _state.copyWith(
          phase: CalibrationPhase.cancelled,
          lastEvent: event,
          progress: event.progress,
          errorMessage: null,
        ),
      );
      return;
    }

    if (event.isTerminal) {
      _setState(
        _state.copyWith(
          phase: event.isSuccess
              ? CalibrationPhase.completed
              : CalibrationPhase.failed,
          lastEvent: event,
          progress: event.isSuccess ? 1 : event.progress,
          errorMessage: event.isSuccess
              ? null
              : event.message ?? calibrationErrorLabel(event.errorCode),
        ),
      );
      return;
    }

    _setState(
      _state.copyWith(
        phase: CalibrationPhase.running,
        lastEvent: event,
        progress: event.progress,
        errorMessage: null,
      ),
    );
  }

  void _handleConnectionState(CalibrationConnectionState connectionState) {
    debugPrint(
      '[CAL connection] phase=${_state.phase.name} '
      'state=${connectionState.name}',
    );
    if (connectionState == CalibrationConnectionState.connected) {
      _setState(_state.copyWith(isConnected: true));
      return;
    }
    if (connectionState != CalibrationConnectionState.disconnected) return;

    final phase = _state.phase;
    final active = switch (phase) {
      CalibrationPhase.connecting ||
      CalibrationPhase.verifyingIdentity ||
      CalibrationPhase.maintenanceRequired ||
      CalibrationPhase.ready ||
      CalibrationPhase.starting ||
      CalibrationPhase.running ||
      CalibrationPhase.cancelling => true,
      _ => false,
    };
    if (!active) {
      _setState(_state.copyWith(isConnected: false));
      return;
    }

    _setState(
      _state.copyWith(
        phase: CalibrationPhase.disconnected,
        isConnected: false,
        errorMessage: 'Connessione BLE persa. Riconnetti e richiedi stato.',
      ),
    );
  }

  String? _validateIdentity(Ic01DeviceInfo info) {
    if (info.protocolVersion != Ic01BleConstants.expectedProtocolVersion) {
      return 'Protocollo IC01 non compatibile: ${info.protocolVersion ?? '-'}';
    }

    final expectedDeviceId = _machine.expectedDeviceId;
    if (expectedDeviceId == null) return null;
    if (info.deviceId == expectedDeviceId) return null;

    return 'Device non associato: atteso $expectedDeviceId, letto ${info.deviceId}.';
  }

  void _fail(String message) {
    _setState(
      _state.copyWith(phase: CalibrationPhase.failed, errorMessage: message),
    );
  }

  void _setState(CalibrationControllerState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  String? _debugIdentityWarning(CalibrationMachineContext machine) {
    if (machine.expectedDeviceId != null) return null;

    // TODO(calibration): debug only. Remove this permissive path before
    // production and require a devices.machine_id association.
    return 'Debug: nessun device associato in backend. Il test continua ma il controllo va reso bloccante.';
  }
}

const _unset = Object();

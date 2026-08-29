import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../domain/calibration_json_object_assembler.dart';
import '../domain/calibration_protocol.dart';
import '../domain/ic01_ble_constants.dart';
import 'calibration_ble_transport.dart';

class ReactiveCalibrationBleTransport implements CalibrationBleTransport {
  ReactiveCalibrationBleTransport({FlutterReactiveBle? ble})
    : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  final _eventsController = StreamController<CalibrationBleEvent>.broadcast();
  final _connectionController =
      StreamController<CalibrationConnectionState>.broadcast();

  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  bool _disposed = false;
  final _eventAssembler = CalibrationJsonObjectAssembler();

  QualifiedCharacteristic? _infoCharacteristic;
  QualifiedCharacteristic? _controlCharacteristic;
  QualifiedCharacteristic? _eventsCharacteristic;

  @override
  Stream<CalibrationBleEvent> get events => _eventsController.stream;

  @override
  Stream<CalibrationConnectionState> get connectionState =>
      _connectionController.stream;

  @override
  Future<List<CalibrationBleDevice>> scan({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final serviceUuid = Uuid.parse(Ic01BleConstants.serviceUuid);
    final exactDevices = await _scanCandidates(
      timeout: timeout,
      serviceUuids: [serviceUuid],
      includeDevice: (_) => true,
    );
    if (exactDevices.isNotEmpty) return exactDevices;

    return _scanCandidates(
      timeout: timeout,
      serviceUuids: const [],
      includeDevice: _isDebugCandidate,
    );
  }

  Future<List<CalibrationBleDevice>> _scanCandidates({
    required Duration timeout,
    required List<Uuid> serviceUuids,
    required bool Function(DiscoveredDevice device) includeDevice,
  }) async {
    final devices = <String, CalibrationBleDevice>{};
    final completer = Completer<void>();

    final subscription = _ble
        .scanForDevices(
          withServices: serviceUuids,
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (device) {
            debugPrint(
              '[BLE scan] name="${device.name}" id=${device.id} '
              'rssi=${device.rssi} services=${device.serviceUuids}',
            );
            if (!includeDevice(device)) return;
            devices[device.id] = CalibrationBleDevice(
              id: device.id,
              name: device.name,
              rssi: device.rssi,
            );
          },
          onError: (Object error) {
            if (!completer.isCompleted) {
              completer.completeError(
                CalibrationTransportException('Scan BLE fallito: $error'),
              );
            }
          },
        );

    try {
      await Future.any<void>([Future<void>.delayed(timeout), completer.future]);
    } finally {
      await subscription.cancel();
    }

    return devices.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  bool _isDebugCandidate(DiscoveredDevice device) {
    final name = device.name.toLowerCase();
    final hasIc01Service = device.serviceUuids.any(
      (uuid) =>
          uuid.toString().toLowerCase() ==
          Ic01BleConstants.serviceUuid.toLowerCase(),
    );
    if (hasIc01Service) return true;
    if (name.isEmpty) return false;
    return name.contains('ic01') ||
        name.contains('ic02') ||
        name.contains('esp32') ||
        name.contains('magma');
  }

  @override
  Future<void> connect(CalibrationBleDevice device) async {
    await disconnect();
    _emitConnectionState(CalibrationConnectionState.connecting);

    final connected = Completer<void>();
    _connectionSubscription = _ble
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (update) {
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                _emitConnectionState(CalibrationConnectionState.connected);
                if (!connected.isCompleted) connected.complete();
                break;
              case DeviceConnectionState.connecting:
                _emitConnectionState(CalibrationConnectionState.connecting);
                break;
              case DeviceConnectionState.disconnecting:
              case DeviceConnectionState.disconnected:
                _emitConnectionState(CalibrationConnectionState.disconnected);
                if (!connected.isCompleted) {
                  connected.completeError(
                    const CalibrationTransportException(
                      'Dispositivo BLE disconnesso.',
                    ),
                  );
                }
                break;
            }
          },
          onError: (Object error) {
            _emitConnectionState(CalibrationConnectionState.disconnected);
            if (!connected.isCompleted) {
              connected.completeError(
                CalibrationTransportException(
                  'Connessione BLE fallita: $error',
                ),
              );
            }
          },
        );

    await connected.future.timeout(
      const Duration(seconds: 14),
      onTimeout: () {
        throw const CalibrationTransportException(
          'Timeout durante la connessione BLE.',
        );
      },
    );

    _bindCharacteristics(device.id);
    await _requestLargeMtu(device.id);
    await _subscribeEvents();
  }

  @override
  Future<void> disconnect() async {
    await _notificationSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _notificationSubscription = null;
    _connectionSubscription = null;
    _infoCharacteristic = null;
    _controlCharacteristic = null;
    _eventsCharacteristic = null;
    _eventAssembler.clear();
    _emitConnectionState(CalibrationConnectionState.disconnected);
  }

  @override
  Future<Ic01DeviceInfo> readInfo() async {
    final characteristic = _infoCharacteristic;
    if (characteristic == null) {
      throw const CalibrationTransportException(
        'Characteristic info non disponibile.',
      );
    }

    final bytes = await _ble.readCharacteristic(characteristic);
    final json = utf8.decode(bytes);
    return Ic01DeviceInfo.fromJsonString(json);
  }

  @override
  Future<void> sendCommand(String commandJson) async {
    final characteristic = _controlCharacteristic;
    if (characteristic == null) {
      throw const CalibrationTransportException(
        'Characteristic control non disponibile.',
      );
    }

    debugPrint('[BLE tx] $commandJson');
    await _ble.writeCharacteristicWithResponse(
      characteristic,
      value: utf8.encode(commandJson),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    unawaited(_eventsController.close());
    unawaited(_connectionController.close());
  }

  void _emitConnectionState(CalibrationConnectionState state) {
    if (_disposed || _connectionController.isClosed) return;
    _connectionController.add(state);
  }

  void _bindCharacteristics(String deviceId) {
    final serviceUuid = Uuid.parse(Ic01BleConstants.serviceUuid);
    _infoCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: Uuid.parse(Ic01BleConstants.infoCharacteristicUuid),
      deviceId: deviceId,
    );
    _controlCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: Uuid.parse(Ic01BleConstants.controlCharacteristicUuid),
      deviceId: deviceId,
    );
    _eventsCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: Uuid.parse(Ic01BleConstants.eventsCharacteristicUuid),
      deviceId: deviceId,
    );
  }

  Future<void> _subscribeEvents() async {
    final characteristic = _eventsCharacteristic;
    if (characteristic == null) {
      throw const CalibrationTransportException(
        'Characteristic events non disponibile.',
      );
    }

    await _notificationSubscription?.cancel();
    _notificationSubscription = _ble
        .subscribeToCharacteristic(characteristic)
        .listen(
          (bytes) {
            try {
              final chunk = utf8.decode(bytes);
              debugPrint('[BLE rx chunk] $chunk');
              final payloads = _eventAssembler.addChunk(chunk);
              for (final json in payloads) {
                debugPrint('[BLE rx] $json');
                _eventsController.add(CalibrationBleEvent.fromJsonString(json));
              }
            } catch (error) {
              debugPrint('[BLE rx error] $error bytes=$bytes');
              _eventsController.add(
                CalibrationBleEvent.fromMap({
                  'type': 'cal.error',
                  'status': 'failed',
                  'progress': 0,
                  'message': 'Notifica BLE non valida: $error',
                  'error': 'invalid_json',
                  'retryable': true,
                  'recover_action': 'retry',
                }),
              );
            }
          },
          onError: (Object error) {
            debugPrint('[BLE notify error] $error');
            _eventsController.add(
              CalibrationBleEvent.fromMap({
                'type': 'cal.error',
                'status': 'failed',
                'progress': 0,
                'message': 'Errore notifiche BLE: $error',
                'error': 'timeout',
                'retryable': true,
                'recover_action': 'reconnect',
              }),
            );
          },
        );
  }

  Future<void> _requestLargeMtu(String deviceId) async {
    try {
      final mtu = await _ble
          .requestMtu(deviceId: deviceId, mtu: 517)
          .timeout(const Duration(seconds: 3));
      debugPrint('[BLE mtu] negotiated=$mtu');
    } catch (error) {
      debugPrint('[BLE mtu] request failed: $error');
    }
  }
}

import 'dart:convert';

import 'package:ic01_operator_app/features/calibration/domain/calibration_json_object_assembler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ic01_operator_app/features/calibration/domain/calibration_protocol.dart';

void main() {
  group('CalibrationCommandCodec', () {
    test('encodes cal.start for hot machines', () {
      final raw = CalibrationCommandCodec.start(
        requestId: 'req-1',
        sessionId: 'sess-1',
        mode: CalibrationMode.hot,
      );

      expect(jsonDecode(raw), {
        'command': 'cal.start',
        'request_id': 'req-1',
        'session_id': 'sess-1',
        'mode': 'hot',
        'profile_set': 'coffee',
      });
    });

    test('encodes cal.status and cal.cancel', () {
      expect(
        jsonDecode(
          CalibrationCommandCodec.status(
            requestId: 'req-status',
            sessionId: 'sess-1',
          ),
        ),
        {
          'command': 'cal.status',
          'request_id': 'req-status',
          'session_id': 'sess-1',
        },
      );

      expect(
        jsonDecode(
          CalibrationCommandCodec.cancel(
            requestId: 'req-cancel',
            sessionId: 'sess-1',
          ),
        ),
        {
          'command': 'cal.cancel',
          'request_id': 'req-cancel',
          'session_id': 'sess-1',
        },
      );
    });
  });

  group('CalibrationBleEvent', () {
    test('decodes cal.error from firmware logs', () {
      final event = CalibrationBleEvent.fromJsonString(
        jsonEncode({
          'type': 'cal.error',
          'status': 'failed',
          'seq': 3,
          'request_id': 'req-no-maint',
          'session_id': 'sess-no-maint',
          'progress': 0,
          'message': 'Maintenance window required for calibration commands',
          'error': 'maintenance_required',
          'retryable': true,
          'recover_action': 'enable_maintenance',
        }),
      );

      expect(event.type, CalibrationBleEventType.error);
      expect(event.errorCode, CalibrationErrorCode.maintenanceRequired);
      expect(event.retryable, isTrue);
      expect(event.raw['recover_action'], 'enable_maintenance');
    });

    test('preserves unknown event raw payload', () {
      final event = CalibrationBleEvent.fromMap({
        'type': 'cal.future',
        'status': 'pending',
        'seq': 10,
        'custom': {'a': 1},
      });

      expect(event.type, CalibrationBleEventType.unknown);
      expect(event.raw['custom'], {'a': 1});
    });
  });

  group('CalibrationJsonObjectAssembler', () {
    test('emits complete json object immediately', () {
      final assembler = CalibrationJsonObjectAssembler();

      expect(assembler.addChunk('{"type":"cal.status"}'), [
        '{"type":"cal.status"}',
      ]);
    });

    test('reassembles split notification chunks', () {
      final assembler = CalibrationJsonObjectAssembler();
      const payload =
          '{"type":"cal.status","status":"collecting_baseline","seq":1,'
          '"request_id":"req","session_id":"sess","progress":0.15,'
          '"message":"calibration_started"}';

      final emitted = <String>[];
      for (var i = 0; i < payload.length; i += 20) {
        emitted.addAll(
          assembler.addChunk(
            payload.substring(i, (i + 20).clamp(0, payload.length)),
          ),
        );
      }

      expect(emitted, [payload]);
      expect(CalibrationBleEvent.fromJsonString(emitted.single).seq, 1);
    });

    test('emits multiple complete objects from one chunk', () {
      final assembler = CalibrationJsonObjectAssembler();

      expect(assembler.addChunk('{"type":"a"}{"type":"b"}'), [
        '{"type":"a"}',
        '{"type":"b"}',
      ]);
    });
  });

  group('Ic01DeviceInfo', () {
    test('decodes maintenance state', () {
      final info = Ic01DeviceInfo.fromMap({
        'device_id': 'ic01-dev-001',
        'fw_version': '0.1.0',
        'protocol_version': 1,
        'maintenance_enabled': true,
      });

      expect(info.deviceId, 'ic01-dev-001');
      expect(info.protocolVersion, 1);
      expect(info.maintenanceEnabled, isTrue);
    });

    test('accepts semantic protocol version from firmware', () {
      final info = Ic01DeviceInfo.fromMap({
        'device_id': 'ic01-dev-001',
        'fw_version': '0.1.0',
        'protocol_version': '1.0.0',
        'maintenance_enabled': false,
      });

      expect(info.protocolVersion, 1);
    });
  });
}

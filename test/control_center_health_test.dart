import 'package:flutter_test/flutter_test.dart';
import 'package:ic01_operator_app/features/control_center/domain/device_health.dart';

void main() {
  group('calculateDeviceHealth', () {
    final now = DateTime.utc(2026, 8, 26, 12);

    test('returns never connected without observed contact', () {
      expect(
        calculateDeviceHealth(now: now, lastContactAt: null),
        DeviceHealth.neverConnected,
      );
    });

    test('returns offline after threshold', () {
      expect(
        calculateDeviceHealth(
          now: now,
          lastContactAt: now.subtract(const Duration(days: 8)),
        ),
        DeviceHealth.offline,
      );
    });

    test('returns degraded for persistent errors', () {
      expect(
        calculateDeviceHealth(
          now: now,
          lastContactAt: now.subtract(const Duration(hours: 1)),
          errorCount: 3,
        ),
        DeviceHealth.degraded,
      );
    });

    test('returns warning for missing calibration', () {
      expect(
        calculateDeviceHealth(
          now: now,
          lastContactAt: now.subtract(const Duration(hours: 1)),
          calibrationState: 'missing',
        ),
        DeviceHealth.warning,
      );
    });

    test('returns healthy when no risk condition is present', () {
      expect(
        calculateDeviceHealth(
          now: now,
          lastContactAt: now.subtract(const Duration(hours: 1)),
        ),
        DeviceHealth.healthy,
      );
    });
  });
}

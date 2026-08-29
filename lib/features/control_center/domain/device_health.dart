enum DeviceHealth {
  healthy('healthy', 'HEALTHY'),
  warning('warning', 'WARNING'),
  degraded('degraded', 'DEGRADED'),
  offline('offline', 'OFFLINE'),
  neverConnected('never_connected', 'NEVER CONNECTED');

  const DeviceHealth(this.value, this.label);

  final String value;
  final String label;

  static DeviceHealth fromValue(String? value) {
    for (final health in DeviceHealth.values) {
      if (health.value == value) return health;
    }
    return DeviceHealth.neverConnected;
  }
}

class DeviceHealthThresholds {
  const DeviceHealthThresholds({
    this.offlineAfter = const Duration(days: 7),
    this.degradedErrorCount = 3,
  });

  final Duration offlineAfter;
  final int degradedErrorCount;
}

DeviceHealth calculateDeviceHealth({
  required DateTime now,
  required DateTime? lastContactAt,
  String? healthHint,
  String? calibrationState,
  int errorCount = 0,
  int warningCount = 0,
  DeviceHealthThresholds thresholds = const DeviceHealthThresholds(),
}) {
  if (lastContactAt == null) return DeviceHealth.neverConnected;

  if (now.difference(lastContactAt.toUtc()) > thresholds.offlineAfter) {
    return DeviceHealth.offline;
  }

  final normalizedHint = healthHint?.trim().toLowerCase();
  if (normalizedHint == DeviceHealth.degraded.value ||
      errorCount >= thresholds.degradedErrorCount) {
    return DeviceHealth.degraded;
  }

  final normalizedCalibration = calibrationState?.trim().toLowerCase();
  if (normalizedHint == DeviceHealth.warning.value ||
      warningCount > 0 ||
      normalizedCalibration == 'missing' ||
      normalizedCalibration == 'invalid' ||
      normalizedCalibration == 'required') {
    return DeviceHealth.warning;
  }

  return DeviceHealth.healthy;
}

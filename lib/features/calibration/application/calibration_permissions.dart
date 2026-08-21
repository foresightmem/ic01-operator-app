import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

enum CalibrationPermissionStatus { granted, denied, unsupportedPlatform }

abstract class CalibrationPermissionGateway {
  bool get isSupportedPlatform;

  Future<CalibrationPermissionStatus> ensurePermissions();
}

class PermissionHandlerCalibrationPermissions
    implements CalibrationPermissionGateway {
  const PermissionHandlerCalibrationPermissions();

  @override
  bool get isSupportedPlatform {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  @override
  Future<CalibrationPermissionStatus> ensurePermissions() async {
    if (!isSupportedPlatform) {
      return CalibrationPermissionStatus.unsupportedPlatform;
    }

    final bluetoothStatuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final bluetoothGranted = bluetoothStatuses.values.every(_isGranted);
    if (!bluetoothGranted) return CalibrationPermissionStatus.denied;

    // Android <= 11 requires location permission for BLE scan. On newer Android
    // this permission is declared with maxSdkVersion=30 and may be unavailable.
    await Permission.locationWhenInUse.request();

    return CalibrationPermissionStatus.granted;
  }

  bool _isGranted(PermissionStatus status) {
    return status.isGranted || status.isLimited;
  }
}

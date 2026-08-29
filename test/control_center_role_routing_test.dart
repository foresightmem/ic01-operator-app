import 'package:flutter_test/flutter_test.dart';
import 'package:ic01_operator_app/core/auth/app_role_service.dart';

void main() {
  group('Control Center role routing', () {
    test('routes internal admin to Control Center', () {
      expect(landingPathForRole(AppRole.internalAdmin), '/control-center');
    });

    test('preserves existing role landing paths', () {
      expect(landingPathForRole(AppRole.admin), '/admin');
      expect(landingPathForRole(AppRole.technician), '/maintenance');
      expect(landingPathForRole(AppRole.refillOperator), '/dashboard');
    });

    test('blocks Control Center for non internal roles', () {
      expect(isPathAllowedForRole('/control-center', AppRole.admin), isFalse);
      expect(
        isPathAllowedForRole('/control-center/devices', AppRole.refillOperator),
        isFalse,
      );
      expect(
        isPathAllowedForRole('/control-center/events', AppRole.internalAdmin),
        isTrue,
      );
    });
  });
}

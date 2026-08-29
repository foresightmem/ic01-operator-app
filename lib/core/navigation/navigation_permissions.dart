import '../auth/app_role_service.dart';

bool canUseExternalNavigation(AppRole role) {
  switch (role) {
    case AppRole.refillOperator:
    case AppRole.technician:
      return true;
    case AppRole.admin:
    case AppRole.internalAdmin:
    case AppRole.unknown:
      return false;
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

enum AppRole {
  refillOperator('refill_operator'),
  technician('technician'),
  admin('admin'),
  internalAdmin('internal_admin'),
  unknown('');

  const AppRole(this.value);

  final String value;

  static AppRole fromValue(String? value) {
    for (final role in AppRole.values) {
      if (role.value == value) return role;
    }
    return AppRole.unknown;
  }
}

class AppRoleService {
  AppRoleService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<AppRole> currentRole() async {
    final user = _client.auth.currentUser;
    if (user == null) return AppRole.unknown;

    final row = await _client
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    return AppRole.fromValue(row?['role'] as String?);
  }
}

String landingPathForRole(AppRole role) {
  switch (role) {
    case AppRole.internalAdmin:
      return '/control-center';
    case AppRole.admin:
      return '/admin';
    case AppRole.technician:
      return '/maintenance';
    case AppRole.refillOperator:
    case AppRole.unknown:
      return '/dashboard';
  }
}

bool isPathAllowedForRole(String path, AppRole role) {
  if (path.startsWith('/control-center')) {
    return role == AppRole.internalAdmin;
  }

  return true;
}

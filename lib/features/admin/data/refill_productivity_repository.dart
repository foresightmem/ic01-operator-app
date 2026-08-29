import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/refill_productivity_kpi.dart';

class RefillProductivityRepository {
  RefillProductivityRepository(this._client);

  final SupabaseClient _client;

  Future<RefillProductivityKpi> load({required int periodDays}) async {
    final data = await _client.rpc(
      'get_refill_productivity_kpi',
      params: {
        'p_period_days': periodDays,
        'p_timezone': 'Europe/Rome',
        'p_theoretical_work_hours_per_day': 6,
      },
    );

    if (data is Map<String, dynamic>) {
      return RefillProductivityKpi.fromJson(data);
    }
    if (data is Map) {
      return RefillProductivityKpi.fromJson(Map<String, dynamic>.from(data));
    }
    throw const FormatException('Risposta KPI refill non valida.');
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ic01_operator_app/features/admin/domain/refill_productivity_kpi.dart';

void main() {
  group('RefillProductivityKpi', () {
    test('parses nullable observed productivity and legacy counters', () {
      final kpi = RefillProductivityKpi.fromJson({
        'period': {
          'start': '2026-08-01T00:00:00Z',
          'end': '2026-08-31T00:00:00Z',
          'days': 30,
          'timezone': 'Europe/Rome',
          'theoretical_work_hours_per_day': 6,
        },
        'previous_period': {
          'start': '2026-07-02T00:00:00Z',
          'end': '2026-08-01T00:00:00Z',
          'days': 30,
          'timezone': 'Europe/Rome',
        },
        'summary': {
          'total_refilled_doses': 300,
          'refill_count': 1,
          'unique_machine_count': 1,
          'active_refill_days': 1,
          'theoretical_hours': 6,
          'observable_days': 0,
          'observed_refill_hours': 0,
          'doses_for_observed_rate': 0,
          'doses_per_theoretical_hour': 50,
          'doses_per_observed_hour': null,
          'observed_window_utilization': null,
          'theoretical_residual_capacity_hours': 0,
          'refill_with_quantity_count': 1,
          'legacy_without_quantity_count': 0,
          'invalid_quantity_count': 0,
        },
        'previous_summary': {
          'total_refilled_doses': 0,
          'refill_count': 0,
          'unique_machine_count': 0,
          'active_refill_days': 0,
          'theoretical_hours': 0,
          'observable_days': 0,
          'observed_refill_hours': 0,
          'doses_for_observed_rate': 0,
          'doses_per_theoretical_hour': null,
          'doses_per_observed_hour': null,
          'observed_window_utilization': null,
          'theoretical_residual_capacity_hours': 0,
          'refill_with_quantity_count': 0,
          'legacy_without_quantity_count': 1,
          'invalid_quantity_count': 0,
        },
        'comparison': {
          'doses_delta_percent': null,
          'refill_delta_percent': null,
          'theoretical_productivity_delta_percent': null,
          'observed_productivity_delta_percent': null,
        },
        'operators': [
          {
            'operator_id': 'operator-1',
            'operator_name': 'Operatore Pilot',
            'total_refilled_doses': 300,
            'refill_count': 1,
            'unique_machine_count': 1,
            'active_refill_days': 1,
            'theoretical_hours': 6,
            'observable_days': 0,
            'observed_refill_hours': 0,
            'doses_for_observed_rate': 0,
            'doses_per_theoretical_hour': 50,
            'doses_per_observed_hour': null,
            'observed_window_utilization': null,
            'theoretical_residual_capacity_hours': 0,
            'refill_with_quantity_count': 1,
            'legacy_without_quantity_count': 0,
            'productivity_delta_percent': null,
          },
        ],
      });

      expect(kpi.period.days, 30);
      expect(kpi.summary.dosesPerObservedHour, isNull);
      expect(kpi.summary.dosesPerTheoreticalHour, 50);
      expect(kpi.previousSummary.legacyWithoutQuantityCount, 1);
      expect(kpi.comparison.dosesDeltaPercent, isNull);
      expect(kpi.operators.single.operatorName, 'Operatore Pilot');
    });
  });
}

class RefillProductivityKpi {
  final RefillKpiPeriod period;
  final RefillKpiPeriod previousPeriod;
  final RefillProductivitySummary summary;
  final RefillProductivitySummary previousSummary;
  final RefillProductivityComparison comparison;
  final List<RefillProductivityOperator> operators;

  const RefillProductivityKpi({
    required this.period,
    required this.previousPeriod,
    required this.summary,
    required this.previousSummary,
    required this.comparison,
    required this.operators,
  });

  bool get hasRefills => summary.refillCount > 0;
  bool get hasDoseSample => summary.refillWithQuantityCount > 0;

  factory RefillProductivityKpi.fromJson(Map<String, dynamic> json) {
    final operatorsJson = (json['operators'] as List<dynamic>? ?? const []);
    return RefillProductivityKpi(
      period: RefillKpiPeriod.fromJson(_map(json['period'])),
      previousPeriod: RefillKpiPeriod.fromJson(_map(json['previous_period'])),
      summary: RefillProductivitySummary.fromJson(_map(json['summary'])),
      previousSummary: RefillProductivitySummary.fromJson(
        _map(json['previous_summary']),
      ),
      comparison: RefillProductivityComparison.fromJson(
        _map(json['comparison']),
      ),
      operators: operatorsJson
          .map(
            (row) => RefillProductivityOperator.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class RefillKpiPeriod {
  final DateTime? start;
  final DateTime? end;
  final int days;
  final String timezone;
  final double? theoreticalWorkHoursPerDay;

  const RefillKpiPeriod({
    required this.start,
    required this.end,
    required this.days,
    required this.timezone,
    required this.theoreticalWorkHoursPerDay,
  });

  factory RefillKpiPeriod.fromJson(Map<String, dynamic> json) {
    return RefillKpiPeriod(
      start: _date(json['start']),
      end: _date(json['end']),
      days: _int(json['days']),
      timezone: (json['timezone'] as String?) ?? 'Europe/Rome',
      theoreticalWorkHoursPerDay: _doubleOrNull(
        json['theoretical_work_hours_per_day'],
      ),
    );
  }
}

class RefillProductivitySummary {
  final int totalRefilledDoses;
  final int refillCount;
  final int uniqueMachineCount;
  final int activeRefillDays;
  final double theoreticalHours;
  final int observableDays;
  final double observedRefillHours;
  final int dosesForObservedRate;
  final double? dosesPerTheoreticalHour;
  final double? dosesPerObservedHour;
  final double? observedWindowUtilization;
  final double theoreticalResidualCapacityHours;
  final int refillWithQuantityCount;
  final int legacyWithoutQuantityCount;
  final int invalidQuantityCount;

  const RefillProductivitySummary({
    required this.totalRefilledDoses,
    required this.refillCount,
    required this.uniqueMachineCount,
    required this.activeRefillDays,
    required this.theoreticalHours,
    required this.observableDays,
    required this.observedRefillHours,
    required this.dosesForObservedRate,
    required this.dosesPerTheoreticalHour,
    required this.dosesPerObservedHour,
    required this.observedWindowUtilization,
    required this.theoreticalResidualCapacityHours,
    required this.refillWithQuantityCount,
    required this.legacyWithoutQuantityCount,
    required this.invalidQuantityCount,
  });

  factory RefillProductivitySummary.fromJson(Map<String, dynamic> json) {
    return RefillProductivitySummary(
      totalRefilledDoses: _int(json['total_refilled_doses']),
      refillCount: _int(json['refill_count']),
      uniqueMachineCount: _int(json['unique_machine_count']),
      activeRefillDays: _int(json['active_refill_days']),
      theoreticalHours: _double(json['theoretical_hours']),
      observableDays: _int(json['observable_days']),
      observedRefillHours: _double(json['observed_refill_hours']),
      dosesForObservedRate: _int(json['doses_for_observed_rate']),
      dosesPerTheoreticalHour: _doubleOrNull(
        json['doses_per_theoretical_hour'],
      ),
      dosesPerObservedHour: _doubleOrNull(json['doses_per_observed_hour']),
      observedWindowUtilization: _doubleOrNull(
        json['observed_window_utilization'],
      ),
      theoreticalResidualCapacityHours: _double(
        json['theoretical_residual_capacity_hours'],
      ),
      refillWithQuantityCount: _int(json['refill_with_quantity_count']),
      legacyWithoutQuantityCount: _int(json['legacy_without_quantity_count']),
      invalidQuantityCount: _int(json['invalid_quantity_count']),
    );
  }
}

class RefillProductivityComparison {
  final double? dosesDeltaPercent;
  final double? refillDeltaPercent;
  final double? theoreticalProductivityDeltaPercent;
  final double? observedProductivityDeltaPercent;

  const RefillProductivityComparison({
    required this.dosesDeltaPercent,
    required this.refillDeltaPercent,
    required this.theoreticalProductivityDeltaPercent,
    required this.observedProductivityDeltaPercent,
  });

  factory RefillProductivityComparison.fromJson(Map<String, dynamic> json) {
    return RefillProductivityComparison(
      dosesDeltaPercent: _doubleOrNull(json['doses_delta_percent']),
      refillDeltaPercent: _doubleOrNull(json['refill_delta_percent']),
      theoreticalProductivityDeltaPercent: _doubleOrNull(
        json['theoretical_productivity_delta_percent'],
      ),
      observedProductivityDeltaPercent: _doubleOrNull(
        json['observed_productivity_delta_percent'],
      ),
    );
  }
}

class RefillProductivityOperator {
  final String operatorId;
  final String operatorName;
  final int totalRefilledDoses;
  final int refillCount;
  final int uniqueMachineCount;
  final int activeRefillDays;
  final double theoreticalHours;
  final int observableDays;
  final double observedRefillHours;
  final int dosesForObservedRate;
  final double? dosesPerTheoreticalHour;
  final double? dosesPerObservedHour;
  final double? observedWindowUtilization;
  final double theoreticalResidualCapacityHours;
  final int refillWithQuantityCount;
  final int legacyWithoutQuantityCount;
  final double? productivityDeltaPercent;

  const RefillProductivityOperator({
    required this.operatorId,
    required this.operatorName,
    required this.totalRefilledDoses,
    required this.refillCount,
    required this.uniqueMachineCount,
    required this.activeRefillDays,
    required this.theoreticalHours,
    required this.observableDays,
    required this.observedRefillHours,
    required this.dosesForObservedRate,
    required this.dosesPerTheoreticalHour,
    required this.dosesPerObservedHour,
    required this.observedWindowUtilization,
    required this.theoreticalResidualCapacityHours,
    required this.refillWithQuantityCount,
    required this.legacyWithoutQuantityCount,
    required this.productivityDeltaPercent,
  });

  factory RefillProductivityOperator.fromJson(Map<String, dynamic> json) {
    return RefillProductivityOperator(
      operatorId: (json['operator_id'] as String?) ?? '',
      operatorName: (json['operator_name'] as String?) ?? 'Operatore',
      totalRefilledDoses: _int(json['total_refilled_doses']),
      refillCount: _int(json['refill_count']),
      uniqueMachineCount: _int(json['unique_machine_count']),
      activeRefillDays: _int(json['active_refill_days']),
      theoreticalHours: _double(json['theoretical_hours']),
      observableDays: _int(json['observable_days']),
      observedRefillHours: _double(json['observed_refill_hours']),
      dosesForObservedRate: _int(json['doses_for_observed_rate']),
      dosesPerTheoreticalHour: _doubleOrNull(
        json['doses_per_theoretical_hour'],
      ),
      dosesPerObservedHour: _doubleOrNull(json['doses_per_observed_hour']),
      observedWindowUtilization: _doubleOrNull(
        json['observed_window_utilization'],
      ),
      theoreticalResidualCapacityHours: _double(
        json['theoretical_residual_capacity_hours'],
      ),
      refillWithQuantityCount: _int(json['refill_with_quantity_count']),
      legacyWithoutQuantityCount: _int(json['legacy_without_quantity_count']),
      productivityDeltaPercent: _doubleOrNull(
        json['productivity_delta_percent'],
      ),
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _double(dynamic value) => _doubleOrNull(value) ?? 0;

double? _doubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? _date(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

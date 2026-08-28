import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/ui/app_design_system.dart';
import '../../data/control_center_repository.dart';
import '../../domain/device_health.dart';

class HealthBadge extends StatelessWidget {
  const HealthBadge({super.key, required this.health});

  final DeviceHealth health;

  @override
  Widget build(BuildContext context) {
    return AppStatusPill(
      label: health.label,
      color: healthColor(health),
      icon: healthIcon(health),
    );
  }
}

class SeverityBadge extends StatelessWidget {
  const SeverityBadge({super.key, required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final normalized = severity.toLowerCase();
    final color = switch (normalized) {
      'critical' => AppColors.stopped,
      'error' => AppColors.danger,
      'warning' => AppColors.warning,
      _ => AppColors.info,
    };
    final icon = switch (normalized) {
      'critical' => Icons.priority_high,
      'error' => Icons.error_outline,
      'warning' => Icons.warning_amber_outlined,
      _ => Icons.info_outline,
    };
    return AppStatusPill(
      label: normalized.toUpperCase(),
      color: color,
      icon: icon,
    );
  }
}

class CommandStatusBadge extends StatelessWidget {
  const CommandStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final color = switch (normalized) {
      'completed' || 'acknowledged' => AppColors.success,
      'failed' || 'expired' || 'unsupported' || 'cancelled' => AppColors.danger,
      'delivered_to_app' || 'sent_to_device' => AppColors.info,
      _ => AppColors.warning,
    };
    final label = normalized.replaceAll('_', ' ').toUpperCase();
    return AppStatusPill(
      label: label,
      color: color,
      icon: Icons.route_outlined,
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.petroleum,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(value, style: theme.textTheme.titleLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class JsonPayloadView extends StatelessWidget {
  const JsonPayloadView({super.key, required this.payload});

  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final pretty = const JsonEncoder.withIndent('  ').convert(payload);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: SelectableText(
        pretty,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}

class EventTable extends StatelessWidget {
  const EventTable({super.key, required this.events, this.onTap});

  final List<ControlCenterEvent> events;
  final ValueChanged<ControlCenterEvent>? onTap;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const AppEmptyState(
        title: 'Nessun evento',
        message: 'Non ci sono eventi tecnici per i filtri selezionati.',
        icon: Icons.event_note_outlined,
      );
    }

    final compact = context.responsive.isCompact;
    if (compact) {
      return Column(
        children: events
            .map(
              (event) => AppSectionCard(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: InkWell(
                  onTap: onTap == null ? null : () => onTap!(event),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          SeverityBadge(severity: event.severity),
                          Text(formatDateTime(event.createdAt)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        event.eventType,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(event.summary ?? event.source),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        [
                          event.deviceId,
                          event.machineCode,
                          event.clientName,
                        ].whereType<String>().join(' / '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(growable: false),
      );
    }

    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: AppSpacing.lg,
          columns: const [
            DataColumn(label: Text('Timestamp')),
            DataColumn(label: Text('Severity')),
            DataColumn(label: Text('Device')),
            DataColumn(label: Text('Machine')),
            DataColumn(label: Text('Event')),
            DataColumn(label: Text('Summary')),
            DataColumn(label: Text('Source')),
          ],
          rows: events
              .map(
                (event) => DataRow(
                  onSelectChanged: onTap == null ? null : (_) => onTap!(event),
                  cells: [
                    DataCell(Text(formatDateTime(event.createdAt))),
                    DataCell(SeverityBadge(severity: event.severity)),
                    DataCell(Text(event.deviceId ?? '-')),
                    DataCell(Text(event.machineCode ?? '-')),
                    DataCell(Text(event.eventType)),
                    DataCell(
                      SizedBox(
                        width: 260,
                        child: Text(
                          event.summary ?? '-',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(event.source)),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

Color healthColor(DeviceHealth health) {
  switch (health) {
    case DeviceHealth.healthy:
      return AppColors.success;
    case DeviceHealth.warning:
      return AppColors.warning;
    case DeviceHealth.degraded:
      return AppColors.danger;
    case DeviceHealth.offline:
      return AppColors.stopped;
    case DeviceHealth.neverConnected:
      return AppColors.muted;
  }
}

IconData healthIcon(DeviceHealth health) {
  switch (health) {
    case DeviceHealth.healthy:
      return Icons.check_circle_outline;
    case DeviceHealth.warning:
      return Icons.warning_amber_outlined;
    case DeviceHealth.degraded:
      return Icons.error_outline;
    case DeviceHealth.offline:
      return Icons.cloud_off_outlined;
    case DeviceHealth.neverConnected:
      return Icons.radio_button_unchecked;
  }
}

String formatDateTime(DateTime? value) {
  if (value == null) return 'Not available';
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}

String formatDurationMs(int? value) {
  if (value == null) return 'Not available';
  if (value < 1000) return '${value}ms';
  final seconds = (value / 1000).toStringAsFixed(1);
  return '${seconds}s';
}

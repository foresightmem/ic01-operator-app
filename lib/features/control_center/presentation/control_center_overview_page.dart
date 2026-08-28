import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_design_system.dart';
import '../data/control_center_repository.dart';
import 'widgets/control_center_widgets.dart';

class ControlCenterOverviewPage extends StatefulWidget {
  const ControlCenterOverviewPage({super.key});

  @override
  State<ControlCenterOverviewPage> createState() =>
      _ControlCenterOverviewPageState();
}

class _ControlCenterOverviewPageState extends State<ControlCenterOverviewPage> {
  final _repository = ControlCenterRepository();
  late Future<ControlCenterOverview> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.loadOverview();
  }

  void _refresh() {
    setState(() {
      _future = _repository.loadOverview();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      center: false,
      maxWidth: 1440,
      child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<ControlCenterOverview>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoading(label: 'Caricamento Control Center...');
            }
            if (snapshot.hasError) {
              return AppErrorState(
                message: snapshot.error.toString(),
                onRetry: _refresh,
              );
            }
            final overview = snapshot.data;
            if (overview == null) {
              return const AppEmptyState(title: 'Dati non disponibili');
            }
            return ListView(
              children: [
                _Header(onRefresh: _refresh),
                const SizedBox(height: AppSpacing.lg),
                _FleetHealthGrid(health: overview.fleetHealth),
                const SizedBox(height: AppSpacing.lg),
                _SystemHealth(systemHealth: overview.systemHealth),
                const SizedBox(height: AppSpacing.lg),
                _AttentionRequired(devices: overview.attentionRequired),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Latest Events',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                EventTable(
                  events: overview.latestEvents,
                  onTap: (event) => _showEventDetail(context, event),
                ),
                const SizedBox(height: AppSpacing.lg),
                _NotAvailable(items: overview.notAvailable),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Overview',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Fleet health from observed Supabase telemetry and events.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Aggiorna',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _FleetHealthGrid extends StatelessWidget {
  const _FleetHealthGrid({required this.health});

  final FleetHealth health;

  @override
  Widget build(BuildContext context) {
    return AppAdaptiveGrid(
      minTileWidth: 180,
      maxColumns: 4,
      childAspectRatio: 2.7,
      children: [
        MetricCard(
          label: 'Device totali',
          value: '${health.total}',
          icon: Icons.memory,
        ),
        MetricCard(
          label: 'Healthy',
          value: '${health.healthy}',
          icon: Icons.check_circle_outline,
          color: AppColors.success,
        ),
        MetricCard(
          label: 'Warning',
          value: '${health.warning}',
          icon: Icons.warning_amber_outlined,
          color: AppColors.warning,
        ),
        MetricCard(
          label: 'Degraded',
          value: '${health.degraded}',
          icon: Icons.error_outline,
          color: AppColors.danger,
        ),
        MetricCard(
          label: 'Offline',
          value: '${health.offline}',
          icon: Icons.cloud_off_outlined,
          color: AppColors.stopped,
        ),
        MetricCard(
          label: 'Never connected',
          value: '${health.neverConnected}',
          icon: Icons.radio_button_unchecked,
          color: AppColors.muted,
        ),
        MetricCard(
          label: 'Calibration missing',
          value: '${health.calibrationMissing}',
          icon: Icons.tune_outlined,
          color: AppColors.warning,
        ),
        MetricCard(
          label: 'Firmware outdated',
          value: health.firmwareOutdated?.toString() ?? 'Not available',
          icon: Icons.system_update_alt,
          color: AppColors.info,
        ),
      ],
    );
  }
}

class _SystemHealth extends StatelessWidget {
  const _SystemHealth({required this.systemHealth});

  final Map<String, dynamic> systemHealth;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Database/backend', _value(systemHealth['database_backend'])),
      ('Edge Functions', _value(systemHealth['edge_functions'])),
      ('BLE success rate 24h', _percent(systemHealth['ble_success_rate_24h'])),
      ('Error rate 24h', _value(systemHealth['error_rate_24h'])),
      ('App versions', _versions(systemHealth['app_versions'])),
      ('Latest event received', _date(systemHealth['latest_event_received'])),
    ];

    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('System Health', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: rows
                .map(
                  (row) => SizedBox(
                    width: context.responsive.isCompact ? double.infinity : 280,
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(row.$1),
                      subtitle: Text(row.$2),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  String _value(Object? value) => value?.toString() ?? 'Not available';

  String _percent(Object? value) {
    if (value == null) return 'Not available';
    return '$value%';
  }

  String _versions(Object? value) {
    if (value is List && value.isNotEmpty) return value.join(', ');
    return 'Not available';
  }

  String _date(Object? value) {
    if (value is String) return formatDateTime(DateTime.tryParse(value));
    return 'Not available';
  }
}

class _AttentionRequired extends StatelessWidget {
  const _AttentionRequired({required this.devices});

  final List<ControlCenterDevice> devices;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attention Required',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (devices.isEmpty)
            const AppEmptyState(
              title: 'Nessun device richiede attenzione',
              icon: Icons.check_circle_outline,
            )
          else
            Column(
              children: devices
                  .map(
                    (device) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: HealthBadge(health: device.health),
                      title: Text(device.deviceId),
                      subtitle: Text(
                        [
                          device.clientName,
                          device.machineCode,
                          device.siteName,
                        ].whereType<String>().join(' / '),
                      ),
                      trailing: Text(formatDateTime(device.lastContactAt)),
                      onTap: () =>
                          context.go('/control-center/devices/${device.id}'),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _NotAvailable extends StatelessWidget {
  const _NotAvailable({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Not Available', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

void _showEventDetail(BuildContext context, ControlCenterEvent event) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(event.eventType),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SeverityBadge(severity: event.severity),
            const SizedBox(height: AppSpacing.sm),
            Text(event.summary ?? event.source),
            const SizedBox(height: AppSpacing.sm),
            JsonPayloadView(payload: event.payload),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );
}

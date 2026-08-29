import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_design_system.dart';
import '../data/control_center_repository.dart';
import 'widgets/control_center_widgets.dart';

class ControlCenterDeviceDetailPage extends StatefulWidget {
  const ControlCenterDeviceDetailPage({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<ControlCenterDeviceDetailPage> createState() =>
      _ControlCenterDeviceDetailPageState();
}

class _ControlCenterDeviceDetailPageState
    extends State<ControlCenterDeviceDetailPage> {
  final _repository = ControlCenterRepository();
  late Future<ControlCenterDeviceDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.loadDeviceDetail(widget.deviceId);
  }

  void _refresh() {
    setState(() {
      _future = _repository.loadDeviceDetail(widget.deviceId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      center: false,
      maxWidth: 1440,
      child: FutureBuilder<ControlCenterDeviceDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading(label: 'Caricamento device...');
          }
          if (snapshot.hasError) {
            return AppErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final detail = snapshot.data;
          final device = detail?.device;
          if (detail == null || detail.error != null || device == null) {
            return AppEmptyState(
              title: detail?.error == 'access_denied'
                  ? 'Accesso negato'
                  : 'Device non trovato',
              icon: Icons.lock_outline,
            );
          }

          return ListView(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Indietro',
                    onPressed: () => context.go('/control-center/devices'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      device.deviceId,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  HealthBadge(health: device.health),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    tooltip: 'Aggiorna',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _SectionGrid(
                children: [
                  _IdentitySection(device: device),
                  _HealthSection(device: device),
                  _FirmwareSection(device: device),
                  _CalibrationSection(device: device, status: detail.status),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _ConnectivitySection(sessions: detail.bleSessions),
              const SizedBox(height: AppSpacing.lg),
              _SensorDataSection(sensorData: detail.latestSensorData),
              const SizedBox(height: AppSpacing.lg),
              _CommandsSection(commands: detail.commands),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Event Timeline',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              EventTable(
                events: detail.events,
                onTap: (event) => _showEventDetail(context, event),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionGrid extends StatelessWidget {
  const _SectionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 850 ? 1 : 2;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: columns == 1 ? 2.8 : 2.2,
          children: children,
        );
      },
    );
  }
}

class _IdentitySection extends StatelessWidget {
  const _IdentitySection({required this.device});

  final ControlCenterDevice device;

  @override
  Widget build(BuildContext context) {
    return _InfoSection(
      title: 'Identity',
      rows: [
        ('Device ID', device.deviceId),
        ('Serial number', device.serialNumber ?? 'Not available'),
        ('Hardware revision', device.hardwareRevision ?? 'Not available'),
        ('Machine', device.machineCode ?? 'Not linked'),
        ('Client', device.clientName ?? 'Not linked'),
        ('Site', device.siteName ?? 'Not linked'),
      ],
    );
  }
}

class _HealthSection extends StatelessWidget {
  const _HealthSection({required this.device});

  final ControlCenterDevice device;

  @override
  Widget build(BuildContext context) {
    return _InfoSection(
      title: 'Health',
      header: HealthBadge(health: device.health),
      rows: [
        ('Last contact', formatDateTime(device.lastContactAt)),
        ('Last event', formatDateTime(device.lastEventAt)),
        ('Warnings 24h', '${device.warningCount}'),
        ('Errors 24h', '${device.errorCount}'),
      ],
    );
  }
}

class _FirmwareSection extends StatelessWidget {
  const _FirmwareSection({required this.device});

  final ControlCenterDevice device;

  @override
  Widget build(BuildContext context) {
    return _InfoSection(
      title: 'Firmware',
      rows: [
        ('Installed version', device.firmwareVersion ?? 'Not available'),
        ('Hardware version', device.hardwareRevision ?? 'Not available'),
        ('Build info', 'Not available'),
      ],
    );
  }
}

class _CalibrationSection extends StatelessWidget {
  const _CalibrationSection({required this.device, required this.status});

  final ControlCenterDevice device;
  final Map<String, dynamic> status;

  @override
  Widget build(BuildContext context) {
    return _InfoSection(
      title: 'Calibration',
      rows: [
        ('Status', device.calibrationState ?? 'Not available'),
        ('Last calibration', _value(status['last_calibration_at'])),
        ('Executed by', _value(status['last_operator_name'])),
        (
          'Parameters',
          status['calibration_parameters'] == null
              ? 'Not available'
              : 'Available',
        ),
      ],
    );
  }
}

class _ConnectivitySection extends StatelessWidget {
  const _ConnectivitySection({required this.sessions});

  final List<BleSession> sessions;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connectivity', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          if (sessions.isEmpty)
            const AppEmptyState(
              title: 'BLE session data not available',
              message: 'L’app non ha ancora inviato sessioni BLE osservate.',
              icon: Icons.bluetooth_disabled,
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Started')),
                  DataColumn(label: Text('Result')),
                  DataColumn(label: Text('Duration')),
                  DataColumn(label: Text('Reason')),
                  DataColumn(label: Text('Operator/app')),
                ],
                rows: sessions
                    .map(
                      (session) => DataRow(
                        cells: [
                          DataCell(Text(formatDateTime(session.startedAt))),
                          DataCell(Text(session.result)),
                          DataCell(Text(formatDurationMs(session.durationMs))),
                          DataCell(
                            Text(
                              session.disconnectReason ??
                                  session.errorCode ??
                                  '-',
                            ),
                          ),
                          DataCell(
                            Text(
                              [
                                session.operatorName,
                                session.appVersion,
                              ].whereType<String>().join(' / '),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }
}

class _SensorDataSection extends StatelessWidget {
  const _SensorDataSection({required this.sensorData});

  final Map<String, dynamic> sensorData;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Latest Sensor Data',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (sensorData.isEmpty)
            const AppEmptyState(
              title: 'Sensor data not available',
              message:
                  'Il firmware oggi invia conteggi e stato, non raw sensor snapshots.',
              icon: Icons.sensors_off_outlined,
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: sensorData.entries
                  .map(
                    (entry) => SizedBox(
                      width: 220,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(entry.key),
                        subtitle: Text(entry.value.toString()),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _CommandsSection extends StatelessWidget {
  const _CommandsSection({required this.commands});

  final List<CommandJob> commands;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Command Audit', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          if (commands.isEmpty)
            const AppEmptyState(
              title: 'Nessun comando',
              message: 'I command job compariranno qui dopo la creazione.',
              icon: Icons.route_outlined,
            )
          else
            Column(
              children: commands
                  .map(
                    (command) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CommandStatusBadge(status: command.status),
                      title: Text(command.command),
                      subtitle: Text(formatDateTime(command.requestedAt)),
                      trailing: Text(command.error ?? ''),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.rows, this.header});

  final String title;
  final List<(String, String)> rows;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final headerWidget = header;
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?headerWidget,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      row.$1,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(
                    child: Text(row.$2, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _value(Object? value) => value?.toString() ?? 'Not available';

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

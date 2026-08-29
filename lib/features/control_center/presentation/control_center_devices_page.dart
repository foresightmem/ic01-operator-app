import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_design_system.dart';
import '../data/control_center_repository.dart';
import '../domain/device_health.dart';
import 'widgets/control_center_widgets.dart';

enum _DeviceSort { lastContact, health, deviceId }

class ControlCenterDevicesPage extends StatefulWidget {
  const ControlCenterDevicesPage({super.key});

  @override
  State<ControlCenterDevicesPage> createState() =>
      _ControlCenterDevicesPageState();
}

class _ControlCenterDevicesPageState extends State<ControlCenterDevicesPage> {
  final _repository = ControlCenterRepository();
  final _searchController = TextEditingController();
  late Future<List<ControlCenterDevice>> _future;
  DeviceHealth? _healthFilter;
  String _firmwareFilter = '';
  String _calibrationFilter = '';
  _DeviceSort _sort = _DeviceSort.lastContact;

  @override
  void initState() {
    super.initState();
    _future = _repository.loadDevices();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = _repository.loadDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      center: false,
      maxWidth: 1440,
      child: FutureBuilder<List<ControlCenterDevice>>(
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
          final devices = _filtered(snapshot.data ?? const []);
          return ListView(
            children: [
              _Header(onRefresh: _refresh),
              const SizedBox(height: AppSpacing.md),
              _Filters(
                searchController: _searchController,
                healthFilter: _healthFilter,
                firmwareFilter: _firmwareFilter,
                calibrationFilter: _calibrationFilter,
                sort: _sort,
                onHealthChanged: (value) =>
                    setState(() => _healthFilter = value),
                onFirmwareChanged: (value) {
                  setState(() => _firmwareFilter = value ?? '');
                },
                onCalibrationChanged: (value) {
                  setState(() => _calibrationFilter = value ?? '');
                },
                onSortChanged: (value) {
                  if (value != null) setState(() => _sort = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (devices.isEmpty)
                const AppEmptyState(
                  title: 'Nessun device trovato',
                  message: 'Modifica i filtri o aggiorna la pagina.',
                  icon: Icons.memory_outlined,
                )
              else if (context.responsive.isCompact)
                _DeviceCards(devices: devices)
              else
                _DeviceTable(devices: devices),
            ],
          );
        },
      ),
    );
  }

  List<ControlCenterDevice> _filtered(List<ControlCenterDevice> devices) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = devices.where((device) {
      final haystack = [
        device.deviceId,
        device.serialNumber,
        device.clientName,
        device.siteName,
        device.siteCity,
        device.machineCode,
        device.firmwareVersion,
        device.lastOperatorName,
      ].whereType<String>().join(' ').toLowerCase();

      if (query.isNotEmpty && !haystack.contains(query)) return false;
      if (_healthFilter != null && device.health != _healthFilter) return false;
      if (_firmwareFilter.isNotEmpty &&
          (device.firmwareVersion ?? '') != _firmwareFilter) {
        return false;
      }
      if (_calibrationFilter.isNotEmpty) {
        final cal = device.calibrationState ?? 'not_available';
        if (cal != _calibrationFilter) return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (_sort) {
        case _DeviceSort.deviceId:
          return a.deviceId.compareTo(b.deviceId);
        case _DeviceSort.health:
          return _healthRank(a.health).compareTo(_healthRank(b.health));
        case _DeviceSort.lastContact:
          return (b.lastContactAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                a.lastContactAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              );
      }
    });
    return filtered;
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
          child: Text(
            'Devices',
            style: Theme.of(context).textTheme.headlineSmall,
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

class _Filters extends StatelessWidget {
  const _Filters({
    required this.searchController,
    required this.healthFilter,
    required this.firmwareFilter,
    required this.calibrationFilter,
    required this.sort,
    required this.onHealthChanged,
    required this.onFirmwareChanged,
    required this.onCalibrationChanged,
    required this.onSortChanged,
  });

  final TextEditingController searchController;
  final DeviceHealth? healthFilter;
  final String firmwareFilter;
  final String calibrationFilter;
  final _DeviceSort sort;
  final ValueChanged<DeviceHealth?> onHealthChanged;
  final ValueChanged<String?> onFirmwareChanged;
  final ValueChanged<String?> onCalibrationChanged;
  final ValueChanged<_DeviceSort?> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final fieldWidth = context.responsive.isCompact ? double.infinity : 220.0;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: context.responsive.isCompact ? double.infinity : 320,
          child: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: 'Search',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: DropdownButtonFormField<DeviceHealth?>(
            initialValue: healthFilter,
            decoration: const InputDecoration(labelText: 'Health'),
            items: [
              const DropdownMenuItem<DeviceHealth?>(
                value: null,
                child: Text('All'),
              ),
              ...DeviceHealth.values.map(
                (health) => DropdownMenuItem<DeviceHealth?>(
                  value: health,
                  child: Text(health.label),
                ),
              ),
            ],
            onChanged: onHealthChanged,
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: DropdownButtonFormField<String>(
            initialValue: calibrationFilter,
            decoration: const InputDecoration(labelText: 'Calibration'),
            items: const [
              DropdownMenuItem(value: '', child: Text('All')),
              DropdownMenuItem(value: 'valid', child: Text('Valid')),
              DropdownMenuItem(value: 'missing', child: Text('Missing')),
              DropdownMenuItem(value: 'invalid', child: Text('Invalid')),
              DropdownMenuItem(
                value: 'not_available',
                child: Text('Not available'),
              ),
            ],
            onChanged: onCalibrationChanged,
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Firmware',
              prefixIcon: Icon(Icons.system_update_alt),
            ),
            onChanged: onFirmwareChanged,
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: DropdownButtonFormField<_DeviceSort>(
            initialValue: sort,
            decoration: const InputDecoration(labelText: 'Sort'),
            items: const [
              DropdownMenuItem(
                value: _DeviceSort.lastContact,
                child: Text('Last contact'),
              ),
              DropdownMenuItem(
                value: _DeviceSort.health,
                child: Text('Health'),
              ),
              DropdownMenuItem(
                value: _DeviceSort.deviceId,
                child: Text('Device ID'),
              ),
            ],
            onChanged: onSortChanged,
          ),
        ),
      ],
    );
  }
}

class _DeviceTable extends StatelessWidget {
  const _DeviceTable({required this.devices});

  final List<ControlCenterDevice> devices;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: AppSpacing.lg,
          columns: const [
            DataColumn(label: Text('Device')),
            DataColumn(label: Text('Client')),
            DataColumn(label: Text('Site')),
            DataColumn(label: Text('Machine')),
            DataColumn(label: Text('Health')),
            DataColumn(label: Text('Last contact')),
            DataColumn(label: Text('Firmware')),
            DataColumn(label: Text('Calibration')),
            DataColumn(label: Text('Last operator/app')),
            DataColumn(label: Text('Warnings')),
          ],
          rows: devices
              .map(
                (device) => DataRow(
                  onSelectChanged: (_) {
                    context.go('/control-center/devices/${device.id}');
                  },
                  cells: [
                    DataCell(Text(device.deviceId)),
                    DataCell(Text(device.clientName ?? '-')),
                    DataCell(Text(device.siteName ?? '-')),
                    DataCell(Text(device.machineCode ?? '-')),
                    DataCell(HealthBadge(health: device.health)),
                    DataCell(Text(formatDateTime(device.lastContactAt))),
                    DataCell(Text(device.firmwareVersion ?? 'Not available')),
                    DataCell(Text(device.calibrationState ?? 'Not available')),
                    DataCell(
                      Text(
                        [
                          device.lastOperatorName,
                          device.appVersion,
                        ].whereType<String>().join(' / '),
                      ),
                    ),
                    DataCell(Text(_warnings(device))),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _DeviceCards extends StatelessWidget {
  const _DeviceCards({required this.devices});

  final List<ControlCenterDevice> devices;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: devices
          .map(
            (device) => AppSectionCard(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(device.deviceId),
                subtitle: Text(
                  [
                    device.clientName,
                    device.siteName,
                    device.machineCode,
                    formatDateTime(device.lastContactAt),
                  ].whereType<String>().join(' / '),
                ),
                trailing: HealthBadge(health: device.health),
                onTap: () => context.go('/control-center/devices/${device.id}'),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

int _healthRank(DeviceHealth health) {
  switch (health) {
    case DeviceHealth.degraded:
      return 0;
    case DeviceHealth.offline:
      return 1;
    case DeviceHealth.warning:
      return 2;
    case DeviceHealth.neverConnected:
      return 3;
    case DeviceHealth.healthy:
      return 4;
  }
}

String _warnings(ControlCenterDevice device) {
  final warnings = <String>[];
  if (device.warningCount > 0) warnings.add('${device.warningCount} warning');
  if (device.errorCount > 0) warnings.add('${device.errorCount} error');
  if (device.calibrationMissing) warnings.add('calibration');
  return warnings.isEmpty ? '-' : warnings.join(', ');
}

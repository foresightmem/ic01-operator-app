import 'package:flutter/material.dart';

import '../../../core/ui/app_design_system.dart';
import '../data/control_center_repository.dart';

class ControlCenterDiagnosticsPage extends StatefulWidget {
  const ControlCenterDiagnosticsPage({super.key});

  @override
  State<ControlCenterDiagnosticsPage> createState() =>
      _ControlCenterDiagnosticsPageState();
}

class _ControlCenterDiagnosticsPageState
    extends State<ControlCenterDiagnosticsPage> {
  final _repository = ControlCenterRepository();
  late Future<_DiagnosticsData> _future;
  String? _selectedDeviceId;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DiagnosticsData> _load() async {
    final results = await Future.wait([
      _repository.loadDevices(),
      _repository.loadSupportedCommands(),
    ]);
    return _DiagnosticsData(
      devices: results[0] as List<ControlCenterDevice>,
      commands: results[1] as List<SupportedCommand>,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _createSetProductsJob(String deviceId) async {
    setState(() => _creating = true);
    try {
      final job = await _repository.createSetProductsCommand(deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${job.command}: ${job.status}')));
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Comando non creato: $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      center: false,
      maxWidth: 1280,
      child: FutureBuilder<_DiagnosticsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoading(label: 'Caricamento diagnostiche...');
          }
          if (snapshot.hasError) {
            return AppErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const AppEmptyState(title: 'Diagnostiche non disponibili');
          }

          final selectedDevice = data.devices
              .where((device) => device.id == _selectedDeviceId)
              .firstOrNull;
          final effectiveSelectedDeviceId =
              selectedDevice?.id ??
              (data.devices.isNotEmpty ? data.devices.first.id : null);
          final supportedCommands = data.commands
              .where((cmd) => cmd.supported)
              .toList();
          final unsupportedCommands = data.commands
              .where((cmd) => !cmd.supported)
              .toList();

          return ListView(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Diagnostics',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Aggiorna',
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target device',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (data.devices.isEmpty)
                      const AppEmptyState(
                        title: 'Nessun device registrato',
                        icon: Icons.memory_outlined,
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue: effectiveSelectedDeviceId,
                        decoration: const InputDecoration(
                          labelText: 'Device',
                          prefixIcon: Icon(Icons.memory_outlined),
                        ),
                        items: data.devices
                            .map(
                              (device) => DropdownMenuItem(
                                value: device.id,
                                child: Text(
                                  [
                                    device.deviceId,
                                    device.machineCode,
                                    device.clientName,
                                  ].whereType<String>().join(' / '),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) =>
                            setState(() => _selectedDeviceId = value),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Supported Commands',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Queued - waiting for a connected operator app or device poll.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (supportedCommands.isEmpty)
                      const AppEmptyState(
                        title: 'Nessun comando supportato',
                        icon: Icons.block,
                      )
                    else
                      Column(
                        children: supportedCommands
                            .map(
                              (command) => _CommandTile(
                                command: command,
                                enabled:
                                    effectiveSelectedDeviceId != null &&
                                    !_creating,
                                onPressed:
                                    command.command == 'set_products' &&
                                        effectiveSelectedDeviceId != null
                                    ? () => _createSetProductsJob(
                                        effectiveSelectedDeviceId,
                                      )
                                    : null,
                              ),
                            )
                            .toList(growable: false),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unsupported Commands',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: unsupportedCommands
                          .map(
                            (command) => AppStatusPill(
                              label: '${command.label}: unsupported',
                              color: AppColors.muted,
                              icon: Icons.block,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CommandTile extends StatelessWidget {
  const _CommandTile({
    required this.command,
    required this.enabled,
    required this.onPressed,
  });

  final SupportedCommand command;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AppStatusPill(
        label: command.readOnly ? 'READ ONLY' : 'WRITE',
        color: command.readOnly ? AppColors.success : AppColors.warning,
        icon: command.readOnly
            ? Icons.visibility_outlined
            : Icons.edit_outlined,
      ),
      title: Text(command.label),
      subtitle: Text(command.description ?? 'Supported by current firmware.'),
      trailing: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.add_task),
        label: const Text('Crea job'),
      ),
    );
  }
}

class _DiagnosticsData {
  const _DiagnosticsData({required this.devices, required this.commands});

  final List<ControlCenterDevice> devices;
  final List<SupportedCommand> commands;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

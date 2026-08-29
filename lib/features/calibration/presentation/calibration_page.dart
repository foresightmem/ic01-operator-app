import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/ui/app_design_system.dart';
import '../application/calibration_controller.dart';
import '../application/calibration_permissions.dart';
import '../data/reactive_calibration_ble_transport.dart';
import '../domain/calibration_protocol.dart';

class CalibrationPage extends StatefulWidget {
  const CalibrationPage({super.key, required this.machineId});

  final String machineId;

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  CalibrationController? _controller;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final context = await _fetchMachineContext();
      final controller = CalibrationController(
        machine: context,
        transport: ReactiveCalibrationBleTransport(),
        permissions: const PermissionHandlerCalibrationPermissions(),
      );
      controller.addListener(_handleControllerChanged);

      if (mounted) {
        setState(() {
          _controller = controller;
          _loading = false;
        });
      } else {
        controller.dispose();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Errore caricamento calibrazione: $error';
        _loading = false;
      });
    }
  }

  Future<CalibrationMachineContext> _fetchMachineContext() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Utente non autenticato.');

    final rows = await supabase
        .from('machine_effective_consumables')
        .select('machine_id, machine_code, effective_operator_id')
        .eq('machine_id', widget.machineId)
        .limit(1);

    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) throw Exception('Macchina non trovata.');

    final effectiveOperatorId = list.first['effective_operator_id'] as String?;
    if (effectiveOperatorId != null && effectiveOperatorId != user.id) {
      throw Exception('Non sei assegnato a questa macchina.');
    }

    final machineId = list.first['machine_id'] as String? ?? widget.machineId;
    final machineCode = list.first['machine_code'] as String? ?? 'N/D';

    final machineRow = await supabase
        .from('machines')
        .select('temperature_mode')
        .eq('id', machineId)
        .maybeSingle();
    final mode = CalibrationMode.fromDb(
      machineRow?['temperature_mode'] as String?,
    );

    String? expectedDeviceId;
    String? backendWarning;
    try {
      final deviceRows = await supabase
          .from('devices')
          .select('device_id')
          .eq('machine_id', machineId)
          .limit(1);
      final devices = (deviceRows as List).cast<Map<String, dynamic>>();
      if (devices.isNotEmpty) {
        expectedDeviceId = devices.first['device_id'] as String?;
      }
    } catch (error) {
      backendWarning =
          'Debug: impossibile verificare devices in backend. Il test continua.';
    }

    return CalibrationMachineContext(
      machineId: machineId,
      machineCode: machineCode,
      mode: mode,
      expectedDeviceId: expectedDeviceId,
      backendWarning: backendWarning,
    );
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: const Text('Calibrazione')),
      body: _loading
          ? const AppLoading(label: 'Caricamento calibrazione')
          : _loadError != null
          ? AppErrorState(message: _loadError!, onRetry: _loadContext)
          : controller == null
          ? const AppEmptyState(
              title: 'Calibrazione non disponibile',
              icon: Icons.bluetooth_disabled,
            )
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return RefreshIndicator(
                  onRefresh: () => _refreshCalibration(controller),
                  child: ListView(
                    padding: context.responsive.pagePadding,
                    children: [
                      _MachineCalibrationHeader(controller: controller),
                      const SizedBox(height: AppSpacing.md),
                      if (controller.state.warningMessage != null) ...[
                        _AlertBand(
                          color: AppColors.warning,
                          icon: Icons.warning_amber,
                          text: controller.state.warningMessage!,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _CalibrationStatusCard(controller: controller),
                      const SizedBox(height: AppSpacing.md),
                      if (controller.state.phase ==
                          CalibrationPhase.selectingDevice)
                        _DeviceList(controller: controller),
                      if (controller.state.phase ==
                          CalibrationPhase.selectingDevice)
                        const SizedBox(height: AppSpacing.md),
                      _CalibrationActions(controller: controller),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _refreshCalibration(CalibrationController controller) {
    if (controller.state.selectedDevice == null) {
      return controller.scan();
    }
    return controller.refreshInfo();
  }
}

class _MachineCalibrationHeader extends StatelessWidget {
  const _MachineCalibrationHeader({required this.controller});

  final CalibrationController controller;

  @override
  Widget build(BuildContext context) {
    final machine = controller.machine;
    final state = controller.state;
    final info = state.deviceInfo;

    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            machine.machineCode,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppStatusPill(
                label: machine.mode.label,
                color: machine.mode == CalibrationMode.hot
                    ? AppColors.warning
                    : AppColors.info,
                icon: machine.mode == CalibrationMode.hot
                    ? Icons.local_fire_department
                    : Icons.ac_unit,
              ),
              if (info != null)
                AppStatusPill(
                  label: info.deviceId.isEmpty
                      ? 'Device sconosciuto'
                      : info.deviceId,
                  color: AppColors.petroleum,
                  icon: Icons.memory,
                ),
              if (info?.fwVersion != null)
                AppStatusPill(
                  label: 'FW ${info!.fwVersion}',
                  color: AppColors.muted,
                  icon: Icons.developer_board,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalibrationStatusCard extends StatelessWidget {
  const _CalibrationStatusCard({required this.controller});

  final CalibrationController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final phaseColor = _phaseColor(state.phase);
    final message =
        state.errorMessage ??
        state.lastEvent?.message ??
        _phaseMessage(state.phase);

    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_phaseIcon(state.phase), color: phaseColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _phaseLabel(state.phase),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: _showsDeterminateProgress(state.phase)
                ? state.progress.clamp(0.0, 1.0)
                : null,
            minHeight: 8,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            backgroundColor: AppColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(phaseColor),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          if (state.lastEvent != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppStatusPill(
              label:
                  'Evento ${state.lastEvent!.rawType} #${state.lastEvent!.seq ?? '-'}',
              color: AppColors.info,
              icon: Icons.notifications_active_outlined,
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.controller});

  final CalibrationController controller;

  @override
  Widget build(BuildContext context) {
    final devices = controller.state.devices;
    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final device in devices)
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(device.displayName),
              subtitle: Text('${device.id} - RSSI ${device.rssi}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: controller.state.isBusy
                  ? null
                  : () => controller.connect(device),
            ),
        ],
      ),
    );
  }
}

class _CalibrationActions extends StatelessWidget {
  const _CalibrationActions({required this.controller});

  final CalibrationController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final buttons = <Widget>[];

    if (_canScan(state)) {
      buttons.add(
        FilledButton.icon(
          onPressed: state.isBusy ? null : controller.scan,
          icon: const Icon(Icons.search),
          label: const Text('Cerca IC01'),
        ),
      );
    }

    if (state.phase == CalibrationPhase.maintenanceRequired) {
      buttons.add(
        FilledButton.icon(
          onPressed: state.isBusy ? null : controller.refreshInfo,
          icon: const Icon(Icons.refresh),
          label: const Text('Rileggi'),
        ),
      );
    }

    if (state.canStart) {
      buttons.add(
        FilledButton.icon(
          onPressed: controller.start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Avvia'),
        ),
      );
    }

    if (state.canCancel) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: controller.cancel,
          icon: const Icon(Icons.stop),
          label: const Text('Annulla'),
        ),
      );
    }

    if (_canReconnect(state)) {
      buttons.add(
        FilledButton.icon(
          onPressed: controller.reconnectAndRequestStatus,
          icon: const Icon(Icons.bluetooth_connected),
          label: const Text('Riconnetti'),
        ),
      );
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: buttons,
    );
  }

  bool _canScan(CalibrationControllerState state) {
    if (state.isConnected) return false;
    return switch (state.phase) {
      CalibrationPhase.idle ||
      CalibrationPhase.permissionsRequired ||
      CalibrationPhase.noDevices ||
      CalibrationPhase.failed ||
      CalibrationPhase.completed ||
      CalibrationPhase.cancelled ||
      CalibrationPhase.unsupportedPlatform => true,
      _ => false,
    };
  }

  bool _canReconnect(CalibrationControllerState state) {
    if (state.selectedDevice == null) return false;
    if (state.isConnected) return false;
    return switch (state.phase) {
      CalibrationPhase.disconnected ||
      CalibrationPhase.completed ||
      CalibrationPhase.failed ||
      CalibrationPhase.cancelled => true,
      _ => false,
    };
  }
}

class _AlertBand extends StatelessWidget {
  const _AlertBand({
    required this.color,
    required this.icon,
    required this.text,
  });

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _showsDeterminateProgress(CalibrationPhase phase) {
  return switch (phase) {
    CalibrationPhase.running ||
    CalibrationPhase.completed ||
    CalibrationPhase.cancelled ||
    CalibrationPhase.failed => true,
    _ => false,
  };
}

String _phaseLabel(CalibrationPhase phase) {
  return switch (phase) {
    CalibrationPhase.idle => 'Pronta per la ricerca',
    CalibrationPhase.unsupportedPlatform => 'Piattaforma non supportata',
    CalibrationPhase.permissionsRequired => 'Permessi richiesti',
    CalibrationPhase.scanning => 'Ricerca IC01',
    CalibrationPhase.noDevices => 'Nessun dispositivo',
    CalibrationPhase.selectingDevice => 'Seleziona dispositivo',
    CalibrationPhase.connecting => 'Connessione',
    CalibrationPhase.verifyingIdentity => 'Verifica device',
    CalibrationPhase.maintenanceRequired => 'Maintenance richiesta',
    CalibrationPhase.ready => 'Pronta',
    CalibrationPhase.starting => 'Avvio',
    CalibrationPhase.running => 'Calibrazione in corso',
    CalibrationPhase.cancelling => 'Annullamento',
    CalibrationPhase.completed => 'Calibrazione completata',
    CalibrationPhase.cancelled => 'Calibrazione annullata',
    CalibrationPhase.failed => 'Calibrazione fallita',
    CalibrationPhase.disconnected => 'Disconnessa',
  };
}

String _phaseMessage(CalibrationPhase phase) {
  return switch (phase) {
    CalibrationPhase.idle => 'Cerca una macchina IC01 nelle vicinanze.',
    CalibrationPhase.unsupportedPlatform =>
      'Questa v1 abilita la calibrazione BLE solo su Android.',
    CalibrationPhase.permissionsRequired =>
      'Apri le impostazioni e autorizza Bluetooth e posizione.',
    CalibrationPhase.scanning => 'Ricerca dispositivi con servizio IC01.',
    CalibrationPhase.noDevices => 'Controlla che il firmware BLE sia avviato.',
    CalibrationPhase.selectingDevice => 'Scegli il dispositivo da calibrare.',
    CalibrationPhase.connecting => 'Apertura connessione GATT.',
    CalibrationPhase.verifyingIdentity =>
      'Lettura info e controllo protocollo.',
    CalibrationPhase.maintenanceRequired =>
      'Abilita maintenance da seriale o BOOT, poi rileggi.',
    CalibrationPhase.ready => 'Puoi avviare la calibrazione.',
    CalibrationPhase.starting => 'Invio comando cal.start.',
    CalibrationPhase.running => 'In attesa degli eventi firmware.',
    CalibrationPhase.cancelling => 'Invio comando cal.cancel.',
    CalibrationPhase.completed => 'Profilo salvato dal firmware.',
    CalibrationPhase.cancelled => 'Sessione annullata.',
    CalibrationPhase.failed => 'Controlla il messaggio e riprova.',
    CalibrationPhase.disconnected =>
      'Riconnetti per chiedere lo stato della sessione.',
  };
}

Color _phaseColor(CalibrationPhase phase) {
  return switch (phase) {
    CalibrationPhase.completed => AppColors.success,
    CalibrationPhase.failed ||
    CalibrationPhase.permissionsRequired ||
    CalibrationPhase.unsupportedPlatform => AppColors.danger,
    CalibrationPhase.maintenanceRequired ||
    CalibrationPhase.cancelled ||
    CalibrationPhase.disconnected => AppColors.warning,
    CalibrationPhase.running ||
    CalibrationPhase.starting ||
    CalibrationPhase.scanning ||
    CalibrationPhase.connecting ||
    CalibrationPhase.verifyingIdentity ||
    CalibrationPhase.cancelling => AppColors.info,
    _ => AppColors.petroleum,
  };
}

IconData _phaseIcon(CalibrationPhase phase) {
  return switch (phase) {
    CalibrationPhase.completed => Icons.check_circle_outline,
    CalibrationPhase.failed => Icons.error_outline,
    CalibrationPhase.permissionsRequired => Icons.lock_outline,
    CalibrationPhase.unsupportedPlatform => Icons.phone_android,
    CalibrationPhase.maintenanceRequired => Icons.build_circle_outlined,
    CalibrationPhase.cancelled => Icons.cancel_outlined,
    CalibrationPhase.disconnected => Icons.bluetooth_disabled,
    CalibrationPhase.running => Icons.sensors,
    CalibrationPhase.scanning => Icons.bluetooth_searching,
    CalibrationPhase.connecting => Icons.bluetooth_connected,
    _ => Icons.tune,
  };
}

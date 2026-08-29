import 'package:flutter/material.dart';

import '../../../core/ui/app_design_system.dart';
import '../data/control_center_repository.dart';
import 'widgets/control_center_widgets.dart';

class ControlCenterEventsPage extends StatefulWidget {
  const ControlCenterEventsPage({super.key});

  @override
  State<ControlCenterEventsPage> createState() =>
      _ControlCenterEventsPageState();
}

class _ControlCenterEventsPageState extends State<ControlCenterEventsPage> {
  final _repository = ControlCenterRepository();
  final _deviceController = TextEditingController();
  final _eventTypeController = TextEditingController();
  late Future<List<ControlCenterEvent>> _future;
  String _severity = '';
  int _limit = 100;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _deviceController.dispose();
    _eventTypeController.dispose();
    super.dispose();
  }

  Future<List<ControlCenterEvent>> _load() {
    return _repository.loadEvents(
      deviceId: _deviceController.text,
      severity: _severity,
      eventType: _eventTypeController.text,
      limit: _limit,
    );
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      center: false,
      maxWidth: 1440,
      child: FutureBuilder<List<ControlCenterEvent>>(
        future: _future,
        builder: (context, snapshot) {
          return ListView(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Events',
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
              _Filters(
                deviceController: _deviceController,
                eventTypeController: _eventTypeController,
                severity: _severity,
                limit: _limit,
                onSeverityChanged: (value) {
                  setState(() => _severity = value ?? '');
                  _refresh();
                },
                onLimitChanged: (value) {
                  if (value == null) return;
                  setState(() => _limit = value);
                  _refresh();
                },
                onApply: _refresh,
              ),
              const SizedBox(height: AppSpacing.md),
              if (snapshot.connectionState == ConnectionState.waiting)
                const AppLoading(label: 'Caricamento eventi...')
              else if (snapshot.hasError)
                AppErrorState(
                  message: snapshot.error.toString(),
                  onRetry: _refresh,
                )
              else
                EventTable(
                  events: snapshot.data ?? const [],
                  onTap: (event) => _showEventDetail(context, event),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.deviceController,
    required this.eventTypeController,
    required this.severity,
    required this.limit,
    required this.onSeverityChanged,
    required this.onLimitChanged,
    required this.onApply,
  });

  final TextEditingController deviceController;
  final TextEditingController eventTypeController;
  final String severity;
  final int limit;
  final ValueChanged<String?> onSeverityChanged;
  final ValueChanged<int?> onLimitChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final fieldWidth = context.responsive.isCompact ? double.infinity : 220.0;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: fieldWidth,
          child: TextField(
            controller: deviceController,
            decoration: const InputDecoration(
              labelText: 'Device UUID',
              prefixIcon: Icon(Icons.memory_outlined),
            ),
            onSubmitted: (_) => onApply(),
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: TextField(
            controller: eventTypeController,
            decoration: const InputDecoration(
              labelText: 'Event type',
              prefixIcon: Icon(Icons.label_outline),
            ),
            onSubmitted: (_) => onApply(),
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: DropdownButtonFormField<String>(
            initialValue: severity,
            decoration: const InputDecoration(labelText: 'Severity'),
            items: const [
              DropdownMenuItem(value: '', child: Text('All')),
              DropdownMenuItem(value: 'info', child: Text('Info')),
              DropdownMenuItem(value: 'warning', child: Text('Warning')),
              DropdownMenuItem(value: 'error', child: Text('Error')),
              DropdownMenuItem(value: 'critical', child: Text('Critical')),
            ],
            onChanged: onSeverityChanged,
          ),
        ),
        SizedBox(
          width: fieldWidth,
          child: DropdownButtonFormField<int>(
            initialValue: limit,
            decoration: const InputDecoration(labelText: 'Limit'),
            items: const [
              DropdownMenuItem(value: 50, child: Text('50')),
              DropdownMenuItem(value: 100, child: Text('100')),
              DropdownMenuItem(value: 250, child: Text('250')),
              DropdownMenuItem(value: 500, child: Text('500')),
            ],
            onChanged: onLimitChanged,
          ),
        ),
        ElevatedButton.icon(
          onPressed: onApply,
          icon: const Icon(Icons.filter_alt_outlined),
          label: const Text('Filtra'),
        ),
      ],
    );
  }
}

void _showEventDetail(BuildContext context, ControlCenterEvent event) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(event.eventType),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  SeverityBadge(severity: event.severity),
                  AppStatusPill(
                    label: event.source,
                    color: AppColors.petroleum,
                    icon: Icons.source_outlined,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(event.summary ?? 'No summary'),
              const SizedBox(height: AppSpacing.sm),
              Text(
                [
                  event.deviceId,
                  event.machineCode,
                  event.clientName,
                  event.operatorName,
                  event.firmwareVersion,
                  event.appVersion,
                ].whereType<String>().join(' / '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              JsonPayloadView(payload: event.payload),
            ],
          ),
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

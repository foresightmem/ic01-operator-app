import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/ui/app_design_system.dart';

enum PublicTicketReason {
  outOfStock('out_of_stock', 'Scorte finite'),
  malfunction('malfunction', 'Malfunzionamento');

  const PublicTicketReason(this.value, this.label);

  final String value;
  final String label;
}

String normalizePublicMachineCode(String value) {
  return value.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '');
}

String publicTicketReasonLabel(String value) {
  for (final reason in PublicTicketReason.values) {
    if (reason.value == value) return reason.label;
  }
  return value;
}

class PublicSupportPage extends StatefulWidget {
  const PublicSupportPage({super.key});

  @override
  State<PublicSupportPage> createState() => _PublicSupportPageState();
}

class _PublicSupportPageState extends State<PublicSupportPage> {
  final _formKey = GlobalKey<FormState>();
  final _machineCodeController = TextEditingController();

  PublicTicketReason? _reason;
  bool _submitting = false;
  bool _submitted = false;
  bool _duplicate = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _machineCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_reason == null) {
      setState(() => _error = 'Seleziona un motivo.');
      return;
    }
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
      _message = null;
      _duplicate = false;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'public_maintenance_ticket',
        body: {
          'machine_code': _machineCodeController.text,
          'reason': _reason!.value,
        },
      );

      final data = response.data;
      final map = data is Map
          ? data.cast<String, dynamic>()
          : <String, dynamic>{};
      final ok = map['ok'] == true;
      final message = map['message'] as String?;

      if (!ok) {
        setState(() {
          _error =
              message ?? 'Non siamo riusciti a registrare la segnalazione.';
          _submitting = false;
        });
        return;
      }

      setState(() {
        _submitted = true;
        _duplicate = map['duplicate'] == true;
        _message = message ?? 'Segnalazione inviata correttamente.';
        _submitting = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Servizio temporaneamente non disponibile. Riprova tra poco.';
        _submitting = false;
      });
    }
  }

  void _resetForm() {
    setState(() {
      _submitted = false;
      _duplicate = false;
      _message = null;
      _error = null;
      _reason = null;
      _machineCodeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: context.responsive.pagePadding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: context.responsive.formMaxWidth,
              ),
              child: _submitted
                  ? _SuccessState(
                      duplicate: _duplicate,
                      message:
                          _message ?? 'Segnalazione inviata correttamente.',
                      onNewReport: _resetForm,
                    )
                  : AppSectionCard(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'MAGMA',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: AppColors.black,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Segnalazione manutenzione',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Inserisci il codice riportato sulla macchina.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _machineCodeController,
                              textCapitalization: TextCapitalization.characters,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: const InputDecoration(
                                labelText: 'Codice macchina',
                                prefixIcon: Icon(Icons.qr_code_2),
                              ),
                              onChanged: (_) {
                                if (_error != null) {
                                  setState(() => _error = null);
                                }
                              },
                              validator: (value) {
                                final normalized = normalizePublicMachineCode(
                                  value ?? '',
                                );
                                if (normalized.isEmpty) {
                                  return 'Inserisci il codice macchina.';
                                }
                                if (normalized.length < 2) {
                                  return 'Controlla il codice macchina.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Motivo',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            for (final reason in PublicTicketReason.values)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _ReasonChoice(
                                  label: reason.label,
                                  selected: _reason == reason,
                                  enabled: !_submitting,
                                  onTap: () {
                                    setState(() {
                                      _reason = reason;
                                      _error = null;
                                    });
                                  },
                                ),
                              ),
                            if (_error != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            ElevatedButton.icon(
                              onPressed: _submitting ? null : _submit,
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                              label: Text(
                                _submitting
                                    ? 'Invio in corso...'
                                    : 'Invia segnalazione',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasonChoice extends StatelessWidget {
  const _ReasonChoice({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
          ),
          color: selected ? AppColors.petroleumSoft : AppColors.surface,
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? theme.colorScheme.primary : AppColors.muted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessState extends StatelessWidget {
  const _SuccessState({
    required this.duplicate,
    required this.message,
    required this.onNewReport,
  });

  final bool duplicate;
  final String message;
  final VoidCallback onNewReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppSectionCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            duplicate ? Icons.info_outline : Icons.check_circle_outline,
            size: 56,
            color: duplicate ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            duplicate ? 'Segnalazione già aperta' : 'Segnalazione inviata',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onNewReport,
            icon: const Icon(Icons.add),
            label: const Text('Nuova segnalazione'),
          ),
        ],
      ),
    );
  }
}

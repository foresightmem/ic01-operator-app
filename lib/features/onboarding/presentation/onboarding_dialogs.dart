import 'dart:async';

import 'package:flutter/material.dart';

import '../data/customer_machine_onboarding_service.dart';

String _newAddressSessionToken() =>
    'addr-${DateTime.now().microsecondsSinceEpoch}-${Object().hashCode}';

Future<ResolvedAddress> _resolveTypedAddressOrFallback(
  CustomerMachineOnboardingService service,
  String input,
) async {
  try {
    return await service.resolveTypedAddress(
      input: input,
      sessionToken: _newAddressSessionToken(),
    );
  } catch (e) {
    onboardingUserMessage(e, OnboardingAction.load);
    return ResolvedAddress(
      address: normalizedRequiredText(input),
      city: null,
      latitude: null,
      longitude: null,
    );
  }
}

Future<bool> showCreateClientDialog(BuildContext context) async {
  final created = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _CreateClientDialog(),
  );
  return created ?? false;
}

Future<bool> showCreateSiteDialog(
  BuildContext context, {
  required String clientId,
}) async {
  final created = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CreateSiteDialog(clientId: clientId),
  );
  return created ?? false;
}

Future<bool> showCreateMachineDialog(
  BuildContext context, {
  String? initialClientId,
}) async {
  final created = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CreateMachineDialog(initialClientId: initialClientId),
  );
  return created ?? false;
}

class _CreateClientDialog extends StatefulWidget {
  const _CreateClientDialog();

  @override
  State<_CreateClientDialog> createState() => _CreateClientDialogState();
}

class _CreateClientDialogState extends State<_CreateClientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _service = CustomerMachineOnboardingService();
  final _clientNameController = TextEditingController();
  final _siteNameController = TextEditingController();
  final _siteAddressController = TextEditingController();

  bool _saving = false;
  String? _error;
  String? _siteCity;
  double? _siteLatitude;
  double? _siteLongitude;

  @override
  void dispose() {
    _clientNameController.dispose();
    _siteNameController.dispose();
    _siteAddressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      var siteAddress = _siteAddressController.text;
      var siteCity = _siteCity;
      if (normalizedRequiredText(siteCity ?? '').isEmpty) {
        final resolved = await _resolveTypedAddressOrFallback(
          _service,
          siteAddress,
        );
        if (resolved.address.trim().isNotEmpty) {
          siteAddress = resolved.address;
          _siteAddressController.text = resolved.address;
        }
        siteCity = resolved.city;
        _siteLatitude = resolved.latitude;
        _siteLongitude = resolved.longitude;
        _siteCity = siteCity;
      }

      final created = await _service.createClientWithPrimarySite(
        clientName: _clientNameController.text,
        siteName: _siteNameController.text,
        siteAddress: siteAddress,
        siteCity: siteCity,
        siteLatitude: _siteLatitude,
        siteLongitude: _siteLongitude,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cliente ${created.clientName} creato.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = onboardingUserMessage(e, OnboardingAction.createClient);
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuovo cliente'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _clientNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome cliente',
                    prefixIcon: Icon(Icons.apartment),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (normalizedRequiredText(value ?? '').isEmpty) {
                      return 'Inserisci il nome cliente.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _siteNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome sede',
                    hintText: 'Sede principale',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _AddressAutocompleteField(
                  service: _service,
                  controller: _siteAddressController,
                  labelText: 'Indirizzo sede principale',
                  onAddressResolved: (resolved) {
                    _siteCity = resolved?.city;
                    _siteLatitude = resolved?.latitude;
                    _siteLongitude = resolved?.longitude;
                  },
                  validator: (value) {
                    if (normalizedRequiredText(value ?? '').isEmpty) {
                      return 'Inserisci l\'indirizzo della sede.';
                    }
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Salva'),
        ),
      ],
    );
  }
}

class _CreateSiteDialog extends StatefulWidget {
  final String clientId;

  const _CreateSiteDialog({required this.clientId});

  @override
  State<_CreateSiteDialog> createState() => _CreateSiteDialogState();
}

class _CreateSiteDialogState extends State<_CreateSiteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _service = CustomerMachineOnboardingService();
  final _siteNameController = TextEditingController();
  final _siteAddressController = TextEditingController();

  bool _saving = false;
  String? _error;
  String? _siteCity;
  double? _siteLatitude;
  double? _siteLongitude;

  @override
  void dispose() {
    _siteNameController.dispose();
    _siteAddressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      var siteAddress = _siteAddressController.text;
      var siteCity = _siteCity;
      if (normalizedRequiredText(siteCity ?? '').isEmpty) {
        final resolved = await _resolveTypedAddressOrFallback(
          _service,
          siteAddress,
        );
        if (resolved.address.trim().isNotEmpty) {
          siteAddress = resolved.address;
          _siteAddressController.text = resolved.address;
        }
        siteCity = resolved.city;
        _siteLatitude = resolved.latitude;
        _siteLongitude = resolved.longitude;
        _siteCity = siteCity;
      }

      final site = await _service.addSiteToClient(
        clientId: widget.clientId,
        siteName: _siteNameController.text,
        siteAddress: siteAddress,
        siteCity: siteCity,
        siteLatitude: _siteLatitude,
        siteLongitude: _siteLongitude,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sede ${site.name} aggiunta.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = onboardingUserMessage(e, OnboardingAction.createSite);
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuova sede'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _siteNameController,
                decoration: const InputDecoration(
                  labelText: 'Nome sede',
                  hintText: 'Sede',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              _AddressAutocompleteField(
                service: _service,
                controller: _siteAddressController,
                labelText: 'Indirizzo',
                onAddressResolved: (resolved) {
                  _siteCity = resolved?.city;
                  _siteLatitude = resolved?.latitude;
                  _siteLongitude = resolved?.longitude;
                },
                validator: (value) {
                  if (normalizedRequiredText(value ?? '').isEmpty) {
                    return 'Inserisci l\'indirizzo della sede.';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Salva'),
        ),
      ],
    );
  }
}

class _CreateMachineDialog extends StatefulWidget {
  final String? initialClientId;

  const _CreateMachineDialog({this.initialClientId});

  @override
  State<_CreateMachineDialog> createState() => _CreateMachineDialogState();
}

class _CreateMachineDialogState extends State<_CreateMachineDialog> {
  final _formKey = GlobalKey<FormState>();
  final _service = CustomerMachineOnboardingService();
  final _codeController = TextEditingController();
  final _capacityController = TextEditingController();
  final _hwSerialController = TextEditingController();

  bool _loading = true;
  bool _loadingSites = false;
  bool _saving = false;
  String? _error;
  String? _role;

  List<OnboardingClient> _clients = [];
  List<OnboardingSite> _sites = [];
  List<OnboardingOperator> _operators = [];

  String? _selectedClientId;
  String? _selectedSiteId;
  String? _selectedOperatorId;
  OnboardingMachineType _selectedType = OnboardingMachineType.hot;

  bool get _isAdmin => _role == 'admin';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _capacityController.dispose();
    _hwSerialController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final role = await _service.currentRole();
      final clients = await _service.loadClients();
      final operators = role == 'admin'
          ? await _service.loadRefillOperators()
          : <OnboardingOperator>[];

      String? clientId = widget.initialClientId;
      if (clientId == null || !clients.any((c) => c.id == clientId)) {
        clientId = clients.isNotEmpty ? clients.first.id : null;
      }

      setState(() {
        _role = role;
        _clients = clients;
        _operators = operators;
        _selectedClientId = clientId;
        _selectedOperatorId = operators.isNotEmpty ? operators.first.id : null;
        _loading = false;
      });

      if (clientId != null) {
        await _loadSites(clientId);
      }
    } catch (e) {
      setState(() {
        _error = onboardingUserMessage(e, OnboardingAction.load);
        _loading = false;
      });
    }
  }

  Future<void> _loadSites(String clientId) async {
    setState(() {
      _loadingSites = true;
      _sites = [];
      _selectedSiteId = null;
    });

    try {
      final sites = await _service.loadSites(clientId);
      setState(() {
        _sites = sites;
        _selectedSiteId = sites.isNotEmpty ? sites.first.id : null;
        _loadingSites = false;
      });
    } catch (e) {
      setState(() {
        _error = onboardingUserMessage(e, OnboardingAction.load);
        _loadingSites = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    final clientId = _selectedClientId;
    final siteId = _selectedSiteId;
    final capacity = parsePositiveInt(_capacityController.text);
    if (clientId == null || siteId == null || capacity == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final machine = await _service.createMachine(
        clientId: clientId,
        siteId: siteId,
        code: _codeController.text,
        type: _selectedType,
        capacityUnits: capacity,
        assignedOperatorId: _isAdmin ? _selectedOperatorId : null,
        hwSerial: _hwSerialController.text,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Macchina ${machine.machineCode} creata.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = onboardingUserMessage(e, OnboardingAction.createMachine);
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuova macchina'),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _buildForm(context),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: _saving || _loading || _clients.isEmpty || _sites.isEmpty
              ? null
              : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Salva'),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    if (_clients.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Crea prima almeno un cliente.'),
      );
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedClientId,
              decoration: const InputDecoration(
                labelText: 'Cliente',
                prefixIcon: Icon(Icons.apartment),
              ),
              items: _clients
                  .map(
                    (client) => DropdownMenuItem(
                      value: client.id,
                      child: Text(client.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (clientId) {
                      setState(() {
                        _selectedClientId = clientId;
                      });
                      if (clientId != null) {
                        _loadSites(clientId);
                      }
                    },
              validator: (value) =>
                  value == null ? 'Seleziona un cliente.' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('${_selectedClientId}_${_sites.length}'),
              initialValue: _selectedSiteId,
              decoration: InputDecoration(
                labelText: 'Sede',
                prefixIcon: _loadingSites
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.place_outlined),
              ),
              items: _sites
                  .map(
                    (site) => DropdownMenuItem(
                      value: site.id,
                      child: Text(site.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving || _loadingSites
                  ? null
                  : (siteId) {
                      setState(() {
                        _selectedSiteId = siteId;
                      });
                    },
              validator: (value) =>
                  value == null ? 'Seleziona una sede.' : null,
            ),
            if (_selectedSiteId != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _sites
                        .firstWhere((site) => site.id == _selectedSiteId)
                        .displaySubtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SegmentedButton<OnboardingMachineType>(
              segments: const [
                ButtonSegment(
                  value: OnboardingMachineType.hot,
                  icon: Icon(Icons.local_fire_department),
                  label: Text('Caldo'),
                ),
                ButtonSegment(
                  value: OnboardingMachineType.cold,
                  icon: Icon(Icons.ac_unit),
                  label: Text('Freddo'),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: _saving
                  ? null
                  : (selection) {
                      setState(() {
                        _selectedType = selection.first;
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _capacityController,
              decoration: const InputDecoration(
                labelText: 'Capacità dosi monitorate',
                hintText: 'Dosi del fattore caldo/freddo selezionato',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (parsePositiveInt(value ?? '') == null) {
                  return 'Inserisci un intero positivo.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Codice macchina',
                prefixIcon: Icon(Icons.qr_code_2),
              ),
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.characters,
              validator: (value) {
                if (!isValidMachineCodeInput(value ?? '')) {
                  return 'Inserisci il codice macchina.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            if (_isAdmin) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedOperatorId,
                decoration: const InputDecoration(
                  labelText: 'Operatore assegnatario',
                  prefixIcon: Icon(Icons.engineering_outlined),
                ),
                items: _operators
                    .map(
                      (operator) => DropdownMenuItem(
                        value: operator.id,
                        child: Text(operator.name),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (operatorId) {
                        setState(() {
                          _selectedOperatorId = operatorId;
                        });
                      },
                validator: (value) =>
                    value == null ? 'Seleziona un operatore.' : null,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _hwSerialController,
              decoration: const InputDecoration(
                labelText: 'Seriale hardware',
                prefixIcon: Icon(Icons.memory),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AddressAutocompleteField extends StatefulWidget {
  final CustomerMachineOnboardingService service;
  final TextEditingController controller;
  final String labelText;
  final ValueChanged<ResolvedAddress?> onAddressResolved;
  final FormFieldValidator<String>? validator;

  const _AddressAutocompleteField({
    required this.service,
    required this.controller,
    required this.labelText,
    required this.onAddressResolved,
    this.validator,
  });

  @override
  State<_AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

class _AddressAutocompleteFieldState extends State<_AddressAutocompleteField> {
  final _sessionToken = _newAddressSessionToken();

  Timer? _debounce;
  List<AddressSuggestion> _suggestions = [];
  bool _loading = false;
  bool _applyingSelection = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    if (_applyingSelection) return;

    widget.onAddressResolved(null);
    _debounce?.cancel();

    final input = normalizedRequiredText(value);
    if (input.length < 3) {
      setState(() {
        _suggestions = [];
        _loading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(input);
    });
  }

  Future<void> _search(String input) async {
    setState(() {
      _loading = true;
    });

    try {
      final suggestions = await widget.service.searchAddressSuggestions(
        input: input,
        sessionToken: _sessionToken,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
        _loading = false;
      });
    } catch (e) {
      onboardingUserMessage(e, OnboardingAction.load);
      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _loading = false;
      });
    }
  }

  Future<void> _select(AddressSuggestion suggestion) async {
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _suggestions = [];
    });

    try {
      final resolved = await widget.service.resolveAddressSuggestion(
        placeId: suggestion.placeId,
        sessionToken: _sessionToken,
      );

      _applyingSelection = true;
      widget.controller.text = resolved.address.isEmpty
          ? suggestion.description
          : resolved.address;
      widget.onAddressResolved(resolved);
      _applyingSelection = false;
    } catch (e) {
      onboardingUserMessage(e, OnboardingAction.load);
      _applyingSelection = true;
      widget.controller.text = suggestion.description;
      widget.onAddressResolved(null);
      _applyingSelection = false;
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: widget.labelText,
            prefixIcon: const Icon(Icons.map_outlined),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          minLines: 1,
          maxLines: 3,
          onChanged: _onChanged,
          validator: widget.validator,
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final suggestion = _suggestions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(suggestion.description),
                  onTap: () => _select(suggestion),
                );
              },
            ),
          ),
      ],
    );
  }
}

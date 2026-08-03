import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum OnboardingMachineType { hot, cold }

enum OnboardingAction {
  load,
  createClient,
  createSite,
  createMachine,
  deleteClient,
}

String machineTypeToDb(OnboardingMachineType type) {
  switch (type) {
    case OnboardingMachineType.hot:
      return 'hot';
    case OnboardingMachineType.cold:
      return 'cold';
  }
}

String machineTypeLabel(OnboardingMachineType type) {
  switch (type) {
    case OnboardingMachineType.hot:
      return 'Caldo';
    case OnboardingMachineType.cold:
      return 'Freddo';
  }
}

String normalizedRequiredText(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

String normalizeMachineCodeInput(String value) {
  return normalizedRequiredText(value).toUpperCase();
}

bool isValidMachineCodeInput(String value) {
  return normalizeMachineCodeInput(value).isNotEmpty;
}

String onboardingUserMessage(Object error, OnboardingAction action) {
  debugPrint('Onboarding ${action.name} failed: $error');

  if (error is PostgrestException) {
    debugPrint(
      'PostgREST code=${error.code} message=${error.message} '
      'details=${error.details} hint=${error.hint}',
    );

    if (error.code == 'PGRST202') {
      return 'Funzione non disponibile. Riprova oppure contatta l\'amministratore.';
    }
    if (error.code == '23505' ||
        error.message.toLowerCase().contains('codice macchina')) {
      return 'Il codice macchina è già in uso.';
    }
    if (error.code == '42501' ||
        error.message.toLowerCase().contains('permission denied') ||
        error.message.toLowerCase().contains('non autorizzato') ||
        error.message.toLowerCase().contains('ruolo non autorizzato')) {
      return 'Non hai i permessi per completare questa operazione.';
    }
    if (error.message.toLowerCase().contains('sede selezionata') ||
        error.message.toLowerCase().contains('cliente non trovato')) {
      return 'Cliente o sede non validi. Aggiorna i dati e riprova.';
    }
    if (error.message.toLowerCase().contains('non cancellabile')) {
      return 'Questo cliente non può essere eliminato perché contiene macchine, ticket o visite.';
    }
  }

  final text = error.toString().toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('clientexception') ||
      text.contains('xmlhttprequest') ||
      text.contains('network')) {
    return 'Errore di rete. Controlla la connessione e riprova.';
  }

  switch (action) {
    case OnboardingAction.load:
      return 'Impossibile caricare i dati. Riprova oppure contatta l\'amministratore.';
    case OnboardingAction.createClient:
      return 'Impossibile creare il cliente. Riprova oppure contatta l\'amministratore.';
    case OnboardingAction.createSite:
      return 'Impossibile creare la sede. Riprova oppure contatta l\'amministratore.';
    case OnboardingAction.createMachine:
      return 'Impossibile creare la macchina. Riprova oppure contatta l\'amministratore.';
    case OnboardingAction.deleteClient:
      return 'Impossibile eliminare il cliente. Riprova oppure contatta l\'amministratore.';
  }
}

int? parsePositiveInt(String value) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

class OnboardingClient {
  final String id;
  final String name;

  const OnboardingClient({required this.id, required this.name});

  factory OnboardingClient.fromMap(Map<String, dynamic> map) {
    return OnboardingClient(
      id: map['id'] as String,
      name: (map['name'] as String?) ?? 'Senza nome',
    );
  }
}

class OnboardingSite {
  final String id;
  final String clientId;
  final String name;
  final String? address;
  final String? city;
  final double? latitude;
  final double? longitude;

  const OnboardingSite({
    required this.id,
    required this.clientId,
    required this.name,
    required this.address,
    required this.city,
    required this.latitude,
    required this.longitude,
  });

  factory OnboardingSite.fromMap(Map<String, dynamic> map) {
    return OnboardingSite(
      id: map['id'] as String,
      clientId: map['client_id'] as String,
      name: (map['name'] as String?) ?? 'Sede',
      address: map['address'] as String?,
      city: map['city'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  String get displaySubtitle {
    final parts = <String>[
      if ((address ?? '').trim().isNotEmpty) address!.trim(),
      if ((city ?? '').trim().isNotEmpty) city!.trim(),
    ];
    return parts.isEmpty ? 'Indirizzo non disponibile' : parts.join(' - ');
  }
}

class AddressSuggestion {
  final String placeId;
  final String description;

  const AddressSuggestion({required this.placeId, required this.description});

  factory AddressSuggestion.fromMap(Map<String, dynamic> map) {
    return AddressSuggestion(
      placeId: (map['place_id'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
    );
  }
}

class ResolvedAddress {
  final String address;
  final String? city;
  final double? latitude;
  final double? longitude;

  const ResolvedAddress({
    required this.address,
    required this.city,
    required this.latitude,
    required this.longitude,
  });

  factory ResolvedAddress.fromMap(Map<String, dynamic> map) {
    final city = (map['city'] as String?)?.trim();
    return ResolvedAddress(
      address: (map['address'] as String?) ?? '',
      city: city == null || city.isEmpty ? null : city,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }
}

class OnboardingOperator {
  final String id;
  final String name;

  const OnboardingOperator({required this.id, required this.name});

  factory OnboardingOperator.fromMap(Map<String, dynamic> map) {
    final name = (map['full_name'] as String?)?.trim();
    return OnboardingOperator(
      id: map['id'] as String,
      name: name == null || name.isEmpty ? 'Operatore' : name,
    );
  }
}

class CreatedClientSite {
  final String clientId;
  final String clientName;
  final String siteId;
  final String siteName;

  const CreatedClientSite({
    required this.clientId,
    required this.clientName,
    required this.siteId,
    required this.siteName,
  });

  factory CreatedClientSite.fromMap(Map<String, dynamic> map) {
    return CreatedClientSite(
      clientId: map['client_id'] as String,
      clientName: map['client_name'] as String,
      siteId: map['site_id'] as String,
      siteName: map['site_name'] as String,
    );
  }
}

class CreatedMachine {
  final String machineId;
  final String machineCode;

  const CreatedMachine({required this.machineId, required this.machineCode});

  factory CreatedMachine.fromMap(Map<String, dynamic> map) {
    return CreatedMachine(
      machineId: map['machine_id'] as String,
      machineCode: map['machine_code'] as String,
    );
  }
}

class CustomerMachineOnboardingService {
  CustomerMachineOnboardingService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String?> currentRole() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final row = await _client
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();

    return row?['role'] as String?;
  }

  Future<List<OnboardingClient>> loadClients() async {
    final rows = await _client
        .from('clients')
        .select('id, name')
        .order('name', ascending: true);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(OnboardingClient.fromMap)
        .toList();
  }

  Future<List<OnboardingSite>> loadSites(String clientId) async {
    final rows = await _client
        .from('sites')
        .select('id, client_id, name, address, city, latitude, longitude')
        .eq('client_id', clientId)
        .order('name', ascending: true);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(OnboardingSite.fromMap)
        .toList();
  }

  Future<List<OnboardingOperator>> loadRefillOperators() async {
    final rows = await _client
        .from('profiles')
        .select('id, full_name')
        .eq('role', 'refill_operator')
        .order('full_name', ascending: true);

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(OnboardingOperator.fromMap)
        .toList();
  }

  Future<List<AddressSuggestion>> searchAddressSuggestions({
    required String input,
    required String sessionToken,
  }) async {
    if (normalizedRequiredText(input).length < 3) {
      return const [];
    }

    final response = await _client.functions.invoke(
      'places_autocomplete',
      body: {
        'action': 'autocomplete',
        'input': input,
        'sessionToken': sessionToken,
      },
    );

    final data = (response.data as Map).cast<String, dynamic>();
    final predictions = (data['predictions'] as List? ?? const [])
        .cast<Map<String, dynamic>>();

    return predictions
        .map(AddressSuggestion.fromMap)
        .where(
          (suggestion) =>
              suggestion.placeId.isNotEmpty &&
              suggestion.description.isNotEmpty,
        )
        .toList();
  }

  Future<ResolvedAddress> resolveAddressSuggestion({
    required String placeId,
    required String sessionToken,
  }) async {
    final response = await _client.functions.invoke(
      'places_autocomplete',
      body: {
        'action': 'details',
        'placeId': placeId,
        'sessionToken': sessionToken,
      },
    );

    return ResolvedAddress.fromMap(
      (response.data as Map).cast<String, dynamic>(),
    );
  }

  Future<ResolvedAddress> resolveTypedAddress({
    required String input,
    required String sessionToken,
  }) async {
    final normalizedInput = normalizedRequiredText(input);
    if (normalizedInput.length < 3) {
      return ResolvedAddress(
        address: normalizedInput,
        city: null,
        latitude: null,
        longitude: null,
      );
    }

    final response = await _client.functions.invoke(
      'places_autocomplete',
      body: {
        'action': 'resolve',
        'input': normalizedInput,
        'sessionToken': sessionToken,
      },
    );

    return ResolvedAddress.fromMap(
      (response.data as Map).cast<String, dynamic>(),
    );
  }

  Future<CreatedClientSite> createClientWithPrimarySite({
    required String clientName,
    required String siteAddress,
    String? siteCity,
    double? siteLatitude,
    double? siteLongitude,
    String? siteName,
  }) async {
    final result = await _client.rpc(
      'create_client_with_primary_site',
      params: {
        'p_client_name': normalizedRequiredText(clientName),
        'p_site_address': normalizedRequiredText(siteAddress),
        'p_site_name': normalizedRequiredText(siteName ?? ''),
        'p_site_city': normalizedRequiredText(siteCity ?? ''),
        'p_site_latitude': siteLatitude,
        'p_site_longitude': siteLongitude,
      },
    );

    return CreatedClientSite.fromMap((result as Map).cast<String, dynamic>());
  }

  Future<OnboardingSite> addSiteToClient({
    required String clientId,
    required String siteAddress,
    String? siteCity,
    double? siteLatitude,
    double? siteLongitude,
    String? siteName,
  }) async {
    final result = await _client.rpc(
      'add_site_to_client',
      params: {
        'p_client_id': clientId,
        'p_site_address': normalizedRequiredText(siteAddress),
        'p_site_name': normalizedRequiredText(siteName ?? ''),
        'p_site_city': normalizedRequiredText(siteCity ?? ''),
        'p_site_latitude': siteLatitude,
        'p_site_longitude': siteLongitude,
      },
    );

    final map = (result as Map).cast<String, dynamic>();
    return OnboardingSite(
      id: map['site_id'] as String,
      clientId: map['client_id'] as String,
      name: map['site_name'] as String,
      address: normalizedRequiredText(siteAddress),
      city: normalizedRequiredText(siteCity ?? '').isEmpty
          ? null
          : normalizedRequiredText(siteCity ?? ''),
      latitude: (map['site_latitude'] as num?)?.toDouble(),
      longitude: (map['site_longitude'] as num?)?.toDouble(),
    );
  }

  Future<CreatedMachine> createMachine({
    required String clientId,
    required String siteId,
    required String code,
    required OnboardingMachineType type,
    required int capacityUnits,
    String? assignedOperatorId,
    String? hwSerial,
  }) async {
    final result = await _client.rpc(
      'create_machine_for_site',
      params: {
        'p_client_id': clientId,
        'p_site_id': siteId,
        'p_code': normalizeMachineCodeInput(code),
        'p_temperature_mode': machineTypeToDb(type),
        'p_capacity_units': capacityUnits,
        'p_assigned_operator_id': assignedOperatorId,
        'p_hw_serial': normalizedRequiredText(hwSerial ?? ''),
      },
    );

    return CreatedMachine.fromMap((result as Map).cast<String, dynamic>());
  }

  Future<void> deleteClient(String clientId) async {
    await _client.rpc(
      'delete_onboarding_client',
      params: {'p_client_id': clientId},
    );
  }
}

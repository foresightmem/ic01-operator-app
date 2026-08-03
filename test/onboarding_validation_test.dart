import 'package:flutter_test/flutter_test.dart';
import 'package:ic01_operator_app/features/onboarding/data/customer_machine_onboarding_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('onboarding validation helpers', () {
    test('normalizes required text by trimming and collapsing spaces', () {
      expect(normalizedRequiredText('  Bar   Centrale  '), 'Bar Centrale');
      expect(normalizedRequiredText('\nVia   Roma 1\t'), 'Via Roma 1');
      expect(normalizedRequiredText('   '), '');
    });

    test('normalizes machine code for manual entry', () {
      expect(normalizeMachineCodeInput('  ic-01 ab  '), 'IC-01 AB');
      expect(normalizeMachineCodeInput('geda42'), 'GEDA42');
    });

    test('requires a non-empty machine code', () {
      expect(isValidMachineCodeInput('IC-01'), isTrue);
      expect(isValidMachineCodeInput('  geda42  '), isTrue);
      expect(isValidMachineCodeInput('   '), isFalse);
    });

    test('accepts only positive integer capacity', () {
      expect(parsePositiveInt('10'), 10);
      expect(parsePositiveInt(' 1 '), 1);
      expect(parsePositiveInt('0'), isNull);
      expect(parsePositiveInt('-4'), isNull);
      expect(parsePositiveInt('1.5'), isNull);
      expect(parsePositiveInt('abc'), isNull);
    });

    test('stores machine types as stable database values', () {
      expect(machineTypeToDb(OnboardingMachineType.hot), 'hot');
      expect(machineTypeToDb(OnboardingMachineType.cold), 'cold');
      expect(machineTypeLabel(OnboardingMachineType.hot), 'Caldo');
      expect(machineTypeLabel(OnboardingMachineType.cold), 'Freddo');
    });

    test('parses resolved address coordinates from edge function payload', () {
      final resolved = ResolvedAddress.fromMap({
        'address': 'Via Appia Nuova, 123, 00183 Roma RM, Italia',
        'city': 'Roma',
        'latitude': 41.8792,
        'longitude': 12.5146,
      });

      expect(resolved.address, 'Via Appia Nuova, 123, 00183 Roma RM, Italia');
      expect(resolved.city, 'Roma');
      expect(resolved.latitude, 41.8792);
      expect(resolved.longitude, 12.5146);
    });

    test('maps technical onboarding errors to user-safe messages', () {
      final missingRpc = PostgrestException(
        message:
            'Could not find the function public.create_client_with_primary_site',
        code: 'PGRST202',
      );
      final duplicateCode = PostgrestException(
        message: 'Il codice macchina è già in uso',
        code: '23505',
      );
      final permissionDenied = PostgrestException(
        message: 'permission denied for table clients',
        code: '42501',
      );
      final notDeletable = PostgrestException(
        message: 'Cliente non cancellabile: contiene macchine, ticket o visite',
      );

      expect(
        onboardingUserMessage(missingRpc, OnboardingAction.createClient),
        'Funzione non disponibile. Riprova oppure contatta l\'amministratore.',
      );
      expect(
        onboardingUserMessage(duplicateCode, OnboardingAction.createMachine),
        'Il codice macchina è già in uso.',
      );
      expect(
        onboardingUserMessage(permissionDenied, OnboardingAction.createSite),
        'Non hai i permessi per completare questa operazione.',
      );
      expect(
        onboardingUserMessage(notDeletable, OnboardingAction.deleteClient),
        'Questo cliente non può essere eliminato perché contiene macchine, ticket o visite.',
      );
      expect(
        onboardingUserMessage(Exception('boom'), OnboardingAction.createClient),
        'Impossibile creare il cliente. Riprova oppure contatta l\'amministratore.',
      );
    });
  });
}

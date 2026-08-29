import 'package:flutter_test/flutter_test.dart';
import 'package:ic01_operator_app/features/admin/presentation/admin_dashboard_page.dart';
import 'package:ic01_operator_app/features/public_support/presentation/public_support_page.dart';

void main() {
  group('public support utilities', () {
    test('normalizes machine codes consistently', () {
      expect(normalizePublicMachineCode('  ic-01 ab  '), 'IC01AB');
      expect(normalizePublicMachineCode('geda  42'), 'GEDA42');
    });

    test('maps stable ticket reasons to visible labels', () {
      expect(publicTicketReasonLabel('out_of_stock'), 'Scorte finite');
      expect(publicTicketReasonLabel('malfunction'), 'Malfunzionamento');
      expect(publicTicketReasonLabel('other'), 'other');
    });
  });

  group('resolution duration formatting', () {
    test('formats minutes, hours and days', () {
      expect(formatResolutionDuration(42 * 60), '42 min');
      expect(formatResolutionDuration((3 * 60 + 15) * 60), '3 h 15 min');
      expect(formatResolutionDuration((30 * 60) * 60), '1 g 6 h');
    });

    test('formats empty values', () {
      expect(formatResolutionDuration(null), '-');
      expect(formatResolutionDuration(-1), '-');
    });
  });
}

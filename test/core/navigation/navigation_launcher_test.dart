import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ic01_operator_app/core/auth/app_role_service.dart';
import 'package:ic01_operator_app/core/navigation/navigation_action_sheet.dart';
import 'package:ic01_operator_app/core/navigation/navigation_launcher.dart';
import 'package:ic01_operator_app/core/navigation/navigation_permissions.dart';

void main() {
  group('SiteNavigationDestination', () {
    test('can navigate with latitude and longitude', () {
      const destination = SiteNavigationDestination(
        siteId: 'site-1',
        siteName: 'Roma EUR',
        latitude: 41.8349,
        longitude: 12.4707,
      );

      expect(destination.canNavigate, isTrue);
      expect(destination.hasCoordinates, isTrue);
    });

    test('can navigate with address only', () {
      const destination = SiteNavigationDestination(
        siteId: 'site-2',
        siteName: 'Milano Centro',
        address: 'Via Caffe 12',
        city: 'Milano',
      );

      expect(destination.canNavigate, isTrue);
      expect(destination.hasCoordinates, isFalse);
      expect(destination.fullAddress, 'Via Caffe 12, Milano');
    });

    test('cannot navigate without coordinates or address', () {
      const destination = SiteNavigationDestination(siteName: 'Sede');

      expect(destination.canNavigate, isFalse);
      expect(NavigationLauncher.googleMapsUrl(destination), isNull);
      expect(NavigationLauncher.wazeUrl(destination), isNull);
      expect(NavigationLauncher.appleMapsUrl(destination), isNull);
    });
  });

  group('NavigationLauncher URLs', () {
    test('builds Google Maps URL from coordinates without origin', () {
      const destination = SiteNavigationDestination(
        siteName: 'Roma EUR',
        latitude: 41.8349,
        longitude: 12.4707,
      );

      final uri = NavigationLauncher.googleMapsUrl(destination)!;

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['destination'], '41.8349,12.4707');
      expect(uri.queryParameters['travelmode'], 'driving');
      expect(uri.queryParameters['dir_action'], 'navigate');
      expect(uri.queryParameters.containsKey('origin'), isFalse);
    });

    test('adds Google Place ID when available', () {
      const destination = SiteNavigationDestination(
        siteName: 'Place Site',
        address: 'Piazza Duomo 1',
        city: 'Milano',
        googlePlaceId: 'ChIJ-place-123',
      );

      final uri = NavigationLauncher.googleMapsUrl(destination)!;

      expect(uri.queryParameters['destination'], 'Piazza Duomo 1, Milano');
      expect(uri.queryParameters['destination_place_id'], 'ChIJ-place-123');
    });

    test('builds Waze universal link from coordinates', () {
      const destination = SiteNavigationDestination(
        siteName: 'Roma EUR',
        latitude: 41.8349,
        longitude: 12.4707,
      );

      final uri = NavigationLauncher.wazeUrl(destination)!;

      expect(uri.scheme, 'https');
      expect(uri.host, 'waze.com');
      expect(uri.path, '/ul');
      expect(uri.queryParameters['ll'], '41.8349,12.4707');
      expect(uri.queryParameters['navigate'], 'yes');
    });

    test('builds Waze search link from address fallback', () {
      const destination = SiteNavigationDestination(
        siteName: 'Napoli',
        address: 'Via Toledo 10',
        city: 'Napoli',
      );

      final uri = NavigationLauncher.wazeUrl(destination)!;

      expect(uri.queryParameters['q'], 'Via Toledo 10, Napoli');
      expect(uri.queryParameters['navigate'], 'yes');
      expect(uri.queryParameters.containsKey('ll'), isFalse);
    });

    test('builds Apple Maps directions URL from coordinates', () {
      const destination = SiteNavigationDestination(
        siteName: 'Roma EUR',
        latitude: 41.8349,
        longitude: 12.4707,
      );

      final uri = NavigationLauncher.appleMapsUrl(destination)!;

      expect(uri.scheme, 'https');
      expect(uri.host, 'maps.apple.com');
      expect(uri.queryParameters['daddr'], '41.8349,12.4707');
      expect(uri.queryParameters['dirflg'], 'd');
    });

    test('encodes addresses with spaces and accents', () {
      const destination = SiteNavigationDestination(
        siteName: 'Sede accenti',
        address: 'Via Caffè 12',
        city: 'San Donà di Piave',
      );

      final google = NavigationLauncher.googleMapsUrl(destination)!.toString();
      final waze = NavigationLauncher.wazeUrl(destination)!.toString();
      final apple = NavigationLauncher.appleMapsUrl(destination)!.toString();

      expect(google, contains('Via+Caff%C3%A8+12%2C+San+Don%C3%A0+di+Piave'));
      expect(waze, contains('Via+Caff%C3%A8+12%2C+San+Don%C3%A0+di+Piave'));
      expect(waze, contains('navigate=yes'));
      expect(apple, contains('San+Don%C3%A0+di+Piave'));
    });

    test('keeps selected site destination when client has multiple sites', () {
      const firstSite = SiteNavigationDestination(
        siteId: 'site-a',
        siteName: 'Sede A',
        address: 'Via A 1',
        city: 'Roma',
      );
      const secondSite = SiteNavigationDestination(
        siteId: 'site-b',
        siteName: 'Sede B',
        latitude: 45.4642,
        longitude: 9.19,
      );

      final firstUrl = NavigationLauncher.googleMapsUrl(firstSite)!;
      final secondUrl = NavigationLauncher.googleMapsUrl(secondSite)!;

      expect(firstUrl.queryParameters['destination'], 'Via A 1, Roma');
      expect(secondUrl.queryParameters['destination'], '45.4642,9.19');
      expect(
        firstUrl.queryParameters['destination'],
        isNot(secondUrl.queryParameters['destination']),
      );
    });
  });

  group('NavigationLauncher launch handling', () {
    test('returns false when launchUrl returns false', () async {
      final launcher = NavigationLauncher(launchUrl: (_) async => false);

      final result = await launcher.openGoogleMaps(
        const SiteNavigationDestination(
          siteName: 'Roma EUR',
          latitude: 41.8349,
          longitude: 12.4707,
        ),
      );

      expect(result, isFalse);
    });

    test('returns false when launchUrl throws', () async {
      final launcher = NavigationLauncher(
        launchUrl: (_) async => throw Exception('not available'),
      );

      final result = await launcher.openWaze(
        const SiteNavigationDestination(
          siteName: 'Roma EUR',
          latitude: 41.8349,
          longitude: 12.4707,
        ),
      );

      expect(result, isFalse);
    });
  });

  group('navigationAppsForPlatform', () {
    test('shows Apple Maps as Mappe on iOS', () {
      expect(navigationAppsForPlatform(TargetPlatform.iOS), const [
        NavigationApp.googleMaps,
        NavigationApp.appleMaps,
        NavigationApp.waze,
      ]);
    });

    test('does not show Mappe on Android', () {
      expect(navigationAppsForPlatform(TargetPlatform.android), const [
        NavigationApp.googleMaps,
        NavigationApp.waze,
      ]);
    });
  });

  group('canUseExternalNavigation', () {
    test('is visible for refill operator and technician', () {
      expect(canUseExternalNavigation(AppRole.refillOperator), isTrue);
      expect(canUseExternalNavigation(AppRole.technician), isTrue);
    });

    test('is hidden for admin, internal admin and unknown roles', () {
      expect(canUseExternalNavigation(AppRole.admin), isFalse);
      expect(canUseExternalNavigation(AppRole.internalAdmin), isFalse);
      expect(canUseExternalNavigation(AppRole.unknown), isFalse);
    });
  });
}

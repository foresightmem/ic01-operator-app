import 'package:url_launcher/url_launcher.dart' as url_launcher;

typedef UrlLaunchDelegate = Future<bool> Function(Uri uri);

enum NavigationApp { googleMaps, appleMaps, waze }

class SiteNavigationDestination {
  final String? siteId;
  final String siteName;
  final String? address;
  final String? city;
  final double? latitude;
  final double? longitude;
  final String? googlePlaceId;

  const SiteNavigationDestination({
    this.siteId,
    required this.siteName,
    this.address,
    this.city,
    this.latitude,
    this.longitude,
    this.googlePlaceId,
  });

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude! >= -90 &&
      latitude! <= 90 &&
      longitude! >= -180 &&
      longitude! <= 180;

  String? get fullAddress {
    final parts = <String>[
      if ((address ?? '').trim().isNotEmpty) address!.trim(),
      if ((city ?? '').trim().isNotEmpty) city!.trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  String? get googlePlaceIdOrNull {
    final value = (googlePlaceId ?? '').trim();
    return value.isEmpty ? null : value;
  }

  bool get canNavigate => hasCoordinates || fullAddress != null;

  String? get _destinationValue {
    if (hasCoordinates) {
      return '${latitude!.toString()},${longitude!.toString()}';
    }
    return fullAddress;
  }
}

class NavigationLauncher {
  NavigationLauncher({UrlLaunchDelegate? launchUrl})
    : _launchUrl =
          launchUrl ??
          ((uri) => url_launcher.launchUrl(
            uri,
            mode: url_launcher.LaunchMode.externalApplication,
          ));

  final UrlLaunchDelegate _launchUrl;

  static Uri? googleMapsUrl(SiteNavigationDestination destination) {
    final destinationValue = destination._destinationValue;
    if (destinationValue == null) return null;

    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destinationValue,
      if (destination.googlePlaceIdOrNull != null)
        'destination_place_id': destination.googlePlaceIdOrNull!,
      'travelmode': 'driving',
      'dir_action': 'navigate',
    });
  }

  static Uri? wazeUrl(SiteNavigationDestination destination) {
    if (!destination.canNavigate) return null;

    return Uri.https('waze.com', '/ul', {
      if (destination.hasCoordinates)
        'll':
            '${destination.latitude!.toString()},${destination.longitude!.toString()}'
      else
        'q': destination.fullAddress!,
      'navigate': 'yes',
    });
  }

  static Uri? appleMapsUrl(SiteNavigationDestination destination) {
    final destinationValue = destination._destinationValue;
    if (destinationValue == null) return null;

    return Uri.https('maps.apple.com', '/', {
      'daddr': destinationValue,
      'dirflg': 'd',
    });
  }

  Future<bool> openGoogleMaps(SiteNavigationDestination destination) {
    return _open(googleMapsUrl(destination));
  }

  Future<bool> openWaze(SiteNavigationDestination destination) {
    return _open(wazeUrl(destination));
  }

  Future<bool> openAppleMaps(SiteNavigationDestination destination) {
    return _open(appleMapsUrl(destination));
  }

  Future<bool> open(NavigationApp app, SiteNavigationDestination destination) {
    switch (app) {
      case NavigationApp.googleMaps:
        return openGoogleMaps(destination);
      case NavigationApp.appleMaps:
        return openAppleMaps(destination);
      case NavigationApp.waze:
        return openWaze(destination);
    }
  }

  Future<bool> _open(Uri? uri) async {
    if (uri == null || !uri.isAbsolute) return false;

    try {
      return await _launchUrl(uri);
    } catch (_) {
      return false;
    }
  }
}

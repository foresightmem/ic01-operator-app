import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../ui/app_design_system.dart';
import 'navigation_launcher.dart';

const navigationLauncherErrorMessage =
    'Impossibile aprire il navigatore per questa sede.';

List<NavigationApp> navigationAppsForPlatform(TargetPlatform platform) {
  return [
    NavigationApp.googleMaps,
    if (platform == TargetPlatform.iOS) NavigationApp.appleMaps,
    NavigationApp.waze,
  ];
}

Future<void> showNavigationLauncherSheet(
  BuildContext context,
  SiteNavigationDestination destination, {
  NavigationLauncher? launcher,
  TargetPlatform? platform,
}) async {
  if (!destination.canNavigate) {
    _showNavigationError(context);
    return;
  }

  final selectedApp = await showModalBottomSheet<NavigationApp>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final apps = navigationAppsForPlatform(platform ?? defaultTargetPlatform);

      return SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.md,
                      bottom: AppSpacing.xs,
                    ),
                    child: Text(
                      'Apri con',
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                  for (final app in apps)
                    ListTile(
                      leading: Icon(_iconForApp(app)),
                      title: Text(_labelForApp(app)),
                      onTap: () => Navigator.of(sheetContext).pop(app),
                    ),
                  ListTile(
                    leading: const Icon(Icons.close),
                    title: const Text('Annulla'),
                    onTap: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  if (selectedApp == null || !context.mounted) return;

  final didLaunch = await (launcher ?? NavigationLauncher()).open(
    selectedApp,
    destination,
  );
  if (!didLaunch && context.mounted) {
    _showNavigationError(context);
  }
}

class SiteNavigationButton extends StatelessWidget {
  final SiteNavigationDestination destination;
  final String label;

  const SiteNavigationButton({
    super.key,
    required this.destination,
    this.label = 'Apri navigatore',
  });

  @override
  Widget build(BuildContext context) {
    if (!destination.canNavigate) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: () => showNavigationLauncherSheet(context, destination),
      icon: const Icon(Icons.navigation_outlined),
      label: Text(label),
    );
  }
}

IconData _iconForApp(NavigationApp app) {
  switch (app) {
    case NavigationApp.googleMaps:
      return Icons.map_outlined;
    case NavigationApp.appleMaps:
      return Icons.map;
    case NavigationApp.waze:
      return Icons.directions_car_filled_outlined;
  }
}

String _labelForApp(NavigationApp app) {
  switch (app) {
    case NavigationApp.googleMaps:
      return 'Google Maps';
    case NavigationApp.appleMaps:
      return 'Mappe';
    case NavigationApp.waze:
      return 'Waze';
  }
}

void _showNavigationError(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text(navigationLauncherErrorMessage)));
}

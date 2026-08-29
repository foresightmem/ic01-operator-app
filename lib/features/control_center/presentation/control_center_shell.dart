import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/ui/app_design_system.dart';

class ControlCenterShell extends StatelessWidget {
  const ControlCenterShell({
    super.key,
    required this.currentIndex,
    required this.child,
  });

  final int currentIndex;
  final Widget child;

  static const _destinations = <_ControlCenterDestination>[
    _ControlCenterDestination(
      path: '/control-center',
      label: 'Overview',
      icon: Icons.monitor_heart_outlined,
      selectedIcon: Icons.monitor_heart,
    ),
    _ControlCenterDestination(
      path: '/control-center/devices',
      label: 'Devices',
      icon: Icons.memory_outlined,
      selectedIcon: Icons.memory,
    ),
    _ControlCenterDestination(
      path: '/control-center/events',
      label: 'Events',
      icon: Icons.event_note_outlined,
      selectedIcon: Icons.event_note,
    ),
    _ControlCenterDestination(
      path: '/control-center/diagnostics',
      label: 'Diagnostics',
      icon: Icons.science_outlined,
      selectedIcon: Icons.science,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.responsive.isDesktop;
    final scaffold = Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: const Text('MAGMA Control Center'),
              actions: [
                IconButton(
                  tooltip: 'Esci',
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (context.mounted) context.go('/login');
                  },
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
      body: isDesktop
          ? _DesktopShell(currentIndex: currentIndex, child: child)
          : child,
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: currentIndex.clamp(0, _destinations.length - 1),
              onDestinationSelected: (index) {
                context.go(_destinations[index].path);
              },
              destinations: _destinations
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: item.label,
                    ),
                  )
                  .toList(growable: false),
            ),
    );

    return Theme(
      data: Theme.of(
        context,
      ).copyWith(scaffoldBackgroundColor: const Color(0xFFF7F8F6)),
      child: scaffold,
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({required this.currentIndex, required this.child});

  final int currentIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 256,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(right: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MAGMA',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Control Center',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                for (
                  var i = 0;
                  i < ControlCenterShell._destinations.length;
                  i++
                )
                  _NavButton(
                    destination: ControlCenterShell._destinations[i],
                    selected: i == currentIndex,
                    onTap: () =>
                        context.go(ControlCenterShell._destinations[i].path),
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Supabase.instance.client.auth.signOut();
                      if (context.mounted) context.go('/login');
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Esci'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _ControlCenterDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.petroleum : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.petroleumSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                destination.label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlCenterDestination {
  const _ControlCenterDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

import 'package:flutter/material.dart';

class AppColors {
  static const black = Color(0xFF111315);
  static const white = Color(0xFFFFFFFF);
  static const petroleum = Color(0xFF0D4F57);
  static const petroleumDark = Color(0xFF08393F);
  static const petroleumSoft = Color(0xFFE6F0F1);
  static const orange = Color(0xFFE8691B);
  static const background = Color(0xFFF3F5F4);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFE9EDEC);
  static const border = Color(0xFFD4DAD8);
  static const text = Color(0xFF1A1F21);
  static const muted = Color(0xFF5A6568);
  static const success = Color(0xFF18794E);
  static const warning = Color(0xFFE8691B);
  static const danger = Color(0xFFB42318);
  static const info = Color(0xFF2563A8);
  static const stopped = Color(0xFF111315);
}

class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class AppRadii {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 8.0;
  static const pill = 999.0;
}

class AppBreakpoints {
  static const compact = 600.0;
  static const medium = 900.0;
  static const expanded = 1200.0;
  static const wide = 1440.0;
}

enum AppWindowClass { compact, medium, expanded, wide }

class AppResponsive {
  const AppResponsive(this.width);

  final double width;

  static AppResponsive of(BuildContext context) =>
      AppResponsive(MediaQuery.sizeOf(context).width);

  AppWindowClass get windowClass {
    if (width < AppBreakpoints.compact) return AppWindowClass.compact;
    if (width < AppBreakpoints.expanded) return AppWindowClass.medium;
    if (width < AppBreakpoints.wide) return AppWindowClass.expanded;
    return AppWindowClass.wide;
  }

  bool get isCompact => windowClass == AppWindowClass.compact;
  bool get isMedium => windowClass == AppWindowClass.medium;
  bool get isDesktop =>
      windowClass == AppWindowClass.expanded ||
      windowClass == AppWindowClass.wide;

  EdgeInsets get pagePadding => EdgeInsets.symmetric(
    horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
    vertical: isCompact ? AppSpacing.md : AppSpacing.lg,
  );

  double get operatorMaxWidth => isCompact ? double.infinity : 760;
  double get adminMaxWidth => isDesktop ? 1280 : 920;
  double get formMaxWidth => isCompact ? double.infinity : 560;
  double get dialogMaxWidth => isCompact ? double.infinity : 560;

  int columnsFor({
    required double minTileWidth,
    int minColumns = 1,
    int maxColumns = 4,
  }) {
    final computed = (width / minTileWidth).floor();
    return computed.clamp(minColumns, maxColumns);
  }
}

extension AppResponsiveContext on BuildContext {
  AppResponsive get responsive => AppResponsive.of(this);
}

ThemeData buildMagmaLightTheme() {
  final base = ThemeData.light(useMaterial3: true);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.petroleum,
    primary: AppColors.petroleum,
    onPrimary: AppColors.white,
    secondary: AppColors.orange,
    onSecondary: AppColors.white,
    tertiary: AppColors.petroleumDark,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
    brightness: Brightness.light,
  );

  final textTheme = base.textTheme.apply(
    bodyColor: AppColors.text,
    displayColor: AppColors.text,
  );

  return base.copyWith(
    colorScheme: colorScheme,
    primaryColor: AppColors.petroleum,
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.border,
    visualDensity: VisualDensity.standard,
    textTheme: textTheme.copyWith(
      headlineSmall: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      bodySmall: textTheme.bodySmall?.copyWith(color: AppColors.muted),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      iconTheme: IconThemeData(color: AppColors.text),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      margin: EdgeInsets.zero,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.petroleum,
        foregroundColor: AppColors.white,
        disabledBackgroundColor: AppColors.surfaceAlt,
        disabledForegroundColor: AppColors.muted,
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.md,
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.petroleum,
        foregroundColor: AppColors.white,
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.petroleum,
        minimumSize: const Size(44, 44),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.petroleum,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.petroleum, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      labelStyle: const TextStyle(color: AppColors.muted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      indicatorColor: AppColors.petroleumSoft,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected ? AppColors.petroleum : AppColors.muted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.petroleum : AppColors.muted,
          size: 23,
        );
      }),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.surfaceAlt,
      selectedColor: AppColors.petroleumSoft,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.petroleum,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.orange,
      dividerColor: AppColors.border,
      labelStyle: TextStyle(fontWeight: FontWeight.w700),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.black,
      contentTextStyle: const TextStyle(color: AppColors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    ),
  );
}

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.center = true,
  });

  final Widget child;
  final double? maxWidth;
  final EdgeInsets? padding;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final responsive = context.responsive;
    final content = Padding(
      padding: padding ?? responsive.pagePadding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? responsive.adminMaxWidth,
        ),
        child: child,
      ),
    );

    if (!center) return content;

    return Align(alignment: Alignment.topCenter, child: content);
  }
}

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      child: Padding(padding: padding, child: child),
    );
  }
}

class AppAdaptiveGrid extends StatelessWidget {
  const AppAdaptiveGrid({
    super.key,
    required this.children,
    this.minTileWidth = 220,
    this.maxColumns = 4,
    this.spacing = AppSpacing.sm,
    this.childAspectRatio = 2.4,
  });

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final double spacing;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final responsive = AppResponsive(constraints.maxWidth);
        final columns = responsive.columnsFor(
          minTileWidth: minTileWidth,
          maxColumns: maxColumns,
        );
        return GridView.count(
          crossAxisCount: columns,
          childAspectRatio: columns == 1
              ? childAspectRatio * 1.35
              : childAspectRatio,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      },
    );
  }
}

class AppStatusPill extends StatelessWidget {
  const AppStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxs,
        horizontal: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.muted),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.error_outline,
      title: 'Qualcosa non ha funzionato',
      message: message,
      action: onRetry == null
          ? null
          : ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
    );
  }
}

class AppLoading extends StatelessWidget {
  const AppLoading({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (label != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(label!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class AppUserEmailAction extends StatelessWidget {
  const AppUserEmailAction({super.key, required this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final value = email;
    if (value == null || value.isEmpty || context.responsive.isCompact) {
      return const SizedBox.shrink();
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final responsive = context.responsive;
  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: responsive.dialogMaxWidth,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.9,
          ),
          child: builder(dialogContext),
        ),
      );
    },
  );
}

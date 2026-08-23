import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root widget. RTL is forced explicitly via [Directionality] rather than
/// relying solely on the `ar` locale, since layout direction should never
/// silently depend on locale-detection edge cases in an Arabic-only system
/// (NFR-1).
class CollapseRiskTrackerApp extends ConsumerWidget {
  const CollapseRiskTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp.router(
        title: 'نظام متابعة المباني الآيلة للسقوط',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        routerConfig: router,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}

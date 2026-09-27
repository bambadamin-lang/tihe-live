import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/l10n.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // media_kit backs playback on Windows, where the first-party plugin is weak (docs/adr/0001).
  // Must run before any player is constructed.
  MediaKit.ensureInitialized();

  runApp(const ProviderScope(child: TiheApp()));
}

class TiheApp extends ConsumerWidget {
  const TiheApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'TihePlayer',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),

      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,

      // Persian-first. The locale is fixed rather than following the system, because the institute's
      // content is Persian and a student whose phone is set to English still wants a Persian
      // interface. English exists for future use (docs/01-requirements.md, A1).
      locale: const Locale('fa'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      builder: (context, child) {
        // RTL is asserted rather than inferred, so a widget that forgets Directionality still lays
        // out correctly.
        return Directionality(
          textDirection: TextDirection.rtl,
          // Clamped so a large system font setting cannot break the player controls, while still
          // respecting a student who needs bigger text.
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.4,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

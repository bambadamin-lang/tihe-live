import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'package:tihe_classroom/tihe_classroom.dart'
    show ClassroomFonts, GlassBackdrop, GlowCursorScope, GlowCursors;

import 'core/preferences.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/window_frame.dart';
import 'l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Modam before the first frame, so no screen is ever drawn in a fallback font and re-laid out.
  // The whole app, the classroom included, is set in the one family (the institute's choice).
  ClassroomFonts.use(AppTheme.fontFamily);
  await ClassroomFonts.ensureLoaded();
  // On Windows the app draws its own title bar, as the classroom always has.
  await setUpWindowFrame();

  // media_kit backs playback on Windows, where the first-party plugin is weak (docs/adr/0001).
  // Must run before any player is constructed.
  MediaKit.ensureInitialized();

  runApp(const ProviderScope(child: TiheApp()));
}

class TiheApp extends ConsumerWidget {
  const TiheApp({super.key, this.frame});

  /// Wraps every page in the window frame the app draws itself. Null decides by platform:
  /// [AppWindowFrame] on Windows, none elsewhere.
  final Widget Function(Widget page)? frame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'TIHE',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),

      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Dark unless the student chose otherwise in Account → Appearance.
      themeMode: ref.watch(themeModeProvider),

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
        final framed =
            frame ??
            (ownsWindowFrame ? (Widget page) => AppWindowFrame(child: page) : (page) => page);
        // RTL is asserted rather than inferred, so a widget that forgets Directionality still lays
        // out correctly.
        return Directionality(
          textDirection: TextDirection.rtl,
          // Clamped so a large system font setting cannot break the player controls, while still
          // respecting a student who needs bigger text.
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.4,
            // The brand's glowing arrow everywhere, dialogs included (docs/11 §11).
            child: GlowCursorScope(
              child: MouseRegion(
                cursor: GlowCursors.basic,
                // One frosted canvas behind every page, as in class.
                child: GlassBackdrop(child: framed(child ?? const SizedBox.shrink())),
              ),
            ),
          ),
        );
      },
    );
  }
}

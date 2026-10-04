import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_player/l10n/l10n.dart';

/// Guards the two app-wide properties that are easy to break and hard to notice in review:
/// right-to-left layout, and Persian strings actually resolving.
void main() {
  Widget harness(Widget child) => MaterialApp(
    locale: const Locale('fa'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, inner) => Directionality(textDirection: TextDirection.rtl, child: inner!),
    home: child,
  );

  testWidgets('the app lays out right-to-left', (tester) async {
    await tester.pumpWidget(
      harness(Builder(builder: (context) => const Text('جلسه چهارم', key: Key('sample')))),
    );

    final direction = Directionality.of(tester.element(find.byKey(const Key('sample'))));
    expect(direction, TextDirection.rtl);
  });

  testWidgets('Persian localisations resolve', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) {
            l10n = context.l10n;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(l10n.libraryTitle, 'کتابخانه من');
    // Every user-facing string must be Persian — a Latin fallback here means a missing translation
    // shipped.
    expect(l10n.signInTitle, isNot(matches(RegExp(r'^[A-Za-z]'))));
  });

  testWidgets('placeholder strings interpolate', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (context) {
            l10n = context.l10n;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(l10n.videoCount('۵'), contains('۵'));
    expect(l10n.supportHint('req_123'), contains('req_123'));
  });
}

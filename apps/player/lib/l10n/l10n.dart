import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// Shorthand for localised strings: `context.l10n.libraryTitle`.
///
/// `AppLocalizations.of` is nullable because a widget could in principle be built outside a
/// `MaterialApp` that registers the delegate. In this app it never is — the delegate is registered in
/// `main.dart` and every screen sits under it — so a null here is a programming error, and asserting
/// it in one place is better than `!` at every call site or a null check that silently renders
/// nothing.
extension L10nContext on BuildContext {
  AppLocalizations get l10n {
    final localizations = AppLocalizations.of(this);
    assert(
      localizations != null,
      'AppLocalizations is missing. The delegate is registered in main.dart — a widget being built '
      'outside MaterialApp cannot see it.',
    );
    return localizations!;
  }
}

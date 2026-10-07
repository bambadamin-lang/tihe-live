import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_player/features/admin/add_user_dialog.dart';
import 'package:tihe_player/l10n/app_localizations_fa.dart';

void main() {
  final l10n = AppLocalizationsFa();

  group('passwordProblem mirrors checkPasswordPolicy', () {
    test('length and repetition', () {
      expect(passwordProblem('1234567', null, l10n), l10n.passwordTooShort);
      expect(passwordProblem('aaaaaaaa', null, l10n), l10n.passwordOneCharacter);
      expect(passwordProblem('tihe-demo-1405', null, l10n), isNull);
    });

    test('refuses the phone number in any form, including Persian digits', () {
      const phone = '+989125550003';
      for (final p in [
        '09125550003',
        '9125550003',
        '989125550003',
        '۰۹۱۲۵۵۵۰۰۰۳',
        'x09125550003y',
      ]) {
        expect(passwordProblem(p, phone, l10n), l10n.passwordIsPhone, reason: p);
      }
      expect(passwordProblem('091255500', phone, l10n), isNull);
    });
  });

  test('temporary passwords are 8 digits and never one repeated character', () {
    // A source that repeats one digit first: the generator must try again.
    var calls = 0;
    final rigged = _Rigged(() => calls++ < 8 ? 7 : calls % 10);
    final password = generateTemporaryPassword(rigged);
    expect(password, matches(RegExp(r'^\d{8}$')));
    expect(password.split('').toSet().length, greaterThan(1));
    for (var i = 0; i < 200; i++) {
      expect(generateTemporaryPassword(), matches(RegExp(r'^\d{8}$')));
    }
  });
}

class _Rigged implements Random {
  _Rigged(this.next);
  final int Function() next;
  @override
  int nextInt(int max) => next() % max;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}

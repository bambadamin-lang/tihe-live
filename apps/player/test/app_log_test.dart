import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_player/core/security/app_log.dart';

void main() {
  group('maskPhone', () {
    // Must match the server's masking exactly (maskPhone in packages/contracts), so a log line here
    // and one in the API describe the same student the same way.
    test('masks an E.164 number', () {
      expect(AppLog.maskPhone('+989123456789'), '0912•••6789');
    });

    test('masks a local number', () {
      expect(AppLog.maskPhone('09123456789'), '0912•••6789');
    });

    test('never reveals the middle digits', () {
      final masked = AppLog.maskPhone('+989123456789');
      expect(masked, isNot(contains('345')));
      expect(masked, isNot(contains('23456')));
    });

    test('degrades safely on short input rather than echoing it', () {
      expect(AppLog.maskPhone('0912'), '••••');
      expect(AppLog.maskPhone(''), '');
    });
  });

  group('maskToken', () {
    test('keeps only a short prefix for correlation', () {
      final masked = AppLog.maskToken('abcdefghijklmnopqrstuvwxyz');
      expect(masked.startsWith('abcd'), isTrue);
      expect(masked, isNot(contains('mnop')));
    });

    test('fully masks a short token', () {
      expect(AppLog.maskToken('abc'), '•••');
    });
  });
}

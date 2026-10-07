import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_player/core/phone.dart';
import 'package:tihe_player/core/server.dart';

void main() {
  group('Phone.normalize', () {
    test('accepts every form students type', () {
      for (final input in [
        '09123456789',
        '9123456789',
        '+989123456789',
        '00989123456789',
        '989123456789',
        '۰۹۱۲۳۴۵۶۷۸۹',
        '٠٩١٢٣٤٥٦٧٨٩',
        '0912 345 6789',
        '0912-345-6789',
      ]) {
        expect(Phone.normalize(input), '+989123456789', reason: input);
      }
    });

    test('refuses what is not an Iranian mobile number', () {
      for (final input in [
        '',
        '0912345678',
        '021123456789',
        '+441234567890',
        'abc',
        '08123456789',
      ]) {
        expect(Phone.normalize(input), isNull, reason: input);
      }
    });

    test('masks as 0912•••6789', () {
      expect(Phone.mask('+989123456789'), '0912•••6789');
    });
  });

  group('ServerConfig.normalize', () {
    test('adds the scheme people leave out and drops paths', () {
      expect(ServerConfig.normalize('192.168.1.10:8080'), 'http://192.168.1.10:8080');
      expect(ServerConfig.normalize('https://tihe.ir/'), 'https://tihe.ir');
      // An address copied from the old classroom app.
      expect(ServerConfig.normalize('http://10.0.0.5:8080/v1/live'), 'http://10.0.0.5:8080');
      expect(ServerConfig.normalize('۱۹۲.۱۶۸.۱.۱۰:۸۰۸۰'), 'http://192.168.1.10:8080');
    });

    test('refuses what cannot be an address', () {
      for (final input in ['', '   ', 'ftp://x.ir', 'http://', 'a b']) {
        expect(ServerConfig.normalize(input), isNull, reason: input);
      }
    });

    test('derives both services from one address', () {
      const config = ServerConfig('http://10.0.0.5:8080');
      expect(config.apiBaseUrl, 'http://10.0.0.5:8080/v1');
      expect(config.liveBaseUrl, 'http://10.0.0.5:8080/v1/live');
    });
  });
}

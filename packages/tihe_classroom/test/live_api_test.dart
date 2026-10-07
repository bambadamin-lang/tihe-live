import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

/// The live API's one promise to the app: whatever goes wrong arrives as [ApiError] with a
/// Persian message, so a screen never shows "ClientException" or "FormatException".
void main() {
  LiveApi api(MockClientHandler handler) => LiveApi(
    baseUrl: 'http://server/v1/live',
    accessToken: () async => 'token',
    client: MockClient(handler),
  );

  TypeMatcher<ApiError> apiError(String code) => isA<ApiError>()
      .having((e) => e.code, 'code', code)
      .having((e) => e.messageFa, 'messageFa', isNotEmpty);

  test('sends the bearer token and lists classes', () async {
    late http.Request seen;
    final classes = await api((request) async {
      seen = request;
      return http.Response(
        jsonEncode([
          {
            'id': 'cls_01J8Z0000000000000000000A1',
            'courseId': 'crs_01J8Z0000000000000000000B1',
            'title': 'ریاضی ۱',
            'description': null,
            'teacherId': 'usr_01J8Z0000000000000000000C1',
            'scheduledStartAt': '2026-10-04T06:30:00.000Z',
            'durationMinutes': 90,
            'liveSessionId': 'ses_01J8Z0000000000000000000D1',
          },
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }).listClasses();

    expect(seen.method, 'GET');
    expect(seen.url.toString(), 'http://server/v1/live/classes');
    expect(seen.headers['authorization'], 'Bearer token');
    expect(classes.single.title, 'ریاضی ۱');
    expect(classes.single.isLive, isTrue);
    expect(classes.single.scheduledStartAt!.isUtc, isTrue);
  });

  test('passes on the server\'s own refusal', () async {
    final call = api(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'NOT_ENROLLED',
            'message': 'not enrolled',
            'messageFa': 'شما در این دوره ثبت‌نام نکرده‌اید.',
          },
        }),
        403,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    ).join('ses_01J8Z0000000000000000000D1');

    await expectLater(
      call,
      throwsA(
        apiError('NOT_ENROLLED')
            .having((e) => e.status, 'status', 403)
            .having(
              (e) => e.messageFa,
              'messageFa',
              'شما در این دوره ثبت‌نام نکرده‌اید.',
            ),
      ),
    );
  });

  test('a proxy error page is an error, not a crash', () async {
    final call = api(
      (_) async => http.Response('<html>502 Bad Gateway</html>', 502),
    ).listClasses();
    await expectLater(
      call,
      throwsA(apiError('INTERNAL').having((e) => e.status, 'status', 502)),
    );
  });

  test('no connection and timeouts read as a network problem', () async {
    // What IOClient throws for a refused or dropped connection.
    await expectLater(
      api(
        (_) async => throw http.ClientException('Connection refused'),
      ).listClasses(),
      throwsA(apiError('NETWORK')),
    );
    await expectLater(
      api((_) async => throw TimeoutException('slow')).end('ses_x'),
      throwsA(apiError('NETWORK')),
    );
  });

  test('a success that is not the contract is reported, not cast', () async {
    await expectLater(
      api((_) async => http.Response('', 200)).listClasses(),
      throwsA(apiError('INTERNAL')),
    );
    await expectLater(
      api((_) async => http.Response('[]', 200)).start('cls_x'),
      throwsA(apiError('INTERNAL')),
    );
  });

  group('LiveApi.reachable', () {
    test('asks the health check, with no token', () async {
      http.Request? asked;
      final ok = await LiveApi.reachable(
        'https://live.tihe.ir/v1/live',
        client: MockClient((request) async {
          asked = request;
          return http.Response('{"ok":true}', 200);
        }),
      );
      expect(ok, isTrue);
      expect(asked!.url.toString(), 'https://live.tihe.ir/v1/live/health');
      expect(asked!.headers.containsKey('authorization'), isFalse);
    });

    test(
      'an error status, a failure or a bad address is unreachable',
      () async {
        expect(
          await LiveApi.reachable(
            'https://live.tihe.ir/v1/live',
            client: MockClient((_) async => http.Response('', 502)),
          ),
          isFalse,
        );
        expect(
          await LiveApi.reachable(
            'https://live.tihe.ir/v1/live',
            client: MockClient((_) async => throw const SocketLikeError()),
          ),
          isFalse,
        );
        expect(await LiveApi.reachable('not a url'), isFalse);
        expect(await LiveApi.reachable(''), isFalse);
      },
    );

    test('a server that does not answer in time is unreachable', () {
      fakeAsync((clock) {
        bool? result;
        LiveApi.reachable(
          'https://live.tihe.ir/v1/live',
          client: MockClient((_) => Completer<http.Response>().future),
        ).then((v) => result = v);
        clock.elapse(const Duration(seconds: 6));
        expect(result, isFalse);
      });
    });
  });
}

class SocketLikeError implements Exception {
  const SocketLikeError();
}

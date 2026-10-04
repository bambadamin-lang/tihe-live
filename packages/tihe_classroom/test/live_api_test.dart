import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

void main() {
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

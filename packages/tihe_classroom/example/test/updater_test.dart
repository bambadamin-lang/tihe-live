import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom_example/updater.dart';

/// A local stand-in for GitHub: the update file and one wizard.
class _Releases {
  _Releases._(this._server);

  final HttpServer _server;
  Object? manifest;
  List<int> setup = utf8.encode('MZ setup wizard');
  int downloads = 0;

  static Future<_Releases> start() async {
    final r = _Releases._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    r._server.listen((req) async {
      if (req.uri.path.endsWith('.json') && r.manifest != null) {
        req.response.write(jsonEncode(r.manifest));
      } else if (req.uri.path.endsWith('.exe')) {
        r.downloads++;
        req.response.add(r.setup);
      } else {
        req.response.statusCode = HttpStatus.notFound;
      }
      await req.response.close();
    });
    return r;
  }

  Uri get manifestUrl => Uri.parse('http://127.0.0.1:${_server.port}/u.json');
  String setupUrl(String v) =>
      'http://127.0.0.1:${_server.port}/TIHE-Live-Setup-$v.exe';

  void publish(String version, {String? hash}) => manifest = {
    'version': version,
    'url': setupUrl(version),
    'sha256': hash ?? sha256.convert(setup).toString(),
  };

  Future<void> close() => _server.close(force: true);
}

void main() {
  group('compareVersions', () {
    test('orders numerically, part by part', () {
      expect(compareVersions('0.1.57', '0.1.9'), greaterThan(0));
      expect(compareVersions('0.2.0', '0.1.99'), greaterThan(0));
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('0.1.3', '0.1.4'), lessThan(0));
    });

    test('anything that is not a version is oldest', () {
      expect(compareVersions('latest', '0.0.1'), lessThan(0));
      expect(compareVersions('0.1.x', '0.1.0'), lessThan(0));
      expect(compareVersions('', '0.0.1'), lessThan(0));
      expect(compareVersions('-1.0', '0.0.1'), lessThan(0));
    });
  });

  group('UpdateManifest', () {
    const hash =
        'a3f1c2d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
    Map<String, Object> m(String url) => {
      'version': '0.1.57',
      'url': url,
      'sha256': hash,
    };

    test('takes a release download from this repository', () {
      final ok = UpdateManifest.tryParse(
        m(
          'https://github.com/bambadamin-lang/tihe-live/releases/download/live-v0.1.57/TIHE-Live-Setup-0.1.57.exe',
        ),
      );
      expect(ok?.version, '0.1.57');
    });

    test('refuses anything not from this repository\'s releases over https', () {
      for (final url in [
        'http://github.com/bambadamin-lang/tihe-live/releases/download/x/a.exe',
        'https://evil.example/bambadamin-lang/tihe-live/releases/download/x/a.exe',
        'https://github.com/someone-else/tihe-live/releases/download/x/a.exe',
        'https://github.com/bambadamin-lang/tihe-live/releases/download/x/a.ps1',
      ]) {
        expect(UpdateManifest.tryParse(m(url)), isNull, reason: url);
      }
    });

    test('refuses a malformed hash or version', () {
      const url =
          'https://github.com/bambadamin-lang/tihe-live/releases/download/x/a.exe';
      expect(UpdateManifest.tryParse({...m(url), 'sha256': 'abc'}), isNull);
      expect(UpdateManifest.tryParse({...m(url), 'version': 'next'}), isNull);
      expect(UpdateManifest.tryParse('not a map'), isNull);
    });
  });

  group('Updater', () {
    late _Releases releases;
    late Directory dir;

    Updater updater(String current) => Updater(
      currentVersion: current,
      directory: Directory('${dir.path}/updates'),
      manifestUrl: releases.manifestUrl,
      trusted: (_) => true,
    );

    setUp(() async {
      releases = await _Releases.start();
      dir = await Directory.systemTemp.createTemp('tihe-update-test');
    });

    tearDown(() async {
      await releases.close();
      await dir.delete(recursive: true);
    });

    test('finds a newer release and nothing when up to date', () async {
      releases.publish('0.1.57');
      expect((await updater('0.1.56').check())?.version, '0.1.57');
      expect(await updater('0.1.57').check(), isNull);
      expect(await updater('0.2.0').check(), isNull);
    });

    test('stays quiet when there is no release or no network', () async {
      final u = updater('0.1.0');
      expect(await u.check(), isNull);
      await releases.close();
      expect(await u.check(), isNull);
    });

    test('keeps a download only if its SHA-256 matches', () async {
      releases.publish('0.1.57', hash: 'f' * 64);
      final u = updater('0.1.56');
      final m = await u.check();
      expect(m, isNotNull);
      expect(await u.download(m!), isNull);
      expect(await u.pending(), isNull);
    });

    test(
      'a verified download waits for the next start, then clears away once installed',
      () async {
        releases.publish('0.1.57');
        final before = updater('0.1.56');
        final file = await before.download((await before.check())!);
        expect(await file!.readAsBytes(), releases.setup);

        final next = await updater('0.1.56').pending();
        expect(next?.$1.version, '0.1.57');
        // Downloading again reuses the verified file.
        await before.download((await before.check())!);
        expect(releases.downloads, 1);

        // Running 0.1.57 now: the old download is not pending any more and is removed.
        expect(await updater('0.1.57').pending(), isNull);
        expect(await Directory('${dir.path}/updates').exists(), isFalse);
      },
    );

    test('a download altered on disk is not installed', () async {
      releases.publish('0.1.57');
      final u = updater('0.1.56');
      final file = await u.download((await u.check())!);
      await file!.writeAsBytes(utf8.encode('tampered'));
      expect(await updater('0.1.56').pending(), isNull);
    });
  });

  group('AppUpdates', () {
    late _Releases releases;
    late Directory dir;

    setUp(() async {
      releases = await _Releases.start();
      dir = await Directory.systemTemp.createTemp('tihe-update-test');
    });

    tearDown(() async {
      await releases.close();
      await dir.delete(recursive: true);
    });

    test(
      'installs a waiting download at start-up once, then offers it instead',
      () async {
        releases.publish('0.1.57');
        final launched = <String>[];
        var quits = 0;
        AppUpdates app() => AppUpdates(
          Updater(
            currentVersion: '0.1.56',
            directory: Directory('${dir.path}/updates'),
            manifestUrl: releases.manifestUrl,
            trusted: (_) => true,
          ),
          launch: (f) async => launched.add(f.path),
          quit: () => quits++,
        );

        final first = app();
        expect(await first.installPendingOnStart(), isFalse);
        await first.poll();
        expect(first.ready?.version, '0.1.57');

        // Next start: the wizard runs and the app should quit.
        expect(await app().installPendingOnStart(), isTrue);
        expect(launched, hasLength(1));

        // The update did not take (permission refused): open normally, offer it, no loop.
        final third = app();
        expect(await third.installPendingOnStart(), isFalse);
        expect(third.ready?.version, '0.1.57');
        expect(launched, hasLength(1));
        await third.installNow();
        expect(launched, hasLength(2));
        expect(quits, 1);
      },
    );
  });

  group('installArguments', () {
    test('silent, keeps the app closed, restarts it, and stays per user', () {
      expect(
        installArguments(
          r'C:\Users\ali\AppData\Local\Programs\TIHE Live\tihe_live.exe',
          programFiles: r'C:\Program Files',
        ),
        containsAll([
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/CLOSEAPPLICATIONS',
          '/CURRENTUSER',
          '/update=1',
        ]),
      );
    });

    test('a copy under Program Files is updated for all users', () {
      expect(
        installArguments(
          r'C:\Program Files\TIHE Live\tihe_live.exe',
          programFiles: r'C:\Program Files',
        ),
        contains('/ALLUSERS'),
      );
    });
  });
}

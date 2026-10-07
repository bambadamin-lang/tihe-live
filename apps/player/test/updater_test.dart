import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tihe_player/core/update/updater.dart';

const _repo = 'tihe/tihe-live-releases';
final _installer = utf8.encode('MZ — a pretend setup wizard');
final _sha = sha256.convert(_installer).toString();

String _manifest({
  String version = '0.2.0',
  String file = 'TIHE-Setup-0.2.0.exe',
  String? sha,
  int? size,
}) => jsonEncode({
  'version': version,
  'windows': {'file': file, 'sha256': sha ?? _sha, 'size': size ?? _installer.length},
});

void main() {
  group('AppVersion', () {
    test('compares numerically, not as text', () {
      const v = AppVersion.tryParse;
      expect(v('0.10.0')! > v('0.9.9')!, isTrue);
      expect(v('1.0.0')! > v('0.99.99')!, isTrue);
      expect(v('0.2.1')! > v('0.2.0')!, isTrue);
      expect(v('0.2.0')! > v('0.2.0')!, isFalse);
      expect(v('0.2.0'), v(' 0.2.0 '));
    });

    test('rejects anything but major.minor.patch', () {
      for (final s in ['', '1', '1.2', '1.2.3.4', 'v1.2.3', '1.2.3-beta', 'a.b.c']) {
        expect(AppVersion.tryParse(s), isNull, reason: s);
      }
    });
  });

  group('ReleaseManifest', () {
    test('parses what CI writes', () {
      final m = ReleaseManifest.tryParse(_manifest())!;
      expect(m.version, AppVersion.tryParse('0.2.0'));
      expect(m.file, 'TIHE-Setup-0.2.0.exe');
      expect(m.sha256, _sha);
      expect(m.size, _installer.length);
    });

    test('accepts an upper-case hash, as Get-FileHash prints it', () {
      final m = ReleaseManifest.tryParse(_manifest(sha: _sha.toUpperCase()))!;
      expect(m.sha256, _sha);
    });

    test('rejects file names that could escape the download folder', () {
      for (final f in ['../x.exe', r'..\x.exe', 'a/b.exe', 'C:x.exe', 'setup.msi', '.exe x']) {
        expect(ReleaseManifest.tryParse(_manifest(file: f)), isNull, reason: f);
      }
    });

    test('rejects bad hashes, sizes, versions and JSON', () {
      expect(ReleaseManifest.tryParse(_manifest(sha: 'abc')), isNull);
      expect(ReleaseManifest.tryParse(_manifest(size: 0)), isNull);
      expect(ReleaseManifest.tryParse(_manifest(size: ReleaseManifest.maxSize + 1)), isNull);
      expect(ReleaseManifest.tryParse(_manifest(version: 'latest')), isNull);
      expect(ReleaseManifest.tryParse('not json'), isNull);
      expect(ReleaseManifest.tryParse('[]'), isNull);
      expect(ReleaseManifest.tryParse('{"version": "0.2.0"}'), isNull);
    });
  });

  group('Updater', () {
    late Directory dir;
    late List<File> launched;
    late List<Uri> requests;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tihe_update_test');
      launched = [];
      requests = [];
    });
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Updater updater({
      String current = '0.1.0',
      String manifest = '',
      int manifestStatus = 200,
      List<int>? installer,
      int installerStatus = 200,
      Duration interval = const Duration(hours: 6),
    }) => Updater(
      current: AppVersion.tryParse(current)!,
      repo: _repo,
      downloadDir: Directory('${dir.path}/update'),
      interval: interval,
      launchInstaller: (f) async => launched.add(f),
      client: MockClient((req) async {
        requests.add(req.url);
        if (req.url.path.endsWith('/latest.json')) {
          return http.Response(manifest.isEmpty ? _manifest() : manifest, manifestStatus);
        }
        return http.Response.bytes(installer ?? _installer, installerStatus);
      }),
    );

    test('reads the manifest from the public repo without the REST API', () async {
      final u = updater();
      await u.check();
      expect(
        requests.single.toString(),
        'https://github.com/$_repo/releases/latest/download/latest.json',
      );
    });

    test('offers a newer version', () async {
      final u = updater();
      await u.check();
      expect((u.value as UpdateAvailable).release.version.toString(), '0.2.0');
    });

    test('stays quiet when up to date or ahead', () async {
      for (final current in ['0.2.0', '0.3.0']) {
        final u = updater(current: current);
        await u.check();
        expect(u.value, isA<UpdateIdle>(), reason: current);
      }
    });

    test('stays quiet before the first release and when offline', () async {
      final missing = updater(manifestStatus: 404);
      await missing.check();
      expect(missing.value, isA<UpdateIdle>());

      final offline = Updater(
        current: AppVersion.tryParse('0.1.0')!,
        repo: _repo,
        downloadDir: dir,
        launchInstaller: (_) async {},
        client: MockClient((_) => throw const SocketException('offline')),
      );
      await offline.check();
      expect(offline.value, isA<UpdateIdle>());
    });

    test('a check the student asked for says what it found', () async {
      expect(await updater().checkNow(), UpdateCheck.available);
      expect(await updater(current: '0.2.0').checkNow(), UpdateCheck.upToDate);
      expect(await updater(manifestStatus: 404).checkNow(), UpdateCheck.upToDate);
      expect(await updater(manifestStatus: 503).checkNow(), UpdateCheck.unreachable);
    });

    test('checking by hand offers a version dismissed earlier', () async {
      final u = updater();
      await u.check();
      u.dismiss();
      await u.check();
      expect(u.value, isA<UpdateIdle>());
      await u.checkNow();
      expect(u.value, isA<UpdateAvailable>());
    });

    test('a broken manifest looks like no release', () async {
      final u = updater(manifest: _manifest(file: '../evil.exe'));
      await u.check();
      expect(u.value, isA<UpdateIdle>());
    });

    test('"later" hides that version until a newer one is published', () async {
      var published = _manifest();
      final u = Updater(
        current: AppVersion.tryParse('0.1.0')!,
        repo: _repo,
        downloadDir: dir,
        launchInstaller: (_) async {},
        client: MockClient((_) async => http.Response(published, 200)),
      );
      await u.check();
      u.dismiss();
      await u.check();
      expect(u.value, isA<UpdateIdle>());

      published = _manifest(version: '0.3.0', file: 'TIHE-Setup-0.3.0.exe');
      await u.check();
      expect((u.value as UpdateAvailable).release.version.toString(), '0.3.0');
    });

    test('downloads from the release tag, verifies, then runs the wizard', () async {
      final u = updater();
      await u.check();
      await u.install();

      expect(
        requests.last.toString(),
        'https://github.com/$_repo/releases/download/live-v0.2.0/TIHE-Setup-0.2.0.exe',
      );
      expect(u.value, isA<UpdateInstalling>());
      expect(launched.single.path, endsWith('TIHE-Setup-0.2.0.exe'));
      expect(launched.single.readAsBytesSync(), _installer);
    });

    test('never runs a download whose hash does not match', () async {
      final tampered = List<int>.of(_installer)..[0] ^= 1;
      final u = updater(installer: tampered);
      await u.check();
      await u.install();

      expect(launched, isEmpty);
      expect((u.value as UpdateFailed).messageFa, isNotEmpty);
      expect(Directory('${dir.path}/update').listSync(), isEmpty);
    });

    test('never runs a cut-off or oversized download', () async {
      for (final bytes in [
        _installer.sublist(1),
        [..._installer, 0],
      ]) {
        final u = updater(installer: bytes);
        await u.check();
        await u.install();
        expect(launched, isEmpty);
        expect(u.value, isA<UpdateFailed>());
      }
    });

    test('a missing file fails with a Persian message, and retry works', () async {
      var status = 404;
      final u = Updater(
        current: AppVersion.tryParse('0.1.0')!,
        repo: _repo,
        downloadDir: Directory('${dir.path}/update'),
        launchInstaller: (f) async => launched.add(f),
        client: MockClient(
          (req) async => req.url.path.endsWith('/latest.json')
              ? http.Response(_manifest(), 200)
              : http.Response.bytes(_installer, status),
        ),
      );
      await u.check();
      await u.install();
      expect((u.value as UpdateFailed).messageFa, contains('پیدا نشد'));

      // A later check must not hide the failure behind a fresh offer.
      await u.check();
      expect(u.value, isA<UpdateFailed>());

      status = 200;
      await u.install();
      expect(u.value, isA<UpdateInstalling>());
      expect(launched, hasLength(1));
    });

    test('checks at start and then every interval', () {
      fakeAsync((async) {
        final u = updater(current: '0.2.0', interval: const Duration(hours: 6));
        u.start();
        async.flushMicrotasks();
        expect(requests, hasLength(1));

        async.elapse(const Duration(hours: 5, minutes: 59));
        expect(requests, hasLength(1));
        async.elapse(const Duration(minutes: 1));
        expect(requests, hasLength(2));

        u.dispose();
        async.elapse(const Duration(hours: 12));
        expect(requests, hasLength(2));
      });
    });

    test('development builds never update', () {
      // No --dart-define=TIHE_APP_VERSION here, and tests do not run on Windows in CI.
      expect(Updater.forThisBuild(), isNull);
    });

    test('only owner/name repos are accepted', () {
      expect(Updater.isValidRepo(_repo), isTrue);
      for (final r in ['', 'tihe', 'a/b/c', 'evil.com/x?y', 'a b/c']) {
        expect(Updater.isValidRepo(r), isFalse, reason: r);
      }
    });
  });
}

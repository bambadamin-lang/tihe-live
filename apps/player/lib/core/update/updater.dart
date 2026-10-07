import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Self-update for the Windows app from GitHub releases. Surfaced by [updaterProvider] as a
/// banner on the dashboard and a row in Account.
///
/// The source repo is private, so CI also publishes each `live-v*` release to a public,
/// code-free repo (`TIHE_UPDATE_REPO`) that the app reads without a token. Each release there
/// carries the setup wizard and `latest.json` ([ReleaseManifest]). The app asks before it
/// installs, never mid-class, and the wizard runs silently and starts the app again.
///
/// Both values come from `--dart-define` in .github/workflows/windows-installer.yml; a build
/// without them (every development build) never updates.
const _appVersion = String.fromEnvironment('TIHE_APP_VERSION');
const _updateRepo = String.fromEnvironment('TIHE_UPDATE_REPO');

/// `major.minor.patch`. Pre-release suffixes are never published, so they are not parsed.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  static final _pattern = RegExp(r'^(\d{1,6})\.(\d{1,6})\.(\d{1,6})$');

  static AppVersion? tryParse(String s) {
    final m = _pattern.firstMatch(s.trim());
    if (m == null) return null;
    return AppVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AppVersion other) => major != other.major
      ? major.compareTo(other.major)
      : minor != other.minor
      ? minor.compareTo(other.minor)
      : patch.compareTo(other.patch);

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// `latest.json`, written by CI next to the setup wizard:
/// `{"version": "0.2.0", "windows": {"file": "TIHE-Live-Setup-0.2.0.exe", "sha256": "…", "size": 1}}`.
@immutable
class ReleaseManifest {
  const ReleaseManifest({
    required this.version,
    required this.file,
    required this.sha256,
    required this.size,
  });

  static final _file = RegExp(r'^[A-Za-z0-9._-]{1,128}\.exe$');
  static final _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// Larger than any real build, so a bad `size` cannot fill the disk.
  static const maxSize = 1024 * 1024 * 1024;

  /// Null for anything malformed — a broken release must look like no release, not crash.
  static ReleaseManifest? tryParse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final version = AppVersion.tryParse('${json['version']}');
      final windows = json['windows'];
      if (version == null || windows is! Map) return null;
      final file = windows['file'], sha = windows['sha256'], size = windows['size'];
      if (file is! String || !_file.hasMatch(file)) return null;
      if (sha is! String || !_sha256.hasMatch(sha.toLowerCase())) return null;
      if (size is! int || size <= 0 || size > maxSize) return null;
      return ReleaseManifest(version: version, file: file, sha256: sha.toLowerCase(), size: size);
    } on FormatException {
      return null;
    }
  }

  final AppVersion version;
  final String file;
  final String sha256;
  final int size;
}

enum UpdateCheck { available, upToDate, unreachable }

sealed class UpdateState {
  const UpdateState();
}

/// Up to date, not checked yet, offline, or dismissed. Nothing to show.
final class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

final class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.release);
  final ReleaseManifest release;
}

final class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.release, this.progress);
  final ReleaseManifest release;

  /// 0 to 1.
  final double progress;
}

/// The wizard is running and the app is about to close.
final class UpdateInstalling extends UpdateState {
  const UpdateInstalling(this.release);
  final ReleaseManifest release;
}

final class UpdateFailed extends UpdateState {
  const UpdateFailed(this.release, this.messageFa);
  final ReleaseManifest release;
  final String messageFa;
}

/// Starts the verified wizard and closes the app.
typedef InstallerLauncher = Future<void> Function(File installer);

class Updater extends ValueNotifier<UpdateState> {
  Updater({
    required this.current,
    required this.repo,
    required this.downloadDir,
    required this.launchInstaller,
    http.Client? client,
    this.interval = const Duration(hours: 6),
  }) : _client = client ?? http.Client(),
       super(const UpdateIdle());

  /// The updater for this build, or null where it cannot update: not Windows (only the
  /// Windows wizard is published), or a development build without the defines.
  static Updater? forThisBuild() {
    final current = AppVersion.tryParse(_appVersion);
    if (!Platform.isWindows || current == null || !isValidRepo(_updateRepo)) {
      return null;
    }
    return Updater(
      current: current,
      repo: _updateRepo,
      downloadDir: Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}tihe_live_update',
      ),
      launchInstaller: launchWindowsInstaller,
    );
  }

  static final _repo = RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$');
  static bool isValidRepo(String repo) => _repo.hasMatch(repo);

  final AppVersion current;

  /// `owner/name` of the public releases repo.
  final String repo;
  final Directory downloadDir;
  final InstallerLauncher launchInstaller;
  final Duration interval;
  final http.Client _client;

  Timer? _timer;
  AppVersion? _dismissed;
  bool _disposed = false;

  /// `releases/latest/download/…` is a plain redirect to the asset, not the REST API, so a
  /// classroom of students behind one address does not run into the API's hourly limit.
  Uri get manifestUrl => Uri.parse('https://github.com/$repo/releases/latest/download/latest.json');

  /// Built from the tag CI publishes (`live-v<version>`), never taken from the manifest, so
  /// the manifest cannot point the download anywhere else.
  Uri installerUrl(ReleaseManifest r) =>
      Uri.parse('https://github.com/$repo/releases/download/live-v${r.version}/${r.file}');

  /// The release the banner offers to install, if any.
  ReleaseManifest? get _offered => switch (value) {
    UpdateAvailable(:final release) || UpdateFailed(:final release) => release,
    _ => null,
  };

  /// Checks now and then every [interval] while the app is open.
  void start() {
    unawaited(check());
    _timer ??= Timer.periodic(interval, (_) => unawaited(check()));
  }

  /// Looks for a newer release. The answer is for a check the student asked for; the
  /// periodic one ignores it.
  Future<UpdateCheck> check() async {
    if (value is UpdateDownloading || value is UpdateInstalling) return UpdateCheck.available;
    final ReleaseManifest? release;
    try {
      final res = await _client.get(manifestUrl).timeout(const Duration(seconds: 20));
      // 404 until the first release exists.
      if (res.statusCode == 404) return UpdateCheck.upToDate;
      if (res.statusCode != 200) return UpdateCheck.unreachable;
      release = ReleaseManifest.tryParse(utf8.decode(res.bodyBytes));
    } on Object {
      // Offline or GitHub unreachable: try again at the next check, without bothering anyone.
      return UpdateCheck.unreachable;
    }
    if (_disposed) return UpdateCheck.unreachable;
    if (release == null || !(release.version > current)) return UpdateCheck.upToDate;
    if (release.version == _dismissed) return UpdateCheck.available;
    // Already offered, or failed: a failure stays on screen until the student retries or a
    // newer version arrives.
    if (_offered?.version != release.version) value = UpdateAvailable(release);
    return UpdateCheck.available;
  }

  /// Shows a dismissed version again, for a check the student asked for.
  Future<UpdateCheck> checkNow() async {
    _dismissed = null;
    return check();
  }

  /// "Later": hide this version until a newer one is published or the app restarts.
  void dismiss() {
    _dismissed = _offered?.version ?? _dismissed;
    value = const UpdateIdle();
  }

  /// Downloads, verifies and runs the wizard. Only ever started by the student.
  Future<void> install() async {
    final release = _offered;
    if (release == null) return;
    value = UpdateDownloading(release, 0);
    final File installer;
    try {
      installer = await _download(release);
    } on _UpdateError catch (e) {
      if (!_disposed) value = UpdateFailed(release, e.messageFa);
      return;
    } on Object {
      if (!_disposed) {
        value = UpdateFailed(
          release,
          'دریافت نسخهٔ تازه ممکن نشد. اتصال اینترنت را بررسی کنید و دوباره تلاش کنید.',
        );
      }
      return;
    }
    if (_disposed) return;
    value = UpdateInstalling(release);
    try {
      await launchInstaller(installer);
    } on Object {
      if (!_disposed) {
        value = UpdateFailed(release, 'اجرای نصب‌کننده ممکن نشد. دوباره تلاش کنید.');
      }
    }
  }

  /// Streams to a `.part` file while hashing, and only renames it to `.exe` once the size and
  /// SHA-256 match the manifest: a cut-off or tampered download is never run.
  Future<File> _download(ReleaseManifest release) async {
    if (downloadDir.existsSync()) {
      // Older wizards and half-finished downloads.
      await downloadDir.delete(recursive: true);
    }
    await downloadDir.create(recursive: true);
    final sep = Platform.pathSeparator;
    final part = File('${downloadDir.path}$sep${release.file}.part');
    final res = await _client
        .send(http.Request('GET', installerUrl(release)))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw const _UpdateError('فایل نسخهٔ تازه پیدا نشد. کمی بعد دوباره تلاش کنید.');
    }
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    final out = part.openWrite();
    var received = 0;
    var reported = 0.0;
    try {
      await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
        received += chunk.length;
        if (received > release.size) throw const _UpdateError(_corrupt);
        hasher.add(chunk);
        out.add(chunk);
        final progress = received / release.size;
        // About a hundred repaints for the whole download, not one per chunk.
        if (progress - reported >= 0.01 && !_disposed) {
          reported = progress;
          value = UpdateDownloading(release, progress);
        }
      }
    } finally {
      await out.close();
    }
    hasher.close();
    if (received != release.size || digest.value.toString() != release.sha256) {
      await part.delete();
      throw const _UpdateError(_corrupt);
    }
    return part.rename('${downloadDir.path}$sep${release.file}');
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}

const _corrupt = 'فایل دریافت‌شده سالم نیست. دوباره تلاش کنید.';

class _UpdateError implements Exception {
  const _UpdateError(this.messageFa);
  final String messageFa;
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Runs the Inno Setup wizard silently and exits so it can replace the app's files.
/// `/relaunch=1` makes the wizard start the app again (installer/windows/tihe_live.iss).
/// A per-machine install still raises the UAC prompt; a per-user one does not.
Future<void> launchWindowsInstaller(File installer) async {
  await Process.start(installer.path, const [
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
    '/relaunch=1',
  ], mode: ProcessStartMode.detached);
  exit(0);
}

/// The updater for this build, started on first read; null where updates do not apply.
final updaterProvider = Provider<Updater?>((ref) {
  final updater = Updater.forThisBuild();
  if (updater == null) return null;
  updater.start();
  ref.onDispose(updater.dispose);
  return updater;
});

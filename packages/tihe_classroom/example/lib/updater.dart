import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// The installed Windows app keeps itself up to date from GitHub releases, so a change merged
/// to main reaches every PC without anyone running a new Setup.exe by hand.
///
/// CI (.github/workflows/windows-installer.yml) publishes each build of main as a release
/// with two assets: the setup wizard and `tihe-live-update.json`:
///
///   {"version": "0.1.57", "url": "https://github.com/…/TIHE-Live-Setup-0.1.57.exe",
///    "sha256": "…"}
///
/// The app reads that file from the latest release on start. When it names a newer version,
/// the app downloads the wizard in the background and checks its SHA-256; the launcher then
/// offers to install it now, and if nobody does, it is installed the next time the app opens.
/// Installing runs the wizard with `/SILENT` (a progress bar, no questions — the server
/// address from the last install is kept) and the wizard starts the app again when done.

/// This build's version, stamped in by CI (`--dart-define=TIHE_APP_VERSION=…`). Empty in a
/// development build, which therefore never updates itself.
const appVersion = String.fromEnvironment('TIHE_APP_VERSION');

/// Where the latest release's update file is. GitHub serves `releases/latest/download/…` as a
/// plain redirect to the asset, outside the API's 60-requests-an-hour limit — which a classroom
/// of students behind one address would otherwise exhaust.
const updateManifestUrl = String.fromEnvironment(
  'TIHE_UPDATE_URL',
  defaultValue:
      'https://github.com/bambadamin-lang/tihe-live/releases/latest/download/tihe-live-update.json',
);

/// Only this repository's release downloads are ever installed.
bool isTrustedDownload(Uri url) =>
    url.scheme == 'https' &&
    url.host == 'github.com' &&
    url.path.startsWith('/bambadamin-lang/tihe-live/releases/download/') &&
    url.path.endsWith('.exe');

/// Compares dotted numeric versions: negative when [a] is older than [b]. Anything that is not
/// a version compares as oldest, so a malformed manifest never triggers an install.
int compareVersions(String a, String b) {
  List<int>? parse(String v) {
    final parts = v.trim().split('.');
    if (parts.isEmpty || parts.length > 4) return null;
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0) return null;
      out.add(n);
    }
    while (out.length < 4) {
      out.add(0);
    }
    return out;
  }

  final x = parse(a), y = parse(b);
  if (x == null || y == null) return x == null ? (y == null ? 0 : -1) : 1;
  for (var i = 0; i < 4; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return 0;
}

/// A release the app could update to, as read from `tihe-live-update.json`.
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.url,
    required this.sha256,
  });

  final String version;
  final Uri url;

  /// Lowercase hex.
  final String sha256;

  /// Null for anything malformed or pointing outside [trusted].
  static UpdateManifest? tryParse(
    Object? json, {
    bool Function(Uri) trusted = isTrustedDownload,
  }) {
    if (json is! Map<String, Object?>) return null;
    final version = json['version'], url = json['url'], hash = json['sha256'];
    if (version is! String || url is! String || hash is! String) return null;
    final uri = Uri.tryParse(url);
    final digest = hash.toLowerCase();
    if (uri == null || !trusted(uri)) return null;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) return null;
    if (compareVersions(version, '0') <= 0) return null;
    return UpdateManifest(version: version, url: uri, sha256: digest);
  }

  Map<String, Object> toJson() => {
    'version': version,
    'url': url.toString(),
    'sha256': sha256,
  };
}

/// Checks, downloads and installs updates. Every failure is quiet: an app that cannot reach
/// GitHub simply stays on the version it has.
class Updater {
  Updater({
    required this.currentVersion,
    required this.directory,
    Uri? manifestUrl,
    this.trusted = isTrustedDownload,
    HttpClient Function()? client,
  }) : manifestUrl = manifestUrl ?? Uri.parse(updateManifestUrl),
       _client = client ?? HttpClient.new;

  final String currentVersion;

  /// Where downloads wait to be installed, e.g. `%LOCALAPPDATA%\TIHE Live\updates`.
  final Directory directory;
  final Uri manifestUrl;
  final bool Function(Uri) trusted;
  final HttpClient Function() _client;

  File get _pendingFile =>
      File('${directory.path}${Platform.pathSeparator}pending.json');

  /// The latest release, when it is newer than this build.
  Future<UpdateManifest?> check() async {
    try {
      final bytes = await _get(manifestUrl, limit: 64 * 1024);
      final manifest = UpdateManifest.tryParse(
        jsonDecode(utf8.decode(bytes)),
        trusted: trusted,
      );
      if (manifest == null) return null;
      return compareVersions(manifest.version, currentVersion) > 0
          ? manifest
          : null;
    } on Object {
      return null;
    }
  }

  /// Downloads the wizard and keeps it only if its SHA-256 matches the manifest. Returns the
  /// verified file, ready for [launchInstaller].
  Future<File?> download(UpdateManifest m) async {
    try {
      final ready = await pending();
      if (ready != null && ready.$1.version == m.version) return ready.$2;
      // An older download this one supersedes goes, with its start-up attempt.
      if (ready != null) await directory.delete(recursive: true);
      await directory.create(recursive: true);
      final bytes = await _get(m.url, limit: 512 * 1024 * 1024);
      if (sha256.convert(bytes).toString() != m.sha256) return null;
      final file = File(_setupPath(m.version));
      await file.writeAsBytes(bytes, flush: true);
      await _pendingFile.writeAsString(jsonEncode(m.toJson()), flush: true);
      return file;
    } on Object {
      return null;
    }
  }

  /// A download from an earlier run that is still newer than this build and still matches its
  /// hash. Anything else in [directory] — an update already installed, a damaged file — is
  /// cleared away.
  Future<(UpdateManifest, File)?> pending() async {
    try {
      if (!await _pendingFile.exists()) return null;
      final m = UpdateManifest.tryParse(
        jsonDecode(await _pendingFile.readAsString()),
        trusted: trusted,
      );
      final file = m == null ? null : File(_setupPath(m.version));
      if (m != null &&
          file != null &&
          compareVersions(m.version, currentVersion) > 0 &&
          await file.exists() &&
          sha256.convert(await file.readAsBytes()).toString() == m.sha256) {
        return (m, file);
      }
      await directory.delete(recursive: true);
      return null;
    } on Object {
      return null;
    }
  }

  File get _attemptFile =>
      File('${directory.path}${Platform.pathSeparator}attempted.txt');

  /// Whether this version's install was already tried once at start-up.
  Future<bool> attempted(String version) async {
    try {
      return (await _attemptFile.readAsString()).trim() == version;
    } on Object {
      return false;
    }
  }

  Future<void> markAttempted(String version) async {
    try {
      await _attemptFile.writeAsString(version, flush: true);
    } on Object {
      // Worst case the start-up install is tried once more.
    }
  }

  String _setupPath(String version) =>
      '${directory.path}${Platform.pathSeparator}TIHE-Live-Setup-$version.exe';

  Future<List<int>> _get(Uri url, {required int limit}) async {
    final client = _client()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(url);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('status ${response.statusCode}', uri: url);
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        out.add(chunk);
        if (out.length > limit) throw const HttpException('too large');
      }
      return out.takeBytes();
    } finally {
      client.close(force: true);
    }
  }
}

/// The wizard's arguments for an unattended update of the copy at [installedExe]:
/// a progress bar only, no questions, the app closed and started again by the wizard
/// (`/update=1`, see tihe_live.iss). A copy under Program Files was installed for all users,
/// so the update goes there too (Windows asks for permission); otherwise it stays per-user —
/// either way the wizard finds the existing folder rather than installing a second copy.
List<String> installArguments(String installedExe, {String? programFiles}) {
  final pf = (programFiles ?? Platform.environment['ProgramFiles'] ?? '')
      .toLowerCase();
  final allUsers =
      pf.isNotEmpty && installedExe.toLowerCase().startsWith('$pf\\');
  return [
    '/SILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
    allUsers ? '/ALLUSERS' : '/CURRENTUSER',
    '/update=1',
  ];
}

/// Starts the wizard on its own and leaves it running; the caller then quits so the wizard
/// can replace the app's files.
Future<void> launchInstaller(File setup) => Process.start(
  setup.path,
  installArguments(Platform.resolvedExecutable),
  mode: ProcessStartMode.detached,
);

/// `%LOCALAPPDATA%\TIHE Live\updates` — per user, never needs administrator rights.
Directory defaultUpdateDirectory() {
  final base =
      Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
  return Directory(
    '$base${Platform.pathSeparator}TIHE Live${Platform.pathSeparator}updates',
  );
}

/// The app's side of updating: installs a download left by an earlier run, and looks for new
/// releases in the background while it runs.
class AppUpdates extends ChangeNotifier {
  AppUpdates(
    this.updater, {
    Future<void> Function(File setup)? launch,
    void Function()? quit,
  }) : _launch = launch ?? launchInstaller,
       _quit = quit ?? (() => exit(0));

  final Updater updater;
  final Future<void> Function(File setup) _launch;
  final void Function() _quit;
  UpdateManifest? _ready;
  File? _file;
  Timer? _timer;

  /// A verified update waiting to be installed, if any.
  UpdateManifest? get ready => _ready;

  /// Starts the wizard for a download from an earlier run; true when the app should now quit.
  /// Once per version: if that attempt did not take (Windows permission refused, say), the
  /// app opens as usual and the launcher offers the update instead of looping on it.
  Future<bool> installPendingOnStart() async {
    final p = await updater.pending();
    if (p == null) return false;
    _ready = p.$1;
    _file = p.$2;
    if (await updater.attempted(p.$1.version)) return false;
    await updater.markAttempted(p.$1.version);
    try {
      await _launch(p.$2);
      return true;
    } on Object {
      return false;
    }
  }

  /// Checks now and every few hours: an app left open all day still finds the day's release.
  void start() {
    unawaited(poll());
    _timer ??= Timer.periodic(const Duration(hours: 3), (_) => poll());
  }

  Future<void> poll() async {
    if (_ready != null) return;
    final m = await updater.check();
    if (m == null) return;
    final f = await updater.download(m);
    if (f == null) return;
    _ready = m;
    _file = f;
    notifyListeners();
  }

  /// Starts the wizard and quits so it can replace the app's files; it starts the app again.
  Future<void> installNow() async {
    final f = _file;
    if (f == null) return;
    try {
      await _launch(f);
    } on Object {
      return;
    }
    _quit();
  }

  /// For tests and screenshots: as if [m] had been downloaded to [f].
  @visibleForTesting
  void debugReady(UpdateManifest m, File f) {
    _ready = m;
    _file = f;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

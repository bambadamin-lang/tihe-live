import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The device identity presented at sign-in.
///
/// Two separate things, often confused:
///
///  * **The fingerprint** answers "is this the same machine as last time?" so the server can
///    enforce the device allowance. It is not a secret and not an authentication factor — every
///    hardware identifier available to an unprivileged app is either spoofable or changes on an OS
///    upgrade.
///  * **The keypair** is the actual security. Content keys are wrapped to its public half, and the
///    private half is sealed by the platform keystore and never leaves the device. That is what
///    makes a `.tihex` file copied to another machine unopenable.
///
/// The keypair is generated and sealed by `packages/secure-core` over FFI (M3). Until that bridge
/// exists this class produces the fingerprint and reads back a stored public key, so the auth flow
/// is complete and the crypto slots in without changing the call sites.
class DeviceIdentity {
  DeviceIdentity({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  final FlutterSecureStorage _storage;

  static const _installIdKey = 'tihe.install_id';
  static const _publicKeyKey = 'tihe.device_public_key';

  Future<Map<String, dynamic>> describe() async {
    final info = await _gatherSignals();
    return {
      'fingerprint': _fingerprint(info),
      'platform': _platformName(),
      'name': info.friendlyName,
      'publicKey': await _publicKey(),
      'appVersion': info.appVersion,
      'osVersion': info.osVersion,
    };
  }

  /// Derives the fingerprint the server stores.
  ///
  /// Note what is excluded: the OS version. An OS upgrade must not look like a new device, or every
  /// Windows update would consume one of the student's device slots. Mirrors
  /// `derive_fingerprint` in secure-core.
  String _fingerprint(_DeviceSignals signals) {
    final material = [
      'tihe-device-fingerprint-v1',
      _platformName(),
      signals.primaryId,
      signals.model,
      signals.installId,
    ].join('\u0000');
    return crypto.sha256.convert(utf8.encode(material)).toString();
  }

  Future<_DeviceSignals> _gatherSignals() async {
    final plugin = DeviceInfoPlugin();
    final package = await PackageInfo.fromPlatform();
    final installId = await _installId();

    if (Platform.isAndroid) {
      final android = await plugin.androidInfo;
      return _DeviceSignals(
        primaryId: android.id,
        model: '${android.manufacturer} ${android.model}',
        friendlyName: android.model,
        osVersion: 'Android ${android.version.release}',
        appVersion: package.version,
        installId: installId,
      );
    }
    if (Platform.isWindows) {
      final windows = await plugin.windowsInfo;
      return _DeviceSignals(
        primaryId: windows.deviceId,
        model: windows.productName,
        friendlyName: windows.computerName,
        osVersion: windows.displayVersion,
        appVersion: package.version,
        installId: installId,
      );
    }
    if (Platform.isIOS) {
      final ios = await plugin.iosInfo;
      return _DeviceSignals(
        // identifierForVendor is per-vendor and resets when the last of our apps is uninstalled,
        // which is the closest iOS offers.
        primaryId: ios.identifierForVendor ?? installId,
        model: ios.utsname.machine,
        friendlyName: ios.name,
        osVersion: 'iOS ${ios.systemVersion}',
        appVersion: package.version,
        installId: installId,
      );
    }

    // Desktop Linux/macOS are not shipping targets yet; the install id alone keeps development
    // working without pretending to identify the hardware.
    return _DeviceSignals(
      primaryId: installId,
      model: Platform.operatingSystem,
      friendlyName: Platform.localHostname,
      osVersion: Platform.operatingSystemVersion,
      appVersion: package.version,
      installId: installId,
    );
  }

  /// A random id created on first launch and kept with the keypair.
  ///
  /// It makes the fingerprint stable when hardware identifiers change, and makes a fresh install
  /// look like a new device — which is the safe direction: the alternative lets a cloned install
  /// share one device slot.
  Future<String> _installId() async {
    final existing = await _storage.read(key: _installIdKey);
    if (existing != null) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final generated = base64Url.encode(bytes);
    await _storage.write(key: _installIdKey, value: generated);
    return generated;
  }

  /// The device's X25519 public key.
  ///
  /// M3 replaces this with a call into secure-core, which generates the keypair and seals the
  /// private half in the platform keystore. Until then a stored placeholder keeps the sign-in
  /// contract intact — the server accepts and stores whatever public key it is given, and wrapping
  /// content keys to it only becomes meaningful once the private half is real.
  Future<String> _publicKey() async {
    final existing = await _storage.read(key: _publicKeyKey);
    if (existing != null) return existing;

    // TODO(M3): replace with SecureCore.generateDeviceKeypair(), which seals the private half in
    // Android Keystore / Windows DPAPI and returns only the public bytes.
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final generated = base64.encode(bytes);
    await _storage.write(key: _publicKeyKey, value: generated);
    return generated;
  }

  String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    return 'linux';
  }
}

class _DeviceSignals {
  const _DeviceSignals({
    required this.primaryId,
    required this.model,
    required this.friendlyName,
    required this.osVersion,
    required this.appVersion,
    required this.installId,
  });

  final String primaryId;
  final String model;
  final String friendlyName;
  final String osVersion;
  final String appVersion;
  final String installId;
}

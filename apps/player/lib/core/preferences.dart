import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'security/app_log.dart';

/// The student's appearance choice.
///
/// Dark by default, as before: the product is a video player and most watching happens in the
/// evening. The choice is restored asynchronously, so the first frame is dark and a light-mode
/// student sees one quick switch — preferable to delaying launch on a disk read.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'appearance.themeMode';

  @override
  ThemeMode build() {
    Future.microtask(_restore);
    return ThemeMode.dark;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      final mode = ThemeMode.values.where((m) => m.name == stored).firstOrNull;
      if (mode != null) state = mode;
    } catch (error) {
      // A preference is never worth a crash; the default stands.
      AppLog.warn('appearance preference not restored: $error');
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (error) {
      AppLog.warn('appearance preference not saved: $error');
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// The installed version, for the About row.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

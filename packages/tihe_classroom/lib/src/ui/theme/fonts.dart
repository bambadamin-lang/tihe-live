import 'package:flutter/services.dart';

/// Registers Modam, the classroom's typeface, from this package's assets (docs/11 §11).
///
/// The files are loaded at runtime rather than declared in pubspec, so the family is plain
/// `Modam` in every app that uses the package (a declared package font would be
/// `packages/tihe_classroom/Modam`). Every asset under `assets/fonts/` named `Modam-*.ttf` is
/// loaded into the one family; the engine reads each file's weight from the file itself.
///
/// An app with its own typeface calls [use] first, so the class is in the same type as the rest
/// of the app. The one TIHE app is set in Modam too.
abstract final class ClassroomFonts {
  static const defaultFamily = 'Modam';
  static String _family = defaultFamily;

  /// The family the classroom is set in.
  static String get family => _family;

  /// Sets the classroom in [name] instead of Modam: `<name>-*.ttf` files from this package's
  /// assets. Call once, before [ensureLoaded].
  static void use(String name) {
    assert(
      _loading == null,
      'ClassroomFonts.use must come before ensureLoaded',
    );
    _family = name;
  }

  /// In an app the package's assets sit under `packages/tihe_classroom/`; in the package's own
  /// tests they do not.
  static const _dirs = [
    'packages/tihe_classroom/assets/fonts/',
    'assets/fonts/',
  ];
  static Future<bool>? _loading;

  /// Loads once; safe to call from every page. True when Modam is available. Apps call it
  /// before `runApp`, so the first frame is already in Modam.
  static Future<bool> ensureLoaded([AssetBundle? bundle]) =>
      _loading ??= _load(bundle ?? rootBundle);

  static Future<bool> _load(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final files = manifest.listAssets().where((path) {
      final dir = _dirs.where(path.startsWith).firstOrNull;
      if (dir == null) return false;
      final name = path.substring(dir.length).toLowerCase();
      // Only the standard cut: ModamFaNum and ModamNoEn are other families. The dash keeps
      // them out.
      return name.startsWith('${_family.toLowerCase()}-') &&
          (name.endsWith('.ttf') || name.endsWith('.otf'));
    }).toList();
    if (files.isEmpty) return false;
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(bundle.load(file));
    }
    await loader.load();
    return true;
  }
}

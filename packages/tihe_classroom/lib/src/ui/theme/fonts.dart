import 'package:flutter/services.dart';

/// Registers Peyda from this package's assets at runtime (docs/11 §11).
///
/// Fonts are not declared in pubspec: a declared font file that does not exist fails the build,
/// and the Peyda files are added later by the institute. Instead every asset under
/// `assets/fonts/` whose name starts with `Peyda` is loaded into one family; the engine reads
/// each file's own weight. With no files present this is a no-op and the fallback fonts apply.
abstract final class PeydaFonts {
  static const family = 'Peyda';
  static const _prefix = 'packages/tihe_classroom/assets/fonts/';
  static Future<bool>? _loading;

  /// Loads once; safe to call from every classroom page. True when Peyda is available.
  static Future<bool> ensureLoaded([AssetBundle? bundle]) =>
      _loading ??= _load(bundle ?? rootBundle);

  static Future<bool> _load(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final files = manifest.listAssets().where((path) {
      if (!path.startsWith(_prefix)) return false;
      final name = path.substring(_prefix.length).toLowerCase();
      return name.startsWith('peyda') &&
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

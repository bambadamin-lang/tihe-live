import 'dart:math';

/// Prefixed ULIDs (`wbi_01J8Z…`), as the server uses. Client-side ids are needed for board
/// items and chat drafts, so a stroke appears the moment it is drawn.
const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
final _random = Random.secure();

String newUlid([DateTime? now]) {
  var time = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final chars = List.filled(26, '0');
  for (var i = 9; i >= 0; i--) {
    chars[i] = _crockford[time % 32];
    time ~/= 32;
  }
  for (var i = 10; i < 26; i++) {
    chars[i] = _crockford[_random.nextInt(32)];
  }
  return chars.join();
}

String newBoardItemId() => 'wbi_${newUlid()}';
String newBoardPageId() => 'wbp_${newUlid()}';

/// The five-digit account id printed in watermarks. Must equal `watermarkShortId` in
/// packages/contracts/src/live/watermark.ts (FNV-1a over UTF-16 code units) — both are tested
/// against fixtures/live/watermark-vectors.json.
String watermarkShortId(String userId) {
  var hash = 0x811c9dc5;
  for (final unit in userId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return (hash % 100000).toString().padLeft(5, '0');
}

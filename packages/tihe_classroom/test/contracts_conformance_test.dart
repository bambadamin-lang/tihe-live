import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/src/contracts.dart';

/// The fixtures in packages/contracts/fixtures/live are produced from the TypeScript contract
/// and validated by zod there. Decoding each one here and encoding it back must give the same
/// JSON: if the server's shapes change and this mirror does not, this fails.
Object? fixture(String name) =>
    jsonDecode(File('../contracts/fixtures/live/$name').readAsStringSync());

const deep = DeepCollectionEquality();

/// JSON equality where an absent key and a null value mean the same thing.
Object? normalise(Object? v) => switch (v) {
  Map() => {
    for (final e in v.entries)
      if (e.value != null) e.key: normalise(e.value),
  },
  List() => [for (final x in v) normalise(x)],
  num() => v.toDouble(),
  _ => v,
};

void expectRoundTrip(Object? original, Object? reencoded) {
  expect(
    deep.equals(normalise(original), normalise(reencoded)),
    isTrue,
    reason:
        'round trip changed the JSON:\n${jsonEncode(original)}\n${jsonEncode(reencoded)}',
  );
}

void main() {
  test('snapshot round-trips', () {
    final raw = fixture('snapshot.json');
    expectRoundTrip(raw, ClassroomSnapshot.fromJson(asJson(raw)).toJson());
  });

  test('class list parses, live and not', () {
    final classes = [
      for (final raw in fixture('live-classes.json') as List)
        LiveClass.fromJson(asJson(raw)),
    ];
    expect(classes.map((c) => c.isLive), [true, false]);
    expect(classes.first.scheduledStartAt, DateTime.utc(2026, 10, 4, 6, 30));
    expect(classes.last.scheduledStartAt, isNull);
  });

  test('join response round-trips', () {
    final raw = fixture('join-response.json');
    expectRoundTrip(raw, JoinResponse.fromJson(asJson(raw)).toJson());
  });

  test('every server message round-trips', () {
    for (final raw in fixture('server-messages.json') as List) {
      expectRoundTrip(raw, ServerMessage.fromJson(asJson(raw)).toJson());
    }
  });

  test('every client command round-trips', () {
    for (final raw in fixture('client-messages.json') as List) {
      final msg = asJson(raw);
      if (msg['t'] != 'cmd') continue;
      final cmd = ClassroomCommand.fromJson(asJson(msg['cmd']));
      expectRoundTrip(msg, ClientMessages.command(msg['id'] as String, cmd));
    }
  });

  test('ephemeral board progress round-trips', () {
    for (final raw in fixture('client-messages.json') as List) {
      final msg = asJson(raw);
      if (msg['t'] != 'eph') continue;
      expectRoundTrip(
        msg,
        ClientMessages.ephemeral(BoardProgress.fromJson(asJson(msg['eph']))),
      );
    }
  });

  test('layout presets equal the contract', () {
    final raw = asJson(fixture('layout-presets.json'));
    for (final preset in LayoutPreset.values) {
      expectRoundTrip(raw[preset.wire], layoutPresets[preset]!.toJson());
      expect(layoutProblems(layoutPresets[preset]!.pods), isEmpty);
    }
  });

  test('pen styles, widths and palette equal the contract', () {
    final raw = asJson(fixture('board-styles.json'));
    expectRoundTrip(raw['penStyles'], {
      for (final e in penStyles.entries) e.key.wire: e.value.toJson(),
    });
    expectRoundTrip(raw['defaultWidths'], defaultToolWidth);
    expectRoundTrip(raw['palette'], boardPalette);
  });

  test('watermark short ids equal the TypeScript implementation', () {
    for (final v in fixture('watermark-vectors.json') as List) {
      final vector = asJson(v);
      expect(watermarkShortId(vector['userId'] as String), vector['shortId']);
    }
  });

  test('client-generated ids match the id format the server validates', () {
    expect(newBoardItemId(), matches(RegExp(r'^wbi_[0-9A-HJKMNP-TV-Z]{26}$')));
  });
}

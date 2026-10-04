import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

/// The glow cursor: a real cursor on Windows, drawn by the root scope on macOS and Linux, the
/// system arrow elsewhere — and never an invisible pointer.
void main() {
  late List<MethodCall> calls;
  Object? Function(MethodCall call)? respond;

  setUp(() {
    calls = [];
    respond = null;
    GlowCursorEngine.instance.debugReset();
  });

  Future<void> pumpRegions(WidgetTester tester, {bool scope = false}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.mouseCursor,
      (call) async {
        calls.add(call);
        return respond?.call(call);
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.mouseCursor,
        null,
      ),
    );
    final regions = Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          const Expanded(
            child: MouseRegion(
              cursor: GlowCursors.click,
              child: SizedBox.expand(),
            ),
          ),
          const Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              child: SizedBox.expand(),
            ),
          ),
          Expanded(child: Container()),
        ],
      ),
    );
    await tester.pumpWidget(scope ? GlowCursorScope(child: regions) : regions);
  }

  // RTL: the first region is on the right.
  const onClick = Offset(700, 300);
  const onText = Offset(400, 300);
  const onPlain = Offset(100, 300);

  Iterable<MethodCall> named(String method) =>
      calls.where((c) => c.method == method);

  testWidgets('on Windows the arrow is a real cursor, made once per scale', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await pumpRegions(tester, scope: true);
    await tester.runAsync(() async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: onPlain);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await mouse.moveTo(onText);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await mouse.moveTo(onPlain);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await mouse.removePointer();
    });

    final created = named('createCustomCursor/windows').toList();
    expect(created, hasLength(1), reason: 'the basic arrow, made once');
    final args = created.single.arguments as Map<Object?, Object?>;
    final width = args['width']! as int, height = args['height']! as int;
    expect(width, (GlowCursorArt.size.width * 3).ceil()); // tests run at 3x
    expect((args['buffer']! as Uint8List).length, width * height * 4);
    expect(args['hotX'], isA<double>());
    expect(args['hotY'], isA<double>());

    final set = named('setCustomCursor/windows').toList();
    expect(set, hasLength(2), reason: 'shown, then shown again after text');
    expect(
      (set.first.arguments as Map<Object?, Object?>)['name'],
      args['name'],
    );
    // The text field keeps the system I-beam.
    expect(
      named(
        'activateSystemCursor',
      ).map((c) => (c.arguments as Map<Object?, Object?>)['kind']),
      ['text'],
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('if Windows refuses the bitmap, the system cursor stays', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    respond = (call) => call.method == 'createCustomCursor/windows'
        ? throw PlatformException(code: 'Argument error')
        : null;
    await pumpRegions(tester);
    await tester.runAsync(() async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: onClick);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await mouse.removePointer();
    });
    expect(named('setCustomCursor/windows'), isEmpty);
    expect(
      named(
        'activateSystemCursor',
      ).map((c) => (c.arguments as Map<Object?, Object?>)['kind']),
      ['click'],
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on macOS the root scope hides the pointer and draws the arrow', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpRegions(tester, scope: true);
    final engine = GlowCursorEngine.instance;
    expect(engine.mode, GlowCursorMode.overlay);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: onPlain);
    await tester.pump();
    expect(engine.overlayKind.value, GlowCursorKind.basic);
    await mouse.moveTo(onClick);
    await tester.pump();
    expect(engine.overlayKind.value, GlowCursorKind.click);
    await mouse.moveTo(onText);
    await tester.pump();
    expect(engine.overlayKind.value, isNull, reason: 'the I-beam, not ours');
    await mouse.removePointer();
    await tester.pump();

    final kinds = named(
      'activateSystemCursor',
    ).map((c) => (c.arguments as Map<Object?, Object?>)['kind']).toList();
    expect(kinds, ['none', 'none', 'text']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('without a scope to draw it, macOS keeps the system arrow', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await pumpRegions(tester);
    expect(GlowCursorEngine.instance.mode, GlowCursorMode.system);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: onClick);
    await tester.pump();
    await mouse.removePointer();
    expect(
      named(
        'activateSystemCursor',
      ).map((c) => (c.arguments as Map<Object?, Object?>)['kind']),
      ['click'],
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'the bitmap: tip at the hot spot, clear corners, no black holes',
    (tester) async {
      await tester.runAsync(() async {
        for (final kind in GlowCursorKind.values) {
          final b = await GlowCursorArt.bitmap(kind, 2);
          expect(b.width, 64);
          expect(b.height, 76);
          expect(b.bgra.length, 64 * 76 * 4);
          int alpha(int x, int y) => b.bgra[(y * b.width + x) * 4 + 3];
          // Just inside the tip is arrow, well away from it is nothing.
          final tip = b.hotSpot + const Offset(2, 5);
          expect(alpha(tip.dx.round(), tip.dy.round()), greaterThan(200));
          expect(alpha(0, 0), 0);
          expect(alpha(b.width - 1, 0), 0);
          // Windows punches opaque pure black out of a cursor.
          for (var i = 0; i < b.bgra.length; i += 4) {
            final black =
                b.bgra[i] == 0 && b.bgra[i + 1] == 0 && b.bgra[i + 2] == 0;
            if (black) expect(b.bgra[i + 3], 0);
          }
        }
      });
    },
  );
}

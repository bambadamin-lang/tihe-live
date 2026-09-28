import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/src/ui/controls/bars.dart';
import 'package:tihe_classroom/src/ui/pods/chat_pod.dart';
import 'package:tihe_classroom/src/ui/pods/media_pods.dart';
import 'package:tihe_classroom/src/ui/protection/watermark_overlay.dart';
import 'package:tihe_classroom/src/ui/whiteboard/whiteboard_pod.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

Future<({ClassroomSession session, DemoClassroomServer server})> pumpClassroom(
  WidgetTester tester, {
  String as = DemoClassroom.host,
  Size size = const Size(1600, 900),
  Layout? layout,
  void Function(ClassroomExit)? onExit,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final demo = DemoClassroom.build(as: as, layout: layout);
  await tester.pumpWidget(
    MaterialApp(
      home: ClassroomPage(session: demo.session, onExit: onExit),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  return (session: demo.session, server: demo.server);
}

void main() {
  testWidgets(
    'shows the host\'s layout: board, speaker and chat, with the watermark on top',
    (tester) async {
      await pumpClassroom(tester);
      expect(find.byType(WhiteboardPod), findsOneWidget);
      expect(find.byType(SpeakerPod), findsOneWidget);
      expect(find.byType(ChatPod), findsOneWidget);
      expect(find.byType(WatermarkOverlay), findsOneWidget);
      // Outline and fill are two layers of the same text.
      expect(find.textContaining('0912•••0001 · #'), findsNWidgets(2));
    },
  );

  testWidgets('every stage follows a layout change', (tester) async {
    final c = await pumpClassroom(tester, as: DemoClassroom.ali);
    c.server.emit(
      LayoutApplied(
        layoutPresets[LayoutPreset.discussion]!,
        DemoClassroom.host,
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GalleryPod), findsOneWidget);
    // The dropped board fades out rather than vanishing, and takes no input while it does.
    expect(
      find.ancestor(
        of: find.byType(WhiteboardPod),
        matching: find.byWidgetPredicate(
          (w) => w is IgnorePointer && w.ignoring,
        ),
      ),
      findsWidgets,
    );
    await tester.pump(Motion.medium);
    await tester.pump();
    expect(find.byType(WhiteboardPod), findsNothing);
  });

  testWidgets(
    'a student cannot draw and sees why; the host gets the marker tray',
    (tester) async {
      await pumpClassroom(tester, as: DemoClassroom.ali);
      expect(find.byType(MarkerTray), findsNothing);
      expect(find.text('تخته فقط برای مشاهده است'), findsOneWidget);
    },
  );

  testWidgets('host sees the marker tray and host controls', (tester) async {
    await pumpClassroom(tester);
    expect(find.byType(MarkerTray), findsOneWidget);
    expect(find.text('پایان کلاس'), findsOneWidget);
    expect(find.text('چیدمان'), findsOneWidget);
  });

  testWidgets('the hand paddle raises and lowers the student\'s hand', (
    tester,
  ) async {
    final c = await pumpClassroom(tester, as: DemoClassroom.ali);
    expect(find.text('دست بالاست'), findsOneWidget);
    await tester.tap(find.byType(HandToggle));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.server.state.participants[DemoClassroom.ali]!.hand, isNull);
    expect(find.text('دست'), findsOneWidget);
  });

  testWidgets('a phone shows one pod at a time behind tabs', (tester) async {
    await pumpClassroom(
      tester,
      as: DemoClassroom.ali,
      size: const Size(390, 844),
    );
    final tabs = find.byType(GlassTabs<String>);
    expect(tabs, findsOneWidget);
    expect(
      find.descendant(of: tabs, matching: find.byType(GlassPressable)),
      findsNWidgets(3),
    );
    expect(find.byType(WhiteboardPod), findsOneWidget);
    expect(find.byType(ChatPod), findsNothing);
    final chatTab = find.descendant(of: tabs, matching: find.text('گفتگو'));
    await tester.ensureVisible(chatTab);
    await tester.pump();
    await tester.tap(chatTab);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ChatPod), findsOneWidget);
  });

  testWidgets('the class ending shows the exit screen and hands control back', (
    tester,
  ) async {
    ClassroomExit? exited;
    final c = await pumpClassroom(
      tester,
      as: DemoClassroom.ali,
      onExit: (e) => exited = e,
    );
    c.server.emit(const ClassEnded('host_ended'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('کلاس به پایان رسید.'), findsOneWidget);
    await tester.tap(find.text('بازگشت'));
    expect(exited, ClassroomExit.ended);
  });

  testWidgets('follows the host app\'s light or dark theme', (tester) async {
    for (final brightness in Brightness.values) {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      final demo = DemoClassroom.build(as: DemoClassroom.ali);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: ClassroomPage(session: demo.session),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final context = tester.element(find.byType(ControlBar));
      expect(ClassroomTheme.of(context).brightness, brightness);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }
    tester.view.reset();
  });

  testWidgets('the top-bar switch flips the theme and tells the host app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Brightness? reported;
    final demo = DemoClassroom.build(as: DemoClassroom.ali);
    await tester.pumpWidget(
      MaterialApp(
        home: ClassroomPage(
          session: demo.session,
          brightness: Brightness.dark,
          onBrightnessChanged: (b) => reported = b,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    ClassroomTheme current() =>
        ClassroomTheme.of(tester.element(find.byType(ControlBar)));
    expect(current().isDark, isTrue);

    await tester.tap(find.byTooltip('پوستهٔ روشن'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(current().isDark, isFalse);
    expect(reported, Brightness.light);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

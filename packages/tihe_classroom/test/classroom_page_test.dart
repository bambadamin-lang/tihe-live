import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/demo.dart';
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
    await tester.tap(find.byType(HandPaddle));
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
    expect(find.byType(ChoiceChip), findsNWidgets(3));
    expect(find.byType(WhiteboardPod), findsOneWidget);
    expect(find.byType(ChatPod), findsNothing);
    final chatTab = find.widgetWithText(ChoiceChip, 'گفتگو');
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
}

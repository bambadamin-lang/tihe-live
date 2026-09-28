import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tihe_classroom/demo.dart';
import 'package:tihe_classroom/tihe_classroom.dart';

void main() {
  late List<ClassroomCommand> sent;
  late List<BoardProgress> previews;
  late BoardController board;
  final room = ClassroomState.fromSnapshot(DemoClassroom.snapshot(), 20);

  BoardController build(String userId) => BoardController(
    userId: userId,
    send: (c) async {
      sent.add(c);
      return const Accepted();
    },
    sendPreview: previews.add,
  );

  setUp(() {
    sent = [];
    previews = [];
  });

  test('streams a stroke as previews and finishes with done', () {
    fakeAsync((async) {
      board = build(DemoClassroom.host)..selectTool(BoardTool.pen);
      board.pointerDown((x: 100, y: 100), room, canManage: true);
      for (var i = 1; i <= 30; i++) {
        board.pointerMove((x: 100 + i * 50, y: 100), room);
        async.elapse(const Duration(milliseconds: 10));
      }
      board.pointerUp();
      async.flushMicrotasks();

      expect(
        previews.length,
        greaterThan(3),
        reason: 'batched roughly every 40 ms',
      );
      expect(previews.where((p) => p.done), hasLength(1));
      expect(previews.last.done, isTrue);
      final streamed = [for (final p in previews) ...p.points];
      final committed = (sent.single as AddBoardItem).item as StrokeItem;
      expect(
        streamed,
        committed.points,
        reason: 'previews carry exactly the committed points',
      );
      expect(board.history.canUndo, isTrue);
    });
  });

  test('a laser only ever sends previews', () {
    fakeAsync((async) {
      board = build(DemoClassroom.host)..selectTool(BoardTool.laser);
      board.pointerDown((x: 100, y: 100), room, canManage: true);
      board.pointerMove((x: 900, y: 900), room);
      async.elapse(const Duration(milliseconds: 50));
      board.pointerUp();
      async.flushMicrotasks();
      expect(sent, isEmpty);
      expect(previews.every((p) => p.isLaser), isTrue);
      expect(board.history.canUndo, isFalse);
    });
  });

  test('a student erases only their own ink; a manager erases anything', () {
    fakeAsync((async) {
      // The demo board is all the host's and the cohost's work.
      board = build(DemoClassroom.ali)..selectTool(BoardTool.eraser);
      board.pointerDown((x: 3400, y: 6000), room, canManage: false);
      board.pointerMove((x: 3400, y: 8200), room);
      board.pointerUp();
      async.flushMicrotasks();
      expect(sent, isEmpty);

      board = build(DemoClassroom.host)..selectTool(BoardTool.eraser);
      board.pointerDown((x: 3400, y: 6000), room, canManage: true);
      board.pointerMove((x: 3400, y: 8200), room);
      board.pointerUp();
      async.flushMicrotasks();
      expect(sent.single, isA<RemoveBoardItems>());
      expect((sent.single as RemoveBoardItems).itemIds, isNotEmpty);
    });
  });

  test('a shape is committed as two corners, and a click is not a shape', () {
    fakeAsync((async) {
      board = build(DemoClassroom.host)..selectTool(BoardTool.rect);
      board.pointerDown((x: 1000, y: 1000), room, canManage: true);
      board.pointerUp();
      async.flushMicrotasks();
      expect(sent, isEmpty);

      board.pointerDown((x: 1000, y: 1000), room, canManage: true);
      board.pointerMove((x: 3000, y: 2500), room);
      board.pointerUp();
      async.flushMicrotasks();
      final shape = (sent.single as AddBoardItem).item as ShapeItem;
      expect(shape.from, (x: 1000, y: 1000));
      expect(shape.to, (x: 3000, y: 2500));
    });
  });
}

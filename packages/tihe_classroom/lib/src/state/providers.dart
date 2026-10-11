import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'classroom_session.dart';

/// The session a classroom page runs. Always overridden by [ClassroomPage]'s own
/// ProviderScope — one scope per class, disposed with the page.
final classroomSessionProvider = Provider<ClassroomSession>(
  (ref) => throw StateError(
    'classroomSessionProvider must be overridden by ClassroomPage',
  ),
  dependencies: const [],
);

/// The whole classroom view. Widgets select the slice they draw
/// (`ref.watch(classroomViewProvider.select((v) => v.room?.layout))`), so a chat message does
/// not rebuild the whiteboard.
final classroomViewProvider =
    NotifierProvider<ClassroomViewNotifier, ClassroomView>(
      ClassroomViewNotifier.new,
      dependencies: [classroomSessionProvider],
    );

/// The view as the dock and the people and video pods use it: the room, and everyone's camera and
/// microphone. It moves on only when those do. Remote ink in flight (a batch every 40 ms while
/// anyone draws, docs/11 §6) and toasts change the whole view too, but none of these widgets
/// shows them, and rebuilding them for each batch costs a student's device thousands of widget
/// rebuilds a second.
final classroomRosterProvider = Provider<ClassroomView>((ref) {
  ref.watch(classroomViewProvider.select((v) => (v.room, v.media)));
  return ref.read(classroomViewProvider);
}, dependencies: [classroomViewProvider]);

class ClassroomViewNotifier extends Notifier<ClassroomView> {
  @override
  ClassroomView build() {
    final session = ref.watch(classroomSessionProvider);
    void listener() => state = session.view.value;
    session.view.addListener(listener);
    ref.onDispose(() => session.view.removeListener(listener));
    return session.view.value;
  }
}

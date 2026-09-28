import 'package:flutter/foundation.dart';
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

/// A list compared by its elements, for `select`: derived lists (the hand queue, the people on
/// camera) are rebuilt on every event, so comparing them by identity would always see a change.
@immutable
class ListSlice<T> {
  const ListSlice(this.items);

  final List<T> items;

  @override
  bool operator ==(Object other) =>
      other is ListSlice<T> && listEquals(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tihe_classroom/demo.dart' show DemoClassroom;
import 'package:tihe_classroom/tihe_classroom.dart' as live;

import '../../core/api/api_error.dart';
import '../../core/preferences.dart';
import '../../core/providers.dart';
import '../../core/security/app_log.dart';
import '../../core/server.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';

/// Opens a class over the whole window, above the shell and its navigation.
///
/// A pageless route on the root navigator: if the account is signed out while the class is open
/// (from another device, or by the institute), the router replaces the pages underneath and the
/// class closes with them, leaving the room exactly as on any other exit.
Future<void> showClassroom(
  BuildContext context,
  ProviderContainer container,
  live.ClassroomSession session,
) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    live.classroomRoute<void>(
      context,
      (_) => live.ClassroomPage(
        session: session,
        onExit: (_) => navigator.pop(),
        // A theme switch made in class carries back to the rest of the app.
        onBrightnessChanged: (brightness) => container
            .read(themeModeProvider.notifier)
            .set(brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light),
      ),
    ),
  );
}

/// Joins a live session and opens it. Refusals (not enrolled, class over, removed) are shown as
/// the server phrased them; nothing is thrown, because this runs from a button.
Future<void> joinLiveClass(BuildContext context, {required String sessionId}) async {
  // The tile that started this can be rebuilt away while the request is in flight.
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final session = await live.openClassroom(
      liveApiBaseUrl: container.read(serverProvider).liveBaseUrl,
      accessToken: container.read(accessTokenProvider),
      sessionId: sessionId,
    );
    if (!context.mounted) {
      await session.dispose();
      return;
    }
    await showClassroom(context, container, session);
  } on Object catch (error) {
    if (context.mounted) _showFailure(context, error);
  } finally {
    // Whatever happened, the list is stale: the class may have ended, or just begun.
    container.invalidate(liveClassesProvider);
  }
}

/// Starts a class (its teacher, or an admin) and walks straight in.
Future<void> startLiveClass(BuildContext context, {required String classId}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final String sessionId;
  try {
    sessionId = (await container.read(liveApiProvider).start(classId)).id;
  } on Object catch (error) {
    if (context.mounted) _showFailure(context, error);
    return;
  }
  if (context.mounted) await joinLiveClass(context, sessionId: sessionId);
}

/// The demo class: a lecture in progress, served in-process, as [as] (one of [DemoClassroom]'s
/// people). Works with no server at all.
Future<void> openDemoClass(BuildContext context, {required String as}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final demo = DemoClassroom.build(
    as: as,
    layout: live.layoutPresets[live.LayoutPreset.whiteboard],
  );
  return showClassroom(context, container, demo.session);
}

void _showFailure(BuildContext context, Object error) {
  final message = switch (error) {
    live.ApiError(:final messageFa) => messageFa,
    ApiError(:final messageFa) => messageFa,
    _ => context.l10n.errorUnknown,
  };
  if (error is! live.ApiError && error is! ApiError) {
    // Not the server's refusal: a contract mismatch or a bug. The type is enough to find it, and
    // carries no token or number.
    AppLog.warn('joining a class failed: ${error.runtimeType}');
  }
  showToast(context, message, tone: ToastTone.danger);
}

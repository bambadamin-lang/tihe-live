/// The TIHE Live classroom: stage and layouts, webcam and screen share, the whiteboard, raised
/// hands and access levels, capture censoring and the identity watermark — in Persian, in a
/// skeuomorphic theme. Design: docs/11-live-classroom.md.
///
/// Apps use [openClassroom] and [ClassroomPage]; the rest is exported for tests, the demo and
/// the video player (which shares the capture guard and theme pieces).
library;

export 'src/contracts.dart';
export 'src/data/fake_media.dart';
export 'src/data/gateway_client.dart';
export 'src/data/live_api.dart';
export 'src/data/media.dart';
export 'src/domain/classroom_state.dart';
export 'src/domain/persian.dart';
export 'src/domain/watermark_hopper.dart';
export 'src/open_classroom.dart';
export 'src/state/board_controller.dart';
export 'src/state/classroom_session.dart';
export 'src/state/providers.dart';
export 'src/ui/classroom_page.dart';
export 'src/ui/theme/classroom_theme.dart';
export 'src/ui/theme/fonts.dart';
export 'src/ui/theme/skeuo.dart';

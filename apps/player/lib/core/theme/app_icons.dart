import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Every icon the app uses, in one place.
///
/// One family (Lucide), one stroke weight, so nothing looks borrowed from a different set. Screens
/// refer to what an icon *means* here, never to a glyph directly: changing the weight or a glyph is
/// a one-line edit.
///
/// Directional glyphs use Lucide's `Dir` variants, which mirror under RTL: [forward] points left in
/// the Persian interface, as it should. Player transport icons are deliberately *not* mirrored —
/// media controls read left-to-right in every locale.
abstract final class AppIcons {
  // Navigation.
  static const IconData library = LucideIcons.libraryBig;
  static const IconData search = LucideIcons.search;
  static const IconData account = LucideIcons.circleUserRound;
  static const IconData devices = LucideIcons.monitorSmartphone;
  static const IconData settings = LucideIcons.settings;
  static const IconData back = LucideIcons.arrowLeftDir;
  static const IconData forward = LucideIcons.chevronRightDir;
  static const IconData chevronDown = LucideIcons.chevronDown;
  static const IconData close = LucideIcons.x;
  static const IconData signOut = LucideIcons.logOutDir;
  static const IconData shortcuts = LucideIcons.keyboard;
  static const IconData info = LucideIcons.info;
  static const IconData appearance = LucideIcons.sunMoon;

  // Content.
  static const IconData course = LucideIcons.bookOpen;
  static const IconData session = LucideIcons.circlePlay;
  static const IconData teacher = LucideIcons.userRound;
  static const IconData duration = LucideIcons.clock;
  static const IconData sessions = LucideIcons.listVideo;
  static const IconData chapter = LucideIcons.bookmark;
  static const IconData download = LucideIcons.arrowDownToLine;
  static const IconData downloaded = LucideIcons.circleCheck;
  static const IconData noDownload = LucideIcons.cloudOff;
  static const IconData locked = LucideIcons.lock;
  static const IconData completed = LucideIcons.check;
  static const IconData protectedContent = LucideIcons.shieldCheck;
  static const IconData watermark = LucideIcons.fingerprint;
  static const IconData capture = LucideIcons.monitorOff;
  static const IconData resumeFrom = LucideIcons.history;

  // Devices.
  static const IconData desktop = LucideIcons.monitor;
  static const IconData laptop = LucideIcons.laptop;
  static const IconData phone = LucideIcons.smartphone;
  static const IconData tablet = LucideIcons.tablet;
  static const IconData remove = LucideIcons.trash2;

  // Sign-in.
  static const IconData phoneInput = LucideIcons.smartphone;
  static const IconData code = LucideIcons.keyRound;

  // Theme.
  static const IconData themeSystem = LucideIcons.monitor;
  static const IconData themeLight = LucideIcons.sun;
  static const IconData themeDark = LucideIcons.moon;

  // States.
  static const IconData error = LucideIcons.circleAlert;
  static const IconData offline = LucideIcons.wifiOff;
  static const IconData retry = LucideIcons.rotateCw;
  static const IconData empty = LucideIcons.inbox;
  static const IconData noResults = LucideIcons.searchX;

  // Player transport. Never mirrored.
  static const IconData play = LucideIcons.play;
  static const IconData pause = LucideIcons.pause;
  static const IconData previous = LucideIcons.skipBack;
  static const IconData next = LucideIcons.skipForward;
  static const IconData seekBack = LucideIcons.rotateCcw;
  static const IconData seekForward = LucideIcons.rotateCw;
  static const IconData volume = LucideIcons.volume2;
  static const IconData volumeLow = LucideIcons.volume1;
  static const IconData muted = LucideIcons.volumeX;
  static const IconData fullscreen = LucideIcons.maximize;
  static const IconData exitFullscreen = LucideIcons.minimize;
  static const IconData playerSettings = LucideIcons.settings2;
  static const IconData speed = LucideIcons.gauge;
  static const IconData quality = LucideIcons.slidersHorizontal;
  static const IconData subtitles = LucideIcons.captions;
  static const IconData nowPlaying = LucideIcons.audioLines;
}

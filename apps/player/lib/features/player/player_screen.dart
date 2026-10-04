import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart';
import '../../core/api/repositories.dart';
import '../../core/providers.dart';
import '../../core/security/app_log.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import 'player_controller.dart';
import 'player_controls.dart';
import 'watermark_overlay.dart';

/// Protected playback.
///
/// At M0 this screen does everything around the video except decode it: it mints a playback session,
/// renders the identity watermark and the full player chrome, and shows what the server returned.
/// The video surface itself arrives in M3 together with the `secure-core` FFI bridge, because the
/// two are inseparable — the player is only ever handed a `127.0.0.1` URL from the loopback server,
/// never a remote manifest and never a key (docs/adr/0008).
///
/// Written this way deliberately rather than wiring a plain player against the manifest URL: a
/// temporary unprotected playback path is exactly the kind of shortcut that survives into a release.
///
/// Always dark, whatever the app theme: chrome around a video should recede.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({required this.videoId, super.key});

  final String videoId;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  PlaybackSession? _session;
  Video? _video;
  PlayerController? _controller;
  Object? _error;
  bool _loading = true;
  bool _fullscreen = false;

  final _controlsKey = GlobalKey<PlayerControlsState>();
  final _focusNode = FocusNode(debugLabel: 'player');

  // Read while the widget is alive: `ref` is unusable inside dispose(), which is exactly where the
  // session has to be ended.
  late final PlaybackRepository _playback = ref.read(playbackRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    // Frees the concurrent-stream slot. Without this, force-quitting the app would leave a session
    // live until it expired, and a student on their allowance of one stream could not restart.
    final session = _session;
    if (session != null) {
      _playback.end(session.sessionId).ignore();
    }
    if (_fullscreen) _restoreSystemUi();
    _controller?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final auth = ref.read(authControllerProvider);
      if (auth is! AuthSignedIn) {
        throw const ApiError(
          code: 'UNAUTHENTICATED',
          message: 'no session',
          messageFa: 'برای ادامه باید وارد حساب خود شوید.',
        );
      }

      final video = await ref.read(catalogRepositoryProvider).video(widget.videoId);

      final session = await _playback.start(
        videoId: widget.videoId,
        deviceId: auth.session.device.id,
        // M3 fills this from secure-core's environment checks (screen recorder, virtual display,
        // emulator, debugger). Sending nothing is honest until those checks exist — a hardcoded set
        // of falses would claim a clean environment we have not verified.
      );

      if (!mounted) return;
      setState(() {
        _video = video;
        _session = session;
        _controller = PlayerController(
          duration: video.duration,
          // Resume where the student left off, unless they finished it.
          initialPosition: video.completed ? Duration.zero : video.progress,
          chapters: video.chapters,
        );
        _loading = false;
      });

      AppLog.info('playback session ${session.sessionId} for ${widget.videoId}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _openVideo(Video video) => context.pushReplacement('/watch/${video.id}');

  void _exit() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_video == null ? '/library' : '/course/${_video!.courseId}');
    }
  }

  Future<void> _toggleFullscreen() async {
    final entering = !_fullscreen;
    setState(() => _fullscreen = entering);
    // Where the platform supports it, fullscreen also hides the system bars and turns the phone.
    // On desktop it is the video filling the window.
    if (entering) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (mounted && isTouchPlatform(context)) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } else {
      await _restoreSystemUi();
    }
    _focusNode.requestFocus();
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const []);
  }

  KeyEventResult _onKey(
    FocusNode node,
    KeyEvent event,
    ({Video? previous, Video? next}) neighbours,
  ) {
    final c = _controller;
    if (c == null || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final repeat = event is KeyRepeatEvent;

    void handled() => _controlsKey.currentState?.reveal();

    if (!repeat && (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK)) {
      c.togglePlay();
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyJ) {
      c.seekBy(const Duration(seconds: -10));
    } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyL) {
      c.seekBy(const Duration(seconds: 10));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      c.setVolume(c.volume + 0.1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      c.setVolume(c.volume - 0.1);
    } else if (!repeat && key == LogicalKeyboardKey.keyM) {
      c.toggleMute();
    } else if (!repeat && key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (!repeat && key == LogicalKeyboardKey.escape && _fullscreen) {
      _toggleFullscreen();
    } else if (!repeat && shift && key == LogicalKeyboardKey.keyN && neighbours.next != null) {
      _openVideo(neighbours.next!);
    } else if (!repeat && shift && key == LogicalKeyboardKey.keyP && neighbours.previous != null) {
      _openVideo(neighbours.previous!);
    } else {
      return KeyEventResult.ignored;
    }
    handled();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark(),
      child: Builder(builder: _buildThemed),
    );
  }

  Widget _buildThemed(BuildContext context) {
    final colors = context.colors;
    final video = _video;
    final course = video == null ? null : ref.watch(courseProvider(video.courseId)).value;
    final neighbours = course == null || video == null
        ? (previous: null, next: null)
        : course.neighboursOf(video.id);

    final Widget body;
    if (_loading) {
      body = const _PlayerSkeleton();
    } else if (_error != null) {
      body = Column(
        children: [
          _TopBar(onBack: _exit),
          Expanded(
            child: ErrorView(error: _error!, onRetry: _start),
          ),
        ],
      );
    } else {
      body = _layout(context, video!, course, neighbours);
    }

    return Scaffold(
      backgroundColor: _fullscreen ? Colors.black : colors.background,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) => _onKey(node, event, neighbours),
        child: body,
      ),
    );
  }

  Widget _layout(
    BuildContext context,
    Video video,
    Course? course,
    ({Video? previous, Video? next}) neighbours,
  ) {
    final size = context.windowSize;
    final stage = _Stage(
      controlsKey: _controlsKey,
      controller: _controller!,
      session: _session!,
      title: video.title,
      fullscreen: _fullscreen,
      rounded: !_fullscreen && !size.isCompact,
      onToggleFullscreen: _toggleFullscreen,
      onPrevious: neighbours.previous == null ? null : () => _openVideo(neighbours.previous!),
      onNext: neighbours.next == null ? null : () => _openVideo(neighbours.next!),
    );

    if (_fullscreen) return stage;

    final info = _VideoInfo(
      video: video,
      course: course,
      session: _session!,
      controller: _controller!,
      neighbours: neighbours,
      onOpen: _openVideo,
      showSessionsTab: !size.isExpanded,
    );

    final topBar = _TopBar(onBack: _exit, courseTitle: course?.title, title: video.title);

    if (size.isExpanded) {
      return Column(
        children: [
          topBar,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // The video is as large as the window allows while leaving the title in view.
                      final maxVideoHeight = constraints.maxHeight - 150;
                      final maxWidth = (maxVideoHeight * 16 / 9).clamp(480.0, 1280.0);
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.x8,
                          AppSpace.x2,
                          AppSpace.x8,
                          AppSpace.x10,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxWidth),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                stage,
                                const SizedBox(height: AppSpace.x6),
                                info,
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (course != null)
                  Container(
                    width: 360,
                    decoration: BoxDecoration(
                      color: context.colors.sidebar,
                      border: BorderDirectional(start: BorderSide(color: context.colors.border)),
                    ),
                    child: _CoursePanel(course: course, currentId: video.id, onOpen: _openVideo),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    final compact = size.isCompact;
    return Column(
      children: [
        topBar,
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              compact ? 0 : AppSpace.x6,
              compact ? 0 : AppSpace.x2,
              compact ? 0 : AppSpace.x6,
              AppSpace.x10 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              stage,
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? AppSpace.x4 : 0,
                  AppSpace.x5,
                  compact ? AppSpace.x4 : 0,
                  0,
                ),
                child: info,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The video frame: surface, controls, and the watermark over everything.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.controlsKey,
    required this.controller,
    required this.session,
    required this.title,
    required this.fullscreen,
    required this.rounded,
    required this.onToggleFullscreen,
    this.onPrevious,
    this.onNext,
  });

  final GlobalKey<PlayerControlsState> controlsKey;
  final PlayerController controller;
  final PlaybackSession session;
  final String title;
  final bool fullscreen;
  final bool rounded;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final frame = Stack(
      fit: StackFit.expand,
      children: [
        // M3: the video surface, fed by secure-core's loopback server.
        const ColoredBox(color: Colors.black),
        PlayerControls(
          key: controlsKey,
          controller: controller,
          fullscreen: fullscreen,
          title: title,
          onToggleFullscreen: onToggleFullscreen,
          onPrevious: onPrevious,
          onNext: onNext,
        ),

        // The watermark is present from the very first build, not added later: a playback path
        // that works without it is a playback path that can ship without it. It sits above the
        // controls, so no control can cover it; it never takes a tap.
        WatermarkOverlay(watermark: session.watermark),
      ],
    );

    if (fullscreen) return frame;

    return ClipRRect(
      borderRadius: rounded ? AppRadius.lgAll : BorderRadius.zero,
      child: AspectRatio(aspectRatio: 16 / 9, child: frame),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, this.courseTitle, this.title});

  final VoidCallback onBack;
  final String? courseTitle;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final compact = context.windowSize.isCompact;

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? AppSpace.x2 : AppSpace.x4),
          child: Row(
            children: [
              AppIconButton(icon: AppIcons.back, tooltip: l10n.back, onPressed: onBack),
              const SizedBox(width: AppSpace.x2),
              if (courseTitle != null)
                Expanded(
                  child: Text(
                    courseTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, height: 1.3, color: colors.textSecondary),
                  ),
                )
              else
                const Spacer(),
              if (!compact && title != null) ...[
                const SizedBox(width: AppSpace.x3),
                Tooltip(
                  message: l10n.protectedPlaybackHint,
                  child: AppBadge(
                    label: l10n.protectedPlayback,
                    icon: AppIcons.protectedContent,
                    tone: BadgeTone.success,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Title, meta, previous/next, and the tabs under the video.
class _VideoInfo extends StatefulWidget {
  const _VideoInfo({
    required this.video,
    required this.course,
    required this.session,
    required this.controller,
    required this.neighbours,
    required this.onOpen,
    required this.showSessionsTab,
  });

  final Video video;
  final Course? course;
  final PlaybackSession session;
  final PlayerController controller;
  final ({Video? previous, Video? next}) neighbours;
  final ValueChanged<Video> onOpen;

  /// Below desktop there is no side panel, so the course content becomes a tab.
  final bool showSessionsTab;

  @override
  State<_VideoInfo> createState() => _VideoInfoState();
}

enum _InfoTab { sessions, chapters, details }

class _VideoInfoState extends State<_VideoInfo> {
  _InfoTab? _selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.colors;
    final video = widget.video;
    final compact = context.windowSize.isCompact;

    final tabs = [
      if (widget.showSessionsTab && widget.course != null) _InfoTab.sessions,
      if (video.chapters.isNotEmpty) _InfoTab.chapters,
      _InfoTab.details,
    ];
    final selected = tabs.contains(_selected) ? _selected! : tabs.first;

    final meta = [
      JalaliFormat.duration(video.duration),
      if (video.recordedAt != null) JalaliFormat.longDate(video.recordedAt!),
    ];

    final prevNext = Row(
      mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _wrap(
          compact,
          AppButton(
            label: l10n.previousSession,
            icon: AppIcons.previous,
            size: AppButtonSize.small,
            expand: compact,
            onPressed: widget.neighbours.previous == null
                ? null
                : () => widget.onOpen(widget.neighbours.previous!),
          ),
        ),
        const SizedBox(width: AppSpace.x2),
        _wrap(
          compact,
          AppButton(
            label: l10n.nextSession,
            trailingIcon: AppIcons.next,
            size: AppButtonSize.small,
            expand: compact,
            variant: widget.neighbours.next == null
                ? AppButtonVariant.secondary
                : AppButtonVariant.primary,
            onPressed: widget.neighbours.next == null
                ? null
                : () => widget.onOpen(widget.neighbours.next!),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpace.x1),
                  MetaLine(
                    items: meta,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            if (!compact && widget.course != null) ...[
              const SizedBox(width: AppSpace.x4),
              prevNext,
            ],
          ],
        ),
        if (compact && widget.course != null) ...[const SizedBox(height: AppSpace.x4), prevNext],
        const SizedBox(height: AppSpace.x5),
        AppTabs(
          selected: tabs.indexOf(selected),
          onChanged: (i) => setState(() => _selected = tabs[i]),
          tabs: [
            for (final tab in tabs)
              switch (tab) {
                _InfoTab.sessions => AppTab(
                  label: l10n.courseContent,
                  count: JalaliFormat.toPersianDigits('${widget.course!.allVideos.length}'),
                ),
                _InfoTab.chapters => AppTab(
                  label: l10n.chapters,
                  count: JalaliFormat.toPersianDigits('${video.chapters.length}'),
                ),
                _InfoTab.details => AppTab(label: l10n.details),
              },
          ],
        ),
        const SizedBox(height: AppSpace.x3),
        AnimatedSwitcher(
          duration: AppMotion.fast,
          child: KeyedSubtree(
            key: ValueKey(selected),
            child: switch (selected) {
              _InfoTab.sessions => _SessionList(
                course: widget.course!,
                currentId: video.id,
                onOpen: widget.onOpen,
              ),
              _InfoTab.chapters => _ChapterList(controller: widget.controller),
              _InfoTab.details => _Details(video: video, session: widget.session),
            },
          ),
        ),
      ],
    );
  }

  Widget _wrap(bool expand, Widget child) => expand ? Expanded(child: child) : child;
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final current = controller.currentChapter;
        return Column(
          children: [
            for (final chapter in controller.chapters)
              AppListRow(
                dense: true,
                title: chapter.title,
                selected: chapter == current,
                leading: SizedBox(
                  width: 52,
                  child: Text(
                    JalaliFormat.duration(chapter.start),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: chapter == current ? colors.accentText : colors.textTertiary,
                    ),
                  ),
                ),
                onTap: () => controller.seek(chapter.start),
              ),
          ],
        );
      },
    );
  }
}

/// What the server granted for this session: the basis of the player's status row, and useful
/// when a student asks support why capture is blocked.
class _Details extends StatelessWidget {
  const _Details({required this.video, required this.session});

  final Video video;
  final PlaybackSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = [
      (AppIcons.duration, l10n.detailDuration, JalaliFormat.duration(video.duration)),
      (AppIcons.resumeFrom, l10n.detailResumeFrom, JalaliFormat.duration(video.progress)),
      (
        AppIcons.capture,
        l10n.detailCapture,
        session.blockCapture ? l10n.captureBlocked : l10n.captureAllowed,
      ),
      (AppIcons.watermark, l10n.detailWatermark, session.watermark.text),
      // The wrapped key is deliberately not shown, not even truncated. It is passed straight to
      // secure-core over FFI and never inspected in Dart.
    ];

    final theme = Theme.of(context);
    final colors = context.colors;

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Hairline(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.x3),
            child: Row(
              children: [
                Icon(rows[i].$1, size: 15, color: colors.textTertiary),
                const SizedBox(width: AppSpace.x3),
                SizedBox(
                  width: 110,
                  child: Text(
                    rows[i].$2,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                  ),
                ),
                Expanded(child: Text(rows[i].$3, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The course's sessions beside the video on desktop.
class _CoursePanel extends StatelessWidget {
  const _CoursePanel({required this.course, required this.currentId, required this.onOpen});

  final Course course;
  final String currentId;
  final ValueChanged<Video> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.x5, AppSpace.x5, AppSpace.x5, AppSpace.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.courseContent,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpace.x3),
              Row(
                children: [
                  Expanded(child: AppProgressBar(value: course.progress, height: 3)),
                  const SizedBox(width: AppSpace.x3),
                  Text(
                    l10n.completedOf(
                      JalaliFormat.toPersianDigits('${course.completedCount}'),
                      JalaliFormat.toPersianDigits('${course.allVideos.length}'),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Hairline(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.x2),
            child: _SessionList(course: course, currentId: currentId, onOpen: onOpen),
          ),
        ),
      ],
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.course, required this.currentId, required this.onOpen});

  final Course course;
  final String currentId;
  final ValueChanged<Video> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final l10n = context.l10n;

    final groups = [
      for (final section in course.sections)
        if (section.videos.isNotEmpty) (section.title, section.videos),
      if (course.looseVideos.isNotEmpty)
        (course.sections.isEmpty ? null : l10n.otherSessions, course.looseVideos),
    ];

    // Numbered across the whole course, as on the course page.
    final numbers = {for (final (i, v) in course.allVideos.indexed) v.id: i + 1};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (title, videos) in groups) ...[
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.x3,
                AppSpace.x4,
                AppSpace.x3,
                AppSpace.x1,
              ),
              child: Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(color: colors.textTertiary),
              ),
            ),
          for (final video in videos) _row(context, video, numbers[video.id] ?? 0),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, Video video, int number) {
    final colors = context.colors;
    final l10n = context.l10n;
    final current = video.id == currentId;
    final playable = video.isReady && !video.isLocked;

    return AppListRow(
      dense: true,
      titleMaxLines: 2,
      title: video.title,
      selected: current,
      enabled: playable || current,
      semanticLabel: current ? '${l10n.nowPlaying}: ${video.title}' : video.title,
      leading: SizedBox(
        width: 22,
        child: Center(
          child: current
              ? Icon(AppIcons.nowPlaying, size: 15, color: colors.accentText)
              : video.completed
              ? Icon(AppIcons.completed, size: 15, color: colors.accentText)
              : video.isLocked
              ? Icon(AppIcons.locked, size: 13, color: colors.textTertiary)
              : Text(
                  JalaliFormat.toPersianDigits('$number'),
                  style: TextStyle(fontSize: 12, height: 1, color: colors.textTertiary),
                ),
        ),
      ),
      trailing: Text(
        video.isProcessing ? l10n.processing : JalaliFormat.duration(video.duration),
        style: TextStyle(fontSize: 12, height: 1.2, color: colors.textTertiary),
      ),
      onTap: current || !playable ? null : () => onOpen(video),
    );
  }
}

class _PlayerSkeleton extends StatelessWidget {
  const _PlayerSkeleton();

  @override
  Widget build(BuildContext context) {
    final size = context.windowSize;
    final pad = size.isCompact ? 0.0 : AppSpace.x8;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SafeArea(bottom: false, child: SizedBox(height: 52)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ClipRRect(
                borderRadius: size.isCompact ? BorderRadius.zero : AppRadius.lgAll,
                child: const AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(child: AppSpinner(size: 22, color: Colors.white54)),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            size.isCompact ? AppSpace.x4 : pad,
            AppSpace.x6,
            size.isCompact ? AppSpace.x4 : pad,
            0,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(width: 280, height: 18),
              SizedBox(height: AppSpace.x3),
              Skeleton(width: 140, height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

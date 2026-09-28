import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/jalali.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/l10n.dart';
import '../../ui/ui.dart';
import 'player_controller.dart';

/// The controls layered over the video.
///
/// Hierarchy is deliberate: the timeline and play/pause are what a student reaches for, so they
/// are the largest and first; volume and time sit beside them; speed, quality and subtitles fold
/// into one settings menu, so the bar never becomes a toolbar. Controls fade out while playing and
/// come back on any movement.
///
/// Transport is laid out left-to-right even in the Persian interface — timelines and media controls
/// read LTR in every locale, and mirroring them is a well-known source of confusion. Text inside
/// (menu labels, chapter titles) keeps the app's own direction.
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    required this.controller,
    required this.fullscreen,
    required this.onToggleFullscreen,
    this.title,
    this.onPrevious,
    this.onNext,
    super.key,
  });

  final PlayerController controller;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;

  /// Shown across the top in fullscreen, where the page title is hidden.
  final String? title;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<PlayerControls> createState() => PlayerControlsState();
}

class PlayerControlsState extends State<PlayerControls> {
  static const _hideAfter = Duration(milliseconds: 2600);

  bool _visible = true;
  bool _menuOpen = false;
  bool _pointerOnBar = false;
  bool _scrubbing = false;
  Timer? _hideTimer;

  PlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onController);
  }

  @override
  void didUpdateWidget(PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _c.removeListener(_onController);
    super.dispose();
  }

  bool _wasPlaying = false;

  void _onController() {
    if (_c.playing != _wasPlaying) {
      _wasPlaying = _c.playing;
      reveal();
    }
    if (mounted) setState(() {});
  }

  /// Shows the controls and restarts the hide countdown. Called on pointer movement, taps and
  /// keyboard shortcuts.
  void reveal() {
    if (!mounted) return;
    if (!_visible) setState(() => _visible = true);
    _hideTimer?.cancel();
    if (_c.playing && !_menuOpen && !_pointerOnBar && !_scrubbing) {
      _hideTimer = Timer(_hideAfter, () {
        if (mounted && _c.playing && !_menuOpen && !_pointerOnBar && !_scrubbing) {
          setState(() => _visible = false);
        }
      });
    }
  }

  void _hide() {
    if (_c.playing && !_menuOpen && !_scrubbing) setState(() => _visible = false);
  }

  void _setMenuOpen(bool open) {
    setState(() => _menuOpen = open);
    reveal();
  }

  Future<void> _openSettings(BuildContext context, {bool asSheet = false, _MenuPage page = _MenuPage.root}) async {
    if (!asSheet) {
      _setMenuOpen(!_menuOpen);
      return;
    }
    _setMenuOpen(true);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => Theme(
        data: AppTheme.dark(),
        child: SafeArea(
          child: _PlayerSettingsMenu(controller: _c, initialPage: page, asSheet: true),
        ),
      ),
    );
    if (mounted) _setMenuOpen(false);
  }

  @override
  Widget build(BuildContext context) {
    final appDirection = Directionality.of(context);
    final touch = isTouchPlatform(context);
    final l10n = context.l10n;

    return LayoutBuilder(
      builder: (context, constraints) {
        final small = constraints.maxWidth < 560;
        final showSheet = small || touch;

        return Directionality(
          textDirection: TextDirection.ltr,
          child: MouseRegion(
            onHover: (_) => reveal(),
            onExit: (_) => _hide(),
            cursor: _visible ? MouseCursor.defer : SystemMouseCursors.none,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _SurfaceGestures(
                  touch: touch,
                  onTap: () {
                    if (touch) {
                      _visible ? setState(() => _visible = false) : reveal();
                    } else {
                      if (_menuOpen) return _setMenuOpen(false);
                      _c.togglePlay();
                    }
                  },
                  onDoubleTap: touch ? null : widget.onToggleFullscreen,
                  onDoubleTapSide: touch
                      ? (forward) {
                          _c.seekBy(Duration(seconds: forward ? 10 : -10));
                          reveal();
                        }
                      : null,
                ),

                // Scrims: only as dark as needed to keep the controls legible over a white slide.
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _visible ? 1 : 0,
                    duration: AppMotion.base,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: widget.fullscreen ? 0.55 : 0),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.72),
                          ],
                          stops: const [0, 0.22, 0.55, 1],
                        ),
                      ),
                    ),
                  ),
                ),

                if (!_c.attached)
                  IgnorePointer(
                    child: Directionality(
                      textDirection: appDirection,
                      child: _NotAttachedNotice(
                        message: l10n.playerUnavailable,
                        compact: small,
                        // Clear of the centre transport on touch.
                        alignment: touch ? const Alignment(0, -0.82) : const Alignment(0, -0.35),
                      ),
                    ),
                  ),

                // Centre: on touch, the transport lives here within thumb reach; on desktop, a
                // single play button marks the paused state.
                if (touch)
                  _Fade(
                    visible: _visible,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PlayerButton(
                            icon: AppIcons.seekBack,
                            tooltip: l10n.seekBack,
                            size: 48,
                            iconSize: 22,
                            onPressed: () {
                              _c.seekBy(const Duration(seconds: -10));
                              reveal();
                            },
                          ),
                          const SizedBox(width: AppSpace.x6),
                          _PlayPauseButton(controller: _c, large: true, onPressed: reveal),
                          const SizedBox(width: AppSpace.x6),
                          _PlayerButton(
                            icon: AppIcons.seekForward,
                            tooltip: l10n.seekForward,
                            size: 48,
                            iconSize: 22,
                            onPressed: () {
                              _c.seekBy(const Duration(seconds: 10));
                              reveal();
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                else if (!_c.playing)
                  Center(child: _PlayPauseButton(controller: _c, large: true, onPressed: reveal)),

                if (widget.fullscreen && widget.title != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _Fade(
                      visible: _visible,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(AppSpace.x5, AppSpace.x4, AppSpace.x5, 0),
                          child: Text(
                            widget.title!,
                            textDirection: appDirection,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _Fade(
                    visible: _visible,
                    slide: true,
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _pointerOnBar = true),
                      onExit: (_) {
                        _pointerOnBar = false;
                        reveal();
                      },
                      child: SafeArea(
                        top: false,
                        left: widget.fullscreen,
                        right: widget.fullscreen,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            small ? AppSpace.x2 : AppSpace.x3,
                            0,
                            small ? AppSpace.x2 : AppSpace.x3,
                            small ? AppSpace.x1 : AppSpace.x2,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpace.x1),
                                child: PlayerTimeline(
                                  controller: _c,
                                  textDirection: appDirection,
                                  onScrubbing: (value) {
                                    _scrubbing = value;
                                    reveal();
                                  },
                                ),
                              ),
                              _ControlBar(
                                controller: _c,
                                small: small,
                                touch: touch,
                                fullscreen: widget.fullscreen,
                                appDirection: appDirection,
                                menuOpen: _menuOpen,
                                onPrevious: widget.onPrevious,
                                onNext: widget.onNext,
                                onToggleFullscreen: widget.onToggleFullscreen,
                                onSettings: (page) => _openSettings(context, asSheet: showSheet, page: page),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                if (_menuOpen && !showSheet)
                  Positioned(
                    right: AppSpace.x3,
                    bottom: 76,
                    child: Directionality(
                      textDirection: appDirection,
                      child: TapRegion(
                        onTapOutside: (_) => _setMenuOpen(false),
                        child: _PlayerSettingsMenu(controller: _c),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SurfaceGestures extends StatefulWidget {
  const _SurfaceGestures({
    required this.touch,
    required this.onTap,
    this.onDoubleTap,
    this.onDoubleTapSide,
  });

  final bool touch;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final void Function(bool forward)? onDoubleTapSide;

  @override
  State<_SurfaceGestures> createState() => _SurfaceGesturesState();
}

class _SurfaceGesturesState extends State<_SurfaceGestures> {
  Offset? _doubleTapAt;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
        onDoubleTap: () {
          if (widget.onDoubleTapSide != null && _doubleTapAt != null) {
            widget.onDoubleTapSide!(_doubleTapAt!.dx > constraints.maxWidth / 2);
          } else {
            widget.onDoubleTap?.call();
          }
        },
      ),
    );
  }
}

/// Fades (and optionally lifts) controls in and out, and stops them taking taps while hidden.
class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child, this.slide = false});

  final bool visible;
  final bool slide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget result = AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: AppMotion.base,
      curve: AppMotion.curve,
      child: child,
    );
    if (slide) {
      result = AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.08),
        duration: AppMotion.base,
        curve: AppMotion.curve,
        child: result,
      );
    }
    return IgnorePointer(ignoring: !visible, child: result);
  }
}

class _NotAttachedNotice extends StatelessWidget {
  const _NotAttachedNotice({required this.message, required this.compact, required this.alignment});

  final String message;
  final bool compact;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpace.x6),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3, vertical: AppSpace.x1 + 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.locked, size: 13, color: Colors.white.withValues(alpha: 0.55)),
            const SizedBox(width: AppSpace.x2),
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 12.5,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.controller,
    required this.small,
    required this.touch,
    required this.fullscreen,
    required this.appDirection,
    required this.menuOpen,
    required this.onToggleFullscreen,
    required this.onSettings,
    this.onPrevious,
    this.onNext,
  });

  final PlayerController controller;
  final bool small;
  final bool touch;
  final bool fullscreen;
  final TextDirection appDirection;
  final bool menuOpen;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onToggleFullscreen;
  final void Function(_MenuPage page) onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = controller;
    final chapter = c.currentChapter;

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          if (!touch) ...[
            if (!small)
              _PlayerButton(
                icon: AppIcons.previous,
                tooltip: l10n.previousSession,
                onPressed: onPrevious,
                iconSize: 17,
              ),
            _PlayPauseButton(controller: c),
            if (!small)
              _PlayerButton(
                icon: AppIcons.next,
                tooltip: l10n.nextSession,
                onPressed: onNext,
                iconSize: 17,
              ),
            _VolumeControl(controller: c),
          ] else if (fullscreen) ...[
            // Under the video on touch; in the bar only when fullscreen hides that.
            _PlayerButton(icon: AppIcons.previous, tooltip: l10n.previousSession, onPressed: onPrevious),
            _PlayerButton(icon: AppIcons.next, tooltip: l10n.nextSession, onPressed: onNext),
          ],
          const SizedBox(width: AppSpace.x2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: JalaliFormat.duration(c.position)),
                TextSpan(
                  text: '  /  ${JalaliFormat.duration(c.duration)}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                ),
              ],
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              height: 1.2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          // The chapter title takes the free space, so the trailing buttons always sit at the edge.
          Expanded(
            child: chapter == null || small
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      const SizedBox(width: AppSpace.x3),
                      Container(width: 1, height: 12, color: Colors.white.withValues(alpha: 0.2)),
                      const SizedBox(width: AppSpace.x3),
                      Flexible(
                        child: Text(
                          chapter.title,
                          textDirection: appDirection,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12.5,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          if (c.speed != 1 && !small)
            _PlayerChip(label: JalaliFormat.speed(c.speed), onPressed: () => onSettings(_MenuPage.speed)),
          if (c.subtitleTracks.isNotEmpty)
            _PlayerButton(
              icon: AppIcons.subtitles,
              tooltip: l10n.subtitles,
              selected: c.subtitle != null,
              onPressed: () => onSettings(_MenuPage.subtitles),
            ),
          _PlayerButton(
            icon: AppIcons.playerSettings,
            tooltip: l10n.playerSettings,
            selected: menuOpen,
            onPressed: () => onSettings(_MenuPage.root),
          ),
          _PlayerButton(
            icon: fullscreen ? AppIcons.exitFullscreen : AppIcons.fullscreen,
            tooltip: fullscreen ? l10n.exitFullscreen : l10n.fullscreen,
            onPressed: onToggleFullscreen,
          ),
        ],
      ),
    );
  }
}

/// An icon button styled for the dark video frame.
class _PlayerButton extends StatelessWidget {
  const _PlayerButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 36,
    this.iconSize = 18,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Pressable(
      onTap: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      borderRadius: BorderRadius.circular(size >= 44 ? AppRadius.full : AppRadius.md),
      color: selected ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
      hoverColor: Colors.white.withValues(alpha: 0.12),
      pressedColor: Colors.white.withValues(alpha: 0.2),
      builder: (context, state) => SizedBox.square(
        dimension: size,
        child: Icon(
          icon,
          size: iconSize,
          color: !enabled
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: state.hovered || selected ? 1 : 0.88),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.controller, this.large = false, this.onPressed});

  final PlayerController controller;
  final bool large;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final playing = controller.playing;
    final icon = AnimatedSwitcher(
      duration: AppMotion.fast,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween(begin: 0.8, end: 1.0).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Icon(
        playing ? AppIcons.pause : AppIcons.play,
        key: ValueKey(playing),
        size: large ? 26 : 19,
        color: Colors.white,
      ),
    );

    if (!large) {
      return Pressable(
        onTap: () {
          controller.togglePlay();
          onPressed?.call();
        },
        tooltip: playing ? l10n.pause : l10n.play,
        semanticLabel: playing ? l10n.pause : l10n.play,
        hoverColor: Colors.white.withValues(alpha: 0.12),
        pressedColor: Colors.white.withValues(alpha: 0.2),
        child: SizedBox.square(dimension: 36, child: icon),
      );
    }

    return Pressable(
      onTap: () {
        controller.togglePlay();
        onPressed?.call();
      },
      semanticLabel: playing ? l10n.pause : l10n.play,
      borderRadius: BorderRadius.circular(AppRadius.full),
      color: Colors.black.withValues(alpha: 0.45),
      hoverColor: Colors.black.withValues(alpha: 0.6),
      pressedColor: Colors.black.withValues(alpha: 0.7),
      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      child: SizedBox.square(
        dimension: 64,
        // The play triangle is optically centred, not geometrically.
        child: Padding(
          padding: EdgeInsets.only(left: playing ? 0 : 3),
          child: icon,
        ),
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.x1),
      child: Pressable(
        onTap: onPressed,
        semanticLabel: label,
        color: Colors.white.withValues(alpha: 0.1),
        hoverColor: Colors.white.withValues(alpha: 0.18),
        borderRadius: AppRadius.smAll,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500, height: 1.3),
        ),
      ),
    );
  }
}

class _VolumeControl extends StatefulWidget {
  const _VolumeControl({required this.controller});

  final PlayerController controller;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final l10n = context.l10n;
    final icon = c.muted
        ? AppIcons.muted
        : c.volume < 0.5
            ? AppIcons.volumeLow
            : AppIcons.volume;

    return MouseRegion(
      onEnter: (_) => setState(() => _open = true),
      onExit: (_) => setState(() => _open = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlayerButton(icon: icon, tooltip: c.muted ? l10n.unmute : l10n.mute, onPressed: c.toggleMute),
          AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.curve,
            width: _open ? 76 : 0,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 76,
                maxWidth: 76,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppSpace.x1, right: AppSpace.x2),
                  child: _ThinSlider(value: c.muted ? 0 : c.volume, onChanged: c.setVolume),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A minimal horizontal slider, for volume.
class _ThinSlider extends StatelessWidget {
  const _ThinSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void update(Offset local) => onChanged((local.dx / constraints.maxWidth).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => update(d.localPosition),
          onHorizontalDragUpdate: (d) => update(d.localPosition),
          child: SizedBox(
            height: 24,
            child: CustomPaint(
              painter: _SliderPainter(value: value),
            ),
          ),
        );
      },
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final track = RRect.fromLTRBR(0, y - 1.5, size.width, y + 1.5, const Radius.circular(2));
    canvas.drawRRect(track, Paint()..color = Colors.white.withValues(alpha: 0.25));
    final x = size.width * value;
    canvas.drawRRect(
      RRect.fromLTRBR(0, y - 1.5, x, y + 1.5, const Radius.circular(2)),
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(Offset(x.clamp(5, size.width - 5), y), 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.value != value;
}

/// The seek bar: played, buffered, chapter segments, and a time preview under the pointer.
class PlayerTimeline extends StatefulWidget {
  const PlayerTimeline({
    required this.controller,
    required this.textDirection,
    this.onScrubbing,
    super.key,
  });

  final PlayerController controller;

  /// Direction for the chapter title in the preview.
  final TextDirection textDirection;
  final ValueChanged<bool>? onScrubbing;

  @override
  State<PlayerTimeline> createState() => _PlayerTimelineState();
}

class _PlayerTimelineState extends State<PlayerTimeline> {
  double? _hoverFraction;
  double? _dragFraction;

  PlayerController get _c => widget.controller;

  double _fractionAt(Offset local, double width) => (local.dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.dark.accent;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final durationMs = _c.duration.inMilliseconds;
        final chapterMarks = [
          if (durationMs > 0)
            for (final chapter in _c.chapters)
              if (chapter.start > Duration.zero) chapter.start.inMilliseconds / durationMs,
        ];

        final previewFraction = _dragFraction ?? _hoverFraction;
        final active = previewFraction != null;
        final previewAt = previewFraction == null
            ? null
            : Duration(milliseconds: (durationMs * previewFraction).round());
        final previewChapter = previewAt == null ? null : _c.chapterAt(previewAt);

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (e) => setState(() => _hoverFraction = _fractionAt(e.localPosition, width)),
          onExit: (_) => setState(() => _hoverFraction = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _c.seekToFraction(_fractionAt(d.localPosition, width)),
            onHorizontalDragStart: (d) {
              widget.onScrubbing?.call(true);
              setState(() => _dragFraction = _fractionAt(d.localPosition, width));
            },
            onHorizontalDragUpdate: (d) =>
                setState(() => _dragFraction = _fractionAt(d.localPosition, width)),
            onHorizontalDragEnd: (_) {
              if (_dragFraction != null) _c.seekToFraction(_dragFraction!);
              setState(() => _dragFraction = null);
              widget.onScrubbing?.call(false);
            },
            onHorizontalDragCancel: () {
              setState(() => _dragFraction = null);
              widget.onScrubbing?.call(false);
            },
            child: Semantics(
              slider: true,
              value: JalaliFormat.duration(_c.position),
              child: SizedBox(
                height: 22,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: active ? 1 : 0),
                        duration: AppMotion.fast,
                        builder: (context, t, _) => CustomPaint(
                          painter: _TimelinePainter(
                            progress: _dragFraction ?? _c.progress,
                            buffered: durationMs == 0 ? 0 : _c.buffered.inMilliseconds / durationMs,
                            hover: _hoverFraction,
                            chapterMarks: chapterMarks,
                            emphasis: t,
                            accent: accent,
                          ),
                        ),
                      ),
                    ),
                    if (previewFraction != null)
                      Positioned(
                        bottom: 24,
                        left: (previewFraction * width - 80).clamp(0.0, (width - 160).clamp(0.0, double.infinity)),
                        width: 160,
                        child: IgnorePointer(
                          child: Center(
                            child: _TimePreview(
                              time: previewAt!,
                              chapter: previewChapter?.title,
                              textDirection: widget.textDirection,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimePreview extends StatelessWidget {
  const _TimePreview({required this.time, required this.textDirection, this.chapter});

  final Duration time;
  final String? chapter;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2, vertical: AppSpace.x1),
      decoration: BoxDecoration(
        color: const Color(0xE6161618),
        borderRadius: AppRadius.smAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chapter != null)
            Text(
              chapter!,
              textDirection: textDirection,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5, height: 1.4),
            ),
          Text(
            JalaliFormat.duration(time),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.progress,
    required this.buffered,
    required this.hover,
    required this.chapterMarks,
    required this.emphasis,
    required this.accent,
  });

  final double progress;
  final double buffered;
  final double? hover;
  final List<double> chapterMarks;

  /// 0 at rest, 1 while hovered or scrubbing: the track thickens and the thumb appears.
  final double emphasis;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final thickness = 3 + 2 * emphasis;
    final w = size.width;

    // Chapter boundaries become 2px gaps, so the bar reads as segments.
    final bounds = [0.0, ...chapterMarks.where((m) => m > 0 && m < 1), 1.0];

    void segmented(double from, double to, Color color) {
      if (to <= from) return;
      final paint = Paint()..color = color;
      for (var i = 0; i < bounds.length - 1; i++) {
        final start = bounds[i] * w + (i == 0 ? 0 : 1);
        final end = bounds[i + 1] * w - (i == bounds.length - 2 ? 0 : 1);
        final a = start.clamp(from * w, to * w);
        final b = end.clamp(from * w, to * w);
        if (b <= a) continue;
        canvas.drawRRect(
          RRect.fromLTRBR(a, y - thickness / 2, b, y + thickness / 2, Radius.circular(thickness / 2)),
          paint,
        );
      }
    }

    segmented(0, 1, Colors.white.withValues(alpha: 0.22));
    segmented(0, buffered, Colors.white.withValues(alpha: 0.36));
    if (hover != null && hover! > progress) {
      segmented(progress, hover!, Colors.white.withValues(alpha: 0.3));
    }
    segmented(0, progress, accent);

    if (emphasis > 0) {
      canvas.drawCircle(
        Offset((progress * w).clamp(0, w), y),
        6 * emphasis,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.hover != hover ||
      old.emphasis != emphasis ||
      old.chapterMarks.length != chapterMarks.length;
}

enum _MenuPage { root, speed, quality, subtitles }

/// Speed, quality and subtitles, behind one button.
///
/// A popover on desktop, a bottom sheet on touch. Two levels: a summary of the current settings,
/// then the options for one of them.
class _PlayerSettingsMenu extends StatefulWidget {
  const _PlayerSettingsMenu({
    required this.controller,
    this.initialPage = _MenuPage.root,
    this.asSheet = false,
  });

  final PlayerController controller;
  final _MenuPage initialPage;
  final bool asSheet;

  @override
  State<_PlayerSettingsMenu> createState() => _PlayerSettingsMenuState();
}

class _PlayerSettingsMenuState extends State<_PlayerSettingsMenu> {
  late _MenuPage _page = widget.initialPage;

  PlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _speedLabel(AppLocalizations l10n, double speed) =>
      speed == 1 ? l10n.normalSpeed : JalaliFormat.speed(speed);

  String _qualityLabel(AppLocalizations l10n, String quality) =>
      quality == PlayerController.qualityAuto ? l10n.qualityAuto : JalaliFormat.toPersianDigits(quality);

  String _subtitleLabel(AppLocalizations l10n) {
    final id = _c.subtitle;
    if (id == null) return l10n.subtitlesOff;
    return _c.subtitleTracks.where((t) => t.id == id).firstOrNull?.label ?? l10n.subtitlesOff;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const colors = AppColors.dark;

    final content = switch (_page) {
      _MenuPage.root => [
          _MenuRow(
            icon: AppIcons.speed,
            label: l10n.speed,
            value: _speedLabel(l10n, _c.speed),
            onTap: () => setState(() => _page = _MenuPage.speed),
          ),
          _MenuRow(
            icon: AppIcons.quality,
            label: l10n.quality,
            value: _qualityLabel(l10n, _c.quality),
            onTap: () => setState(() => _page = _MenuPage.quality),
          ),
          _MenuRow(
            icon: AppIcons.subtitles,
            label: l10n.subtitles,
            value: _subtitleLabel(l10n),
            onTap: () => setState(() => _page = _MenuPage.subtitles),
          ),
        ],
      _MenuPage.speed => [
          _MenuHeader(label: l10n.speed, onBack: () => setState(() => _page = _MenuPage.root)),
          for (final speed in PlayerController.speeds)
            _OptionRow(
              label: _speedLabel(l10n, speed),
              selected: _c.speed == speed,
              onTap: () => _c.setSpeed(speed),
            ),
        ],
      _MenuPage.quality => [
          _MenuHeader(label: l10n.quality, onBack: () => setState(() => _page = _MenuPage.root)),
          for (final quality in _c.qualities)
            _OptionRow(
              label: _qualityLabel(l10n, quality),
              selected: _c.quality == quality,
              onTap: () => _c.setQuality(quality),
            ),
        ],
      _MenuPage.subtitles => [
          _MenuHeader(label: l10n.subtitles, onBack: () => setState(() => _page = _MenuPage.root)),
          _OptionRow(
            label: l10n.subtitlesOff,
            selected: _c.subtitle == null,
            onTap: () => _c.setSubtitle(null),
          ),
          for (final track in _c.subtitleTracks)
            _OptionRow(
              label: track.label,
              selected: _c.subtitle == track.id,
              onTap: () => _c.setSubtitle(track.id),
            ),
        ],
    };

    final column = Padding(
      padding: EdgeInsets.all(widget.asSheet ? AppSpace.x2 : AppSpace.x1 + 2),
      child: Column(mainAxisSize: MainAxisSize.min, children: content),
    );

    if (widget.asSheet) return column;

    return Container(
      width: 252,
      decoration: BoxDecoration(
        color: const Color(0xF2141416),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: AnimatedSize(
        duration: AppMotion.base,
        curve: AppMotion.curve,
        alignment: Alignment.bottomCenter,
        child: column,
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, required this.value, required this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      hoverColor: Colors.white.withValues(alpha: 0.07),
      pressedColor: Colors.white.withValues(alpha: 0.1),
      borderRadius: AppRadius.mdAll,
      child: SizedBox(
        height: isTouchPlatform(context) ? 48 : 38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2 + 2),
          child: Row(
            children: [
              Icon(icon, size: 16, color: colors.textSecondary),
              const SizedBox(width: AppSpace.x2 + 2),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 13.5, height: 1.2, color: colors.text)),
              ),
              Text(value, style: TextStyle(fontSize: 13, height: 1.2, color: colors.textSecondary)),
              const SizedBox(width: AppSpace.x1),
              Icon(AppIcons.forward, size: 14, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.label, required this.onBack});

  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.x1),
      child: Column(
        children: [
          Pressable(
            onTap: onBack,
            semanticLabel: context.l10n.back,
            hoverColor: Colors.white.withValues(alpha: 0.07),
            borderRadius: AppRadius.mdAll,
            child: SizedBox(
              height: isTouchPlatform(context) ? 44 : 36,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2),
                child: Row(
                  children: [
                    Icon(AppIcons.back, size: 15, color: colors.textSecondary),
                    const SizedBox(width: AppSpace.x2),
                    Text(
                      label,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.2, color: colors.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const colors = AppColors.dark;
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        hoverColor: Colors.white.withValues(alpha: 0.07),
        pressedColor: Colors.white.withValues(alpha: 0.1),
        borderRadius: AppRadius.mdAll,
        child: SizedBox(
          height: isTouchPlatform(context) ? 44 : 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.x2 + 2),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: selected ? Icon(AppIcons.completed, size: 15, color: colors.accentText) : null,
                ),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      color: selected ? colors.text : colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

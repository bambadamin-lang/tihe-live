import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/models.dart';
import '../../core/providers.dart';
import '../../core/security/app_log.dart';
import '../../core/theme/jalali.dart';
import '../../l10n/l10n.dart';
import '../shared/error_view.dart';
import 'watermark_overlay.dart';

/// Protected playback.
///
/// At M0 this screen does everything around the video except decode it: it mints a playback session,
/// renders the identity watermark, and shows what the server returned. The video surface itself
/// arrives in M3 together with the `secure-core` FFI bridge, because the two are inseparable — the
/// player is only ever handed a `127.0.0.1` URL from the loopback server, never a remote manifest
/// and never a key (docs/adr/0008).
///
/// Written this way deliberately rather than wiring a plain player against the manifest URL: a
/// temporary unprotected playback path is exactly the kind of shortcut that survives into a release.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({required this.videoId, super.key});

  final String videoId;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  PlaybackSession? _session;
  Video? _video;
  Object? _error;
  bool _loading = true;

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
      ref.read(playbackRepositoryProvider).end(session.sessionId).ignore();
    }
    super.dispose();
  }

  Future<void> _start() async {
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

      final session = await ref.read(playbackRepositoryProvider).start(
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_video?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(error: _error!, onRetry: _start)
              : _player(l10n),
    );
  }

  Widget _player(AppLocalizations l10n) {
    final session = _session!;
    final video = _video!;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // M3: the video surface, fed by secure-core's loopback server.
              const ColoredBox(color: Color(0xFF07090B)),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline, size: 40, color: Colors.white24),
                    const SizedBox(height: 12),
                    Text(
                      'پخش محافظت‌شده در مرحله بعد فعال می‌شود',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white38,
                          ),
                    ),
                  ],
                ),
              ),

              // The watermark is present from the very first build, not added later: a playback path
              // that works without it is a playback path that can ship without it.
              WatermarkOverlay(watermark: session.watermark),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SessionSummary(session: session, video: video),
              if (video.chapters.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(l10n.chapters, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final chapter in video.chapters)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bookmark_border, size: 18),
                    title: Text(chapter.title),
                    trailing: Text(JalaliFormat.duration(chapter.start)),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// What the server granted for this session — useful during development, and the basis of the
/// player's status row later.
class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.session, required this.video});

  final PlaybackSession session;
  final Video video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(video.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _row(theme, 'مدت', JalaliFormat.duration(video.duration)),
            _row(theme, 'ادامه از', JalaliFormat.duration(video.progress)),
            _row(
              theme,
              'ضبط صفحه',
              session.blockCapture ? 'مسدود' : 'مجاز',
            ),
            _row(theme, 'واترمارک', session.watermark.text),
            // The wrapped key is deliberately not shown, not even truncated. It is passed straight to
            // secure-core over FFI and never inspected in Dart.
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
          ],
        ),
      );
}

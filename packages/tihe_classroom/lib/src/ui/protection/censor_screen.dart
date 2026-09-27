import 'package:capture_guard/capture_guard.dart';
import 'package:flutter/material.dart';

import '../theme/classroom_theme.dart';
import '../theme/glass.dart';

/// Replaces the whole class while the screen is being recorded (ADR-0011). Opaque — nothing of
/// the class shows through — and it explains what to do to get back in.
class CensorScreen extends StatelessWidget {
  const CensorScreen({super.key, required this.verdict});

  final CaptureVerdict verdict;

  String get _why {
    if (verdict.signals.contains(CaptureSignal.recorderProcess)) {
      return 'برنامهٔ ضبط صفحه${verdict.detail == null ? '' : ' (${verdict.detail})'} در حال اجراست. آن را ببندید.';
    }
    if (verdict.signals.contains(CaptureSignal.externalDisplay)) {
      return 'صفحهٔ شما روی نمایشگر دیگری نشان داده می‌شود. انعکاس تصویر را قطع کنید.';
    }
    if (verdict.signals.contains(CaptureSignal.remoteSession)) {
      return 'کلاس از راه دور (Remote Desktop) باز شده است. مستقیم روی دستگاه خود وارد شوید.';
    }
    return 'ضبط صفحه در حال انجام است. آن را متوقف کنید.';
  }

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    // The backdrop paints the whole canvas, so this stays opaque: the glass card blurs only the
    // canvas's own glows, never the class.
    return Semantics(
      liveRegion: true,
      label: 'ضبط صفحه در کلاس مجاز نیست',
      child: GlassBackdrop(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Glass(
                radius: 24,
                padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: t.dangerSubtle,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: t.danger.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(
                        ClassroomIcons.captureBlocked,
                        size: 28,
                        color: t.danger,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'ضبط صفحه در کلاس مجاز نیست',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.text,
                        fontSize: 22,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _why,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 15,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: t.glassHover,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'کلاس به‌محض توقف ضبط برمی‌گردد. میزبان از این مورد باخبر شده است.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: t.textTertiary,
                          fontSize: 12.5,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

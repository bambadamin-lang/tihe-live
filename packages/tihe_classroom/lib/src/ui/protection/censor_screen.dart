import 'package:capture_guard/capture_guard.dart';
import 'package:flutter/material.dart';

import '../theme/classroom_theme.dart';
import '../theme/materials.dart';

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
    return Semantics(
      liveRegion: true,
      label: 'ضبط صفحه در کلاس مجاز نیست',
      child: ColoredBox(
        color: const Color(0xFF14100C),
        child: CustomPaint(
          painter: WoodGrainPainter(t, seed: 23),
          child: Container(
            color: Colors.black.withValues(alpha: 0.72),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: t.brassPlate,
                      border: Border.all(color: t.brassDark, width: 2),
                      boxShadow: t.raised,
                    ),
                    child: const Icon(
                      Icons.videocam_off,
                      size: 46,
                      color: Color(0xFF3A2A10),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'ضبط صفحه در کلاس مجاز نیست',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _why,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: t.paperLow,
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'کلاس به‌محض توقف ضبط برمی‌گردد. میزبان از این مورد باخبر شده است.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.paperEdge, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

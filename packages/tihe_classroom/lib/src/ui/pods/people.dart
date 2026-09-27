import 'package:flutter/material.dart';

import '../../contracts.dart';
import '../theme/classroom_theme.dart';
import '../theme/skeuo.dart';

/// Small pieces shared by the people-showing pods.

/// A person with no video: their initial on an enamel disc, coloured from their id.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.userId,
    required this.name,
    this.size = 64,
  });

  final String userId;
  final String name;
  final double size;

  static const _hues = [18.0, 34.0, 152.0, 188.0, 212.0, 262.0, 330.0];

  @override
  Widget build(BuildContext context) {
    final hue = _hues[userId.hashCode.abs() % _hues.length];
    final base = HSLColor.fromAHSL(1, hue, 0.35, 0.42).toColor();
    final initial = name.trim().isEmpty ? '؟' : name.trim().characters.first;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [
            Color.lerp(base, Colors.white, 0.35)!,
            base,
            Color.lerp(base, Colors.black, 0.4)!,
          ],
        ),
        border: Border.all(color: ClassroomTheme.of(context).brass, width: 2),
        boxShadow: ClassroomTheme.of(context).lifted,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The name strip at the bottom of a video tile, with a mic lamp.
class NameStrip extends StatelessWidget {
  const NameStrip({
    super.key,
    required this.name,
    required this.micOn,
    this.speaking = false,
    this.hand = false,
  });

  final String name;
  final bool micOn;
  final bool speaking;
  final bool hand;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Led(color: speaking ? t.ledGreen : t.ledRed, on: micOn, size: 7),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (hand) ...[
            const SizedBox(width: 6),
            Icon(Icons.back_hand, size: 13, color: t.ledAmber),
          ],
        ],
      ),
    );
  }
}

/// The role pin shown next to a name.
class RolePin extends StatelessWidget {
  const RolePin({super.key, required this.role});

  final ClassRole role;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return switch (role) {
      ClassRole.host => EnamelPin(label: role.labelFa, color: t.pinPlum),
      ClassRole.cohost => EnamelPin(label: role.labelFa, color: t.pinNavy),
      ClassRole.presenter => EnamelPin(label: role.labelFa, color: t.pinTeal),
      _ => const SizedBox.shrink(),
    };
  }
}

/// A frame with a speaking glow, used around every video tile.
class SpeakingFrame extends StatelessWidget {
  const SpeakingFrame({super.key, required this.speaking, required this.child});

  final bool speaking;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: speaking
            ? ClassroomTheme.of(context).ledGreen
            : Colors.transparent,
        width: 2.5,
      ),
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(6), child: child),
  );
}

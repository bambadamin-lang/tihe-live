import 'package:flutter/material.dart';

import '../../contracts.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';

/// Small pieces shared by the people-showing pods.

/// A person with no video: their initial on a soft disc, its hue taken from their id so the same
/// person always looks the same.
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
    final top = HSLColor.fromAHSL(1, hue, 0.55, 0.62).toColor();
    final bottom = HSLColor.fromAHSL(1, (hue + 24) % 360, 0.5, 0.46).toColor();
    final initial = name.trim().isEmpty ? '؟' : name.trim().characters.first;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: size >= 48 ? 1.5 : 1,
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}

/// The name strip at the bottom of a video tile. A muted microphone shows as a red crossed-out
/// mic; a live one lights up while its owner speaks.
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            micOn ? ClassroomIcons.mic : ClassroomIcons.micOff,
            size: 12,
            color: !micOn
                ? t.danger
                : speaking
                ? t.success
                : Colors.white70,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (hand) ...[
            const SizedBox(width: 6),
            Icon(ClassroomIcons.hand, size: 12, color: t.warning),
          ],
        ],
      ),
    );
  }
}

/// The role tag shown next to a name.
class RolePin extends StatelessWidget {
  const RolePin({super.key, required this.role});

  final ClassRole role;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return switch (role) {
      ClassRole.host => RoleBadge(label: role.labelFa, color: t.roleHost),
      ClassRole.cohost => RoleBadge(label: role.labelFa, color: t.roleCohost),
      ClassRole.presenter => RoleBadge(
        label: role.labelFa,
        color: t.rolePresenter,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// A frame with a speaking ring, used around every video tile.
class SpeakingFrame extends StatelessWidget {
  const SpeakingFrame({super.key, required this.speaking, required this.child});

  final bool speaking;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: speaking ? t.success : Colors.white.withValues(alpha: 0.06),
          width: speaking ? 2 : 1,
        ),
        boxShadow: speaking
            ? [
                BoxShadow(
                  color: t.success.withValues(alpha: 0.35),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(9), child: child),
    );
  }
}

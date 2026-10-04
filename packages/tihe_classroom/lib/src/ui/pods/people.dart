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

  static const _hues = [18.0, 44.0, 152.0, 196.0, 222.0, 262.0, 330.0];

  @override
  Widget build(BuildContext context) {
    final hue = _hues[userId.hashCode.abs() % _hues.length];
    final top = HSLColor.fromAHSL(1, hue, 0.62, 0.64).toColor();
    final bottom = HSLColor.fromAHSL(1, (hue + 18) % 360, 0.56, 0.44).toColor();
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
          color: Colors.white.withValues(alpha: 0.24),
          width: size >= 48 ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: bottom.withValues(alpha: 0.35),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.06),
          ),
        ],
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

/// A person's name over their video: a dark chip with their microphone state. A muted microphone
/// shows as a red crossed-out mic; a live one lights green while its owner speaks.
class NameStrip extends StatelessWidget {
  const NameStrip({
    super.key,
    required this.name,
    required this.micOn,
    this.speaking = false,
    this.hand = false,
    this.large = false,
  });

  final String name;
  final bool micOn;
  final bool speaking;
  final bool hand;

  /// The speaker pod's bigger chip.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 8,
        vertical: large ? 7 : 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF070C1A).withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(large ? 12 : 8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MicGlyph(
            on: micOn,
            speaking: speaking,
            size: large ? 16 : 12,
            onColor: micOn && large ? t.success : null,
          ),
          SizedBox(width: large ? 8 : 6),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: large ? 14.5 : 12,
                height: 1.3,
                fontWeight: large ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (hand) ...[
            const SizedBox(width: 6),
            Icon(ClassroomIcons.hand, size: large ? 15 : 12, color: t.warning),
          ],
        ],
      ),
    );
  }
}

/// The name along the bottom of a gallery tile, over a soft shade so it reads on any video.
class TileLabel extends StatelessWidget {
  const TileLabel({
    super.key,
    required this.name,
    required this.micOn,
    this.speaking = false,
    this.hand = false,
    this.dense = false,
  });

  final String name;
  final bool micOn;
  final bool speaking;
  final bool hand;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00060B18), Color(0xB3060B18)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, dense ? 12 : 18, 8, dense ? 6 : 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hand) ...[
              Icon(ClassroomIcons.hand, size: 13, color: t.warning),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: dense ? 12 : 13,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _MicGlyph(on: micOn, speaking: speaking, size: dense ? 13 : 14),
          ],
        ),
      ),
    );
  }
}

class _MicGlyph extends StatelessWidget {
  const _MicGlyph({
    required this.on,
    required this.speaking,
    required this.size,
    this.onColor,
  });

  final bool on;
  final bool speaking;
  final double size;
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    // Fixed light colours: this sits on video in both themes.
    return Icon(
      on ? ClassroomIcons.mic : ClassroomIcons.micOff,
      size: size,
      color: !on
          ? const Color(0xFFFF5C70)
          : speaking
          ? t.success
          : onColor ?? Colors.white70,
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
  const SpeakingFrame({
    super.key,
    required this.speaking,
    required this.child,
    this.radius = 14,
  });

  final bool speaking;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: speaking ? t.success : Colors.white.withValues(alpha: 0.08),
          width: speaking ? 2 : 1,
        ),
        boxShadow: speaking
            ? [
                BoxShadow(
                  color: t.success.withValues(alpha: 0.35),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: child,
      ),
    );
  }
}

/// A row in a people list: sunk into the pod's glass, with a lit border when it needs attention.
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.child,
    this.alert,
    this.padding = const EdgeInsetsDirectional.fromSTEB(10, 8, 6, 8),
  });

  final Widget child;

  /// Tints the row: red for someone recording their screen.
  final Color? alert;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: padding,
      decoration: BoxDecoration(
        color: alert?.withValues(alpha: 0.12) ?? t.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: alert?.withValues(alpha: 0.5) ?? t.fieldBorder,
        ),
      ),
      child: child,
    );
  }
}

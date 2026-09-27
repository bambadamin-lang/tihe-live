import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/tokens.dart';

/// A placeholder block that gently pulses while content loads.
///
/// Loading states show the *shape* of what is coming, so the page does not jump when it arrives and
/// the student can already see where things will be.
class Skeleton extends StatefulWidget {
  const Skeleton({this.width, this.height = 12, this.radius = AppRadius.sm, super.key});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FadeTransition(
      opacity: Tween(begin: 0.55, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: colors.surfaceHover,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A skeleton for an [AppListRow]-shaped item.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({this.leadingSize = 36, this.titleWidth = 220, super.key});

  final double leadingSize;
  final double titleWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3, vertical: AppSpace.x3),
      child: Row(
        children: [
          Skeleton(width: leadingSize, height: leadingSize, radius: AppRadius.md),
          const SizedBox(width: AppSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: titleWidth, height: 12),
                const SizedBox(height: AppSpace.x2),
                const Skeleton(width: 120, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

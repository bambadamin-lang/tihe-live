import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../state/providers.dart';
import '../stage/stage_view.dart' show podIcons;
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';

/// The six recommended layouts as miniature stages, plus the editor for a custom one
/// (docs/11 §5). Picking one changes the stage for everyone.
class LayoutPickerSheet extends ConsumerWidget {
  const LayoutPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      classroomViewProvider.select((v) => v.room?.layout),
    );
    final session = ref.read(classroomSessionProvider);
    return GlassSheet(
      title: 'چیدمان کلاس',
      width: 720,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'چیدمان پیشنهادی را انتخاب کنید؛ صفحهٔ همهٔ شرکت‌کنندگان و ضبط کلاس به همین شکل درمی‌آید.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, box) {
                final columns = box.maxWidth > 560 ? 3 : 2;
                final width = (box.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final preset in LayoutPreset.values)
                      SizedBox(
                        width: width,
                        child: _PresetTile(
                          layout: layoutPresets[preset]!,
                          hint: layoutPresetHintsFa[preset]!,
                          selected: current?.preset == preset,
                          onTap: () {
                            session.send(ApplyLayout(layoutPresets[preset]!));
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                icon: const Icon(ClassroomIcons.edit, size: 16),
                label: const Text('ساختن چیدمان دلخواه'),
                onPressed: current == null
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final edited = await navigator.push<List<Pod>>(
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            // A pushed route does not inherit the classroom's theme on its own:
                            // capture it, or the editor opens in the host app's look.
                            builder: (_) => InheritedTheme.captureAll(
                              context,
                              UncontrolledProviderScope(
                                container: ProviderScope.containerOf(context),
                                child: Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: LayoutEditor(initial: current.pods),
                                ),
                              ),
                            ),
                          ),
                        );
                        if (edited == null) return;
                        await session.send(
                          ApplyLayout(
                            Layout(
                              id: 'custom',
                              name: 'دلخواه',
                              preset: null,
                              pods: edited,
                            ),
                          ),
                        );
                        navigator.pop();
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.layout,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final Layout layout;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GlassPressable(
      onTap: onTap,
      semanticLabel: layout.name,
      selected: selected,
      radius: 14,
      builder: (context, state) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? t.accentSubtle
              : state.hovered
              ? t.glassHover
              : t.glass,
          border: Border.all(
            color: selected ? t.accent : t.edgeLow,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: MiniStage(pods: layout.pods),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    layout.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: t.text,
                    ),
                  ),
                ),
                if (selected)
                  Icon(ClassroomIcons.check, size: 15, color: t.accentText),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              hint,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: t.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A layout drawn small: translucent panes on the canvas, with their icons. Reads
/// right-to-left like the stage.
class MiniStage extends StatelessWidget {
  const MiniStage({super.key, required this.pods});

  final List<Pod> pods;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(t.glows[0].withValues(alpha: 0.25), t.canvas),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final cw = box.maxWidth / layoutGrid,
                ch = box.maxHeight / layoutGrid;
            return Stack(
              children: [
                for (final p in pods)
                  Positioned(
                    left: (rtl ? layoutGrid - p.x - p.w : p.x) * cw + 1.5,
                    top: p.y * ch + 1.5,
                    width: p.w * cw - 3,
                    height: p.h * ch - 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.kind == PodKind.whiteboard
                            ? const Color(0xFFFBFBF7)
                            : p.kind.isMedia
                            ? t.screen
                            : t.glassStrong,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: t.edgeLow, width: 0.8),
                      ),
                      child: FittedBox(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            podIcons[p.kind],
                            color: p.kind == PodKind.whiteboard
                                ? const Color(0xFF8A8F99)
                                : p.kind.isMedia
                                ? Colors.white54
                                : t.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Drag pods to move them, drag the corner handle to resize, add or remove kinds. Everything
/// snaps to the 12 × 12 grid and is validated live with the server's own rules.
class LayoutEditor extends StatefulWidget {
  const LayoutEditor({super.key, required this.initial});

  final List<Pod> initial;

  @override
  State<LayoutEditor> createState() => _LayoutEditorState();
}

class _LayoutEditorState extends State<LayoutEditor> {
  late List<Pod> _pods = [...widget.initial];
  final Map<String, Offset> _drag = {};

  void _replace(Pod next) => setState(
    () => _pods = [for (final p in _pods) p.id == next.id ? next : p],
  );

  void _add(PodKind kind) {
    // First free 3 × 3 spot, scanning from the start edge.
    for (var y = 0; y <= layoutGrid - 3; y++) {
      for (var x = 0; x <= layoutGrid - 3; x++) {
        final candidate = Pod(
          id: kind.wire,
          kind: kind,
          x: x,
          y: y,
          w: 3,
          h: 3,
        );
        if (_pods.every((p) => !p.overlaps(candidate))) {
          setState(() => _pods = [..._pods, candidate]);
          return;
        }
      }
    }
    setState(
      () => _pods = [
        ..._pods,
        Pod(id: kind.wire, kind: kind, x: 0, y: 0, w: 2, h: 2),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final problems = layoutProblems(_pods);
    final missing = PodKind.values
        .where((k) => _pods.every((p) => p.kind != k))
        .toList();
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Scaffold(
      backgroundColor: t.canvas,
      body: GlassBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassBar(
                  padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 8),
                  child: Row(
                    children: [
                      GlassIconButton(
                        icon: ClassroomIcons.close,
                        tooltip: 'انصراف',
                        size: 34,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'چیدمان دلخواه',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: problems.isEmpty
                            ? () => Navigator.of(context).pop(_pods)
                            : null,
                        icon: const Icon(ClassroomIcons.check, size: 16),
                        label: const Text('اعمال برای همه'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('افزودن:', style: TextStyle(color: t.textSecondary)),
                    for (final kind in missing)
                      OutlinedButton.icon(
                        icon: Icon(podIcons[kind], size: 15),
                        label: Text(kind.labelFa),
                        onPressed: () => _add(kind),
                      ),
                    if (missing.isEmpty)
                      Text(
                        'همهٔ بخش‌ها روی صفحه‌اند',
                        style: TextStyle(color: t.textTertiary),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final cw = box.maxWidth / layoutGrid,
                              ch = box.maxHeight / layoutGrid;
                          int cellsX(double dx) =>
                              ((rtl ? -dx : dx) / cw).round();
                          int cellsY(double dy) => (dy / ch).round();
                          return DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: t.glass,
                              border: Border.all(color: t.edgeLow),
                            ),
                            child: Stack(
                              children: [
                                CustomPaint(
                                  size: box.biggest,
                                  painter: _GridPainter(t.hairline),
                                ),
                                for (final p in _pods)
                                  Positioned(
                                    left:
                                        (rtl ? layoutGrid - p.x - p.w : p.x) *
                                            cw +
                                        2,
                                    top: p.y * ch + 2,
                                    width: p.w * cw - 4,
                                    height: p.h * ch - 4,
                                    child: _EditablePod(
                                      pod: p,
                                      clash: problems.any(
                                        (m) => m.contains(p.kind.labelFa),
                                      ),
                                      onMove: (delta) {
                                        final acc =
                                            (_drag[p.id] ?? Offset.zero) +
                                            delta;
                                        final dx = cellsX(acc.dx),
                                            dy = cellsY(acc.dy);
                                        if (dx == 0 && dy == 0) {
                                          _drag[p.id] = acc;
                                          return;
                                        }
                                        _drag[p.id] = Offset.zero;
                                        _replace(
                                          p.copyWith(
                                            x: (p.x + dx).clamp(
                                              0,
                                              layoutGrid - p.w,
                                            ),
                                            y: (p.y + dy).clamp(
                                              0,
                                              layoutGrid - p.h,
                                            ),
                                          ),
                                        );
                                      },
                                      onResize: (delta) {
                                        final acc =
                                            (_drag['${p.id}#size'] ??
                                                Offset.zero) +
                                            delta;
                                        final dw = cellsX(acc.dx),
                                            dh = cellsY(acc.dy);
                                        if (dw == 0 && dh == 0) {
                                          _drag['${p.id}#size'] = acc;
                                          return;
                                        }
                                        _drag['${p.id}#size'] = Offset.zero;
                                        _replace(
                                          p.copyWith(
                                            w: (p.w + dw).clamp(
                                              1,
                                              layoutGrid - p.x,
                                            ),
                                            h: (p.h + dh).clamp(
                                              1,
                                              layoutGrid - p.y,
                                            ),
                                          ),
                                        );
                                      },
                                      onRemove: _pods.length > 1
                                          ? () => setState(
                                              () => _pods = _pods
                                                  .where((x) => x.id != p.id)
                                                  .toList(),
                                            )
                                          : null,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (problems.isEmpty)
                  Row(
                    children: [
                      Icon(ClassroomIcons.check, size: 15, color: t.success),
                      const SizedBox(width: 6),
                      Text(
                        'چیدمان معتبر است.',
                        style: TextStyle(
                          color: t.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                else
                  for (final m in problems)
                    Text(
                      '• $m',
                      style: TextStyle(
                        color: t.danger,
                        fontWeight: FontWeight.w500,
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

class _EditablePod extends StatelessWidget {
  const _EditablePod({
    required this.pod,
    required this.clash,
    required this.onMove,
    required this.onResize,
    required this.onRemove,
  });

  final Pod pod;
  final bool clash;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GestureDetector(
      onPanUpdate: (d) => onMove(d.delta),
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: Container(
          decoration: BoxDecoration(
            color: t.glassStrong,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: clash ? t.danger : t.edgeLow,
              width: clash ? 1.5 : 1,
            ),
            boxShadow: t.lifted,
          ),
          child: Stack(
            children: [
              Center(
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        Icon(podIcons[pod.kind], color: t.textSecondary),
                        const SizedBox(height: 4),
                        Text(
                          pod.kind.labelFa,
                          style: TextStyle(
                            color: t.text,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (onRemove != null)
                PositionedDirectional(
                  top: 4,
                  end: 4,
                  child: GlassIconButton(
                    icon: ClassroomIcons.close,
                    tooltip: 'حذف',
                    size: 24,
                    iconSize: 13,
                    onPressed: onRemove,
                  ),
                ),
              // The resize handle, on the bottom corner at the end of the reading direction.
              PositionedDirectional(
                bottom: 0,
                end: 0,
                child: GestureDetector(
                  onPanUpdate: (d) => onResize(d.delta),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownLeft,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: t.accentSubtle,
                        borderRadius: const BorderRadiusDirectional.only(
                          topStart: Radius.circular(8),
                          bottomEnd: Radius.circular(10),
                        ),
                      ),
                      child: Icon(
                        ClassroomIcons.resize,
                        size: 12,
                        color: t.accentText,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 1; i < layoutGrid; i++) {
      final x = size.width * i / layoutGrid, y = size.height * i / layoutGrid;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.color != color;
}

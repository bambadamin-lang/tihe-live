import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/skeuo.dart';

const _podIcons = {
  PodKind.speaker: Icons.person,
  PodKind.gallery: Icons.grid_view,
  PodKind.screen: Icons.desktop_windows_outlined,
  PodKind.whiteboard: Icons.draw_outlined,
  PodKind.chat: Icons.chat_bubble_outline,
  PodKind.participants: Icons.people_alt_outlined,
  PodKind.hands: Icons.back_hand_outlined,
};

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
    return PaperSheet(
      title: 'چیدمان کلاس',
      width: 720,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'چیدمان پیشنهادی را انتخاب کنید؛ صفحهٔ همهٔ شرکت‌کنندگان و ضبط کلاس به همین شکل درمی‌آید.',
              style: TextStyle(
                color: ClassroomTheme.of(context).inkSoft,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('ساختن چیدمان دلخواه'),
                onPressed: current == null
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final edited = await navigator.push<List<Pod>>(
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => UncontrolledProviderScope(
                              container: ProviderScope.containerOf(context),
                              child: Directionality(
                                textDirection: TextDirection.rtl,
                                child: LayoutEditor(initial: current.pods),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? t.brassHigh.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.55),
          border: Border.all(
            color: selected ? t.brassDark : t.paperEdge,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: MiniStage(pods: layout.pods),
            ),
            const SizedBox(height: 6),
            Text(
              layout.name,
              style: TextStyle(fontWeight: FontWeight.w700, color: t.ink),
            ),
            Text(hint, style: TextStyle(fontSize: 11.5, color: t.inkSoft)),
          ],
        ),
      ),
    );
  }
}

/// A layout drawn small: wood desk, paper pods with their icons. Reads right-to-left like the
/// stage.
class MiniStage extends StatelessWidget {
  const MiniStage({super.key, required this.pods});

  final List<Pod> pods;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(colors: [t.woodMid, t.woodDark]),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final cw = box.maxWidth / layoutGrid, ch = box.maxHeight / layoutGrid;
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
                          ? t.enamel
                          : p.kind.isMedia
                          ? const Color(0xFF3A342C)
                          : t.paperHigh,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: t.paperEdge, width: 0.8),
                    ),
                    child: FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          _podIcons[p.kind],
                          color: p.kind.isMedia && p.kind != PodKind.whiteboard
                              ? t.paperLow
                              : t.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
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
      backgroundColor: t.paperHigh,
      appBar: AppBar(
        backgroundColor: t.paperLow,
        title: const Text('چیدمان دلخواه'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              onPressed: problems.isEmpty
                  ? () => Navigator.of(context).pop(_pods)
                  : null,
              icon: const Icon(Icons.check),
              label: const Text('اعمال برای همه'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('افزودن:'),
                for (final kind in missing)
                  ActionChip(
                    avatar: Icon(_podIcons[kind], size: 16),
                    label: Text(kind.labelFa),
                    onPressed: () => _add(kind),
                  ),
                if (missing.isEmpty)
                  Text(
                    'همهٔ بخش‌ها روی صفحه‌اند',
                    style: TextStyle(color: t.inkSoft),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final cw = box.maxWidth / layoutGrid,
                          ch = box.maxHeight / layoutGrid;
                      int cellsX(double dx) => ((rtl ? -dx : dx) / cw).round();
                      int cellsY(double dy) => (dy / ch).round();
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: LinearGradient(
                            colors: [t.woodMid, t.woodDark],
                          ),
                        ),
                        child: Stack(
                          children: [
                            CustomPaint(
                              size: box.biggest,
                              painter: _GridPainter(),
                            ),
                            for (final p in _pods)
                              Positioned(
                                left:
                                    (rtl ? layoutGrid - p.x - p.w : p.x) * cw +
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
                                        (_drag[p.id] ?? Offset.zero) + delta;
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
                                        (_drag['${p.id}#size'] ?? Offset.zero) +
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
            const SizedBox(height: 10),
            if (problems.isEmpty)
              Text(
                'چیدمان معتبر است.',
                style: TextStyle(color: t.pinTeal, fontWeight: FontWeight.w600),
              )
            else
              for (final m in problems)
                Text(
                  '• $m',
                  style: const TextStyle(
                    color: Color(0xFFB3261E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
          ],
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
            gradient: t.paper,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: clash ? const Color(0xFFB3261E) : t.paperEdge,
              width: clash ? 2 : 1,
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
                        Icon(_podIcons[pod.kind], color: t.inkSoft),
                        Text(
                          pod.kind.labelFa,
                          style: TextStyle(
                            color: t.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (onRemove != null)
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: IconButton(
                    tooltip: 'حذف',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
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
                        gradient: t.brassPlate,
                        borderRadius: const BorderRadiusDirectional.only(
                          topStart: Radius.circular(8),
                          bottomEnd: Radius.circular(8),
                        ),
                      ),
                      child: const Icon(
                        Icons.open_in_full,
                        size: 12,
                        color: Color(0xFF3A2A10),
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
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (var i = 1; i < layoutGrid; i++) {
      final x = size.width * i / layoutGrid, y = size.height * i / layoutGrid;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

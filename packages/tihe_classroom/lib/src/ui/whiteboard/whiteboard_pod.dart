import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../domain/board_model.dart';
import '../../domain/persian.dart';
import '../../state/board_controller.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';
import 'board_painter.dart';

/// The whiteboard pod: the board on the pod's glass, with the tool tray below it. The page stays
/// near-white in both themes — ink colours are chosen for it, and it is what the recording shows.
/// Anyone can watch; drawing needs `whiteboard.draw`, page control `whiteboard.manage`.
class WhiteboardPod extends ConsumerWidget {
  const WhiteboardPod({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ClassroomTheme.of(context);
    final canDraw = ref.watch(
      classroomViewProvider.select((v) => v.can(Capability.whiteboardDraw)),
    );
    final canManage = ref.watch(
      classroomViewProvider.select((v) => v.can(Capability.whiteboardManage)),
    );
    return LayoutBuilder(
      builder: (context, box) {
        // One row needs room for ten markers, eight colours and the actions; managers have
        // page controls too. Narrower than that, the tray takes two rows.
        final compactTray = box.maxWidth < (canManage ? 930 : 780);
        return Column(
          children: [
            Expanded(
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: t.edgeLow),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: ColoredBox(
                    // Around the page, where the pod's shape and the page's differ.
                    color: t.isDark
                        ? const Color(0xFF1C1E24)
                        : const Color(0xFFE3E6ED),
                    child: BoardCanvas(canDraw: canDraw, canManage: canManage),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (canDraw)
              MarkerTray(canManage: canManage, compact: compactTray)
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(ClassroomIcons.lock, size: 13, color: t.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      'تخته فقط برای مشاهده است',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: t.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The drawing surface. Pointer input goes to the [BoardController]; everything else is drawn
/// from the room state, the pending (optimistic) items and other people's previews.
class BoardCanvas extends ConsumerStatefulWidget {
  const BoardCanvas({
    super.key,
    required this.canDraw,
    required this.canManage,
  });

  final bool canDraw;
  final bool canManage;

  @override
  ConsumerState<BoardCanvas> createState() => _BoardCanvasState();
}

class _BoardCanvasState extends ConsumerState<BoardCanvas>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));
  Size _size = Size.zero;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  BoardPoint _toPage(Offset local) => BoardViewport(_size).toPage(local);

  Future<void> _placeText(
    BoardController board,
    Offset local,
    String pageId,
  ) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => GlassSheet(
        title: 'نوشتن روی تخته',
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              maxLength: maxTextLength,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(hintText: 'متن…'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('گذاشتن روی تخته'),
              ),
            ),
          ],
        ),
      ),
    );
    if (text != null) await board.placeText(_toPage(local), text, pageId);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(classroomSessionProvider);
    final board = session.board;
    final room = ref.watch(classroomViewProvider.select((v) => v.room));
    final previews = ref.watch(classroomViewProvider.select((v) => v.previews));
    final page = room?.activePage;
    if (room == null || page == null) return const SizedBox.expand();
    final fontFamily = ClassroomTheme.of(context).fontFamily;

    return LayoutBuilder(
      builder: (context, box) {
        _size = box.biggest;
        return ListenableBuilder(
          listenable: board,
          builder: (context, _) {
            final hasLaser =
                previews.values.any((p) => p.isLaser) ||
                board.draft?.tool == BoardTool.laser;
            if (hasLaser && !_ticker.isActive) _ticker.start();
            if (!hasLaser && _ticker.isActive) _ticker.stop();

            final items = [
              ...room.itemsOn(page.id),
              ...board.pending.values.where(
                (i) => i.pageId == page.id && !room.items.containsKey(i.id),
              ),
            ];
            final canvas = CustomPaint(
              size: Size.infinite,
              painter: BoardPainter(
                page: page,
                items: items,
                hidden: board.erasing,
                previews: previews.values.toList(),
                draft: board.draft,
                now: DateTime.now(),
                fontFamily: fontFamily,
              ),
            );
            if (!widget.canDraw) return canvas;
            return MouseRegion(
              cursor: switch (board.tool) {
                BoardTool.text => SystemMouseCursors.text,
                BoardTool.eraser => SystemMouseCursors.cell,
                _ => SystemMouseCursors.precise,
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  if (board.tool == BoardTool.text) {
                    _placeText(board, e.localPosition, page.id);
                    return;
                  }
                  board.pointerDown(
                    _toPage(e.localPosition),
                    room,
                    canManage: widget.canManage,
                  );
                },
                onPointerMove: (e) =>
                    board.pointerMove(_toPage(e.localPosition), room),
                onPointerUp: (_) => board.pointerUp(),
                onPointerCancel: (_) => board.pointerUp(),
                child: canvas,
              ),
            );
          },
        );
      },
    );
  }
}

/// The tool tray: tools, colours, width, undo/redo and pages.
class MarkerTray extends ConsumerWidget {
  const MarkerTray({super.key, required this.canManage, this.compact = false});

  final bool canManage;
  final bool compact;

  static const _icons = {
    BoardTool.pen: ClassroomIcons.pen,
    BoardTool.marker: ClassroomIcons.marker,
    BoardTool.highlighter: ClassroomIcons.highlighter,
    BoardTool.line: ClassroomIcons.line,
    BoardTool.arrow: ClassroomIcons.arrow,
    BoardTool.rect: ClassroomIcons.rect,
    BoardTool.ellipse: ClassroomIcons.ellipse,
    BoardTool.text: ClassroomIcons.text,
    BoardTool.eraser: ClassroomIcons.eraser,
    BoardTool.laser: ClassroomIcons.laser,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(classroomSessionProvider);
    final board = session.board;
    final room = ref.watch(classroomViewProvider.select((v) => v.room));
    final t = ClassroomTheme.of(context);
    return ListenableBuilder(
      listenable: board,
      builder: (context, _) {
        final tools = [
          for (final tool in BoardTool.values)
            _Marker(
              icon: _icons[tool]!,
              label: tool.labelFa,
              // The eraser and laser have no ink of their own.
              cap: tool == BoardTool.eraser
                  ? null
                  : tool == BoardTool.laser
                  ? const Color(0xFFD32F2F)
                  : colorFromHex(board.color),
              selected: board.tool == tool,
              onTap: () => board.selectTool(tool),
            ),
        ];
        final colors = [
          for (final hex in boardPalette)
            _ColorCap(
              color: colorFromHex(hex),
              selected: board.color == hex,
              onTap: () => board.selectColor(hex),
            ),
        ];
        final actions = [
          _TrayIcon(
            icon: ClassroomIcons.undo,
            label: 'واگرد',
            onTap: board.history.canUndo ? board.undo : null,
          ),
          _TrayIcon(
            icon: ClassroomIcons.redo,
            label: 'انجام دوباره',
            onTap: board.history.canRedo ? board.redo : null,
          ),
          if (board.tool == BoardTool.rect || board.tool == BoardTool.ellipse)
            _TrayIcon(
              icon: board.fillShapes
                  ? ClassroomIcons.fill
                  : ClassroomIcons.noFill,
              label: board.fillShapes ? 'بدون رنگ داخل' : 'با رنگ داخل',
              onTap: board.toggleFill,
            ),
          _WidthDial(
            value: board.width,
            onChanged: board.setWidth,
            tool: board.tool,
          ),
          if (canManage && room != null) ...[
            const _PageSwitcher(),
            _TrayIcon(
              icon: ClassroomIcons.newPage,
              label: 'صفحهٔ تازه',
              onTap: () => _pickBackground(context, board),
            ),
            _TrayIcon(
              icon: ClassroomIcons.clearPage,
              label: 'پاک کردن صفحه',
              onTap: () => board.clearPage(room),
            ),
          ],
        ];
        final content = compact
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    alignment: WrapAlignment.center,
                    children: tools,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [...colors, ...actions],
                  ),
                ],
              )
            : Row(
                children: [
                  ...tools,
                  const _TrayDivider(),
                  ...colors,
                  const _TrayDivider(),
                  const Spacer(),
                  ...actions,
                ],
              );
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: t.glassHover,
            border: Border.all(color: t.hairline),
          ),
          child: content,
        );
      },
    );
  }

  Future<void> _pickBackground(
    BuildContext context,
    BoardController board,
  ) async {
    final chosen = await showDialog<BoardBackground>(
      context: context,
      builder: (context) => GlassSheet(
        title: 'صفحهٔ تازه',
        width: 360,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final bg in BoardBackground.values)
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(bg),
                child: Text(bg.labelFa),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await board.addPage(chosen);
  }
}

/// A tool key. Drawing tools show the current ink as a bar under the icon.
class _Marker extends StatelessWidget {
  const _Marker({
    required this.icon,
    required this.label,
    required this.cap,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color? cap;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GlassPressable(
      onTap: onTap,
      tooltip: label,
      semanticLabel: label,
      selected: selected,
      radius: 9,
      builder: (context, s) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 32,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: selected
              ? t.accentSubtle
              : s.hovered
              ? t.glassHover
              : Colors.transparent,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? t.accentText : t.textSecondary,
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: selected ? 14 : 10,
              height: 2.5,
              decoration: BoxDecoration(
                color:
                    cap?.withValues(alpha: selected ? 1 : 0.55) ??
                    Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorCap extends StatelessWidget {
  const _ColorCap({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return GlassPressable(
      onTap: onTap,
      semanticLabel: 'رنگ',
      selected: selected,
      radius: 12,
      builder: (context, s) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 20,
          height: 20,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? t.accent
                  : s.hovered
                  ? t.edgeHigh
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrayIcon extends StatelessWidget {
  const _TrayIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GlassIconButton(
    icon: icon,
    tooltip: label,
    size: 32,
    iconSize: 16,
    onPressed: onTap,
  );
}

class _TrayDivider extends StatelessWidget {
  const _TrayDivider();

  @override
  Widget build(BuildContext context) => const BarDivider(height: 22);
}

/// Pen width: a small stepped control, since exact numbers mean nothing on a board.
class _WidthDial extends StatelessWidget {
  const _WidthDial({
    required this.value,
    required this.onChanged,
    required this.tool,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final BoardTool tool;

  @override
  Widget build(BuildContext context) {
    final base = defaultToolWidth[tool.name] ?? 28;
    final steps = [base ~/ 2, base, base * 2, base * 4];
    return PopupMenuButton<int>(
      tooltip: 'ضخامت',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final (i, w) in steps.indexed)
          PopupMenuItem(
            value: w,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 2.0 + i * 3,
                  decoration: BoxDecoration(
                    color: ClassroomTheme.of(context).text,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Text(['نازک', 'معمولی', 'پهن', 'خیلی پهن'][i]),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          ClassroomIcons.width,
          size: 16,
          color: ClassroomTheme.of(context).textSecondary,
        ),
      ),
    );
  }
}

class _PageSwitcher extends ConsumerWidget {
  const _PageSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(classroomViewProvider.select((v) => v.room));
    if (state == null) return const SizedBox.shrink();
    final board = ref.watch(classroomSessionProvider).board;
    final index = state.pages.indexWhere((p) => p.id == state.activePageId);
    final count = state.pages.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TrayIcon(
          icon: ClassroomIcons.previousPage,
          label: 'صفحهٔ قبل',
          onTap: index > 0
              ? () => board.selectPage(state.pages[index - 1].id)
              : null,
        ),
        Text(
          toPersianDigits('${index + 1} / $count'),
          style: TextStyle(
            fontSize: 12,
            color: ClassroomTheme.of(context).textSecondary,
          ),
        ),
        _TrayIcon(
          icon: ClassroomIcons.nextPage,
          label: 'صفحهٔ بعد',
          onTap: index < count - 1
              ? () => board.selectPage(state.pages[index + 1].id)
              : null,
        ),
      ],
    );
  }
}

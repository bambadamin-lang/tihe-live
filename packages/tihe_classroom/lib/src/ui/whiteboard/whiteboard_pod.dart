import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../domain/board_model.dart';
import '../../domain/persian.dart';
import '../../state/board_controller.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/skeuo.dart';
import 'board_painter.dart';

/// The whiteboard pod: an enamel board in an aluminium frame, with the marker tray below it.
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
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: t.raised,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [t.metalHigh, t.metalMid, t.metalHigh, t.metalLow],
                stops: const [0, 0.38, 0.55, 1],
              ),
              border: Border.all(color: Colors.black.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: ColoredBox(
                        color: const Color(0xFFE9E9E4),
                        child: BoardCanvas(
                          canDraw: canDraw,
                          canManage: canManage,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (canDraw)
                  MarkerTray(canManage: canManage, compact: compactTray)
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'تخته فقط برای مشاهده است',
                      style: TextStyle(
                        fontSize: 12,
                        color: t.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
      builder: (context) => PaperSheet(
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
              decoration: const InputDecoration(
                hintText: 'متن…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
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

/// The marker tray: tools as physical markers, colour caps, width, undo/redo and pages.
class MarkerTray extends ConsumerWidget {
  const MarkerTray({super.key, required this.canManage, this.compact = false});

  final bool canManage;
  final bool compact;

  static const _icons = {
    BoardTool.pen: Icons.edit,
    BoardTool.marker: Icons.brush,
    BoardTool.highlighter: Icons.highlight,
    BoardTool.line: Icons.horizontal_rule,
    BoardTool.arrow: Icons.call_made,
    BoardTool.rect: Icons.crop_square,
    BoardTool.ellipse: Icons.circle_outlined,
    BoardTool.text: Icons.title,
    BoardTool.eraser: Icons.auto_fix_normal,
    BoardTool.laser: Icons.flare,
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
              cap: tool == BoardTool.eraser
                  ? const Color(0xFFE8E2D6)
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
            icon: Icons.undo,
            label: 'واگرد',
            onTap: board.history.canUndo ? board.undo : null,
          ),
          _TrayIcon(
            icon: Icons.redo,
            label: 'انجام دوباره',
            onTap: board.history.canRedo ? board.redo : null,
          ),
          if (board.tool == BoardTool.rect || board.tool == BoardTool.ellipse)
            _TrayIcon(
              icon: board.fillShapes
                  ? Icons.format_color_fill
                  : Icons.format_color_reset,
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
              icon: Icons.note_add_outlined,
              label: 'صفحهٔ تازه',
              onTap: () => _pickBackground(context, board),
            ),
            _TrayIcon(
              icon: Icons.layers_clear_outlined,
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(8),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [t.metalMid, t.metalHigh, t.metalLow],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 3,
                offset: Offset(0, 2),
              ),
            ],
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
      builder: (context) => PaperSheet(
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

/// A marker lying in the tray; the chosen one is lifted out.
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
  final Color cap;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.only(
                top: selected ? 0 : 6,
                bottom: selected ? 6 : 0,
                left: 2,
                right: 2,
              ),
              width: 30,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.white, t.paperLow, t.paperEdge],
                ),
                border: Border(top: BorderSide(color: cap, width: 7)),
                boxShadow: selected
                    ? t.lifted
                    : const [
                        BoxShadow(color: Color(0x33000000), blurRadius: 1),
                      ],
              ),
              child: Icon(icon, size: 15, color: t.ink),
            ),
          ),
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
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: selected ? 22 : 18,
        height: selected ? 22 : 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.35, -0.35),
            colors: [
              Color.lerp(color, Colors.white, 0.45)!,
              color,
              Color.lerp(color, Colors.black, 0.3)!,
            ],
          ),
          border: Border.all(
            color: selected ? Colors.black87 : Colors.black26,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    visualDensity: VisualDensity.compact,
    iconSize: 20,
    color: ClassroomTheme.of(context).ink,
    onPressed: onTap,
    icon: Icon(icon),
  );
}

class _TrayDivider extends StatelessWidget {
  const _TrayDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 2,
    height: 26,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      border: Border(
        left: BorderSide(color: Color(0x55000000)),
        right: BorderSide(color: Color(0xAAFFFFFF)),
      ),
    ),
  );
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
                  color: Colors.black87,
                ),
                const SizedBox(width: 10),
                Text(['نازک', 'معمولی', 'پهن', 'خیلی پهن'][i]),
              ],
            ),
          ),
      ],
      child: const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(Icons.line_weight, size: 20),
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
          icon: Icons.chevron_right,
          label: 'صفحهٔ قبل',
          onTap: index > 0
              ? () => board.selectPage(state.pages[index - 1].id)
              : null,
        ),
        Text(
          toPersianDigits('${index + 1} / $count'),
          style: const TextStyle(fontSize: 12),
        ),
        _TrayIcon(
          icon: Icons.chevron_left,
          label: 'صفحهٔ بعد',
          onTap: index < count - 1
              ? () => board.selectPage(state.pages[index + 1].id)
              : null,
        ),
      ],
    );
  }
}

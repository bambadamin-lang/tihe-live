import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';
import '../theme/menu.dart';
import '../theme/motion.dart';
import 'people.dart';

/// The quick reactions in the dock. A reaction is sent as a chat message of that one emoji —
/// the class needs no new message type — and every screen floats it up over the stage.
const reactionEmoji = ['👍', '👏', '❤️', '😂', '😮', '🎉', '🙏', '🤔'];

/// Whether a chat message is one of the [reactionEmoji] on its own.
bool isReaction(String text) => reactionEmoji.contains(text.trim());

/// Emoji for the composer, a small everyday set.
const _composerEmoji = [
  '🙂', '😊', '😂', '😅', '😍', '🤔', '😮', '😢', //
  '👍', '👎', '👏', '🙏', '💪', '👌', '✋', '🙋', //
  '❤️', '🔥', '🎉', '✅', '❌', '❓', '💡', '📌', //
];

/// Chat: each message a card with the sender's avatar; the teachers' messages lit with the
/// accent. Sending needs `chat.send`; managers can delete any message.
class ChatPod extends ConsumerStatefulWidget {
  const ChatPod({super.key});

  @override
  ConsumerState<ChatPod> createState() => _ChatPodState();
}

class _ChatPodState extends ConsumerState<ChatPod> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _lastCount = 0;

  /// Messages already on screen when the pod opened don't replay their arrival.
  SeenSet? _seen;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await ref.read(classroomSessionProvider).send(SendChat(text));
  }

  Future<void> _pickEmoji(BuildContext anchor) async {
    final emoji = await showEmojiPopover(anchor, _composerEmoji);
    if (emoji == null) return;
    // In at the caret, replacing any selection.
    final value = _input.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    _input.value = value.replaced(selection, emoji);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    final chat = ref.watch(
      classroomViewProvider.select(
        (v) => v.room?.chat ?? const <ChatMessage>[],
      ),
    );
    final me = ref.watch(classroomViewProvider.select((v) => v.userId));
    final canSend = ref.watch(
      classroomViewProvider.select((v) => v.can(Capability.chatSend)),
    );
    final canManage = ref.watch(
      classroomViewProvider.select((v) => v.can(Capability.participantsManage)),
    );

    final seen = _seen ??= SeenSet(chat.map((m) => m.id));
    if (chat.length != _lastCount) {
      // The first fill jumps to the end; later messages glide it into view.
      final first = _lastCount == 0;
      _lastCount = chat.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final end = _scroll.position.maxScrollExtent;
        final duration = Motion.of(context, Motion.medium);
        if (first || duration == Duration.zero) {
          _scroll.jumpTo(end);
        } else {
          _scroll.animateTo(end, duration: duration, curve: Motion.enter);
        }
      });
    }

    return Column(
      children: [
        Expanded(
          child: chat.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        ClassroomIcons.chat,
                        size: 24,
                        color: t.textTertiary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'هنوز پیامی نیست',
                        style: TextStyle(color: t.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
                  itemCount: chat.length,
                  itemBuilder: (context, i) {
                    final m = chat[i];
                    return Appear(
                      key: ValueKey(m.id),
                      animate: seen.isNew(m.id),
                      offset: const Offset(0, 12),
                      scale: 0.98,
                      child: _Message(
                        message: m,
                        onDelete: (m.userId == me || canManage)
                            ? () => ref
                                  .read(classroomSessionProvider)
                                  .send(DeleteChat(m.id))
                            : null,
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: canSend
              ? Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 48,
                        padding: const EdgeInsetsDirectional.only(
                          start: 14,
                          end: 4,
                        ),
                        decoration: BoxDecoration(
                          color: t.field,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: t.fieldBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                focusNode: _focus,
                                textDirection: TextDirection.rtl,
                                maxLength: 1000,
                                onSubmitted: (_) => _send(),
                                style: TextStyle(color: t.text, fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: 'پیام خود را بنویسید…',
                                  counterText: '',
                                  filled: false,
                                  isCollapsed: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                            Builder(
                              builder: (context) => GlassIconButton(
                                icon: ClassroomIcons.emoji,
                                tooltip: 'شکلک',
                                size: 36,
                                iconSize: 19,
                                radius: 11,
                                onPressed: () => _pickEmoji(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GlassPressable(
                      onTap: _send,
                      tooltip: 'ارسال',
                      semanticLabel: 'ارسال',
                      radius: 15,
                      builder: (context, s) => AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: t.accentGradient(
                            Directionality.of(context),
                          ),
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: t.accentGlow(
                            strength: s.hovered ? 1.2 : 0.7,
                          ),
                        ),
                        child: Icon(
                          ClassroomIcons.send,
                          size: 20,
                          color: t.onAccent,
                        ),
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        ClassroomIcons.lock,
                        size: 14,
                        color: t.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'میزبان گفتگو را بسته است',
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// A grid of emoji beside [anchor]; returns the one tapped.
Future<String?> showEmojiPopover(BuildContext anchor, List<String> emoji) =>
    showGlassPopover<String>(
      context: anchor,
      width: emoji.length <= 8 ? 8 * 42 + 12 : 8 * 38 + 12,
      builder: (context) {
        final t = ClassroomTheme.of(context);
        final big = emoji.length <= 8;
        return Wrap(
          children: [
            for (final e in emoji)
              GlassPressable(
                onTap: () => Navigator.of(context).pop(e),
                semanticLabel: e,
                radius: 10,
                builder: (context, s) => AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: big ? 42 : 38,
                  height: big ? 44 : 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: s.hovered ? t.glassHover : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 120),
                    scale: s.hovered ? 1.2 : 1,
                    child: Text(
                      e,
                      style: TextStyle(fontSize: big ? 24 : 20, height: 1.2),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.onDelete});

  final ChatMessage message;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    // The teachers' messages stand out: they are the ones students scroll back for.
    final staff = message.role.rank >= ClassRole.cohost.rank;
    final reaction = isReaction(message.text);
    final card = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 10, 11),
      decoration: BoxDecoration(
        color: staff ? t.accentSubtle : t.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: staff ? t.accent.withValues(alpha: 0.55) : t.fieldBorder,
          width: staff ? 1.2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        message.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: t.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    RolePin(role: message.role),
                    const Spacer(),
                    Text(
                      clockTime(DateTime.parse(message.at)),
                      style: TextStyle(fontSize: 11.5, color: t.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message.text,
                  style: TextStyle(
                    fontSize: reaction ? 24 : 14,
                    color: t.text,
                    height: reaction ? 1.3 : 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Avatar(userId: message.userId, name: message.name, size: 34),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (onDelete != null)
            Builder(
              builder: (context) => GlassIconButton(
                icon: ClassroomIcons.more,
                tooltip: 'پیام',
                size: 24,
                iconSize: 15,
                onPressed: () async {
                  final delete = await showGlassMenu<bool>(
                    context: context,
                    width: 180,
                    entries: const [
                      GlassMenuItem(
                        value: true,
                        label: 'حذف پیام',
                        icon: ClassroomIcons.close,
                        danger: true,
                      ),
                    ],
                  );
                  if (delete ?? false) onDelete!();
                },
              ),
            ),
          Expanded(child: card),
        ],
      ),
    );
  }
}

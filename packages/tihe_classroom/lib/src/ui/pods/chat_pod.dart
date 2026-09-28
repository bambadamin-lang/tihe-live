import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/glass.dart';
import 'people.dart';

/// Chat, as bubbles on the pod's glass — yours tinted with the accent. Sending needs
/// `chat.send`; managers can delete any message.
class ChatPod extends ConsumerStatefulWidget {
  const ChatPod({super.key});

  @override
  ConsumerState<ChatPod> createState() => _ChatPodState();
}

class _ChatPodState extends ConsumerState<ChatPod> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  /// Each message's widget, kept while the message and the viewer's rights stay the same. A new
  /// message then rebuilds only itself: Flutter skips a widget that is the identical instance,
  /// where a fresh one per build would rebuild every visible message and its delete button.
  final _built =
      <String, ({ChatMessage message, bool canDelete, Widget widget})>{};

  Widget _message(ChatMessage m, String me, bool canManage) {
    final canDelete = m.userId == me || canManage;
    final cached = _built[m.id];
    if (cached != null &&
        identical(cached.message, m) &&
        cached.canDelete == canDelete) {
      return cached.widget;
    }
    final widget = _Message(
      key: ValueKey(m.id),
      message: m,
      mine: m.userId == me,
      onDelete: canDelete
          ? () => ref.read(classroomSessionProvider).send(DeleteChat(m.id))
          : null,
    );
    _built[m.id] = (message: m, canDelete: canDelete, widget: widget);
    return widget;
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await ref.read(classroomSessionProvider).send(SendChat(text));
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

    if (chat.length != _lastCount) {
      if (chat.length < _lastCount) {
        final ids = {for (final m in chat) m.id};
        _built.removeWhere((id, _) => !ids.contains(id));
      }
      _lastCount = chat.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
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
                        size: 22,
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
                  // Messages hold no state worth keeping alive off-screen.
                  addAutomaticKeepAlives: false,
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                  itemCount: chat.length,
                  itemBuilder: (context, i) => _message(chat[i], me, canManage),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
          child: canSend
              ? Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        textDirection: TextDirection.rtl,
                        maxLength: 1000,
                        onSubmitted: (_) => _send(),
                        style: TextStyle(color: t.text, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'پیام…',
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: t.edgeLow),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: t.edgeLow),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GlassPressable(
                      onTap: _send,
                      tooltip: 'ارسال',
                      semanticLabel: 'ارسال',
                      radius: 12,
                      builder: (context, s) => AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: s.hovered ? t.accentHover : t.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          ClassroomIcons.send,
                          size: 17,
                          color: t.onAccent,
                        ),
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        ClassroomIcons.lock,
                        size: 13,
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

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.message,
    required this.mine,
    required this.onDelete,
  });

  final ChatMessage message;
  final bool mine;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = ClassroomTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 7, 11, 8),
        decoration: BoxDecoration(
          color: mine ? t.accentSubtle : t.glassHover,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: mine ? t.accent.withValues(alpha: 0.18) : t.hairline,
          ),
        ),
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
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: t.text,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                RolePin(role: message.role),
                const Spacer(),
                Text(
                  clockTime(DateTime.parse(message.at)),
                  style: TextStyle(fontSize: 11, color: t.textTertiary),
                ),
                if (onDelete != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 2),
                    child: GlassIconButton(
                      icon: ClassroomIcons.close,
                      tooltip: 'حذف پیام',
                      size: 20,
                      iconSize: 12,
                      onPressed: onDelete,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              message.text,
              style: TextStyle(fontSize: 14, color: t.text, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

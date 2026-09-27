import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts.dart';
import '../../domain/persian.dart';
import '../../state/providers.dart';
import '../theme/classroom_theme.dart';
import '../theme/materials.dart';
import 'people.dart';

/// Chat on lined notebook paper. Sending needs `chat.send`; managers can delete any message.
class ChatPod extends ConsumerStatefulWidget {
  const ChatPod({super.key});

  @override
  ConsumerState<ChatPod> createState() => _ChatPodState();
}

class _ChatPodState extends ConsumerState<ChatPod> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

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
      _lastCount = chat.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }

    return CustomPaint(
      painter: PaperPainter(t, radius: 10, lined: true),
      child: Column(
        children: [
          Expanded(
            child: chat.isEmpty
                ? Center(
                    child: Text(
                      'هنوز پیامی نیست',
                      style: TextStyle(color: t.inkSoft),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    itemCount: chat.length,
                    itemBuilder: (context, i) {
                      final m = chat[i];
                      return _Message(
                        message: m,
                        mine: m.userId == me,
                        onDelete: (m.userId == me || canManage)
                            ? () => ref
                                  .read(classroomSessionProvider)
                                  .send(DeleteChat(m.id))
                            : null,
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.paperEdge)),
            ),
            child: canSend
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          textDirection: TextDirection.rtl,
                          maxLength: 1000,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: 'پیام…',
                            counterText: '',
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.7),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'ارسال',
                        onPressed: _send,
                        icon: Icon(
                          Icons.send,
                          color: t.pinTeal,
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'میزبان گفتگو را بسته است',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.inkSoft, fontSize: 12),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
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
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
        decoration: BoxDecoration(
          color: mine
              ? const Color(0xFFFFF6C9)
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
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
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: t.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                RolePin(role: message.role),
                const Spacer(),
                Text(
                  clockTime(DateTime.parse(message.at)),
                  style: TextStyle(fontSize: 11, color: t.inkSoft),
                ),
                if (onDelete != null)
                  InkWell(
                    onTap: onDelete,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 4),
                      child: Icon(Icons.close, size: 13, color: t.inkSoft),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              message.text,
              style: TextStyle(fontSize: 14, color: t.ink, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../domain/senavi.dart';
import '../../domain/social.dart';
import '../../mock/mock_backend.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';

/// 1 対 1 のやりとり。
///
/// スタンプを本文と同じ重さで置いてあるのは、災害時に文字を打つ余裕が
/// ないことがあるため。「無事」「助けて」を一押しで送れる場所が、平時から
/// 使っているのと同じ位置にあることに意味がある。
class ChatPage extends ConsumerStatefulWidget {
  final FriendEntry friend;
  const ChatPage({super.key, required this.friend});
  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send({String? text, String? reaction}) {
    if ((text?.trim().isEmpty ?? true) && reaction == null) return;
    if (ref.read(mockModeProvider)) {
      ref.read(mockBackendProvider.notifier).send(widget.friend.uid, text: text?.trim(), reaction: reaction);
    } else {
      ref.read(apiProvider).sendMessage(toUid: widget.friend.uid, text: text?.trim(), reaction: reaction);
    }
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(chatProvider(widget.friend.uid));
    final name = widget.friend.relation != null ? '${widget.friend.displayName}(${widget.friend.relation})' : widget.friend.displayName;

    return Scaffold(
      backgroundColor: HinaColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          HinaAvatar(imageBase64: widget.friend.avatarImage, moodName: widget.friend.avatarMood, fallbackName: widget.friend.displayName, size: 32),
          const SizedBox(width: 8),
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: msgs.isEmpty
              ? const _EmptyChat()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(HinaSpace.m, HinaSpace.m, HinaSpace.m, HinaSpace.s),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) => _Bubble(msg: msgs[i], friend: widget.friend),
                ),
        ),
        // スタンプ列。文字を打たずに済む経路を常に見えるところに置く。
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: HinaSpace.m),
            children: [
              for (final r in kReactions)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    backgroundColor: r.emoji == '🆘' ? HinaColors.alertBg : HinaColors.surface,
                    side: BorderSide(color: r.emoji == '🆘' ? HinaColors.alert : HinaColors.line),
                    label: Text('${r.emoji} ${r.label}'),
                    onPressed: () => _send(reaction: r.emoji),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HinaSpace.m, 0, HinaSpace.s, HinaSpace.s),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (v) => _send(text: v),
                  decoration: InputDecoration(
                    hintText: 'メッセージ',
                    filled: true,
                    fillColor: HinaColors.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(HinaRadius.button), borderSide: BorderSide.none),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _send(text: _input.text),
                icon: const Icon(Icons.send_rounded, color: HinaColors.sky),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg;
  final FriendEntry friend;
  const _Bubble({required this.msg, required this.friend});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mine = msg.fromUid == 'me';
    final time = '${msg.at.hour.toString().padLeft(2, '0')}:${msg.at.minute.toString().padLeft(2, '0')}';

    // スタンプは吹き出しを付けず、絵だけ大きく出す。
    final body = msg.isReaction
        ? Text(msg.reaction!, style: const TextStyle(fontSize: 34))
        : Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.66),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? HinaColors.mist : HinaColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: HinaShadow.card,
            ),
            child: Text(msg.text ?? '', style: t.bodyMedium),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            HinaAvatar(imageBase64: friend.avatarImage, moodName: friend.avatarMood, fallbackName: friend.displayName, size: 30),
            const SizedBox(width: 6),
          ],
          if (mine) ...[Text(time, style: t.bodySmall), const SizedBox(width: 6)],
          Flexible(child: body),
          if (!mine) ...[const SizedBox(width: 6), Text(time, style: t.bodySmall)],
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(HinaSpace.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SenaviAvatar(SenaviMood.normal, size: 96),
            const SizedBox(height: 8),
            Text('まだやりとりがありません。\n災害のときは、下のスタンプが一押しで届きます。',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/senavi.dart';
import '../../state/providers.dart';
import '../../ui/molecules/molecules.dart';

/// セナヴィに聞く。
///
/// 答えられるのは直近60分のレーダーと今日・明日の予報、現在地のハザードまで。
/// それ以外は「分からない」と言う ── 推測で補い始めると、災害の日に
/// 信用できなくなる。
void showAskSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: HinaColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: const _AskBody(),
    ),
  );
}

/// 最初に出す例。何を聞けるかが分からないと、人は何も聞かない。
const _examples = ['今日雨降る？', '傘いる？', 'ここって浸水する？', '明日は晴れる？'];

class _AskBody extends ConsumerStatefulWidget {
  const _AskBody();
  @override
  ConsumerState<_AskBody> createState() => _AskBodyState();
}

class _AskBodyState extends ConsumerState<_AskBody> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _log = <({bool mine, String text})>[];
  bool _asking = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String q) async {
    final question = q.trim();
    if (question.isEmpty || _asking) return;
    _ctrl.clear();
    setState(() {
      _log.add((mine: true, text: question));
      _asking = true;
    });
    _toBottom();
    try {
      final loc = ref.read(locationProvider) ?? await ref.read(locationProvider.notifier).refresh();
      final r = await ref.read(apiProvider).ask(question: question, lat: loc.point.latitude, lng: loc.point.longitude);
      if (mounted) setState(() => _log.add((mine: false, text: (r['answer'] ?? '') as String)));
    } catch (e) {
      // 繋がらないときに黙ると「無視された」に見える。状況を言う。
      if (mounted) setState(() => _log.add((mine: false, text: 'いまうまく調べられなかった。少し待ってもう一度聞いてみて')));
      debugPrint('[ask] failed: $e');
    } finally {
      if (mounted) setState(() => _asking = false);
      _toBottom();
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(HinaSpace.m, HinaSpace.m, HinaSpace.m, HinaSpace.s),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const SenaviAvatar(SenaviMood.normal, size: 40),
            const SizedBox(width: 10),
            Expanded(child: Text('セナヴィに聞く', style: t.titleLarge)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          ]),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('答えられるのは、いまの雨と今日・明日の天気、この場所のハザードまで。', style: t.bodySmall?.copyWith(color: HinaColors.inkSub)),
          ),
          const SizedBox(height: 12),
          if (_log.isEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final e in _examples) ActionChip(label: Text(e), onPressed: () => _ask(e))],
            )
          else
            Flexible(
              child: ListView.builder(
                controller: _scroll,
                shrinkWrap: true,
                itemCount: _log.length,
                itemBuilder: (_, i) => _Bubble(mine: _log[i].mine, text: _log[i].text),
              ),
            ),
          if (_asking)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Row(children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('調べてるね…')]),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLength: 100,
                textInputAction: TextInputAction.send,
                onSubmitted: _ask,
                decoration: const InputDecoration(hintText: '聞いてみる', counterText: '', border: OutlineInputBorder(), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _asking ? null : () => _ask(_ctrl.text), icon: const Icon(Icons.arrow_upward)),
          ]),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool mine;
  final String text;
  const _Bubble({required this.mine, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: mine ? HinaColors.sky : HinaColors.bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text, style: t.bodyMedium?.copyWith(color: mine ? Colors.white : HinaColors.ink, height: 1.5)),
      ),
    );
  }
}

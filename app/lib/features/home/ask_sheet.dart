import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/senavi.dart';
import '../../state/providers.dart';
import '../../ui/molecules/molecules.dart';

/// セナヴィに聞く。
///
/// **決まった問いだけを並べる。** 自由入力にすると、LLM は答えられない問いにも
/// それらしく答えてしまう ── 実際、避難場所を自由に聞いたときに付いてきた
/// 自治体の URL は4本中4本が404だった。
///
/// 代わりに、答えられる問いを最初から見せて、**答えの出どころも一緒に出す**。
void showAskSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: HinaColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _AskBody(),
  );
}

/// セナヴィが答えられること。サーバーの COMMANDS と対になっている。
const _commands = <({String id, String label, IconData icon})>[
  (id: 'rain', label: 'いま雨降ってる？', icon: Icons.water_drop_outlined),
  (id: 'weather', label: '今日の天気は？', icon: Icons.wb_cloudy_outlined),
  (id: 'hazard', label: 'ここは安全？', icon: Icons.shield_outlined),
  (id: 'shelters', label: '近くの避難場所は？', icon: Icons.home_work_outlined),
];

class _AskBody extends ConsumerStatefulWidget {
  const _AskBody();
  @override
  ConsumerState<_AskBody> createState() => _AskBodyState();
}

class _AskBodyState extends ConsumerState<_AskBody> {
  String? _asking;
  String? _question;
  String? _answer;
  List<({String name, String url})> _sources = const [];

  Future<void> _ask(({String id, String label, IconData icon}) c) async {
    if (_asking != null) return;
    setState(() {
      _asking = c.id;
      _question = c.label;
      _answer = null;
      _sources = const [];
    });
    try {
      final loc = ref.read(locationProvider) ?? await ref.read(locationProvider.notifier).refresh();
      final r = await ref.read(apiProvider).ask(command: c.id, lat: loc.point.latitude, lng: loc.point.longitude);
      if (!mounted) return;
      setState(() {
        _answer = (r['answer'] ?? '') as String;
        _sources = ((r['sources'] as List?) ?? const [])
            .map((e) => (name: (e['name'] ?? '') as String, url: (e['url'] ?? '') as String))
            .toList();
      });
    } catch (e) {
      // 繋がらないときに黙ると「無視された」に見える。状況を言う。
      if (mounted) setState(() => _answer = 'いまうまく調べられなかった。少し待ってもう一度押してみて');
      debugPrint('[ask] failed: $e');
    } finally {
      if (mounted) setState(() => _asking = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(HinaSpace.m, HinaSpace.m, HinaSpace.m, HinaSpace.m),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const SenaviAvatar(SenaviMood.normal, size: 40),
            const SizedBox(width: 10),
            Expanded(child: Text('セナヴィに聞く', style: t.titleLarge)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
          ]),
          const SizedBox(height: 4),
          Text('答えられることだけを並べています。答えの出どころも一緒に出します。',
              style: t.bodySmall?.copyWith(color: HinaColors.inkSub)),
          const SizedBox(height: 14),

          if (_question != null) ...[
            Align(alignment: Alignment.centerRight, child: _Bubble(mine: true, text: _question!)),
            const SizedBox(height: 6),
            if (_answer == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('調べてるね…'),
                ]),
              )
            else ...[
              _Bubble(mine: false, text: _answer!),
              if (_sources.isNotEmpty) ...[
                const SizedBox(height: 8),
                // 出典は LLM に書かせず、アプリが持っているものを出す。
                // 自分で書かせると、実在しない URL を本物らしく並べる。
                for (final s in _sources)
                  InkWell(
                    onTap: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        const Icon(Icons.open_in_new, size: 13, color: HinaColors.inkSub),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('出典: ${s.name}',
                              style: t.bodySmall?.copyWith(color: HinaColors.inkSub, decoration: TextDecoration.underline)),
                        ),
                      ]),
                    ),
                  ),
              ],
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
          ],

          Text('聞けること', style: t.bodySmall?.copyWith(color: HinaColors.inkSub)),
          const SizedBox(height: 8),
          for (final c in _commands)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                onPressed: _asking != null ? null : () => _ask(c),
                icon: Icon(c.icon, size: 18),
                label: Align(alignment: Alignment.centerLeft, child: Text(c.label)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  alignment: Alignment.centerLeft,
                  side: const BorderSide(color: HinaColors.line),
                  foregroundColor: HinaColors.ink,
                ),
              ),
            ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: mine ? HinaColors.sky : HinaColors.bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text, style: t.bodyMedium?.copyWith(color: mine ? Colors.white : HinaColors.ink, height: 1.5)),
      ),
    );
  }
}

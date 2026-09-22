import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../core/config.dart';
import '../../domain/senavi.dart';
import '../../state/providers.dart';
import '../../ui/molecules/molecules.dart';
import '../../core/user_message.dart';

enum _Tab { all, user, judge }

/// セナヴィの判断記録 — same timeline, three audiences (設計書 §17.5).
class AgentLogPage extends ConsumerStatefulWidget {
  final String? incidentId;
  const AgentLogPage({super.key, this.incidentId});
  @override
  ConsumerState<AgentLogPage> createState() => _AgentLogPageState();
}

class _AgentLogPageState extends ConsumerState<AgentLogPage> {
  _Tab tab = _Tab.all;
  @override
  Widget build(BuildContext context) {
    final latest = ref.watch(latestIncidentProvider).value;
    final id = widget.incidentId ?? latest?.id;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AgentLog')),
      body: id == null
          ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SenaviAvatar(SenaviMood.lying, size: 96),
              const SizedBox(height: 12),
              Text('まだ記録がありません。災害が起きるとここにセナヴィの判断が並びます。', textAlign: TextAlign.center, style: t.bodySmall),
            ])))
          : Column(children: [
              // 会場ビルドでは「◯◯向け」の絞り込みを出さない。触る人にとっては
              // 自分がどれなのか分からないうえ、全部出した方が情報は多い。
              if (!AppConfig.kiosk)
                Padding(
                  padding: const EdgeInsets.fromLTRB(HinaSpace.m, HinaSpace.s, HinaSpace.m, 0),
                  child: SegmentedButton<_Tab>(
                    segments: const [ButtonSegment(value: _Tab.all, label: Text('すべて')), ButtonSegment(value: _Tab.user, label: Text('ユーザー向け')), ButtonSegment(value: _Tab.judge, label: Text('審査員向け'))],
                    selected: {tab},
                    onSelectionChanged: (s) => setState(() => tab = s.first),
                    style: SegmentedButton.styleFrom(selectedBackgroundColor: HinaColors.mist, selectedForegroundColor: HinaColors.ink),
                  ),
                ),
              if (latest != null && latest.id == id)
                Padding(
                  padding: const EdgeInsets.fromLTRB(HinaSpace.m, HinaSpace.s, HinaSpace.m, 0),
                  child: Row(children: [
                    Expanded(child: Text('${latest.alertTitle}  /  ${latest.validatedBy == 'fallback' ? 'ルールで選定' : latest.validatedBy.contains('escalated') ? 'AI(昇格)+ルール' : 'AI+ルール'}', style: t.bodySmall)),
                    Text('\$${latest.costUsd.toStringAsFixed(4)} / LLM ${latest.llmCalls}回', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: HinaColors.ink)),
                  ]),
                ),
              Expanded(
                child: ref.watch(agentLogProvider(id)).when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text(userMessage(e, action: '記録を読み込み'))),
                      data: (all) {
                        final list = all.where((e) => tab == _Tab.all || (tab == _Tab.user ? e.forUser : e.forJudge)).toList();
                        if (list.isEmpty) return Center(child: Text('この表示に該当する記録はありません', style: t.bodySmall));
                        return ListView.separated(
                          padding: const EdgeInsets.only(bottom: 24, top: 4),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 58, endIndent: 16),
                          itemBuilder: (_, i) => AgentLogTile(list[i]),
                        );
                      },
                    ),
              ),
            ]),
    );
  }
}

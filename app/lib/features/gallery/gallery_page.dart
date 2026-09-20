import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../domain/senavi.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';

/// Dev-only catalogue of every widget in every state (設計書 §17.7 step 2). Compare side-by-side with the design sheet.
class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});
  @override
  Widget build(BuildContext context) {
    final shelter = ShelterInfo(id: 'x', name: '南行徳小学校', address: '千葉県市川市南行徳1-1', point: const LatLng(35.66, 139.9), walkMin: 8, distanceM: 550, elevationM: 1.2, crowdPct: 30);
    final reasons = const ['広域避難場所', '浸水想定なし', '混雑30%'];
    return Scaffold(
      appBar: AppBar(title: const Text('Widget ギャラリー')),
      body: ListView(padding: const EdgeInsets.all(HinaSpace.m), children: [
        const SectionHeader('Buttons'),
        const HinaButton.primary('メインボタン'), const SizedBox(height: 8),
        const HinaButton.secondary('サブボタン'), const SizedBox(height: 8),
        const HinaButton.danger('警告ボタン'), const SizedBox(height: 8),
        const HinaButton.ghost('ゴースト'), const SizedBox(height: 8),
        const HinaButton.primary('無効', onPressed: null), const SizedBox(height: 8),
        CountdownButton(label: 'このルートで行く', seconds: 30, onTap: () {}, onTimeout: () {}),
        const SectionHeader('StatusChip (5)'),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final s in PublicStatus.values) StatusChip(s)]),
        const SectionHeader('セナヴィの表情'),
        Wrap(spacing: 12, runSpacing: 12, children: [for (final m in SenaviMood.values) Column(mainAxisSize: MainAxisSize.min, children: [SenaviAvatar(m, size: 64), Text(m.name, style: const TextStyle(fontSize: 11))])]),
        const SectionHeader('SenaviSpeech'),
        for (final s in [IncidentState.idle, IncidentState.assessing, IncidentState.proposing, IncidentState.guiding, IncidentState.reselecting, IncidentState.arrived, IncidentState.fallbackGuiding, IncidentState.offline])
          Padding(padding: const EdgeInsets.only(bottom: 8), child: HinaCard(child: SenaviSpeech(mood: moodFor(s), text: lineFor(s, shelter: '南行徳小学校', walkMin: 8, weather: '晴れ'), sub: s.name))),
        const SectionHeader('ShelterCard'),
        ShelterCard(shelter: shelter, reasons: reasons, header: 'セナヴィが安全な場所を選びました', onDetail: () {}, actions: const HinaButton.primary('ここへ行く', icon: Icons.navigation_outlined)),
        const SizedBox(height: 8),
        ShelterCard(shelter: shelter, reasons: reasons, remainingMin: 5, compact: true, actions: Row(children: const [Expanded(child: HinaButton.primary('到着した', icon: Icons.check)), SizedBox(width: 8), Expanded(child: HinaButton.secondary('別の場所へ'))])),
        const SectionHeader('CrowdMeter'),
        const CrowdMeter(30), const SizedBox(height: 6), const CrowdMeter(65), const SizedBox(height: 6), const CrowdMeter(95),
        const SectionHeader('AlertBanner'),
        const AlertBanner(title: '地震が発生しました(震度6弱)', subtitle: '避難が必要です'),
        const SectionHeader('FriendTile'),
        for (final (i, s) in PublicStatus.values.indexed)
          FriendTile(friend: FriendEntry(uid: '$i', displayName: ['お母さん', 'ゆうた', 'さくら', 'たくみ', 'まい', 'けん'][i], relation: ['家族', '友人', '同僚', '同僚', '友人', '友人'][i], autoShare: true), status: FriendStatus(state: s, shelterName: s == PublicStatus.evacuating || s == PublicStatus.arrived ? '〇〇小学校' : null, note: s == PublicStatus.unknown ? '応答なし' : null, updatedAt: DateTime.now())),
        const SectionHeader('AgentLogTile'),
        for (final (i, k) in LogKind.values.indexed)
          AgentLogTile(AgentLogEntry(seq: i, at: DateTime.now(), kind: k, title: 'サンプル: ${k.name}', detail: '一行要約がここに入ります。タップで展開。', model: k == LogKind.llmResponse ? 'openai/gpt-4o-mini' : null, costUsd: k == LogKind.llmResponse ? 0.0026 : null, latencyMs: k == LogKind.llmResponse ? 812 : null, payload: k == LogKind.llmRequest ? {'areaName': '千葉県市川市', 'candidates': [{'id': 'A', 'walkMin': 8}]} : null)),
        const SectionHeader('HazardLegend / DemoBand'),
        const Align(alignment: Alignment.centerLeft, child: HazardLegend(flood: true, tsunami: true, landslide: true)),
        const SizedBox(height: 8),
        const DemoBand(),
        const SizedBox(height: 40),
      ]),
    );
  }
}

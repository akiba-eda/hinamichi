import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../core/config.dart';
import '../../domain/models.dart';
import '../../domain/senavi.dart';
import '../../state/providers.dart';
import '../../ui/organisms/location_unavailable.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';
import '../../ui/organisms/hina_map.dart';
import '../friends/friend_detail_sheet.dart';
import '../shelter/shelter_detail_page.dart';

/// マップ(デザイン書 シート3 のボトムナビ / 設計書 §17.3)。
///
/// 近隣情報。
///
/// ホームは「いま何が起きているか」と日常のやりとりの場所。こちらは
/// **平時に、自分の土地のことを知るための画面**にしている ── 自宅が浸水想定に
/// 入っているか、近くのどこへ逃げればいいかを、何も起きていない日に眺められる。
///
/// 友だち・合流・雨雲はホームに集約したので、ここには出さない。
/// 同じものが2画面にあると、どちらを見ればいいのか分からなくなる。
class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  final _map = MapController();
  String? _highlighted;

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(locationProvider);
    final nearby = ref.watch(nearbyProvider);
    final demo = ref.watch(demoProvider);
    final type = ref.watch(mapDisasterTypeProvider);
    // ホームと同じく、位置が無いときに既定地点へ寄せない。
    if (loc == null) return const LocationUnavailableView();
    final here = loc.point;
    final shelters = nearby.value?.shelters ?? const <ShelterInfo>[];
    ShelterInfo? highlighted;
    for (final s in shelters) {
      if (s.id == _highlighted) highlighted = s;
    }

    // 詳細シートの「地図で見る」から来た指定を拾って寄せる。使い捨て。
    final focus = ref.watch(mapFocusProvider);
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _map.move(focus, 16);
        ref.read(mapFocusProvider.notifier).state = null;
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('近隣情報'),
        actions: [
          IconButton(
            tooltip: '現在地',
            onPressed: () async {
              final r = await ref.read(locationProvider.notifier).refresh();
              _map.move(r.point, 15);
            },
            icon: const HinaIconView(HinaIcon.locate, size: 22, color: HinaColors.ink),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.42,
          child: Stack(children: [
            Positioned.fill(
              child: HinaMap(
                controller: _map,
                center: here,
                shelters: shelters,
                // 合流の旗はここにも出す。近隣情報から避難所を眺めているときに
                // 「どこで落ち合う約束だったか」が消えると、選び直しの判断ができない。
                meetup: ref.watch(meetupProvider),
                selected: highlighted,
                showFlood: demo.showFlood,
                showTsunami: demo.showTsunami,
                showLandslide: demo.showLandslide,
                mood: SenaviMood.normal,
                basemap: ref.watch(basemapProvider),
                onShelterTap: _open,
              ),
            ),
            Positioned(
              top: HinaSpace.s,
              left: HinaSpace.m,
              child: DisasterTypeSelector(
                selected: type,
                shelterCount: nearby.value?.shelters.length,
                onChanged: (d) {
                  ref.read(mapDisasterTypeProvider.notifier).state = d;
                  ref.read(demoProvider.notifier).setLayers(flood: d != DisasterType.earthquake, tsunami: d == DisasterType.tsunami);
                },
              ),
            ),
            Positioned(
              right: HinaSpace.m,
              bottom: HinaSpace.s,
              child: HazardLegend(flood: demo.showFlood, tsunami: demo.showTsunami, landslide: demo.showLandslide),
            ),
          ]),
        ),
        // 何も起きていない日に開く画面なので、まず「自分の場所はどうなのか」を出す。
        // 避難場所の一覧だけだと、自分に関係のある情報にならない。
        if (nearby.value?.hazard != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(HinaSpace.m, HinaSpace.s, HinaSpace.m, 0),
            child: _HereHazard(nearby.value!.hazard!),
          ),
        Expanded(
          child: nearby.when(
            loading: () => const Center(child: CircularProgressIndicator(color: HinaColors.sky)),
            error: (e, _) => _Empty(mood: SenaviMood.troubled, text: '周辺の避難場所を取得できませんでした。\n設定の API サーバーを確認してね。'),
            data: (d) {
              if (d.shelters.isEmpty) {
                return _Empty(mood: SenaviMood.lying, text: 'この辺りの避難場所が見つからなかったよ。\n場所を移動して試してみて。');
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: d.shelters.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: HinaSpace.m, endIndent: HinaSpace.m),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    // 見出しに災害種別を入れる。切り替えても「周辺の避難場所」のままだと、
                    // 件数と顔ぶれが変わったこと自体に気づけない。
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SectionHeader(type.shelterHeading, trailing: Text('${d.shelters.length}件', style: Theme.of(context).textTheme.bodySmall)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(HinaSpace.m, 0, HinaSpace.m, HinaSpace.s),
                        child: Text(type.shelterNote, style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ]);
                  }
                  return _ShelterRow(shelter: d.shelters[i - 1], onTap: _open);
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  void _open(ShelterInfo s) {
    setState(() => _highlighted = s.id);
    _map.move(s.point, 16);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShelterDetailPage(shelter: s)));
  }
}

class _ShelterRow extends StatelessWidget {
  final ShelterInfo shelter;
  final ValueChanged<ShelterInfo> onTap;
  const _ShelterRow({required this.shelter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onTap(shelter),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HinaSpace.m, vertical: 12),
        child: Row(children: [
          HinaIconView(HinaIcon.shelter, size: 26, color: shelter.full ? HinaColors.stUnknown : HinaColors.sky),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shelter.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('徒歩 ${shelter.walkMin}分 (約${shelter.distanceM}m)', style: t.bodySmall),
              const SizedBox(height: 6),
              Row(children: [
                if (shelter.full) ...[const HinaTag('満員', color: HinaColors.alert), const SizedBox(width: 6)],
                if (shelter.elevationM != null) HinaTag('標高 ${shelter.elevationM!.toStringAsFixed(0)}m'),
                const Spacer(),
                SizedBox(width: 118, child: CrowdMeter(shelter.crowdPct)),
              ]),
            ]),
          ),
          const Icon(Icons.chevron_right, color: HinaColors.inkSub),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final SenaviMood mood;
  final String text;
  const _Empty({required this.mood, required this.text});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(HinaSpace.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SenaviAvatar(mood, size: 96),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}

/// いまいる場所のハザード。平時にこれを見て「うちは浸水想定なんだ」と
/// 知ってもらうのが、この画面を置いている理由。
class _HereHazard extends StatelessWidget {
  final HazardHere hz;
  const _HereHazard(this.hz);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final risks = <String>[
      if (hz.flood > 0) '浸水 ${hz.floodLabel}',
      if (hz.tsunami > 0) '津波想定あり',
      if (hz.landslide) '土砂災害警戒区域',
    ];
    final safe = risks.isEmpty;
    return HinaCard(
      color: safe ? HinaColors.surface : HinaColors.alert.withValues(alpha: 0.08),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Icon(safe ? Icons.check_circle_outline : Icons.info_outline,
            color: safe ? HinaColors.stArrived : HinaColors.alert, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('いまいる場所', style: t.bodySmall?.copyWith(color: HinaColors.inkSub)),
            Text(safe ? '想定区域には入っていません' : risks.join(' / '), style: t.titleMedium),
          ]),
        ),
      ]),
    );
  }
}

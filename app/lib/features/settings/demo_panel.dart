import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../mock/mock_backend.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';

/// 設計書 §14.2 — fire scenarios anchored at the device's current location; simulate movement; inject LLM failure.
class DemoPanel extends ConsumerStatefulWidget {
  const DemoPanel({super.key});
  @override
  ConsumerState<DemoPanel> createState() => _DemoPanelState();
}

class _DemoPanelState extends ConsumerState<DemoPanel> {
  String? busy;
  Timer? _mover;

  @override
  void dispose() {
    _mover?.cancel();
    super.dispose();
  }

  Future<void> _run(String key, Future<void> Function() f) async {
    setState(() => busy = key);
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Future<void> _fire(String scenario) => _run(scenario, () async {
        ref.read(agentBusyProvider.notifier).state = true;
        try {
          final loc = await ref.read(locationProvider.notifier).refresh();
          if (ref.read(mockModeProvider)) {
            await ref.read(mockBackendProvider.notifier).fire(DisasterType.parse(scenario), loc.point);
          } else {
            await ref.read(apiProvider).demoFire(scenario: scenario, lat: loc.point.latitude, lng: loc.point.longitude, locationSource: loc.source, failLlm: ref.read(demoProvider).failLlm);
          }
        } finally {
          ref.read(agentBusyProvider.notifier).state = false;
        }
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });

  Future<void> _crowdFull() => _run('crowd', () async {
        final inc = ref.read(activeIncidentProvider);
        if (inc?.shelter == null) throw '避難誘導中ではありません';
        final loc = ref.read(locationProvider) ?? await ref.read(locationProvider.notifier).refresh();
        if (ref.read(mockModeProvider)) {
          ref.read(mockBackendProvider.notifier).markFull(loc.point);
        } else {
          await ref.read(apiProvider).demoCrowd(shelterId: inc!.shelter!.id, full: true, lat: loc.point.latitude, lng: loc.point.longitude, locationSource: loc.source);
        }
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });

  Future<void> _friends(String action) async {
    if (ref.read(mockModeProvider)) {
      final b = ref.read(mockBackendProvider.notifier);
      if (action == 'advance') {
        final loc = ref.read(locationProvider) ?? await ref.read(locationProvider.notifier).refresh();
        b.advanceFriends(loc.point);
      } else {
        b.seedFriendsAtRest();
      }
      return;
    }
    await ref.read(apiProvider).demoFriends(action);
  }

  Future<void> _simulateArrival() async {
    if (!ref.read(mockModeProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('モックモードのときだけ動きます')));
      return;
    }
    final loc = ref.read(locationProvider) ?? await ref.read(locationProvider.notifier).refresh();
    final b = ref.read(mockBackendProvider.notifier)..seedPlaces(loc.point);
    b.simulateArrival('mock_mother');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('友だち画面の「できごと」に出ます')));
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  void _cycleWeather() {
    if (!ref.read(mockModeProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('モックモードのときだけ切り替えられます')));
      return;
    }
    ref.read(mockBackendProvider.notifier).cycleWeather();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _reset() async {
    if (ref.read(mockModeProvider)) {
      ref.read(mockBackendProvider.notifier)
        ..close()
        ..seedFriendsAtRest();
      return;
    }
    await ref.read(apiProvider).demoReset();
  }

  void _simulateMove() {
    final inc = ref.read(activeIncidentProvider);
    final pts = inc?.route?.points;
    if (inc == null || pts == null || pts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('経路がありません(避難誘導中に使ってください)')));
      return;
    }
    _mover?.cancel();
    final samples = _resample(pts, 12);
    var i = 0;
    _mover = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (i >= samples.length) { t.cancel(); return; }
      final p = samples[i++];
      ref.read(locationProvider.notifier).simulate(p);
      try { await ref.read(agentControllerProvider).reportPosition(inc.id, p); } catch (_) {}
    });
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  List<LatLng> _resample(List<LatLng> pts, int n) {
    const d = Distance();
    final total = [for (var i = 1; i < pts.length; i++) d(pts[i - 1], pts[i])].fold<double>(0, (a, b) => a + b);
    final out = <LatLng>[];
    for (var k = 1; k <= n; k++) {
      var target = total * k / n, acc = 0.0;
      for (var i = 1; i < pts.length; i++) {
        final seg = d(pts[i - 1], pts[i]);
        if (acc + seg >= target || i == pts.length - 1) {
          final f = seg == 0 ? 0.0 : ((target - acc) / seg).clamp(0.0, 1.0);
          out.add(LatLng(pts[i - 1].latitude + (pts[i].latitude - pts[i - 1].latitude) * f, pts[i - 1].longitude + (pts[i].longitude - pts[i - 1].longitude) * f));
          break;
        }
        acc += seg;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final demo = ref.watch(demoProvider);
    final t = Theme.of(context).textTheme;
    Widget tile(String key, String label, Color color, IconData icon, VoidCallback onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: FilledButton.icon(
              onPressed: busy != null ? null : onTap,
              style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              icon: busy == key ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(icon, size: 18),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        );
    return HinaCard(
      color: const Color(0xFFFFF6D6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('発火する災害(現在地を基準に生成)', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: HinaColors.ink)),
        const SizedBox(height: 6),
        Row(children: [
          tile('earthquake', '地震', const Color(0xFFE57373), Icons.vibration, () => _fire('earthquake')),
          tile('heavy_rain', '豪雨', const Color(0xFF5AA8D6), Icons.water_drop_outlined, () => _fire('heavy_rain')),
        ]),
        Row(children: [
          tile('tsunami', '津波', const Color(0xFF26A69A), Icons.waves, () => _fire('tsunami')),
          tile('crowd', '満員(避難所)', const Color(0xFF8E7CC3), Icons.groups, _crowdFull),
        ]),
        Row(children: [
          tile('move', '移動シミュレーション', const Color(0xFF7FB366), Icons.directions_walk, _simulateMove),
          // 平時のセナヴィの一言(雨雲ナウキャスト)を順に見せるため。
          tile('weather', '天気を切り替え', const Color(0xFF5AA8D6), Icons.cloud_outlined, _cycleWeather),
        ]),
        Row(children: [
          // 平時の「着いたよ」。災害時の避難所到着と同じ仕組みで動く。
          tile('arrive', 'お母さんが自宅に到着', const Color(0xFF8E7CC3), Icons.home_outlined, _simulateArrival),
        ]),
        const Divider(),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('位置を南行徳に固定(リハーサル用)'), value: demo.overrideLocation, onChanged: (v) => ref.read(demoProvider.notifier).setOverride(v)),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('LLM 障害を注入(フォールバック実演)'), value: demo.failLlm, onChanged: (v) => ref.read(demoProvider.notifier).setFailLlm(v)),
        const Divider(),
        Text('フレンド(モック)', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: HinaColors.ink)),
        Row(children: [
          Expanded(child: HinaButton.secondary('追加', onPressed: () => _run('seed', () => _friends('seed')))),
          const SizedBox(width: 6),
          Expanded(child: HinaButton.secondary('状態を進める', onPressed: () => _run('adv', () => _friends('advance')))),
          const SizedBox(width: 6),
          Expanded(child: HinaButton.secondary('戻す', onPressed: () => _run('rst', () => _friends('reset')))),
        ]),
        const SizedBox(height: 8),
        HinaButton.ghost('リセット(インシデント・混雑・状態)', icon: Icons.restart_alt, onPressed: () => _run('reset', _reset)),
        const SizedBox(height: HinaSpace.xs),
      ]),
    );
  }
}

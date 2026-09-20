import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme/hina_colors.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../domain/senavi.dart';
import '../../state/providers.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';
import '../../ui/organisms/hina_map.dart';
import '../agent_log/agent_log_page.dart';
import '../shelter/shelter_detail_page.dart';
import 'approval_sheet.dart';

/// Home = one map. Peacetime, proposal (03), guidance (04) and arrival are states layered on top.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _map = MapController();
  Timer? _positionTimer;
  String? _fittedFor;
  IncidentState? _lastState;
  bool _acting = false;

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  void _syncTimers(Incident? inc) {
    final guiding = inc != null && inc.state.isGuiding;
    if (guiding && _positionTimer == null) {
      _positionTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        final loc = ref.read(locationProvider);
        if (loc == null || inc.shelter == null) return;
        try {
          await ref.read(agentControllerProvider).reportPosition(inc.id, loc.point);
        } catch (_) {}
      });
    } else if (!guiding) {
      _positionTimer?.cancel();
      _positionTimer = null;
    }
  }

  void _fitRoute(Incident inc, LatLng here) {
    if (inc.shelter == null || _fittedFor == '${inc.id}:${inc.shelter!.id}') return;
    _fittedFor = '${inc.id}:${inc.shelter!.id}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pts = inc.route?.points.isNotEmpty == true ? inc.route!.points : [here, inc.shelter!.point];
      _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.fromLTRB(40, 120, 40, 320)));
    });
  }

  Future<void> _act(Future<void> Function() f) async {
    setState(() => _acting = true);
    try {
      await f();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(locationProvider);
    final inc = ref.watch(activeIncidentProvider);
    final state = ref.watch(incidentStateProvider);
    final senavi = ref.watch(senaviProvider);
    final demo = ref.watch(demoProvider);
    final nearby = ref.watch(nearbyProvider);
    final myStatus = ref.watch(myStatusProvider).value ?? FriendStatus.unknown;
    final here = loc?.point ?? const LatLng(35.6588, 139.9013);

    _syncTimers(inc);
    if (inc != null && (inc.state == IncidentState.proposing || inc.state.isGuiding)) _fitRoute(inc, here);
    if (_lastState != null && _lastState != IncidentState.reselecting && state == IncidentState.reselecting) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showRerouteToast(context, lineFor(IncidentState.reselecting)));
    }
    _lastState = state;

    final shelters = inc?.shelter != null && (inc!.state == IncidentState.proposing || inc.state.isGuiding || inc.state.isFinished) ? <ShelterInfo>[inc.shelter!] : (nearby.value?.shelters ?? const <ShelterInfo>[]);

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: HinaMap(
            controller: _map,
            center: here,
            shelters: shelters,
            selected: inc?.shelter,
            route: inc?.route?.points ?? const [],
            showFlood: demo.showFlood,
            showTsunami: demo.showTsunami || inc?.type == DisasterType.tsunami,
            showLandslide: demo.showLandslide,
            mood: senavi.mood,
            onShelterTap: (s) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShelterDetailPage(shelter: s, incident: inc))),
          ),
        ),
        // Top chrome
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            bottom: false,
            child: Column(children: [
              if (demo.enabled) const DemoBand(),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  _RoundButton(icon: Icons.my_location, onTap: () async {
                    final r = await ref.read(locationProvider.notifier).refresh();
                    _map.move(r.point, 15);
                  }),
                  const SizedBox(width: 8),
                  if (state == IncidentState.idle) _TypeSelector(),
                  const Spacer(),
                  StatusChip(myStatus.state),
                ]),
              ),
              if (inc != null && (inc.state == IncidentState.proposing || inc.state.isGuiding || state == IncidentState.assessing))
                Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: AlertBanner(title: inc.alertTitle.isEmpty ? '災害情報を確認中' : inc.alertTitle, subtitle: inc.state == IncidentState.proposing ? '避難が必要です' : (inc.state.isGuiding ? '避難中' : null))),
            ]),
          ),
        ),
        Positioned(right: 12, bottom: 300, child: HazardLegend(flood: demo.showFlood, tsunami: demo.showTsunami || inc?.type == DisasterType.tsunami, landslide: demo.showLandslide)),
        // Bottom sheet
        Positioned(left: 0, right: 0, bottom: 0, child: _sheet(context, inc, state, senavi, nearby)),
      ]),
    );
  }

  Widget _sheet(BuildContext context, Incident? inc, IncidentState state, ({SenaviMood mood, String line}) senavi, AsyncValue nearby) {
    final ctrl = ref.read(agentControllerProvider);
    Widget body;
    if (state == IncidentState.assessing) {
      body = HinaCard(child: Column(children: [
        SenaviSpeech(mood: senavi.mood, text: senavi.line, sub: '災害情報・現在地のハザード・避難場所を照らし合わせています'),
        const SizedBox(height: 12),
        const LinearProgressIndicator(minHeight: 4, color: HinaColors.sky, backgroundColor: HinaColors.line),
      ]));
    } else if (inc != null && inc.state == IncidentState.proposing && inc.shelter != null) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        HinaCard(child: SenaviSpeech(mood: senavi.mood, text: senavi.line, avatarSize: 52)),
        const SizedBox(height: 8),
        ShelterCard(
          shelter: inc.shelter!,
          reasons: inc.reasons,
          header: inc.validatedBy == 'fallback' ? 'セナヴィが安全ルールで選びました' : 'セナヴィが安全な場所を選びました',
          onDetail: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShelterDetailPage(shelter: inc.shelter!, incident: inc))),
          actions: Column(children: [
            CountdownButton(
              key: ValueKey('cd_${inc.id}_${inc.shelter!.id}'),
              label: 'このルートで行く',
              seconds: 30,
              loading: _acting,
              onTap: () => _act(() => ctrl.approveStart(inc.id, byTimeout: false)),
              onTimeout: () => _act(() => ctrl.approveStart(inc.id, byTimeout: true)),
            ),
            const SizedBox(height: 6),
            HinaButton.ghost('あとで確認する', onPressed: _acting ? null : () => _act(() => ctrl.later(inc.id))),
          ]),
        ),
      ]);
    } else if (inc != null && inc.state.isGuiding && inc.shelter != null) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        HinaCard(child: SenaviSpeech(mood: senavi.mood, text: senavi.line, avatarSize: 52)),
        const SizedBox(height: 8),
        ShelterCard(
          shelter: inc.shelter!,
          reasons: inc.reasons,
          remainingMin: inc.remainingMin,
          compact: true,
          onDetail: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShelterDetailPage(shelter: inc.shelter!, incident: inc))),
          actions: Row(children: [
            Expanded(child: HinaButton.primary('到着した', icon: Icons.check, loading: _acting, onPressed: () => _act(() => ctrl.arrived(inc.id)))),
            const SizedBox(width: 8),
            Expanded(child: HinaButton.secondary('別の場所へ', onPressed: _acting ? null : () => _act(() async { await ctrl.reselect(inc.id, reason: 'user'); }))),
            const SizedBox(width: 8),
            _RoundButton(icon: Icons.chat_bubble_outline, onTap: () => showApprovalSheet(context, ref, incidentId: inc.id)),
          ]),
        ),
      ]);
    } else if (inc != null && inc.state.isFinished) {
      body = HinaCard(child: Column(children: [
        SenaviSpeech(mood: senavi.mood, text: senavi.line, sub: inc.shelter != null ? '${inc.shelter!.name} / 同意済みの家族・友人に共有しました' : null),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: HinaButton.secondary('判断の記録を見る', icon: Icons.receipt_long_outlined, onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AgentLogPage(incidentId: inc.id))))),
          const SizedBox(width: 8),
          Expanded(child: HinaButton.primary('ホームに戻る', onPressed: () => _act(() => ctrl.close(inc.id)))),
        ]),
      ]));
    } else if (inc != null && (inc.state == IncidentState.monitoringStay || inc.state == IncidentState.notRelevant)) {
      body = HinaCard(child: Column(children: [
        SenaviSpeech(mood: senavi.mood, text: senavi.line, sub: inc.reasons.join(' / ')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: HinaButton.secondary('判断の記録', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AgentLogPage(incidentId: inc.id))))),
          const SizedBox(width: 8),
          Expanded(child: HinaButton.primary('了解', onPressed: () => _act(() => ctrl.close(inc.id)))),
        ]),
      ]));
    } else {
      final hz = nearby.value?.hazard as HazardHere?;
      final sub = hz == null ? '現在地周辺の避難場所とハザードを表示しています' : 'この場所: 浸水 ${hz.floodLabel}${hz.landslide ? ' / 土砂警戒' : ''}${hz.tsunami > 0 ? ' / 津波想定' : ''}';
      body = HinaCard(child: SenaviSpeech(mood: senavi.mood, text: senavi.line, sub: sub));
    }
    return SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(HinaSpace.m, 0, HinaSpace.m, HinaSpace.s), child: body));
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: HinaColors.surface,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: Colors.black26,
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 44, height: 44, child: Icon(icon, color: HinaColors.ink, size: 22))),
      );
}

class _TypeSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(mapDisasterTypeProvider);
    return Container(
      decoration: BoxDecoration(color: HinaColors.surface, borderRadius: BorderRadius.circular(22), boxShadow: HinaShadow.card),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final d in [DisasterType.earthquake, DisasterType.flood, DisasterType.tsunami])
          GestureDetector(
            onTap: () {
              ref.read(mapDisasterTypeProvider.notifier).state = d;
              ref.read(demoProvider.notifier).setLayers(flood: d != DisasterType.earthquake, tsunami: d == DisasterType.tsunami);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: t == d ? HinaColors.mist : Colors.transparent, borderRadius: BorderRadius.circular(18)),
              child: Text(d.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: t == d ? HinaColors.ink : HinaColors.inkSub)),
            ),
          ),
      ]),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme/hina_colors.dart';
import '../../core/config.dart';
import '../../app/theme/hina_theme.dart';
import '../../domain/models.dart';
import '../../domain/senavi.dart';
import '../../domain/weather.dart';
import '../../domain/social.dart';
import '../../state/providers.dart';
import '../../ui/organisms/location_unavailable.dart';
import '../sos/sos_sheet.dart';
import 'ask_sheet.dart';
import '../../ui/atoms/atoms.dart';
import '../../ui/molecules/molecules.dart';
import '../../ui/organisms/hina_map.dart';
import '../agent_log/agent_log_page.dart';
import '../friends/friend_detail_sheet.dart';
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
    final Incident? guiding = (inc != null && inc.state.isGuiding) ? inc : null;
    if (guiding != null && _positionTimer == null) {
      _positionTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        final loc = ref.read(locationProvider);
        if (loc == null || guiding.shelter == null) return;
        try {
          await ref.read(agentControllerProvider).reportPosition(guiding.id, loc.point);
        } catch (_) {}
      });
    } else if (guiding == null) {
      _positionTimer?.cancel();
      _positionTimer = null;
    }
  }

  void _fitRoute(Incident inc, LatLng here) {
    if (inc.shelter == null) return;
    final key = '${inc.id}:${inc.shelter!.id}';
    if (_fittedFor == key) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = MediaQuery.sizeOf(context).height;
      // 画面より大きい padding を渡すと可視領域が負になり、ズームが NaN になって
      // タイルが一枚も引けなくなる(地図が背景色のまま灰色になる)。画面高に対する
      // 割合で頭を押さえる。
      final top = math.min(120.0, h * 0.15);
      final bottom = math.min(320.0, h * 0.40);
      final pts = inc.route?.points.isNotEmpty == true ? inc.route!.points : [here, inc.shelter!.point];
      try {
        _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: EdgeInsets.fromLTRB(40, top, 40, bottom)));
        // 成功したときだけ覚える。失敗を覚えると二度と合わせ直せない。
        _fittedFor = key;
      } catch (e) {
        debugPrint('[Home] fitCamera failed, will retry next frame: $e');
      }
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
    final rainOn = ref.watch(rainOverlayProvider);
    final myStatus = ref.watch(myStatusProvider).value ?? FriendStatus.unknown;
    // 位置が取れていないときは、地図を描かずにそう言う。既定地点に寄せると
    // 「あなたはここにいます」と宣言したことになり、そこの避難所を案内してしまう。
    if (loc == null) return const LocationUnavailableView();
    final here = loc.point;

    _syncTimers(inc);
    if (inc != null && (inc.state == IncidentState.proposing || inc.state.isGuiding)) _fitRoute(inc, here);
    if (_lastState != null && _lastState != IncidentState.reselecting && state == IncidentState.reselecting) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showRerouteToast(context, lineFor(IncidentState.reselecting)));
    }
    _lastState = state;

    final shelters = inc?.shelter != null && (inc!.state == IncidentState.proposing || inc.state.isGuiding || inc.state.isFinished) ? <ShelterInfo>[inc.shelter!] : (nearby.value?.shelters ?? const <ShelterInfo>[]);

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
      body: Stack(children: [
        Positioned.fill(
          child: HinaMap(
            controller: _map,
            center: here,
            shelters: shelters,
            selected: inc?.shelter,
            // 災害中は避難経路。平時は合流地点までの道案内を出す。
            route: inc?.route?.points ?? ref.watch(meetupRouteProvider).value?.points ?? const [],
            showFlood: demo.showFlood,
            showTsunami: demo.showTsunami || inc?.type == DisasterType.tsunami,
            showLandslide: demo.showLandslide,
            rain: ref.watch(rainFrameProvider).value,
            mood: senavi.mood,
            basemap: ref.watch(basemapProvider),
            friends: ref.watch(friendsOnMapProvider),
            onFriendTap: (f) => showFriendDetail(context, f),
            meetup: ref.watch(meetupProvider),
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
              // 届いた通報依頼は何より先に出す。埋もれたら意味が無い。
              for (final sos in ref.watch(incomingSosProvider).value ?? const <SosRequest>[])
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _SosBanner(sos: sos, onTap: () => showSosSheet(context, sos)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  _RoundButton(icon: HinaIcon.locate, onTap: () async {
                    final r = await ref.read(locationProvider.notifier).refresh();
                    _map.move(r.point, 15);
                  }),
                  const SizedBox(width: 8),
                  // 雨雲は見たい時にすぐ出せないと意味がないので、設定ではなくここに置く。
                  _RoundButton(
                    icon: HinaIcon.rain,
                    active: rainOn,
                    onTap: () => ref.read(rainOverlayProvider.notifier).state = !rainOn,
                  ),
                  const SizedBox(width: 8),
                  if (state == IncidentState.idle)
                    DisasterTypeSelector(
                      selected: ref.watch(mapDisasterTypeProvider),
                      onChanged: (d) {
                        ref.read(mapDisasterTypeProvider.notifier).state = d;
                        ref.read(demoProvider.notifier).setLayers(flood: d != DisasterType.earthquake, tsunami: d == DisasterType.tsunami);
                      },
                    ),
                  const Spacer(),
                  if (inc != null && inc.state.isActive)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _SosButton(incident: inc),
                    ),
                  StatusChip(myStatus.state),
                ]),
              ),
              if (inc != null && (inc.state == IncidentState.proposing || inc.state.isGuiding || state == IncidentState.assessing))
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: AlertBanner(
                    title: inc.alertTitle.isEmpty ? '災害情報を確認中' : inc.alertTitle,
                    // 強い揺れ・津波のあいだは、この帯にも身の安全を出す。
                    subtitle: inc.needsImmediateSafety && !inc.state.isGuiding
                        ? (inc.hasTsunamiWarning ? '海や川から離れ、高い場所へ移動してください' : '頭を守り、揺れが収まるまで動かないでください')
                        : (inc.state == IncidentState.proposing ? '避難が必要です' : (inc.state.isGuiding ? '避難中' : null)),
                  ),
                ),
            ]),
          ),
        ),
        // 雨雲を出している間はハザードを重ねないので、凡例も入れ替える。
        Positioned(
          right: 12,
          bottom: 300,
          child: rainOn
              ? RainLegend(at: ref.watch(rainFrameProvider).value?.at)
              : HazardLegend(flood: demo.showFlood, tsunami: demo.showTsunami || inc?.type == DisasterType.tsunami, landslide: demo.showLandslide),
        ),
        // Bottom sheet
        Positioned(left: 0, right: 0, bottom: 0, child: _sheet(context, inc, state, senavi, nearby)),
      ]),
    );
  }

  Widget _sheet(BuildContext context, Incident? inc, IncidentState state, ({SenaviMood mood, String line}) senavi, AsyncValue<({List<ShelterInfo> shelters, HazardHere? hazard})> nearby) {
    final ctrl = ref.read(agentControllerProvider);
    Widget body;
    if (state == IncidentState.assessing) {
      // 揺れている最中や津波警報下では、避難先を探していることより
      // 「まず身の安全」を先に伝える。行動の順序が逆になると危ない。
      final safety = inc == null
          ? null
          : immediateSafetyFor(tsunami: inc.hasTsunamiWarning, strongShaking: inc.isStrongShaking, intensityLabel: inc.intensityLabel);
      body = HinaCard(child: Column(children: [
        SenaviSpeech(
          mood: safety?.mood ?? senavi.mood,
          text: safety?.line ?? senavi.line,
          sub: safety?.sub ?? '災害情報・現在地のハザード・避難場所を照らし合わせています',
        ),
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
            _RoundButton(icon: HinaIcon.chat, onTap: () => showApprovalSheet(context, ref, incidentId: inc.id)),
          ]),
        ),
      ]);
    } else if (inc != null && inc.state.isFinished) {
      body = HinaCard(child: Column(children: [
        SenaviSpeech(mood: senavi.mood, text: senavi.line, sub: inc.shelter != null ? '${inc.shelter!.name} / 同意済みの家族・友人に共有しました' : null),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: HinaButton.secondary('判断の記録', icon: Icons.receipt_long_outlined, onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AgentLogPage(incidentId: inc.id))))),
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
      // 平時。雨に動きがあるときはそれを補足に出し、無ければこの場所のハザードに譲る。
      final hz = nearby.value?.hazard;
      final hazardSub = hz == null ? '現在地周辺の避難場所とハザードを表示しています' : 'この場所: 浸水 ${hz.floodLabel}${hz.landslide ? ' / 土砂警戒' : ''}${hz.tsunami > 0 ? ' / 津波想定' : ''}';
      final sub = weatherSub(ref.watch(weatherProvider).value) ?? hazardSub;
      // 吹き出しから聞けるようにする。何を聞けるかは開いた先で例を出す
      // ── 入口が無いと、聞けること自体に気づかれない。
      final meetup = ref.watch(meetupProvider);
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        if (meetup != null) ...[
          MeetupBanner(meetup: meetup, focusOnTap: false),
          const SizedBox(height: 8),
        ],
        HinaCard(
        onTap: () => showAskSheet(context),
        child: Column(children: [
          SenaviSpeech(mood: senavi.mood, text: senavi.line, sub: sub),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.chat_bubble_outline, size: 14, color: HinaColors.inkSub),
            const SizedBox(width: 6),
            Text('セナヴィに聞く', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HinaColors.inkSub)),
          ]),
        ]),
        ),
      ]);
    }
    return SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(HinaSpace.m, 0, HinaSpace.m, HinaSpace.s), child: body));
  }
}

class _RoundButton extends StatelessWidget {
  final HinaIcon icon;
  final VoidCallback onTap;

  /// 押しっぱなしで効き続ける種類のボタン(雨雲の重ねなど)の、入り切りの見た目。
  final bool active;
  const _RoundButton({required this.icon, required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) => Material(
        color: active ? HinaColors.sky : HinaColors.surface,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: HinaIconView(icon, size: 22, color: active ? Colors.white : HinaColors.ink)),
          ),
        ),
      );
}

/// 届いた通報依頼の帯。
///
/// **ここには本名も住所も出さない。** ニックネームと市区町村だけ。
/// 開いて「確認する」を押した人にだけ個人情報が見える。
class _SosBanner extends StatelessWidget {
  final SosRequest sos;
  final VoidCallback onTap;
  const _SosBanner({required this.sos, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: HinaColors.stUnknown,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            const Icon(Icons.sos, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('通報の依頼が届いています', style: t.titleMedium?.copyWith(color: Colors.white)),
                Text(sos.headline, style: t.bodySmall?.copyWith(color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}

/// 自分が動けないときに、家族・友人へ通報を頼むボタン。
///
/// 押したら確認を挟む。誤爆すると相手に個人情報が開いてしまうので、
/// 一度で飛ばさない。
class _SosButton extends ConsumerStatefulWidget {
  final Incident incident;
  const _SosButton({required this.incident});
  @override
  ConsumerState<_SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<_SosButton> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HinaColors.stUnknown,
      shape: const StadiumBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _sending ? null : _confirm,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: _sending
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('通報を代わりに頼みますか?'),
        content: const Text(
          '家族・友人に「代わりに通報してほしい」と伝えます。'
          '相手が確認を押すと、あなたの本名・住所・年齢・電話番号が相手にだけ見えます。\n\n'
          '119番や自治体には繋がりません。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('依頼する')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _sending = true);
    try {
      final loc = ref.read(locationProvider);
      final r = await ref.read(apiProvider).requestSos(
            lat: loc?.point.latitude,
            lng: loc?.point.longitude,
            incidentId: widget.incident.id,
            disaster: widget.incident.type.label,
          );
      messenger?.showSnackBar(SnackBar(content: Text('${r['sentTo']}人に通報を依頼しました')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('依頼できませんでした: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

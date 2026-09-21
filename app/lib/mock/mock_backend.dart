import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../domain/social.dart';
import '../domain/weather.dart';

/// サーバー(Vercel API + Firestore)を丸ごと置き換える、端末内だけで動く偽の
/// バックエンド。
///
/// 目的は「繋ぎ込みが終わったらこう動くはず」を先に見えるようにすること。
/// 避難所・ハザード・インシデントの状態遷移・AgentLog・フレンドの安否まで、
/// 画面が必要とするデータを全部ここが持つ。実サーバーが要らないので、
/// オフラインでもデモの全画面を通せる。
///
/// 本物に差し替えるときの手順は docs/api_integration_tasks.md を参照。
class MockBackend extends StateNotifier<MockState> {
  MockBackend() : super(const MockState());

  Timer? _think;
  Timer? _walk;

  @override
  void dispose() {
    _disposed = true;
    _think?.cancel();
    _walk?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- 避難所
  /// 現在地から相対で避難所を生成する。
  ///
  /// 固定の緯度経度にすると、シミュレータの位置が変わった途端に画面外へ消えて
  /// 「何も出ない」ように見えてしまう。名前と混雑率だけ固定し、位置は常に
  /// 現在地のまわりに置く。
  static const _layout = <({String id, String name, String address, double eastM, double northM, int crowd, double elev, bool full})>[
    (id: 'sh_minamigyotoku_jhs', name: '南行徳中学校', address: '市川市相之川4丁目', eastM: 320, northM: 480, crowd: 32, elev: 3.8, full: false),
    (id: 'sh_dai7_jhs', name: '第七中学校', address: '市川市欠真間2丁目', eastM: -420, northM: 260, crowd: 58, elev: 2.9, full: false),
    (id: 'sh_fukuei_es', name: '福栄小学校', address: '市川市福栄3丁目', eastM: 560, northM: -300, crowd: 21, elev: 4.6, full: false),
    (id: 'sh_minamigyotoku_park', name: '南行徳公園', address: '市川市広尾2丁目', eastM: 180, northM: -620, crowd: 76, elev: 2.4, full: false),
    (id: 'sh_shiohama_gakuen', name: '塩浜学園', address: '市川市塩浜4丁目', eastM: -680, northM: -180, crowd: 44, elev: 4.2, full: false),
  ];

  static List<ShelterInfo> sheltersAround(LatLng here, {Set<String> fullIds = const {}}) {
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos(here.latitude * math.pi / 180);
    const d = Distance();
    return _layout.map((s) {
      final p = LatLng(here.latitude + s.northM / mPerDegLat, here.longitude + s.eastM / mPerDegLng);
      final metres = d(here, p).round();
      return ShelterInfo(
        id: s.id,
        name: s.name,
        address: s.address,
        point: p,
        distanceM: metres,
        walkMin: math.max(1, (metres / 80).round()), // 徒歩 80m/分
        elevationM: s.elev,
        crowdPct: fullIds.contains(s.id) ? 100 : s.crowd,
        full: fullIds.contains(s.id),
      );
    }).toList();
  }

  static const hazardHere = HazardHere(flood: 2, tsunami: 0, floodLabel: '0.5〜3m', landslide: false);

  // ---------------------------------------------------------------- 雨雲
  /// 平時のセナヴィの一言を出し分けるための見本。デモで順に切り替えられる。
  static const weatherCycle = <RainNowcast>[
    RainNowcast(nowMmh: 0, maxMmh: 0, cloudPct: 8), // しばらく快晴みたい
    RainNowcast(nowMmh: 0, maxMmh: 0.2, cloudPct: 85), // 曇ってるけど降らなさそう
    RainNowcast(nowMmh: 0, maxMmh: 3.4, startsInMin: 25), // あと25分で雨
    RainNowcast(nowMmh: 0, maxMmh: 18.0, startsInMin: 10), // あと10分で強い雨
    RainNowcast(nowMmh: 2.1, maxMmh: 4.0, stopsInMin: 40), // いま雨
    RainNowcast(nowMmh: 14.5, maxMmh: 22.0, stopsInMin: 55), // いま強い雨
  ];

  /// 見本を順送りする。設定 → DEMO から押す。
  void cycleWeather() {
    final i = weatherCycle.indexOf(state.weather ?? weatherCycle.last);
    state = state.copyWith(weather: weatherCycle[(i + 1) % weatherCycle.length]);
  }

  // ---------------------------------------------------------------- フレンド
  static const friends = <FriendEntry>[
    FriendEntry(uid: 'mock_mother', displayName: 'お母さん', relation: '家族', autoShare: true, isMock: true, shareLocation: true, avatarMood: 'smile'),
    FriendEntry(uid: 'mock_yuta', displayName: 'ゆうた', relation: '友人', autoShare: true, isMock: true, shareLocation: true, avatarMood: 'normal'),
    FriendEntry(uid: 'mock_sakura', displayName: 'さくら', relation: '同僚', autoShare: true, isMock: true, avatarMood: 'serious'),
    FriendEntry(uid: 'mock_takumi', displayName: 'たくみ', relation: '同僚', autoShare: false, isMock: true, avatarMood: 'lookback'),
    FriendEntry(uid: 'mock_mai', displayName: 'まい', relation: '友人', autoShare: true, isMock: true, shareLocation: true, avatarMood: 'troubled'),
  ];

  /// 位置を許可しているフレンドの「最後に届いた位置」。
  /// 鮮度の差(たった今 / 12分前 / 4時間前)を意図的に混ぜてある ── 古い位置を
  /// 現在地と読み違える事故が、この機能でいちばん怖いので。
  /// areaName は本来サーバーが逆ジオして入れる。モックでは固定文言。
  static const _friendOffsets = <String, ({double eastM, double northM, int ageMin, int battery, String area})>{
    'mock_mother': (eastM: 260, northM: 380, ageMin: 3, battery: 72, area: '千葉県市川市'),
    'mock_yuta': (eastM: 430, northM: -240, ageMin: 12, battery: 28, area: '千葉県市川市'),
    'mock_sakura': (eastM: -310, northM: -180, ageMin: 6, battery: 54, area: '千葉県浦安市'),
    'mock_mai': (eastM: -520, northM: 210, ageMin: 245, battery: 9, area: '東京都江戸川区'),
  };

  static Map<String, FriendLocation> friendLocationsAround(LatLng here) {
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos(here.latitude * math.pi / 180);
    final now = DateTime.now();
    return _friendOffsets.map((uid, o) => MapEntry(
          uid,
          FriendLocation(
            point: LatLng(here.latitude + o.northM / mPerDegLat, here.longitude + o.eastM / mPerDegLng),
            at: now.subtract(Duration(minutes: o.ageMin)),
            accuracyM: 12,
            batteryPct: o.battery,
            areaName: o.area,
          ),
        ));
  }

  /// 平時の安否。災害を発火すると [friendsDuringIncident] に切り替わる。
  /// note は本人が書いた一言という想定。
  static Map<String, FriendStatus> _friendsAtRest() {
    final now = DateTime.now();
    return {
      'mock_mother': FriendStatus(state: PublicStatus.safe, note: '今日は一日在宅です。夕飯は18時ごろ', updatedAt: now.subtract(const Duration(minutes: 42))),
      'mock_yuta': FriendStatus(state: PublicStatus.safe, note: '職場。21時まで残業の予定', updatedAt: now.subtract(const Duration(hours: 2))),
      'mock_sakura': FriendStatus(state: PublicStatus.safe, note: '会社にいます', updatedAt: now.subtract(const Duration(minutes: 8))),
      'mock_takumi': FriendStatus(state: PublicStatus.safe, updatedAt: now.subtract(const Duration(minutes: 20))),
      'mock_mai': FriendStatus(state: PublicStatus.unknown, note: '応答なし', updatedAt: now.subtract(const Duration(hours: 5))),
    };
  }

  /// 災害時。避難先は現在地まわりの避難所から引く(地図に線を引けるよう座標も持つ)。
  static Map<String, FriendStatus> friendsDuringIncident(LatLng here) {
    final now = DateTime.now();
    final shelters = {for (final s in sheltersAround(here)) s.id: s};
    final toJhs = shelters['sh_minamigyotoku_jhs'];
    final toEs = shelters['sh_fukuei_es'];
    return {
      'mock_mother': FriendStatus(
          state: PublicStatus.arrived,
          shelterName: toJhs?.name,
          shelterPoint: toJhs?.point,
          note: '体育館に入れました。毛布あり。こちらは大丈夫',
          updatedAt: now.subtract(const Duration(minutes: 3))),
      'mock_yuta': FriendStatus(
          state: PublicStatus.evacuating,
          shelterName: toEs?.name,
          shelterPoint: toEs?.point,
          note: '徒歩で向かっています。途中の橋は通れました',
          updatedAt: now.subtract(const Duration(minutes: 1))),
      'mock_sakura': FriendStatus(state: PublicStatus.assessing, note: 'ビルの4階。いまは動かず様子を見ます', updatedAt: now),
      'mock_takumi': FriendStatus(state: PublicStatus.safe, note: '被害なし。水と食料は3日分あり', updatedAt: now.subtract(const Duration(minutes: 2))),
      'mock_mai': FriendStatus(state: PublicStatus.unknown, note: '応答なし', updatedAt: now.subtract(const Duration(hours: 5))),
    };
  }

  // ---------------------------------------------------------------- 場所と到着
  /// よく行く場所の見本。現在地の周りに置くので、端末がどこにあっても成立する。
  static List<SavedPlace> placesAround(LatLng here) {
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos(here.latitude * math.pi / 180);
    LatLng at(double eastM, double northM) => LatLng(here.latitude + northM / mPerDegLat, here.longitude + eastM / mPerDegLng);
    return [
      SavedPlace(id: 'pl_home', name: '自宅', point: at(120, 90), radiusM: 150, kind: PlaceKind.home),
      SavedPlace(id: 'pl_work', name: '職場', point: at(-540, 420), radiusM: 200, kind: PlaceKind.work),
    ];
  }

  void seedPlaces(LatLng here) {
    if (state.places.isNotEmpty) return;
    state = state.copyWith(places: placesAround(here));
  }

  void addPlace(SavedPlace p) => state = state.copyWith(places: [...state.places, p]);

  /// 追加と編集を同じ入口で扱う。id が既にあるものは差し替える
  /// ── サーバー側(me/places)も id の有無で同じ分岐をしている。
  void savePlace(SavedPlace p) {
    final id = p.id.isEmpty ? 'pl_${DateTime.now().millisecondsSinceEpoch}' : p.id;
    final saved = SavedPlace(id: id, name: p.name, point: p.point, radiusM: p.radiusM, kind: p.kind);
    final rest = state.places.where((e) => e.id != id).toList();
    state = state.copyWith(places: [...rest, saved]);
  }
  void removePlace(String id) => state = state.copyWith(places: state.places.where((p) => p.id != id).toList());

  /// フレンドの位置を登録済みの場所と突き合わせて、到着/出発を作る。
  /// 本番はサーバーが位置を受けた時に同じ判定をする(端末が寝ていても動くように)。
  static String? placeNameFor(LatLng p, List<SavedPlace> places) {
    const d = Distance();
    for (final pl in places) {
      if (d(p, pl.point) <= pl.radiusM) return pl.name;
    }
    return null;
  }

  /// デモ用。指定のフレンドを自宅に「着かせる」。
  void simulateArrival(String friendUid, {bool arrived = true}) {
    final f = friends.where((e) => e.uid == friendUid).firstOrNull;
    final place = state.places.isEmpty ? null : state.places.first;
    if (f == null || place == null) return;
    final ev = PlaceEvent(friendUid: f.uid, friendName: f.displayName, placeName: place.name, arrived: arrived, at: DateTime.now());
    // 新しいものが先頭。一覧は上から読むので。
    state = state.copyWith(placeEvents: [ev, ...state.placeEvents].take(20).toList());
  }

  // ---------------------------------------------------------------- 合流
  void startMeetup({required String name, required LatLng point, required List<String> memberUids, bool fromIncident = false}) {
    state = state.copyWith(
      // サーバーは作った本人を必ずメンバーに入れる。モックだけ入れないと
      // 「自分の合流なのにメンバーに自分がいない」という別物になる。
      meetup: Meetup(id: 'mu_${DateTime.now().millisecondsSinceEpoch}', name: name, point: point, memberUids: {myUid, ...memberUids}.toList(), createdAt: DateTime.now(), fromIncident: fromIncident),
    );
  }

  void endMeetup() => state = state.copyWith(clearMeetup: true);

  // ---------------------------------------------------------------- メッセージ
  /// モックでの自分。送信者の既定値として既に 'me' を使っている。
  static const myUid = 'me';

  void send(String friendUid, {String? text, String? reaction, String fromUid = 'me'}) {
    final msg = ChatMessage(
      id: 'm_${DateTime.now().microsecondsSinceEpoch}',
      fromUid: fromUid,
      text: text,
      reaction: reaction,
      at: DateTime.now(),
    );
    state = state.copyWith(chats: {...state.chats, friendUid: [...(state.chats[friendUid] ?? const []), msg]});

    // 相手が返してくる。届いている感じが無いと会話として確かめられないので、
    // モックでは一言だけ自動で返す。
    if (fromUid == 'me') {
      Timer(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        final reply = reaction != null ? '👍' : _replyTo(friendUid);
        final r = ChatMessage(
          id: 'm_${DateTime.now().microsecondsSinceEpoch}',
          fromUid: friendUid,
          text: reaction != null ? null : reply,
          reaction: reaction != null ? reply : null,
          at: DateTime.now(),
        );
        state = state.copyWith(chats: {...state.chats, friendUid: [...(state.chats[friendUid] ?? const []), r]});
      });
    }
  }

  bool get mounted => !_disposed;
  bool _disposed = false;

  static String _replyTo(String uid) => switch (uid) {
        'mock_mother' => 'わかった。気をつけてね',
        'mock_yuta' => 'りょうかい！',
        'mock_sakura' => 'こっちは大丈夫です',
        _ => 'ありがとう',
      };

  // ---------------------------------------------------------------- 状態遷移
  /// 災害を発火する。assessing を挟んでから proposing に落ち着く。
  Future<void> fire(DisasterType type, LatLng here) async {
    _think?.cancel();
    _walk?.cancel();
    final id = 'mock_${DateTime.now().millisecondsSinceEpoch}';
    final title = switch (type) {
      DisasterType.earthquake => '強い揺れを検知しました(震度5強)',
      DisasterType.heavyRain || DisasterType.flood => '記録的短時間大雨情報(市川市)',
      DisasterType.tsunami => '津波警報(東京湾内湾)',
      DisasterType.landslide => '土砂災害警戒情報(市川市)',
      DisasterType.stormSurge => '高潮警報(東京湾)',
    };

    state = state.copyWith(
      incident: Incident(
        id: id,
        state: IncidentState.assessing,
        alertTitle: title,
        type: type,
        reasons: const [],
        userMessage: '',
        validatedBy: 'none',
        costUsd: 0,
        llmCalls: 0,
        locationSource: 'mock',
        createdAt: DateTime.now(),
      ),
      log: _logAssessing(),
      statuses: friendsDuringIncident(here),
      myStatus: FriendStatus(state: PublicStatus.assessing, updatedAt: DateTime.now()),
    );

    // 「AI が考えている」間を見せてから結果を出す。
    _think = Timer(const Duration(milliseconds: 2600), () => _propose(here, type));
  }

  void _propose(LatLng here, DisasterType type, {Set<String> exclude = const {}}) {
    final all = sheltersAround(here, fullIds: state.fullShelters);
    final pick = all.where((s) => !s.full && !exclude.contains(s.id)).toList()..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    if (pick.isEmpty) return;
    final shelter = pick.first;
    final inc = state.incident;
    if (inc == null) return;

    state = state.copyWith(
      incident: _copy(
        inc,
        state: IncidentState.proposing,
        shelter: shelter,
        route: _route(here, shelter.point),
        reasons: [
          '浸水想定の外',
          '徒歩${shelter.walkMin}分',
          '混雑 ${shelter.crowdPct}%',
        ],
        validatedBy: 'llm+rules',
        costUsd: 0.0026,
        llmCalls: 2,
      ),
      log: [...state.log, ..._logDecision(shelter, type, all)],
    );
  }

  /// 承認(または 30 秒経過)。誘導を開始する。
  void start({bool byTimeout = false}) {
    final inc = state.incident;
    if (inc?.shelter == null) return;
    state = state.copyWith(
      incident: _copy(inc!, state: IncidentState.guiding, remainingMin: inc.shelter!.walkMin),
      myStatus: FriendStatus(state: PublicStatus.evacuating, shelterName: inc.shelter!.name, updatedAt: DateTime.now()),
      log: [
        ...state.log,
        _entry(state.log.length, LogKind.action, byTimeout ? '自動で開始した(30秒無操作)' : 'ユーザーが承認した',
            detail: '「このルートで行く」→ 誘導開始。同意済みのフレンドへ「避難中」を共有', audience: 'user'),
      ],
    );
    _tickWalk();
  }

  /// 誘導中の残り時間を進める。到着するとセナヴィが笑顔になる。
  void _tickWalk() {
    _walk?.cancel();
    _walk = Timer.periodic(const Duration(seconds: 6), (t) {
      final inc = state.incident;
      if (inc == null || !inc.state.isGuiding) {
        t.cancel();
        return;
      }
      final left = (inc.remainingMin ?? 0) - 1;
      if (left <= 0) {
        t.cancel();
        arrived();
      } else {
        state = state.copyWith(incident: _copy(inc, remainingMin: left));
      }
    });
  }

  void arrived() {
    _walk?.cancel();
    final inc = state.incident;
    if (inc == null) return;
    state = state.copyWith(
      incident: _copy(inc, state: IncidentState.arrived, remainingMin: 0),
      myStatus: FriendStatus(state: PublicStatus.arrived, shelterName: inc.shelter?.name, updatedAt: DateTime.now()),
      log: [
        ...state.log,
        _entry(state.log.length, LogKind.action, '到着を確認した', detail: '${inc.shelter?.name ?? '避難場所'} のジオフェンス(100m)に入りました。フレンドへ「到着」を共有', audience: 'user'),
      ],
    );
  }

  void later() {
    final inc = state.incident;
    if (inc == null) return;
    state = state.copyWith(
      incident: _copy(inc, state: IncidentState.monitoringStay),
      log: [...state.log, _entry(state.log.length, LogKind.action, 'あとで確認する', detail: '今は動かず様子を見ます。状況が変わったら呼びます', audience: 'user')],
    );
  }

  /// 満員などで選び直す。いまの避難所を除外して次点を出す。
  void reselect(LatLng here, {String reason = 'user'}) {
    final inc = state.incident;
    if (inc == null) return;
    final excluded = inc.shelter?.id;
    state = state.copyWith(
      incident: _copy(inc, state: IncidentState.reselecting),
      log: [
        ...state.log,
        _entry(state.log.length, LogKind.info, reason == 'crowd' ? '避難所が満員になった' : '別の場所を探す', detail: '${inc.shelter?.name ?? ''} を候補から外して選び直します', audience: 'both'),
      ],
    );
    _think?.cancel();
    _think = Timer(const Duration(milliseconds: 1500), () {
      _propose(here, inc.type, exclude: {if (excluded != null) excluded});
      final after = state.incident;
      if (after != null) state = state.copyWith(incident: _copy(after, state: IncidentState.guiding, remainingMin: after.shelter?.walkMin));
      _tickWalk();
    });
  }

  /// 「満員」デモ。いまの避難所を満員にして再選定へ流す。
  void markFull(LatLng here) {
    final id = state.incident?.shelter?.id;
    if (id == null) return;
    state = state.copyWith(fullShelters: {...state.fullShelters, id});
    reselect(here, reason: 'crowd');
  }

  void close() {
    _think?.cancel();
    _walk?.cancel();
    state = const MockState();
  }

  /// 自分のプロフィール。モックでは Firestore の users/{uid} の代わり。
  void setProfile({String? displayName, String? avatarImage, String? avatarMood}) {
    final p = {...state.profile};
    if (displayName != null) p['displayName'] = displayName;
    // 空文字は「消す」の意味。片方を選んだらもう片方は落とす。
    if (avatarImage != null) avatarImage.isEmpty ? p.remove('avatarImage') : p['avatarImage'] = avatarImage;
    if (avatarMood != null) avatarMood.isEmpty ? p.remove('avatarMood') : p['avatarMood'] = avatarMood;
    state = state.copyWith(profile: p);
  }

  /// 自分のメモを書き換える。相手に見えるのは myStatus.note。
  void setMyNote(String note) => state = state.copyWith(
        myStatus: FriendStatus(
          state: state.myStatus.state,
          shelterName: state.myStatus.shelterName,
          shelterPoint: state.myStatus.shelterPoint,
          note: note.trim().isEmpty ? null : note.trim(),
          updatedAt: DateTime.now(),
        ),
      );

  void seedFriendsAtRest() => state = state.copyWith(statuses: _friendsAtRest(), weather: state.weather ?? weatherCycle.first);

  /// 位置が分かった時点で、よく行く場所の見本を用意する。
  void seedAll(LatLng here) {
    seedFriendsAtRest();
    seedPlaces(here);
  }

  /// フレンドを「災害が起きたあと」の安否に進める(到着・避難中・確認中が混ざる)。
  void advanceFriends(LatLng here) => state = state.copyWith(statuses: friendsDuringIncident(here));

  // ---------------------------------------------------------------- 組み立て
  static Incident _copy(
    Incident i, {
    IncidentState? state,
    ShelterInfo? shelter,
    RouteInfo? route,
    List<String>? reasons,
    String? validatedBy,
    double? costUsd,
    int? llmCalls,
    int? remainingMin,
  }) =>
      Incident(
        id: i.id,
        state: state ?? i.state,
        alertTitle: i.alertTitle,
        type: i.type,
        shelter: shelter ?? i.shelter,
        route: route ?? i.route,
        reasons: reasons ?? i.reasons,
        userMessage: i.userMessage,
        validatedBy: validatedBy ?? i.validatedBy,
        costUsd: costUsd ?? i.costUsd,
        llmCalls: llmCalls ?? i.llmCalls,
        remainingMin: remainingMin ?? i.remainingMin,
        locationSource: i.locationSource,
        createdAt: i.createdAt,
      );

  /// 直線を数回だけ折る、それらしい徒歩経路。
  /// 本物は OpenRouteService の foot-walking が返す。
  static RouteInfo _route(LatLng from, LatLng to) {
    const d = Distance();
    final mid1 = LatLng(from.latitude, from.longitude + (to.longitude - from.longitude) * 0.62);
    final mid2 = LatLng(from.latitude + (to.latitude - from.latitude) * 0.78, mid1.longitude);
    final pts = [from, mid1, mid2, to];
    final metres = [for (var i = 1; i < pts.length; i++) d(pts[i - 1], pts[i])].fold<double>(0, (a, b) => a + b).round();
    return RouteInfo(points: pts, distanceM: metres, durationS: (metres / 1.33).round(), provider: 'mock');
  }

  static AgentLogEntry _entry(
    int seq,
    LogKind kind,
    String title, {
    String? detail,
    String audience = 'both',
    String? toolName,
    String? chosenBy,
    String? model,
    String? router,
    String? promptRef,
    int? fallbackLevel,
    int? latencyMs,
    double? costUsd,
    Object? payload,
  }) =>
      AgentLogEntry(
        seq: seq,
        at: DateTime.now(),
        kind: kind,
        title: title,
        detail: detail,
        audience: audience,
        toolName: toolName,
        chosenBy: chosenBy,
        model: model,
        router: router,
        promptRef: promptRef,
        fallbackLevel: fallbackLevel,
        latencyMs: latencyMs,
        costUsd: costUsd,
        payload: payload,
      );

  static List<AgentLogEntry> _logAssessing() => [
        _entry(0, LogKind.toolCall, 'ツールを呼んだ — 逆ジオコーディング',
            detail: '現在地を市区町村レベルの地名に変換', toolName: 'reverse_geocode', latencyMs: 180, payload: {'source': '国土地理院', 'result': '千葉県市川市南行徳'}),
        _entry(1, LogKind.toolCall, 'ツールを呼んだ — ハザード判定',
            detail: 'ハザードマップポータルのタイルを読み、現在地の浸水深クラスを取得', toolName: 'hazard_here', latencyMs: 420, payload: {'flood': '0.5〜3m', 'landslide': false, 'tsunami': 'なし'}),
        _entry(2, LogKind.toolCall, 'ツールを呼んだ — 周辺の避難場所を検索',
            detail: '指定緊急避難場所データから半径1.5km以内を取得', toolName: 'shelters_nearby', latencyMs: 510, payload: {'count': 5, 'radius_m': 1500}),
      ];

  /// 審査で見せたい 4 行(LLM 入力に座標が無い / 却下 / 昇格 / コスト)を必ず含める。
  static List<AgentLogEntry> _logDecision(ShelterInfo picked, DisasterType type, List<ShelterInfo> all) {
    final candidates = all.take(4).toList();
    return [
      _entry(3, LogKind.llmRequest, 'AI に渡した情報',
          detail: '座標・氏名・連絡先は渡していません。地名と候補の相対情報だけ',
          audience: 'judge',
          model: 'orcarouter/hina-decide',
          router: 'hina-decide',
          promptRef: 'hina-decide-system@production',
          latencyMs: 1240,
          payload: {
            'area_name': '千葉県市川市南行徳',
            'disaster_type': type.label,
            'hazard_here': {'flood': '0.5〜3m', 'landslide': false},
            'candidates': [
              for (var i = 0; i < candidates.length; i++)
                {
                  'ref': String.fromCharCode(65 + i),
                  'walk_min': candidates[i].walkMin,
                  'crowd_pct': candidates[i].crowdPct,
                  'flood': i == 3 ? '0.5〜3m' : 'なし',
                  'elevation_m': candidates[i].elevationM,
                },
            ],
          }),
      _entry(4, LogKind.llmResponse, 'AI の答え',
          detail: '${picked.name} を推薦。浸水想定の外で、徒歩${picked.walkMin}分・混雑${picked.crowdPct}%',
          chosenBy: 'llm',
          model: 'anthropic/claude-sonnet-4.5',
          latencyMs: 1240,
          payload: {'pick': 'A', 'reasons': ['浸水想定の外', '徒歩${picked.walkMin}分', '混雑 ${picked.crowdPct}%']}),
      _entry(5, LogKind.validator, '安全ルールで却下した候補がある',
          detail: '南行徳公園は混雑76%かつ浸水想定域内のため、候補から除外',
          audience: 'judge',
          payload: {'rejected': '南行徳公園', 'rule': 'flood_depth > 0 && crowd_pct > 70'}),
      _entry(6, LogKind.fallback, '却下されたので一段上のモデルへ昇格した',
          detail: 'X-OrcaRouter-Escalate: once — 安全ルールを満たす候補が残るまで 1 回だけ昇格',
          audience: 'judge',
          fallbackLevel: 1,
          model: 'anthropic/claude-sonnet-4.5'),
      _entry(7, LogKind.cost, 'モデル名とコスト',
          detail: 'この判断にかかった合計', audience: 'judge', model: 'anthropic/claude-sonnet-4.5', costUsd: 0.0026, payload: {'llm_calls': 2, 'total_usd': 0.0026}),
    ];
  }
}

/// モックが保持する、本来はサーバーにある状態。
class MockState {
  final Incident? incident;
  final List<AgentLogEntry> log;
  final Map<String, FriendStatus> statuses;
  final FriendStatus myStatus;
  final Set<String> fullShelters;
  final RainNowcast? weather;
  final Map<String, dynamic> profile;
  final List<SavedPlace> places;
  final List<PlaceEvent> placeEvents;
  final Meetup? meetup;

  /// フレンド uid -> やりとり。1 対 1 だけなので相手 uid で引ける。
  final Map<String, List<ChatMessage>> chats;

  const MockState({
    this.incident,
    this.log = const [],
    this.statuses = const {},
    this.myStatus = const FriendStatus(state: PublicStatus.safe),
    this.fullShelters = const {},
    this.weather,
    this.profile = const {'displayName': 'わたし', 'inviteCode': 'HINA-7QK3', 'avatarMood': 'normal'},
    this.places = const [],
    this.placeEvents = const [],
    this.meetup,
    this.chats = const {},
  });

  MockState copyWith({
    Incident? incident,
    List<AgentLogEntry>? log,
    Map<String, FriendStatus>? statuses,
    FriendStatus? myStatus,
    Set<String>? fullShelters,
    RainNowcast? weather,
    Map<String, dynamic>? profile,
    List<SavedPlace>? places,
    List<PlaceEvent>? placeEvents,
    Meetup? meetup,
    bool clearMeetup = false,
    Map<String, List<ChatMessage>>? chats,
  }) =>
      MockState(
        incident: incident ?? this.incident,
        log: log ?? this.log,
        statuses: statuses ?? this.statuses,
        myStatus: myStatus ?? this.myStatus,
        fullShelters: fullShelters ?? this.fullShelters,
        weather: weather ?? this.weather,
        profile: profile ?? this.profile,
        places: places ?? this.places,
        placeEvents: placeEvents ?? this.placeEvents,
        meetup: clearMeetup ? null : (meetup ?? this.meetup),
        chats: chats ?? this.chats,
      );
}

// ------------------------------------------------------------------ providers
final mockBackendProvider = StateNotifierProvider<MockBackend, MockState>((_) => MockBackend());

/// モックモードの ON/OFF。端末に覚えさせるので、再起動してもデモ状態が続く。
final mockModeProvider = StateNotifierProvider<MockModeNotifier, bool>((ref) => MockModeNotifier(ref));

class MockModeNotifier extends StateNotifier<bool> {
  final Ref ref;
  MockModeNotifier(this.ref) : super(false) {
    _load();
  }
  Future<void> _load() async {
    state = (await SharedPreferences.getInstance()).getBool('mockMode') ?? false;
    if (state) ref.read(mockBackendProvider.notifier).seedFriendsAtRest();
  }

  Future<void> set(bool v) async {
    state = v;
    (await SharedPreferences.getInstance()).setBool('mockMode', v);
    final backend = ref.read(mockBackendProvider.notifier);
    if (v) {
      backend.seedFriendsAtRest();
    } else {
      backend.close();
    }
  }
}

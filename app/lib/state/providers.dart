import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/my_area.dart';
import '../core/rain_tiles.dart';
import '../core/location_service.dart';
import '../core/location_uploader.dart';
import '../core/pending_locations.dart';
import '../domain/models.dart';
import '../domain/senavi.dart';
import '../domain/social.dart';
import '../domain/weather.dart';
import '../mock/mock_backend.dart';
import '../ui/organisms/hina_basemap.dart';

final apiProvider = Provider((_) => ApiClient());

/// いま自分がいる市区町村。警報を自分宛てに絞るためだけに使う。
final myAreaProvider = Provider((ref) => MyArea(ref.watch(apiProvider)));
final firestoreProvider = Provider((_) => FirebaseFirestore.instance);

/// Anonymous auth user (signed in at startup).
final authUserProvider = StreamProvider<User?>((_) => FirebaseAuth.instance.authStateChanges());
final uidProvider = Provider<String?>((ref) => ref.watch(authUserProvider).value?.uid);

// ------------------------------------------------------------------ own profile
final myProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  if (ref.watch(mockModeProvider)) {
    return Stream.value({
      ...ref.watch(mockBackendProvider).profile,
      'consent': {'shareStatusWithFriends': true, 'shareShelterName': true},
    });
  }
  final uid = ref.watch(uidProvider);
  if (uid == null) return const Stream.empty();
  return ref.watch(firestoreProvider).collection('users').doc(uid).snapshots().map((d) => d.data());
});

// ------------------------------------------------------------------ incident
/// The newest incident for this user (active or just finished). Requires index (uid asc, createdAt desc).
final latestIncidentProvider = StreamProvider<Incident?>((ref) {
  if (ref.watch(mockModeProvider)) return Stream.value(ref.watch(mockBackendProvider).incident);
  final uid = ref.watch(uidProvider);
  if (uid == null) return const Stream.empty();
  return ref
      .watch(firestoreProvider)
      .collection('incidents')
      .where('uid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .snapshots()
      .map((q) => q.docs.isEmpty ? null : Incident.fromDoc(q.docs.first));
});

/// ホームに重ねるインシデント。
///
/// 到着カードは少しのあいだ残す(共有できたことを確かめる時間)が、
/// **`closed` は本人が「ホームに戻る」を押した結果**なので即座に消す。
/// ここを `isFinished` でまとめると、閉じてもカードが居座る。
final activeIncidentProvider = Provider<Incident?>((ref) {
  final inc = ref.watch(latestIncidentProvider).value;
  if (inc == null) return null;
  if (inc.state == IncidentState.closed) return null;
  if (inc.state.isActive) return inc;
  if (inc.state.isFinished && inc.createdAt != null && DateTime.now().difference(inc.createdAt!) < const Duration(minutes: 30)) return inc;
  return null;
});

final incidentStateProvider = Provider<IncidentState>((ref) {
  final busy = ref.watch(agentBusyProvider);
  final inc = ref.watch(activeIncidentProvider);
  if (busy && (inc == null || !inc.state.isActive)) return IncidentState.assessing;
  return inc?.state ?? IncidentState.idle;
});

/// Local flag while /api/agent/run is in flight (before Firestore catches up).
final agentBusyProvider = StateProvider<bool>((_) => false);

final senaviProvider = Provider<({SenaviMood mood, String line})>((ref) {
  final s = ref.watch(incidentStateProvider);
  final inc = ref.watch(activeIncidentProvider);
  // 平時は災害の状態が何も語らないので、雨雲の見通しで表情と一言を決める。
  if (s == IncidentState.idle) {
    final w = ref.watch(weatherProvider).value;
    return (mood: moodForWeather(w), line: weatherLine(w));
  }
  return (
    mood: moodFor(s),
    line: lineFor(s, shelter: inc?.shelter?.name, walkMin: inc?.remainingMin ?? inc?.shelter?.walkMin, custom: inc?.userMessage),
  );
});

// ------------------------------------------------------------------ 平時の雨雲
/// 起動時と現在地更新のたびに引き直す、直近 60 分の雨雲ナウキャスト。
/// 災害が起きていないときのホーム(セナヴィの一言)はこれで決まる。
final weatherProvider = FutureProvider<RainNowcast?>((ref) async {
  final loc = ref.watch(locationProvider);
  if (loc == null) return null;
  if (ref.watch(mockModeProvider)) return ref.watch(mockBackendProvider).weather;
  try {
    final j = await ref.read(apiProvider).weather(lat: loc.point.latitude, lng: loc.point.longitude);
    return RainNowcast.fromJson(j);
  } catch (e) {
    // 天気が引けなくても平時のホームは成立する。黙って落とさず、一言だけ既定に戻す。
    debugPrint('weather nowcast unavailable: $e');
    return null;
  }
});

final agentLogProvider = StreamProvider.family<List<AgentLogEntry>, String>((ref, incidentId) {
  if (ref.watch(mockModeProvider)) return Stream.value(ref.watch(mockBackendProvider).log);
  return ref.watch(firestoreProvider).collection('incidents').doc(incidentId).collection('agentLog').orderBy('at').snapshots().map((q) => q.docs.map(AgentLogEntry.fromDoc).toList());
});

// ------------------------------------------------------------------ friends
final friendsProvider = StreamProvider<List<FriendEntry>>((ref) {
  if (ref.watch(mockModeProvider)) return Stream.value(MockBackend.friends);
  final uid = ref.watch(uidProvider);
  if (uid == null) return const Stream.empty();
  return ref.watch(firestoreProvider).collection('friends').doc(uid).collection('list').where('status', isEqualTo: 'accepted').snapshots().map((q) => q.docs.map(FriendEntry.fromDoc).toList());
});

final friendStatusProvider = StreamProvider.family<FriendStatus, String>((ref, friendUid) {
  if (ref.watch(mockModeProvider)) return Stream.value(ref.watch(mockBackendProvider).statuses[friendUid] ?? FriendStatus.unknown);
  return ref.watch(firestoreProvider).collection('statuses').doc(friendUid).snapshots().map(FriendStatus.fromDoc);
});

/// 許可してくれたフレンドの、最後に届いた位置。許可が無ければ null。
final friendLocationProvider = StreamProvider.family<FriendLocation?, String>((ref, friendUid) {
  if (ref.watch(mockModeProvider)) {
    final loc = ref.watch(locationProvider);
    if (loc == null) return Stream.value(null);
    return Stream.value(MockBackend.friendLocationsAround(loc.point)[friendUid]);
  }
  // 許可されていない相手のドキュメントはルールで弾かれる。権限エラーは
  // 「共有されていない」と同義なので、落とさず null にする。
  return ref
      .watch(firestoreProvider)
      .collection('locations')
      .doc(friendUid)
      .snapshots()
      .map((d) => d.exists ? FriendLocation.fromDoc(d) : null)
      .handleError((Object e) => debugPrint('friend location unavailable ($friendUid): $e'));
});

/// 地図に出せるフレンド = 位置を許可してくれていて、実際に位置が届いている人。
/// 一覧と地図で同じ材料を使うため、ここで 1 か所にまとめる。
final friendsOnMapProvider = Provider<List<FriendOnMap>>((ref) {
  final friends = ref.watch(friendsProvider).value ?? const <FriendEntry>[];
  final out = <FriendOnMap>[];
  for (final f in friends) {
    final loc = ref.watch(friendLocationProvider(f.uid)).value;
    if (loc == null) continue;
    out.add(FriendOnMap(
      entry: f,
      status: ref.watch(friendStatusProvider(f.uid)).value ?? FriendStatus.unknown,
      location: loc,
    ));
  }
  return out;
});

final myStatusProvider = StreamProvider<FriendStatus>((ref) {
  if (ref.watch(mockModeProvider)) return Stream.value(ref.watch(mockBackendProvider).myStatus);
  final uid = ref.watch(uidProvider);
  if (uid == null) return const Stream.empty();
  return ref.watch(firestoreProvider).collection('statuses').doc(uid).snapshots().map(FriendStatus.fromDoc);
});

// ------------------------------------------------------------------ location
final locationProvider = StateNotifierProvider<LocationNotifier, ResolvedLocation?>((ref) => LocationNotifier());

class LocationNotifier extends StateNotifier<ResolvedLocation?> {
  LocationNotifier() : super(null) {
    refresh();
  }
  Future<ResolvedLocation> refresh() async {
    final r = await LocationService.resolve();
    state = r;
    return r;
  }
  /// Demo move simulation: follow route points.
  void simulate(LatLng p) {
    LocationService.injectSimulated(p);
    state = ResolvedLocation(p, 'override');
  }
}

/// 「地図で見る」で寄せたい地点。地図側が拾ったら null に戻す使い捨ての指示。
final mapFocusProvider = StateProvider<LatLng?>((_) => null);

/// ボトムナビでいま開いているタブ。0=ホーム 1=マップ 2=友だち 3=設定。
/// 詳細シートから「マップで見る」に飛ぶために、画面側からも動かせるようにしている。
final selectedTabProvider = StateProvider<int>((_) => 0);

// ------------------------------------------------------------------ 場所・合流・やりとり
/// よく行く場所(自宅・職場…)。到着/出発の判定に使う。
final placesProvider = StreamProvider<List<SavedPlace>>((ref) {
  if (ref.watch(mockModeProvider)) return Stream.value(ref.watch(mockBackendProvider).places);
  final uid = ref.watch(uidProvider);
  if (uid == null) return const Stream.empty();
  return ref.watch(firestoreProvider).collection('places').doc(uid).collection('list').snapshots().map((q) => q.docs.map(SavedPlace.fromDoc).toList());
});

/// 「◯◯が自宅に着きました」の履歴。新しいものが先頭。
///
/// 相手ごとに購読する。イベントは相手の領域(placeEvents/{friendUid})にあり、
/// 安否を共有している相手だけがルールで読める。
final friendPlaceEventsProvider = StreamProvider.family<List<PlaceEvent>, FriendEntry>((ref, friend) {
  if (ref.watch(mockModeProvider)) return const Stream.empty();
  return ref
      .watch(firestoreProvider)
      .collection('placeEvents')
      .doc(friend.uid)
      .collection('list')
      .orderBy('at', descending: true)
      .limit(5)
      .snapshots()
      .map((q) => q.docs.map((d) => PlaceEvent.fromDoc(d, friend)).toList())
      // 共有されていない相手はルールで弾かれる。権限エラーは「見えない」と
      // 同義なので、落とさず空にする。
      .handleError((Object e) => debugPrint('placeEvents unavailable: $e'));
});

final placeEventsProvider = Provider<List<PlaceEvent>>((ref) {
  if (ref.watch(mockModeProvider)) return ref.watch(mockBackendProvider).placeEvents;
  final out = <PlaceEvent>[];
  for (final f in ref.watch(friendsProvider).value ?? const <FriendEntry>[]) {
    out.addAll(ref.watch(friendPlaceEventsProvider(f)).value ?? const []);
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return out.take(10).toList();
});

/// いま進行中の合流。無ければ null。
final meetupProvider = Provider<Meetup?>((ref) {
  if (ref.watch(mockModeProvider)) return ref.watch(mockBackendProvider).meetup;
  return ref.watch(activeMeetupProvider).value;
});

final activeMeetupProvider = StreamProvider<Meetup?>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null || ref.watch(mockModeProvider)) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .collection('meetups')
      .where('memberUids', arrayContains: uid)
      .where('active', isEqualTo: true)
      .limit(1)
      .snapshots()
      .map((q) => q.docs.isEmpty ? null : Meetup.fromDoc(q.docs.first));
});

/// 相手ごとのやりとり。
final chatProvider = Provider.family<List<ChatMessage>, String>((ref, friendUid) {
  if (ref.watch(mockModeProvider)) return ref.watch(mockBackendProvider).chats[friendUid] ?? const [];
  return ref.watch(chatStreamProvider(friendUid)).value ?? const [];
});

/// スレッド名は uid を並べ替えて繋いだもの。どちらから見ても同じ名前になる。
String threadIdOf(String a, String b) => ([a, b]..sort()).join('_');

final chatStreamProvider = StreamProvider.family<List<ChatMessage>, String>((ref, friendUid) {
  final uid = ref.watch(uidProvider);
  if (uid == null || ref.watch(mockModeProvider)) return Stream.value(const <ChatMessage>[]);
  return ref
      .watch(firestoreProvider)
      .collection('messages')
      .doc(threadIdOf(uid, friendUid))
      .collection('list')
      .orderBy('at')
      .limit(200)
      .snapshots()
      .map((q) => q.docs.map(ChatMessage.fromDoc).toList());
});

/// 未読の代わりに「最後の一言」だけ持つ。一覧のプレビュー用。
final lastMessageProvider = Provider.family<ChatMessage?, String>((ref, friendUid) {
  final list = ref.watch(chatProvider(friendUid));
  return list.isEmpty ? null : list.last;
});

// ------------------------------------------------------------------ 位置共有
/// フレンドへの位置共有のマスタースイッチ。
///
/// 相手ごとの許可(FriendEntry.shareLocation)とは別で、こちらが元栓。
/// オフの間は位置ストリームを起動すらしない ── 災害時に電池を削らないため。
final locationSharingProvider = StateNotifierProvider<LocationSharingNotifier, bool>((ref) => LocationSharingNotifier(ref));

class LocationSharingNotifier extends StateNotifier<bool> {
  final Ref ref;
  LocationUploader? _uploader;
  LocationSharingNotifier(this.ref) : super(false) {
    _load();
  }

  Future<void> _load() async {
    final on = (await SharedPreferences.getInstance()).getBool('shareLocation') ?? false;
    state = on;
    if (on) await _startUploader();
  }

  /// オンにするときだけ権限を尋ねる。断られたらスイッチを戻す
  /// (オンに見えるのに送っていない、という嘘の状態を作らない)。
  Future<bool> set(bool v) async {
    if (v) {
      final ok = await LocationUploader.ensureAlwaysPermission();
      if (!ok) {
        state = false;
        return false;
      }
      await _startUploader();
    } else {
      await _uploader?.stop();
      _uploader = null;
    }
    state = v;
    (await SharedPreferences.getInstance()).setBool('shareLocation', v);
    return true;
  }

  Future<void> _startUploader() async {
    if (ref.read(mockModeProvider)) return; // モックは送らない
    _uploader ??= LocationUploader(ref.read(apiProvider), await PendingLocations.open());
    await _uploader!.start();
  }

  @override
  void dispose() {
    _uploader?.stop();
    super.dispose();
  }
}

/// 送信待ちの件数。設定画面に出して、圏外で溜まっていることが分かるようにする。
final pendingLocationCountProvider = FutureProvider<int>((ref) async {
  ref.watch(locationSharingProvider);
  return (await PendingLocations.open()).length;
});

// ------------------------------------------------------------------ 基図
/// 地図の見た目。端末に覚えさせて、起動しても選んだままにする。
final basemapProvider = StateNotifierProvider<BasemapNotifier, HinaBasemap>((_) => BasemapNotifier());

class BasemapNotifier extends StateNotifier<HinaBasemap> {
  BasemapNotifier() : super(HinaBasemap.esriGray) {
    _load();
  }
  Future<void> _load() async {
    final name = (await SharedPreferences.getInstance()).getString('basemap');
    state = HinaBasemap.values.firstWhere((b) => b.name == name, orElse: () => HinaBasemap.esriGray);
  }
  Future<void> set(HinaBasemap b) async {
    state = b;
    (await SharedPreferences.getInstance()).setString('basemap', b.name);
  }
}

// ------------------------------------------------------------------ 雨雲レーダー
/// 地図に雨雲を重ねるか。ホームのボタンで切り替える。
final rainOverlayProvider = StateProvider<bool>((_) => false);

/// 雨雲タイルの観測時刻。5 分ごとに更新されるので、出している間だけ引き直す。
final rainFrameProvider = FutureProvider<RainFrame?>((ref) async {
  if (!ref.watch(rainOverlayProvider)) return null;
  final t = Timer(const Duration(minutes: 5), ref.invalidateSelf);
  ref.onDispose(t.cancel);
  return fetchLatestRainFrame();
});

// ------------------------------------------------------------------ nearby shelters (peacetime map)
final mapDisasterTypeProvider = StateProvider<DisasterType>((_) => DisasterType.earthquake);

final nearbyProvider = FutureProvider<({List<ShelterInfo> shelters, HazardHere? hazard})>((ref) async {
  final loc = ref.watch(locationProvider);
  final type = ref.watch(mapDisasterTypeProvider);
  if (ref.watch(mockModeProvider)) {
    if (loc == null) return (shelters: <ShelterInfo>[], hazard: null);
    return (shelters: MockBackend.sheltersAround(loc.point, fullIds: ref.watch(mockBackendProvider).fullShelters), hazard: MockBackend.hazardHere);
  }
  if (loc == null) return (shelters: <ShelterInfo>[], hazard: null);
  final j = await ref.read(apiProvider).nearby(lat: loc.point.latitude, lng: loc.point.longitude, type: type.apiValue);
  final shelters = ((j['shelters'] as List?) ?? const []).map((e) => ShelterInfo.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  final hz = j['hazardHere'] is Map ? HazardHere.fromJson(Map<String, dynamic>.from(j['hazardHere'] as Map)) : null;
  return (shelters: shelters, hazard: hz);
});

// ------------------------------------------------------------------ demo settings
class DemoSettings {
  final bool enabled, overrideLocation, failLlm, showFlood, showTsunami, showLandslide;
  const DemoSettings({this.enabled = false, this.overrideLocation = false, this.failLlm = false, this.showFlood = true, this.showTsunami = false, this.showLandslide = false});
  DemoSettings copyWith({bool? enabled, bool? overrideLocation, bool? failLlm, bool? showFlood, bool? showTsunami, bool? showLandslide}) => DemoSettings(
        enabled: enabled ?? this.enabled,
        overrideLocation: overrideLocation ?? this.overrideLocation,
        failLlm: failLlm ?? this.failLlm,
        showFlood: showFlood ?? this.showFlood,
        showTsunami: showTsunami ?? this.showTsunami,
        showLandslide: showLandslide ?? this.showLandslide,
      );
}

final demoProvider = StateNotifierProvider<DemoNotifier, DemoSettings>((ref) => DemoNotifier(ref));

class DemoNotifier extends StateNotifier<DemoSettings> {
  final Ref ref;
  DemoNotifier(this.ref) : super(const DemoSettings()) {
    _load();
  }
  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    state = DemoSettings(enabled: sp.getBool('demoEnabled') ?? false, overrideLocation: sp.getBool('overrideEnabled') ?? false, failLlm: sp.getBool('demoFailLlm') ?? false);
  }
  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    (await SharedPreferences.getInstance()).setBool('demoEnabled', v);
  }
  Future<void> setOverride(bool v) async {
    state = state.copyWith(overrideLocation: v);
    await LocationService.setOverride(enabled: v);
    await ref.read(locationProvider.notifier).refresh();
  }
  Future<void> setFailLlm(bool v) async {
    state = state.copyWith(failLlm: v);
    (await SharedPreferences.getInstance()).setBool('demoFailLlm', v);
  }
  void setLayers({bool? flood, bool? tsunami, bool? landslide}) => state = state.copyWith(showFlood: flood, showTsunami: tsunami, showLandslide: landslide);
}

// ------------------------------------------------------------------ agent actions (used by screens)
class AgentController {
  final Ref ref;
  AgentController(this.ref);
  ApiClient get api => ref.read(apiProvider);

  /// モックモード中はサーバーを叩かず、端末内のバックエンドを動かす。
  bool get _mock => ref.read(mockModeProvider);
  MockBackend get _backend => ref.read(mockBackendProvider.notifier);

  Future<Map<String, dynamic>> runForAlert(String alertId, {bool force = false}) async {
    ref.read(agentBusyProvider.notifier).state = true;
    try {
      final loc = await ref.read(locationProvider.notifier).refresh();
      if (_mock) {
        await _backend.fire(DisasterType.earthquake, loc.point);
        return const {'ok': true, 'mock': true};
      }
      return await api.runAgent(alertId: alertId, lat: loc.point.latitude, lng: loc.point.longitude, locationSource: loc.source, force: force, failLlm: ref.read(demoProvider).failLlm);
    } finally {
      ref.read(agentBusyProvider.notifier).state = false;
    }
  }

  Future<void> approveStart(String incidentId, {required bool byTimeout}) async {
    if (_mock) return _backend.start(byTimeout: byTimeout);
    await api.action(incidentId: incidentId, action: 'start', via: byTimeout ? 'timeout' : 'user');
  }

  Future<void> later(String incidentId) async {
    if (_mock) return _backend.later();
    await api.action(incidentId: incidentId, action: 'later');
  }

  Future<void> arrived(String incidentId) async {
    if (_mock) return _backend.arrived();
    await api.action(incidentId: incidentId, action: 'arrived');
  }

  Future<void> safeZone(String incidentId) async {
    if (_mock) return _backend.arrived();
    await api.action(incidentId: incidentId, action: 'safe_zone');
  }

  Future<void> close(String incidentId) async {
    if (_mock) return _backend.close();
    await api.action(incidentId: incidentId, action: 'close');
  }

  Future<Map<String, dynamic>> reselect(String incidentId, {String reason = 'user'}) async {
    ref.read(agentBusyProvider.notifier).state = true;
    try {
      final loc = ref.read(locationProvider) ?? await ref.read(locationProvider.notifier).refresh();
      if (_mock) {
        _backend.reselect(loc.point, reason: reason);
        return const {'ok': true, 'mock': true};
      }
      return await api.reselect(incidentId: incidentId, lat: loc.point.latitude, lng: loc.point.longitude, locationSource: loc.source, reason: reason);
    } finally {
      ref.read(agentBusyProvider.notifier).state = false;
    }
  }

  /// 誘導中の位置報告。モックでは残り時間をタイマーで進めているので何もしない。
  Future<Map<String, dynamic>> reportPosition(String incidentId, LatLng p) async {
    if (_mock) return const {'ok': true, 'mock': true};
    return api.position(incidentId: incidentId, lat: p.latitude, lng: p.longitude);
  }
}

final agentControllerProvider = Provider((ref) => AgentController(ref));

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/location_service.dart';
import '../domain/models.dart';
import '../domain/senavi.dart';

final apiProvider = Provider((_) => ApiClient());
final firestoreProvider = Provider((_) => FirebaseFirestore.instance);

/// Anonymous auth user (signed in at startup).
final authUserProvider = StreamProvider<User?>((_) => FirebaseAuth.instance.authStateChanges());
final uidProvider = Provider<String?>((ref) => ref.watch(authUserProvider).value?.uid);

// ------------------------------------------------------------------ own profile
final myProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return const Stream.empty();
  return ref.watch(firestoreProvider).collection('users').doc(uid).snapshots().map((d) => d.data());
});

// ------------------------------------------------------------------ incident
/// The newest incident for this user (active or just finished). Requires index (uid asc, createdAt desc).
final latestIncidentProvider = StreamProvider<Incident?>((ref) {
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

/// Active incident only (drives Home overlay). Finished incidents stay visible for 2 minutes.
final activeIncidentProvider = Provider<Incident?>((ref) {
  final inc = ref.watch(latestIncidentProvider).value;
  if (inc == null) return null;
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
  return (
    mood: moodFor(s),
    line: lineFor(s, shelter: inc?.shelter?.name, walkMin: inc?.remainingMin ?? inc?.shelter?.walkMin, weather: ref.watch(weatherHintProvider), custom: inc?.userMessage),
  );
});

final weatherHintProvider = StateProvider<String?>((_) => null);

final agentLogProvider = StreamProvider.family<List<AgentLogEntry>, String>((ref, incidentId) {
  return ref.watch(firestoreProvider).collection('incidents').doc(incidentId).collection('agentLog').orderBy('at').snapshots().map((q) => q.docs.map(AgentLogEntry.fromDoc).toList());
});

// ------------------------------------------------------------------ friends
final friendsProvider = StreamProvider<List<FriendEntry>>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return const Stream.empty();
  return ref.watch(firestoreProvider).collection('friends').doc(uid).collection('list').where('status', isEqualTo: 'accepted').snapshots().map((q) => q.docs.map(FriendEntry.fromDoc).toList());
});

final friendStatusProvider = StreamProvider.family<FriendStatus, String>((ref, friendUid) {
  return ref.watch(firestoreProvider).collection('statuses').doc(friendUid).snapshots().map(FriendStatus.fromDoc);
});

final myStatusProvider = StreamProvider<FriendStatus>((ref) {
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

// ------------------------------------------------------------------ nearby shelters (peacetime map)
final mapDisasterTypeProvider = StateProvider<DisasterType>((_) => DisasterType.earthquake);

final nearbyProvider = FutureProvider<({List<ShelterInfo> shelters, HazardHere? hazard})>((ref) async {
  final loc = ref.watch(locationProvider);
  final type = ref.watch(mapDisasterTypeProvider);
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

  Future<Map<String, dynamic>> runForAlert(String alertId, {bool force = false}) async {
    ref.read(agentBusyProvider.notifier).state = true;
    try {
      final loc = await ref.read(locationProvider.notifier).refresh();
      return await api.runAgent(alertId: alertId, lat: loc.point.latitude, lng: loc.point.longitude, locationSource: loc.source, force: force, failLlm: ref.read(demoProvider).failLlm);
    } finally {
      ref.read(agentBusyProvider.notifier).state = false;
    }
  }

  Future<void> approveStart(String incidentId, {required bool byTimeout}) => api.action(incidentId: incidentId, action: 'start', via: byTimeout ? 'timeout' : 'user');
  Future<void> later(String incidentId) => api.action(incidentId: incidentId, action: 'later');
  Future<void> arrived(String incidentId) => api.action(incidentId: incidentId, action: 'arrived');
  Future<void> safeZone(String incidentId) => api.action(incidentId: incidentId, action: 'safe_zone');
  Future<void> close(String incidentId) => api.action(incidentId: incidentId, action: 'close');

  Future<Map<String, dynamic>> reselect(String incidentId, {String reason = 'user'}) async {
    ref.read(agentBusyProvider.notifier).state = true;
    try {
      final loc = ref.read(locationProvider) ?? await ref.read(locationProvider.notifier).refresh();
      return await api.reselect(incidentId: incidentId, lat: loc.point.latitude, lng: loc.point.longitude, locationSource: loc.source, reason: reason);
    } finally {
      ref.read(agentBusyProvider.notifier).state = false;
    }
  }

  Future<Map<String, dynamic>> reportPosition(String incidentId, LatLng p) => api.position(incidentId: incidentId, lat: p.latitude, lng: p.longitude);
}

final agentControllerProvider = Provider((ref) => AgentController(ref));

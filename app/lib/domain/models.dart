import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// Server-side incident state (設計書 §6.1).
enum IncidentState {
  idle,
  assessing,
  notRelevant,
  monitoringStay,
  proposing,
  guiding,
  reselecting,
  arrived,
  safeZone,
  fallbackGuiding,
  closed,
  offline;

  static IncidentState parse(String? s) => switch (s) {
        'assessing' => assessing,
        'not_relevant' => notRelevant,
        'monitoring_stay' => monitoringStay,
        'proposing' => proposing,
        'guiding' => guiding,
        'reselecting' => reselecting,
        'arrived' => arrived,
        'safe_zone' => safeZone,
        'fallback_guiding' => fallbackGuiding,
        'closed' => closed,
        _ => idle,
      };

  bool get isActive => this != idle && this != closed && this != notRelevant;
  bool get isGuiding => this == guiding || this == fallbackGuiding || this == reselecting;
  bool get isFinished => this == arrived || this == safeZone || this == closed;
}

/// What friends see (statuses/{uid}.state).
enum PublicStatus {
  safe,
  assessing,
  evacuating,
  arrived,
  safeZone,
  unknown;

  static PublicStatus parse(String? s) => switch (s) {
        'safe' => safe,
        'assessing' => assessing,
        'evacuating' => evacuating,
        'arrived' => arrived,
        'safe_zone' => safeZone,
        _ => unknown,
      };

  String get label => switch (this) {
        safe => '安全',
        assessing => '確認中',
        evacuating => '避難中',
        arrived => '到着',
        safeZone => '安全地帯',
        unknown => '不明',
      };
}

enum DisasterType {
  earthquake,
  heavyRain,
  flood,
  tsunami,
  landslide,
  stormSurge;

  static DisasterType parse(String? s) => switch (s) {
        'heavy_rain' => heavyRain,
        'flood' => flood,
        'tsunami' => tsunami,
        'landslide' => landslide,
        'storm_surge' => stormSurge,
        _ => earthquake,
      };
  String get apiValue => switch (this) {
        earthquake => 'earthquake',
        heavyRain => 'heavy_rain',
        flood => 'flood',
        tsunami => 'tsunami',
        landslide => 'landslide',
        stormSurge => 'storm_surge',
      };
  String get label => switch (this) {
        earthquake => '地震',
        heavyRain => '大雨',
        flood => '洪水',
        tsunami => '津波',
        landslide => '土砂災害',
        stormSurge => '高潮',
      };
}

class ShelterInfo {
  final String id, name, address;
  final LatLng point;
  final int walkMin, distanceM;
  final double? elevationM;
  final int crowdPct;
  final bool full;
  const ShelterInfo({required this.id, required this.name, required this.address, required this.point, required this.walkMin, required this.distanceM, this.elevationM, this.crowdPct = 0, this.full = false});

  factory ShelterInfo.fromJson(Map<String, dynamic> j) => ShelterInfo(
        id: j['id'] as String,
        name: (j['name'] ?? '避難場所') as String,
        address: (j['address'] ?? '') as String,
        point: LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
        walkMin: (j['walkMin'] as num?)?.toInt() ?? 0,
        distanceM: (j['distanceM'] as num?)?.toInt() ?? 0,
        elevationM: (j['elevationM'] as num?)?.toDouble(),
        crowdPct: (j['crowdPct'] as num?)?.toInt() ?? 0,
        full: j['full'] == true,
      );
}

class RouteInfo {
  final List<LatLng> points;
  final int distanceM, durationS;
  final String provider;
  const RouteInfo({required this.points, required this.distanceM, required this.durationS, required this.provider});
  factory RouteInfo.fromJson(Map<String, dynamic> j) => RouteInfo(
        points: ((j['points'] as List?) ?? const []).map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())).toList(),
        distanceM: (j['distanceM'] as num?)?.toInt() ?? 0,
        durationS: (j['durationS'] as num?)?.toInt() ?? 0,
        provider: (j['provider'] ?? 'straight') as String,
      );
}

class Incident {
  final String id;
  final IncidentState state;
  final String alertTitle;
  final DisasterType type;
  final ShelterInfo? shelter;
  final RouteInfo? route;
  final List<String> reasons;
  final String userMessage;
  final String validatedBy;
  final double costUsd;
  final int llmCalls;
  final int? remainingMin;
  final String locationSource;
  final DateTime? createdAt;

  const Incident({required this.id, required this.state, required this.alertTitle, required this.type, this.shelter, this.route, required this.reasons, required this.userMessage, required this.validatedBy, required this.costUsd, required this.llmCalls, this.remainingMin, required this.locationSource, this.createdAt});

  factory Incident.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? {};
    return Incident(
      id: d.id,
      state: IncidentState.parse(j['state'] as String?),
      alertTitle: (j['alertTitle'] ?? '') as String,
      type: DisasterType.parse(j['alertType'] as String?),
      shelter: j['shelter'] is Map ? ShelterInfo.fromJson(Map<String, dynamic>.from(j['shelter'] as Map)) : null,
      route: j['route'] is Map ? RouteInfo.fromJson(Map<String, dynamic>.from(j['route'] as Map)) : null,
      reasons: ((j['reasons'] as List?) ?? const []).map((e) => e.toString()).toList(),
      userMessage: (j['userMessage'] ?? '') as String,
      validatedBy: (j['validatedBy'] ?? 'none') as String,
      costUsd: ((j['cost'] as Map?)?['totalUsd'] as num?)?.toDouble() ?? 0,
      llmCalls: ((j['cost'] as Map?)?['llmCalls'] as num?)?.toInt() ?? 0,
      remainingMin: (j['remainingMin'] as num?)?.toInt(),
      locationSource: (j['locationSource'] ?? 'gps') as String,
      createdAt: DateTime.tryParse((j['createdAt'] ?? '') as String),
    );
  }
}

class FriendEntry {
  final String uid, displayName;
  final String? relation;
  final bool autoShare, isMock;
  const FriendEntry({required this.uid, required this.displayName, this.relation, required this.autoShare, this.isMock = false});
  factory FriendEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? {};
    return FriendEntry(uid: d.id, displayName: (j['displayName'] ?? '友だち') as String, relation: j['relation'] as String?, autoShare: j['autoShare'] != false, isMock: j['isMock'] == true);
  }
}

class FriendStatus {
  final PublicStatus state;
  final String? shelterName, note;
  final DateTime? updatedAt;
  const FriendStatus({required this.state, this.shelterName, this.note, this.updatedAt});
  static const unknown = FriendStatus(state: PublicStatus.unknown);
  factory FriendStatus.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data();
    if (j == null) return unknown;
    return FriendStatus(state: PublicStatus.parse(j['state'] as String?), shelterName: j['shelterName'] as String?, note: j['note'] as String?, updatedAt: (j['updatedAt'] as Timestamp?)?.toDate());
  }
}

enum LogKind { toolCall, toolResult, llmRequest, llmResponse, validator, fallback, action, approval, cost, info;
  static LogKind parse(String? s) => switch (s) {
        'tool_call' => toolCall, 'tool_result' => toolResult, 'llm_request' => llmRequest, 'llm_response' => llmResponse,
        'validator' => validator, 'fallback' => fallback, 'action' => action, 'approval' => approval, 'cost' => cost, _ => info,
      };
}

class AgentLogEntry {
  final int seq;
  final DateTime at;
  final LogKind kind;
  final String title;
  final String? detail, audience, toolName, chosenBy, model, router, sessionTier, promptRef;
  final int? fallbackLevel, latencyMs;
  final double? costUsd;
  final Object? payload;
  const AgentLogEntry({required this.seq, required this.at, required this.kind, required this.title, this.detail, this.audience, this.toolName, this.chosenBy, this.model, this.router, this.sessionTier, this.promptRef, this.fallbackLevel, this.latencyMs, this.costUsd, this.payload});
  factory AgentLogEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? {};
    return AgentLogEntry(
      seq: (j['seq'] as num?)?.toInt() ?? 0,
      at: DateTime.tryParse((j['at'] ?? '') as String) ?? DateTime.now(),
      kind: LogKind.parse(j['kind'] as String?),
      title: (j['title'] ?? '') as String,
      detail: j['detail'] as String?,
      audience: j['audience'] as String?,
      toolName: j['toolName'] as String?,
      chosenBy: j['chosenBy'] as String?,
      model: j['model'] as String?,
      router: j['router'] as String?,
      sessionTier: j['sessionTier'] as String?,
      promptRef: j['promptRef'] as String?,
      fallbackLevel: (j['fallbackLevel'] as num?)?.toInt(),
      latencyMs: (j['latencyMs'] as num?)?.toInt(),
      costUsd: (j['costUsd'] as num?)?.toDouble(),
      payload: j['payload'],
    );
  }
  bool get forUser => audience == 'user' || audience == 'both' || audience == null;
  bool get forJudge => audience == 'judge' || audience == 'both';
}

class HazardHere {
  final int flood, tsunami;
  final String floodLabel;
  final bool landslide;
  const HazardHere({required this.flood, required this.tsunami, required this.floodLabel, required this.landslide});
  factory HazardHere.fromJson(Map<String, dynamic> j) => HazardHere(flood: (j['flood'] as num?)?.toInt() ?? 0, tsunami: (j['tsunami'] as num?)?.toInt() ?? 0, floodLabel: (j['floodLabel'] ?? '') as String, landslide: j['landslide'] == true);
}

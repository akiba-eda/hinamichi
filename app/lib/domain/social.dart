import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import 'models.dart';

/// よく行く場所。到着/出発の判定に使う。
///
/// 平時は「自宅に着いた」、災害時は「避難場所に着いた」。同じ仕組みで両方を
/// 賄う ── 災害時だけの機能にすると、いざという時に誰も設定していない。
class SavedPlace {
  final String id, name;
  final LatLng point;
  final int radiusM;
  final PlaceKind kind;

  const SavedPlace({required this.id, required this.name, required this.point, this.radiusM = 150, this.kind = PlaceKind.other});

  factory SavedPlace.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? {};
    return SavedPlace(
      id: d.id,
      name: (j['name'] ?? '場所') as String,
      point: LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
      radiusM: (j['radiusM'] as num?)?.toInt() ?? 150,
      kind: PlaceKind.parse(j['kind'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'lat': point.latitude, 'lng': point.longitude, 'radiusM': radiusM, 'kind': kind.name};
}

enum PlaceKind {
  home,
  work,
  school,
  shelter,
  other;

  static PlaceKind parse(String? s) => PlaceKind.values.firstWhere((k) => k.name == s, orElse: () => other);

  String get label => switch (this) {
        home => '自宅',
        work => '職場',
        school => '学校',
        shelter => '避難場所',
        other => 'その他',
      };
}

/// 「◯◯が自宅に着きました」。到着と出発の両方をこの形で流す。
class PlaceEvent {
  final String friendUid, friendName, placeName;
  final bool arrived;
  final DateTime at;
  const PlaceEvent({required this.friendUid, required this.friendName, required this.placeName, required this.arrived, required this.at});

  /// 名前はイベント側に持たせず、一覧の相手から受け取る ── 相手が表示名を
  /// 変えたときに、過去のできごとまで古い名前で残らないように。
  factory PlaceEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> d, FriendEntry friend) {
    final j = d.data() ?? {};
    return PlaceEvent(
      friendUid: friend.uid,
      friendName: friend.displayName,
      placeName: (j['placeName'] ?? '場所') as String,
      arrived: j['arrived'] == true,
      at: (j['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  String get line => arrived ? '$friendNameが$placeNameに着きました' : '$friendNameが$placeNameを出ました';
}

/// 合流。平時は待ち合わせ、災害時は「どの避難場所で落ち合うか」。
class Meetup {
  final String id, name;
  final LatLng point;
  final List<String> memberUids;
  final DateTime createdAt;

  /// 災害から作られた合流かどうか。UI の色と文言を変える。
  final bool fromIncident;

  const Meetup({required this.id, required this.name, required this.point, required this.memberUids, required this.createdAt, this.fromIncident = false});

  factory Meetup.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? {};
    return Meetup(
      id: d.id,
      name: (j['name'] ?? '待ち合わせ') as String,
      point: LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
      memberUids: ((j['memberUids'] as List?) ?? const []).map((e) => e.toString()).toList(),
      createdAt: (j['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      fromIncident: j['fromIncident'] == true,
    );
  }

  /// 徒歩 80m/分。避難経路の見積もりと同じ係数を使う(画面ごとに違うと混乱する)。
  static int walkMinutes(LatLng from, LatLng to) {
    const d = Distance();
    return (d(from, to) / 80).ceil().clamp(1, 999);
  }
}

/// 1 対 1 のやりとり。スタンプだけの返事も 1 件として扱う。
///
/// エージェントが本人の代わりに送る文面は承認ゲートを通す(設計書 §6.4)が、
/// 本人が自分で打つこれは別経路。ゲートは「AI が勝手に送らない」ための壁で、
/// 人が人に送ることまで止める必要はない。
class ChatMessage {
  final String id, fromUid;
  final String? text;

  /// スタンプ。text と排他。
  final String? reaction;
  final DateTime at;

  const ChatMessage({required this.id, required this.fromUid, this.text, this.reaction, required this.at});

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data() ?? {};
    return ChatMessage(
      id: d.id,
      fromUid: (j['fromUid'] ?? '') as String,
      text: j['text'] as String?,
      reaction: j['reaction'] as String?,
      at: (j['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  bool get isReaction => reaction != null && reaction!.isNotEmpty;
}

/// 送れるスタンプ。災害時に「無事」「助けて」を一押しで送れることが要点で、
/// 平時用の軽いものと混ぜてある ── 普段から使っている場所にあるから、
/// とっさに押せる。
const kReactions = <({String emoji, String label})>[
  (emoji: '👍', label: 'OK'),
  (emoji: '🙂', label: 'ありがとう'),
  (emoji: '🏃', label: '向かってる'),
  (emoji: '🏠', label: '家にいる'),
  (emoji: '✅', label: '無事'),
  (emoji: '🆘', label: '助けて'),
];

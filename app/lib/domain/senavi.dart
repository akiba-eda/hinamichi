import 'models.dart';

/// セナヴィの表情 — assets/senavi/{name}.png
enum SenaviMood {
  normal, serious, surprised, smile, troubled, lying, running, lookback;
  String get asset => 'assets/senavi/$name.png';
  String get smallAsset => 'assets/senavi_small/$name.png';
}

/// 設計書 §17.4 — state → mood / line. Single source for every screen.
SenaviMood moodFor(IncidentState s) => switch (s) {
      IncidentState.idle => SenaviMood.normal,
      IncidentState.assessing => SenaviMood.serious,
      IncidentState.proposing => SenaviMood.serious,
      IncidentState.guiding => SenaviMood.running,
      IncidentState.reselecting => SenaviMood.surprised,
      IncidentState.arrived || IncidentState.safeZone => SenaviMood.smile,
      IncidentState.notRelevant || IncidentState.monitoringStay => SenaviMood.normal,
      IncidentState.fallbackGuiding => SenaviMood.serious,
      IncidentState.closed => SenaviMood.normal,
      IncidentState.offline => SenaviMood.troubled,
    };

String lineFor(IncidentState s, {String? shelter, int? walkMin, String? weather, String? custom}) {
  if (custom != null && custom.isNotEmpty && (s == IncidentState.proposing || s == IncidentState.guiding || s == IncidentState.monitoringStay)) return custom;
  return switch (s) {
    IncidentState.idle => '今日は${weather ?? 'おだやか'}。お出かけ気をつけて',
    IncidentState.assessing => 'ちょっと待ってね、確認してる',
    IncidentState.proposing => '${shelter ?? '避難場所'}へ。徒歩${walkMin ?? '-'}分。一緒に行こう',
    IncidentState.guiding => 'あと${walkMin ?? '-'}分。このまま進もう',
    IncidentState.reselecting => 'あっちは混んでる。こっちに変えるね',
    IncidentState.arrived || IncidentState.safeZone => '無事に着いたよ。みんなに伝えたよ',
    IncidentState.notRelevant => '今回は大丈夫。念のため様子を見てるね',
    IncidentState.monitoringStay => '今は動かない方が安全。ここで待とう',
    IncidentState.fallbackGuiding => '返事が遅いから、安全ルールで決めたよ',
    IncidentState.closed => 'おつかれさま。また何かあったら呼んでね',
    IncidentState.offline => '電波が弱いみたい。最後に決めた道を進もう',
  };
}

import 'models.dart';
import 'weather.dart';

/// セナヴィの表情 — assets/senavi/{name}.png
enum SenaviMood {
  normal, serious, surprised, smile, troubled, lying, running, lookback;
  String get asset => 'assets/senavi/$name.png';
  String get smallAsset => 'assets/senavi_small/$name.png';
}

/// 設計書 §17.4 — state → mood / line. Single source for every screen.
///
/// 2026-09-20 のセナヴィ表情シート(docs/senavi_sheet_v2.png)に合わせて
/// 3 つ差し替えた。シートは 8 枚の絵に状態ラベルが直接振られており、
/// §17.4 の当初案より細かく描き分けられている:
///   避難提案   → lookback (「一緒に行こう」と振り向いて呼びかける絵)
///   対象外/様子見 → lying   (「念のため様子を見てるね」と伏せる絵)
///   AI応答なし → troubled (「返事が遅いから安全ルールで決めたよ」の絵)
SenaviMood moodFor(IncidentState s) => switch (s) {
      IncidentState.idle => SenaviMood.normal,
      IncidentState.assessing => SenaviMood.serious,
      IncidentState.proposing => SenaviMood.lookback,
      IncidentState.guiding => SenaviMood.running,
      IncidentState.reselecting => SenaviMood.surprised,
      IncidentState.arrived || IncidentState.safeZone => SenaviMood.smile,
      IncidentState.notRelevant || IncidentState.monitoringStay => SenaviMood.lying,
      IncidentState.fallbackGuiding => SenaviMood.troubled,
      IncidentState.closed => SenaviMood.normal,
      IncidentState.offline => SenaviMood.troubled,
    };

/// 平時(idle)の表情は災害の状態では決まらないので、雨雲の見通しから選ぶ。
/// 「災害が起きていないときも意味がある」ための表情割り当て。
SenaviMood moodForWeather(RainNowcast? w) => switch (w?.outlook) {
      null || RainOutlook.calm || RainOutlook.cloudy => SenaviMood.normal,
      RainOutlook.clear => SenaviMood.smile,
      RainOutlook.rainSoon => SenaviMood.lookback,
      RainOutlook.strongRainSoon => SenaviMood.serious,
      RainOutlook.rainNow => SenaviMood.serious,
      RainOutlook.strongRainNow => SenaviMood.troubled,
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

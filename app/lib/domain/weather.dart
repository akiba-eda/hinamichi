/// 平時の雨雲ナウキャスト(直近 60 分)。
///
/// 災害が起きていないときにアプリを開く理由を作るための情報。
/// 提供元(気象庁 / Yahoo! 気象情報 / Open-Meteo のいずれか)はサーバー側で
/// 吸収し、アプリはこの形だけを知る。
class RainNowcast {
  /// いまの降水強度 (mm/h)。
  final double nowMmh;

  /// 60 分以内の最大降水強度 (mm/h)。
  final double maxMmh;

  /// 降り始めるまでの分。いま降っている / 60分以内に降らないなら null。
  final int? startsInMin;

  /// 止むまでの分。いま降っていない / 60分以内に止まないなら null。
  final int? stopsInMin;

  /// 雲量 (%)。取れない提供元もあるので nullable。
  final int? cloudPct;

  const RainNowcast({
    required this.nowMmh,
    required this.maxMmh,
    this.startsInMin,
    this.stopsInMin,
    this.cloudPct,
  });

  factory RainNowcast.fromJson(Map<String, dynamic> j) => RainNowcast(
        nowMmh: (j['nowMmh'] as num?)?.toDouble() ?? 0,
        maxMmh: (j['maxMmh'] as num?)?.toDouble() ?? 0,
        startsInMin: (j['startsInMin'] as num?)?.toInt(),
        stopsInMin: (j['stopsInMin'] as num?)?.toInt(),
        cloudPct: (j['cloudPct'] as num?)?.toInt(),
      );

  /// 気象庁の雨の強さの表現に合わせた閾値。
  /// 10mm/h 以上 = やや強い雨、20mm/h 以上 = 強い雨。
  static const _strong = 10.0;

  bool get rainingNow => nowMmh >= 0.5;
  bool get strongNow => nowMmh >= _strong;
  bool get strongSoon => maxMmh >= _strong;

  RainOutlook get outlook {
    if (strongNow) return RainOutlook.strongRainNow;
    if (rainingNow) return RainOutlook.rainNow;
    if (startsInMin != null) return strongSoon ? RainOutlook.strongRainSoon : RainOutlook.rainSoon;
    if (cloudPct != null && cloudPct! <= 20) return RainOutlook.clear;
    if (cloudPct != null && cloudPct! >= 80) return RainOutlook.cloudy;
    return RainOutlook.calm;
  }
}

enum RainOutlook { clear, calm, cloudy, rainSoon, strongRainSoon, rainNow, strongRainNow }

/// 平時のセナヴィの一言。災害時の文面(senavi.dart の lineFor)と同じ口調で揃える。
String weatherLine(RainNowcast? w) {
  if (w == null) return '今日はおだやか。お出かけ気をつけて';
  return switch (w.outlook) {
    RainOutlook.clear => 'しばらく快晴みたい。お出かけ日和だね',
    RainOutlook.calm => 'しばらく雨は降らなさそう。いってらっしゃい',
    RainOutlook.cloudy => '曇ってるけど雨は降らなさそう。いってらっしゃい',
    RainOutlook.rainSoon => 'あと${w.startsInMin}分くらいで雨が降りそう。傘があると安心',
    RainOutlook.strongRainSoon => 'あと${w.startsInMin}分くらいで強い雨が降りそう。急ごう',
    RainOutlook.rainNow => '雨が降ってるよ。足元に気をつけて',
    RainOutlook.strongRainNow => '強い雨が降ってる。無理せず屋内にいよう',
  };
}

/// 吹き出しの下に出す補足。何を見て言っているのかが分かるようにする。
///
/// 雨に動きがないときは null を返し、呼び出し側でハザードの補足に譲る
/// (「雨は降らなさそう」と「この場所: 浸水 0.5〜3m」なら後者の方が役に立つ)。
String? weatherSub(RainNowcast? w) {
  if (w == null) return null;
  return switch (w.outlook) {
    RainOutlook.rainNow || RainOutlook.strongRainNow =>
      '今 ${w.nowMmh.toStringAsFixed(1)}mm/h${w.stopsInMin != null ? ' / あと${w.stopsInMin}分でやみそう' : ''}',
    RainOutlook.rainSoon || RainOutlook.strongRainSoon => '60分以内の最大 ${w.maxMmh.toStringAsFixed(1)}mm/h',
    _ => null,
  };
}

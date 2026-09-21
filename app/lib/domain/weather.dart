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

/// 平時のセナヴィの一言。
///
/// **言えるのは1時間先までにする。** 雨の有無はレーダー(降水ナウキャスト)の
/// 0〜60分から出していて、それ以上先は見ていない。雲量だけは府県予報
/// (半日〜1日単位)から補っているので、「空が青い」と空の話に留めて、
/// 時間の保証は雨の側だけが持つ。
///
/// 口調はセナヴィ本人。平時は毎日開いてもらう場所なので、やわらかく喋る。
/// ただし**雨の強さと時間は削らない** ── 傘を持つかの判断材料なので、
/// かわいさで潰すと役に立たなくなる。災害時の文面(senavi.dart)は別で、
/// そちらは落ち着いた言い方のまま。ここと同じ調子にすると、いざという時に
/// 軽く見える。
String weatherLine(RainNowcast? w) {
  // 取れなかったときに天気を断定しない。何も見ていない。
  if (w == null) return '天気を見てくるね';
  return switch (w.outlook) {
    RainOutlook.clear => '空が青いワン！1時間は降らないよ',
    RainOutlook.calm => '1時間は降らなそう。だいじょうぶ',
    RainOutlook.cloudy => '曇ってるけど、1時間は降らないよ',
    RainOutlook.rainSoon => 'あと${w.startsInMin}分で雨だよ。傘、持った？',
    RainOutlook.strongRainSoon => 'あと${w.startsInMin}分で強い雨！急ごう',
    // 止む時刻が読めるならそれが一番知りたいこと。読めないなら「続く」と言う。
    RainOutlook.rainNow => w.stopsInMin != null ? 'あと${w.stopsInMin}分でやみそう。もう少し' : '1時間は雨が続きそう',
    RainOutlook.strongRainNow =>
      w.stopsInMin != null ? '強い雨。あと${w.stopsInMin}分でやみそう' : '強い雨が続くよ。おうちにいよう',
  };
}

/// 吹き出しの下に出す補足。何を見て言っているのかが分かるようにする。
///
/// 雨に動きがないときは null を返し、呼び出し側でハザードの補足に譲る
/// (「雨は降らなさそう」と「この場所: 浸水 0.5〜3m」なら後者の方が役に立つ)。
String? weatherSub(RainNowcast? w) {
  if (w == null) return null;
  return switch (w.outlook) {
    RainOutlook.rainNow || RainOutlook.strongRainNow => '今 ${w.nowMmh.toStringAsFixed(1)}mm/h',
    RainOutlook.rainSoon || RainOutlook.strongRainSoon => '60分以内の最大 ${w.maxMmh.toStringAsFixed(1)}mm/h',
    _ => null,
  };
}

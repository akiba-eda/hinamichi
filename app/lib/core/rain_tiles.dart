import 'dart:convert';

import 'package:http/http.dart' as http;

/// 雨雲レーダー(気象庁 高解像度降水ナウキャスト)のタイルを引くための時刻。
///
/// タイルの URL に観測時刻が入るので、先に「いまの観測はいつのものか」を
/// 引いてくる必要がある。5 分ごとに更新される。
class RainFrame {
  final String basetime, validtime;
  final DateTime at;
  const RainFrame(this.basetime, this.validtime, this.at);

  /// `hrpns` は z=10 までしか無い。これ以上は空タイルが 200 で返ってくるので、
  /// 拡大時は z10 のタイルを引き伸ばして使う。
  static const maxNativeZoom = 10;

  String get urlTemplate =>
      'https://www.jma.go.jp/bosai/jmatile/data/nowc/$basetime/none/$validtime/surf/hrpns/{z}/{x}/{y}.png';
}

/// 最新の観測時刻。取れなければ null(雨雲を出さないだけで、地図は成立する)。
Future<RainFrame?> fetchLatestRainFrame() async {
  try {
    final r = await http
        .get(Uri.parse('https://www.jma.go.jp/bosai/jmatile/data/nowc/targetTimes_N1.json'))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final list = jsonDecode(r.body) as List;
    if (list.isEmpty) return null;
    // 新しい順に並んでいる。
    final j = list.first as Map<String, dynamic>;
    final b = j['basetime'] as String?, v = j['validtime'] as String?;
    if (b == null || v == null) return null;
    return RainFrame(b, v, _parse(v));
  } catch (_) {
    return null;
  }
}

/// "20260921063000" → DateTime(UTC)。
DateTime _parse(String s) => DateTime.utc(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
      int.parse(s.substring(8, 10)),
      int.parse(s.substring(10, 12)),
    );

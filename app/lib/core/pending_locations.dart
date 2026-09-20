import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 送れなかった位置の控え。
///
/// 「ネットが死んでも最後にいた場所がわかる」ためには、圏外の間に測った位置を
/// 捨てないことが要る。回線が戻った瞬間に古い順へ送り直し、サーバーは観測時刻
/// (at)の新しい方を採用する。
///
/// SharedPreferences に JSON の配列として持つ。件数を絞っているのは、長時間の
/// 圏外でも端末側が太らないようにするため ── 救助に効くのは「いつ・どこ」の
/// 並びであって、秒単位の全点ではない。
class PendingLocations {
  /// 溜める上限。超えたら古いものから捨てる(新しいほうが役に立つ)。
  static const max = 120;
  static const _key = 'pendingLocations';

  final SharedPreferences _prefs;
  PendingLocations(this._prefs);

  static Future<PendingLocations> open() async => PendingLocations(await SharedPreferences.getInstance());

  List<Map<String, dynamic>> load() {
    final raw = _prefs.getStringList(_key) ?? const <String>[];
    final out = <Map<String, dynamic>>[];
    for (final s in raw) {
      try {
        out.add((jsonDecode(s) as Map).cast<String, dynamic>());
      } catch (_) {
        // 壊れた行は黙って捨てる。1 行のために全部を失う方が損。
      }
    }
    return out;
  }

  Future<void> add(Map<String, dynamic> fix) async {
    final list = _prefs.getStringList(_key) ?? <String>[];
    list.add(jsonEncode(fix));
    // 先頭(古い方)から落とす。
    final trimmed = list.length > max ? list.sublist(list.length - max) : list;
    await _prefs.setStringList(_key, trimmed);
  }

  /// 送信に成功した分を先頭から取り除く。
  Future<void> drop(int count) async {
    final list = _prefs.getStringList(_key) ?? <String>[];
    await _prefs.setStringList(_key, count >= list.length ? <String>[] : list.sublist(count));
  }

  Future<void> clear() => _prefs.remove(_key);

  int get length => (_prefs.getStringList(_key) ?? const <String>[]).length;
}

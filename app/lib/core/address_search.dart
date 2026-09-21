import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class AddressHit {
  final String title;
  final LatLng point;
  const AddressHit(this.title, this.point);
}

/// 住所・地名から座標を引く(国土地理院 地名検索。無料・キー不要)。
///
/// GPS が取れないときに、本人が「いまここ」を入れるためだけに使う。
/// 入力した文字列も結果もサーバーには送らない ── 端末から直接引いて、
/// 選ばれた座標だけを以降の通常フローに流す。
Future<List<AddressHit>> searchAddress(String query, {int limit = 8}) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final uri = Uri.parse('https://msearch.gsi.go.jp/address-search/AddressSearch?q=${Uri.encodeQueryComponent(q)}');
  final r = await http.get(uri).timeout(const Duration(seconds: 10));
  if (r.statusCode != 200) throw '住所を検索できませんでした(${r.statusCode})';
  final list = jsonDecode(utf8.decode(r.bodyBytes));
  if (list is! List) return const [];
  final out = <AddressHit>[];
  for (final e in list) {
    final c = (e as Map)['geometry']?['coordinates'];
    final title = (e['properties']?['title'] ?? '').toString();
    // 返ってくるのは [経度, 緯度] の順。取り違えると日本の外に飛ぶ。
    if (c is List && c.length >= 2 && title.isNotEmpty) {
      out.add(AddressHit(title, LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())));
    }
    if (out.length >= limit) break;
  }
  return out;
}

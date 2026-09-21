import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'notifications.dart';

/// いま自分がいる市区町村。**警報を自分宛てに絞るためだけ**に使う。
///
/// 座標はサーバーに預けない。市区町村コードだけを端末が持ち、そのコードの
/// FCM トピックを購読する ── こうすると「その土地に警報が出たときだけ鳴る」を、
/// サーバーが誰の居場所も知らないまま実現できる。
class MyArea {
  static const _kCode = 'my_area_class20';
  static const _kLat = 'my_area_lat';
  static const _kLng = 'my_area_lng';

  /// これ以上動いたら市区町村が変わったかもしれないので引き直す。
  static const _refreshM = 1500.0;

  final ApiClient _api;
  MyArea(this._api);

  String? _code;

  /// 端末が把握している自分の市区町村コード(7桁)。まだ引けていなければ null。
  String? get code => _code;

  Future<void> load() async {
    _code = (await SharedPreferences.getInstance()).getString(_kCode);
  }

  /// 現在地から市区町村を引き直し、変わっていればトピックを張り替える。
  Future<void> update(LatLng here) async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_kLat), lng = prefs.getDouble(_kLng);
    if (_code != null && lat != null && lng != null && const Distance()(LatLng(lat, lng), here) < _refreshM) return;

    try {
      final j = await _api.myArea(lat: here.latitude, lng: here.longitude);
      final next = j['class20'] as String?;
      if (next == null) return;
      if (next != _code) {
        // 前の土地の警報で鳴り続けないよう、先に外す。
        if (_code != null) await Notifications.unsubscribeArea(_code!);
        await Notifications.subscribeArea(next);
        _code = next;
        await prefs.setString(_kCode, next);
      }
      await prefs.setDouble(_kLat, here.latitude);
      await prefs.setDouble(_kLng, here.longitude);
    } catch (e) {
      // 引けなくても致命傷ではない。全国向けの通知(地震)は従来どおり届く。
      debugPrint('[MyArea] update failed: $e');
    }
  }

  /// このアラートが自分に関係あるか。対象が空なら全国向け(地震など)。
  bool matches(List<String> areaCodes) => areaCodes.isEmpty || (_code != null && areaCodes.contains(_code));
}

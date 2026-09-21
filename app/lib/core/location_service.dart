import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 実際の位置がどうしても取れなかったとき。
///
/// 以前はここで開発用の固定地点に落として動かし続けていたが、それは
/// **その土地と無関係な避難所を自信たっぷりに案内する**ことになる。
/// 防災アプリで一番やってはいけない嘘なので、取れないときは取れないと言い、
/// 仮の現在地を本人に入れてもらう。
class LocationUnavailable implements Exception {
  const LocationUnavailable();
  @override
  String toString() => '位置が取得できません';
}

class ResolvedLocation {
  final LatLng point;
  final String source; // gps | cached | manual
  const ResolvedLocation(this.point, this.source);
}

/// 設計書 §19.3 — 実GPS を最優先。取れなければ 10 分以内のキャッシュ、
/// それも無ければ本人が入れた仮の現在地、どれも無ければ失敗を返す。
class LocationService {
  static LatLng? _last;
  static DateTime? _lastAt;

  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  // ---- 仮の現在地(本人が住所で入れたもの)。既定値は持たない。 ----

  static Future<LatLng?> manualPoint() async {
    final sp = await SharedPreferences.getInstance();
    final lat = sp.getDouble('manualLat'), lng = sp.getDouble('manualLng');
    return (lat == null || lng == null) ? null : LatLng(lat, lng);
  }

  static Future<String?> manualLabel() async => (await SharedPreferences.getInstance()).getString('manualLabel');

  /// [force] は「GPS が取れてもこちらを使う」= リハーサル用。
  /// 取得に失敗したときの受け皿として入れる場合は false にする。
  static Future<void> setManual(LatLng p, String label, {bool force = false}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('manualLat', p.latitude);
    await sp.setDouble('manualLng', p.longitude);
    await sp.setString('manualLabel', label);
    await sp.setBool('manualForce', force);
  }

  static Future<bool> manualForced() async => (await SharedPreferences.getInstance()).getBool('manualForce') ?? false;

  static Future<void> clearManual() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('manualLat');
    await sp.remove('manualLng');
    await sp.remove('manualLabel');
    await sp.remove('manualForce');
  }

  /// Demo "move simulation" pushes points through here so the whole app follows.
  static void injectSimulated(LatLng p) {
    _last = p;
    _lastAt = DateTime.now();
  }

  static Future<ResolvedLocation> resolve({Duration gpsTimeout = const Duration(seconds: 15)}) async {
    // リハーサルで明示的に地点を固定しているときだけ、GPS より先に使う。
    if (await manualForced()) {
      final m = await manualPoint();
      if (m != null) return ResolvedLocation(m, 'manual');
    }
    try {
      if (await ensurePermission()) {
        final pos = await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: gpsTimeout));
        _last = LatLng(pos.latitude, pos.longitude);
        _lastAt = DateTime.now();
        return ResolvedLocation(_last!, 'gps');
      }
    } catch (_) {/* fall through */}
    if (_last != null && _lastAt != null && DateTime.now().difference(_lastAt!) < const Duration(minutes: 10)) {
      return ResolvedLocation(_last!, 'cached');
    }
    final m = await manualPoint();
    if (m != null) return ResolvedLocation(m, 'manual');
    throw const LocationUnavailable();
  }
}

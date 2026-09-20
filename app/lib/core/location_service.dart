import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ResolvedLocation {
  final LatLng point;
  final String source; // gps | cached | override
  const ResolvedLocation(this.point, this.source);
}

/// 設計書 §19.3 — real GPS first, then a 10-minute cache, then the demo override point.
class LocationService {
  static LatLng? _last;
  static DateTime? _lastAt;

  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  static Future<bool> overrideEnabled() async => (await SharedPreferences.getInstance()).getBool('overrideEnabled') ?? false;
  static Future<void> setOverride({required bool enabled, LatLng? point}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('overrideEnabled', enabled);
    if (point != null) {
      await sp.setDouble('overrideLat', point.latitude);
      await sp.setDouble('overrideLng', point.longitude);
    }
  }
  static Future<LatLng> overridePoint() async {
    final sp = await SharedPreferences.getInstance();
    return LatLng(sp.getDouble('overrideLat') ?? AppConfig.demoDefaultLat, sp.getDouble('overrideLng') ?? AppConfig.demoDefaultLng);
  }

  /// Demo "move simulation" pushes points through here so the whole app follows.
  static void injectSimulated(LatLng p) {
    _last = p;
    _lastAt = DateTime.now();
  }

  static Future<ResolvedLocation> resolve({Duration gpsTimeout = const Duration(seconds: 6)}) async {
    if (await overrideEnabled()) return ResolvedLocation(await overridePoint(), 'override');
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
    return ResolvedLocation(await overridePoint(), 'override');
  }
}

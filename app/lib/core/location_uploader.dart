import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'api_client.dart';
import 'pending_locations.dart';

/// 許可した相手に「最後にいた場所」を届けるための送信係。
///
/// 設計の要点は 3 つ:
///   * **止まっている間は送らない** — 距離フィルタで動いたときだけ起きる。
///     災害時は電池が命綱なので、一定間隔のポーリングにはしない。
///   * **圏外の分を捨てない** — 送れなければ端末に積み、繋がった時に古い順で流す。
///   * **観測時刻を送る** — 送信時刻ではない。まとめて届いても順序が壊れない。
class LocationUploader {
  final ApiClient _api;
  final PendingLocations _pending;
  final Battery _battery;

  LocationUploader(this._api, this._pending, {Battery? battery}) : _battery = battery ?? Battery();

  StreamSubscription<Position>? _sub;
  bool _flushing = false;

  bool get isRunning => _sub != null;

  /// iOS で常時許可まで取る。取れなければ false を返し、呼び出し側が設定を戻す。
  static Future<bool> ensureAlwaysPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    // iOS は「アプリ使用中」を一度許可させてから、改めて常時を尋ねる作りになる。
    // ここで whileInUse なら、もう一度要求して常時に上げられるか試す。
    if (p == LocationPermission.whileInUse) p = await Geolocator.requestPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  Future<void> start() async {
    if (_sub != null) return;
    final settings = defaultTargetPlatform == TargetPlatform.iOS
        ? AppleSettings(
            accuracy: LocationAccuracy.medium,
            // 50m 動いたときだけ。歩く速度なら 1 分に 1 回程度で、
            // 「最後にいた場所」には十分な粒度。
            distanceFilter: 50,
            pauseLocationUpdatesAutomatically: true,
            // 位置を送っている間は iOS のインジケータを出す。黙って測らない。
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          )
        : const LocationSettings(accuracy: LocationAccuracy.medium, distanceFilter: 50);

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      _onFix,
      onError: (Object e) => debugPrint('[LocationUploader] stream error: $e'),
      cancelOnError: false,
    );
    // 起動直後に、前回の圏外ぶんを流しておく。
    unawaited(flush());
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _onFix(Position p) async {
    final fix = <String, dynamic>{
      'lat': p.latitude,
      'lng': p.longitude,
      'at': p.timestamp.toUtc().toIso8601String(),
      'accuracyM': p.accuracy,
      'batteryPct': await _batteryPct(),
    };
    await _pending.add(fix);
    await flush();
  }

  Future<int?> _batteryPct() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return null; // 取れない端末でも位置は送る
    }
  }

  /// 溜まっている分を古い順に送る。1 件でも失敗したらそこで止める
  /// (順序を保ったまま次の機会に持ち越す)。
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      var sent = 0;
      for (final fix in _pending.load()) {
        try {
          await _api.reportLocation(
            lat: (fix['lat'] as num).toDouble(),
            lng: (fix['lng'] as num).toDouble(),
            at: DateTime.parse(fix['at'] as String),
            accuracyM: (fix['accuracyM'] as num?)?.toDouble(),
            batteryPct: (fix['batteryPct'] as num?)?.toInt(),
          );
          sent++;
        } catch (e) {
          debugPrint('[LocationUploader] upload paused after $sent: $e');
          break;
        }
      }
      if (sent > 0) await _pending.drop(sent);
    } finally {
      _flushing = false;
    }
  }
}

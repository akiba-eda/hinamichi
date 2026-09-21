import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

class ApiException implements Exception {
  final int status;
  final String code, message;
  ApiException(this.status, this.code, this.message);
  @override
  String toString() => 'ApiException($status $code): $message';
}

/// Thin client for the Vercel API. Every call carries the Firebase ID token.
class ApiClient {
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {Duration timeout = const Duration(seconds: 45)}) async {
    final base = await AppConfig.apiBase();
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final res = await http
        .post(Uri.parse('$base$path'), headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'}, body: jsonEncode(body))
        .timeout(timeout);

    // 向き先が未デプロイだと Vercel が HTML のエラーページを返す。そのまま
    // jsonDecode に渡すと FormatException になって原因が読めないので、
    // JSON でない応答は「サーバーが JSON を返していない」として扱う。
    Map<String, dynamic> json;
    try {
      json = res.body.isEmpty ? <String, dynamic>{} : (jsonDecode(res.body) as Map).cast<String, dynamic>();
    } on FormatException {
      throw ApiException(res.statusCode, 'not_json', 'API から JSON が返りませんでした ($base$path / ${res.statusCode})。設定の API サーバー URL を確認してください');
    }
    if (res.statusCode >= 400) throw ApiException(res.statusCode, (json['error'] ?? 'error').toString(), (json['message'] ?? res.reasonPhrase ?? '').toString());
    return json;
  }

  // ---- typed helpers ----
  Future<Map<String, dynamic>> register({String? displayName, String? fcmToken, String? platform, Map<String, dynamic>? consent}) =>
      post('/api/me/register', {if (displayName != null) 'displayName': displayName, if (fcmToken != null) 'fcmToken': fcmToken, if (platform != null) 'platform': platform, if (consent != null) 'consent': consent});

  Future<Map<String, dynamic>> runAgent({required String alertId, required double lat, required double lng, required String locationSource, bool force = false, bool failLlm = false}) =>
      post('/api/agent/run', {'alertId': alertId, 'lat': lat, 'lng': lng, 'locationSource': locationSource, 'force': force, if (failLlm) 'demo': {'failLlm': true}});

  Future<Map<String, dynamic>> reselect({required String incidentId, required double lat, required double lng, required String locationSource, String reason = 'user'}) =>
      post('/api/agent/reselect', {'incidentId': incidentId, 'lat': lat, 'lng': lng, 'locationSource': locationSource, 'reason': reason});

  Future<Map<String, dynamic>> action({required String incidentId, required String action, String via = 'user'}) =>
      post('/api/agent/action', {'incidentId': incidentId, 'action': action, 'via': via});

  Future<Map<String, dynamic>> position({required String incidentId, required double lat, required double lng}) =>
      post('/api/agent/position', {'incidentId': incidentId, 'lat': lat, 'lng': lng}, timeout: const Duration(seconds: 15));

  /// 平時の雨雲ナウキャスト(直近 60 分)。提供元はサーバー側で吸収する。
  Future<Map<String, dynamic>> weather({required double lat, required double lng}) =>
      post('/api/weather/nowcast', {'lat': lat, 'lng': lng}, timeout: const Duration(seconds: 15));

  /// 自分がいまどの市区町村にいるかだけを引く。サーバーは何も保存しない。
  /// 警報を自分宛てに絞るための市区町村コードを得るのが目的。
  Future<Map<String, dynamic>> myArea({required double lat, required double lng}) =>
      post('/api/me/area', {'lat': lat, 'lng': lng}, timeout: const Duration(seconds: 15));

  Future<Map<String, dynamic>> nearby({required double lat, required double lng, String type = 'earthquake'}) =>
      post('/api/shelters/nearby', {'lat': lat, 'lng': lng, 'type': type}, timeout: const Duration(seconds: 30));

  Future<Map<String, dynamic>> acceptFriend(String code, {String? relation}) => post('/api/friends/accept', {'code': code, if (relation != null) 'relation': relation});
  Future<Map<String, dynamic>> shareFriend(String friendUid, {bool? autoShare, bool? shareLocation}) =>
      post('/api/friends/share', {'friendUid': friendUid, if (autoShare != null) 'autoShare': autoShare, if (shareLocation != null) 'shareLocation': shareLocation});

  /// プロフィール(表示名 / アイコン)を更新する。
  /// avatarImage は 256px まで縮めた JPEG の base64。空文字は「消す」を意味する。
  Future<Map<String, dynamic>> setProfile({String? displayName, String? avatarImage, String? avatarMood}) =>
      post('/api/me/register', {
        if (displayName != null) 'displayName': displayName,
        if (avatarImage != null) 'avatarImage': avatarImage,
        if (avatarMood != null) 'avatarMood': avatarMood,
      });

  /// 自分のメモ(フレンドに見える一言)を更新する。
  Future<Map<String, dynamic>> setNote(String note) => post('/api/me/status', {'note': note});

  /// 最後に居た場所を送る。`at` は観測時刻で、送信時刻ではない。
  /// 圏外で溜めた分をまとめて送るので、サーバーは `at` の新しい方を採用する。
  Future<Map<String, dynamic>> reportLocation({required double lat, required double lng, required DateTime at, double? accuracyM, int? batteryPct}) =>
      post('/api/me/location', {
        'lat': lat,
        'lng': lng,
        'at': at.toUtc().toIso8601String(),
        if (accuracyM != null) 'accuracyM': accuracyM,
        if (batteryPct != null) 'batteryPct': batteryPct,
      }, timeout: const Duration(seconds: 15));
  // ---- 場所 / 合流 / やりとり ----
  Future<Map<String, dynamic>> addPlace(Map<String, dynamic> place) => post('/api/me/places', {'place': place});
  Future<Map<String, dynamic>> removePlace(String placeId) => post('/api/me/places', {'remove': placeId});

  Future<Map<String, dynamic>> startMeetup({required String name, required double lat, required double lng, required List<String> memberUids}) =>
      post('/api/meetup/start', {'name': name, 'lat': lat, 'lng': lng, 'memberUids': memberUids});
  Future<Map<String, dynamic>> endMeetup(String meetupId) => post('/api/meetup/end', {'meetupId': meetupId});

  /// 本人が自分で打つメッセージ。エージェントが代筆する経路(承認ゲート付きの
  /// messageFriends)とは別。
  Future<Map<String, dynamic>> sendMessage({required String toUid, String? text, String? reaction}) =>
      post('/api/friends/send', {'toUid': toUid, if (text != null) 'text': text, if (reaction != null) 'reaction': reaction});

  Future<Map<String, dynamic>> messageFriends(String text) => post('/api/friends/message', {'text': text});

  // ---- demo ----
  Future<Map<String, dynamic>> demoFire({required String scenario, required double lat, required double lng, required String locationSource, bool failLlm = false}) =>
      post('/api/demo/fire', {'scenario': scenario, 'lat': lat, 'lng': lng, 'locationSource': locationSource, 'runNow': true, if (failLlm) 'demo': {'failLlm': true}}, timeout: const Duration(seconds: 60));
  Future<Map<String, dynamic>> demoCrowd({required String shelterId, required bool full, required double lat, required double lng, required String locationSource}) =>
      post('/api/demo/crowd', {'shelterId': shelterId, 'full': full, 'lat': lat, 'lng': lng, 'locationSource': locationSource}, timeout: const Duration(seconds: 60));
  /// 位置を渡すと、モックのフレンドを現在地のまわりに置いてくれる(地図と
  /// 「最後にいた場所」を成立させるため)。渡さなくても安否だけは動く。
  Future<Map<String, dynamic>> demoFriends(String action, {double? lat, double? lng}) =>
      post('/api/demo/friends', {'action': action, if (lat != null) 'lat': lat, if (lng != null) 'lng': lng});
  Future<Map<String, dynamic>> demoReset() => post('/api/demo/reset', {});
}

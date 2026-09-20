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
    final json = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
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

  Future<Map<String, dynamic>> nearby({required double lat, required double lng, String type = 'earthquake'}) =>
      post('/api/shelters/nearby', {'lat': lat, 'lng': lng, 'type': type}, timeout: const Duration(seconds: 30));

  Future<Map<String, dynamic>> acceptFriend(String code, {String? relation}) => post('/api/friends/accept', {'code': code, if (relation != null) 'relation': relation});
  Future<Map<String, dynamic>> shareFriend(String friendUid, bool autoShare) => post('/api/friends/share', {'friendUid': friendUid, 'autoShare': autoShare});
  Future<Map<String, dynamic>> messageFriends(String text) => post('/api/friends/message', {'text': text});

  // ---- demo ----
  Future<Map<String, dynamic>> demoFire({required String scenario, required double lat, required double lng, required String locationSource, bool failLlm = false}) =>
      post('/api/demo/fire', {'scenario': scenario, 'lat': lat, 'lng': lng, 'locationSource': locationSource, 'runNow': true, if (failLlm) 'demo': {'failLlm': true}}, timeout: const Duration(seconds: 60));
  Future<Map<String, dynamic>> demoCrowd({required String shelterId, required bool full, required double lat, required double lng, required String locationSource}) =>
      post('/api/demo/crowd', {'shelterId': shelterId, 'full': full, 'lat': lat, 'lng': lng, 'locationSource': locationSource}, timeout: const Duration(seconds: 60));
  Future<Map<String, dynamic>> demoFriends(String action) => post('/api/demo/friends', {'action': action});
  Future<Map<String, dynamic>> demoReset() => post('/api/demo/reset', {});
}

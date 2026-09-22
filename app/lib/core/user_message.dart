import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'location_service.dart';

/// 例外を、画面に出せる日本語の一文にする。
///
/// 以前は `$e` をそのまま出していたので、`ApiException(500 error): ...` や
/// `TimeoutException after 0:00:45.000000` が利用者の画面に現れていた。
/// 何が起きたかは開発者が知りたいことで、利用者が知りたいのは
/// 「自分は何をすればいいか」。原因は debugPrint に残し、画面には後者だけ出す。
String userMessage(Object e, {String? action}) {
  debugPrint('[error] ${action ?? ''}: $e');
  final head = action == null ? '' : '$actionできませんでした。';
  return head + _reason(e);
}

String _reason(Object e) {
  if (e is String) return e; // アプリ内で意図して投げた日本語
  if (e is LocationUnavailable) return '位置が取得できていません。';
  if (e is TimeoutException) return 'サーバーの応答が遅いようです。電波の良い場所でもう一度お試しください。';
  if (e is SocketException || e is http.ClientException) return 'インターネットに接続できません。';
  if (e is ApiException) {
    switch (e.code) {
      case 'rate_limited':
        return e.message; // サーバーが利用者向けの日本語で返している
      case 'unauthenticated':
        return 'ログインの有効期限が切れました。アプリを開き直してください。';
      case 'forbidden':
        return _jp(e.message, '許可されていない操作です。');
      case 'not_found':
        return _jp(e.message, '対象が見つかりませんでした。');
      case 'bad_request':
      case 'guardrail_blocked':
        return _jp(e.message, '入力内容を確認してください。');
      case 'not_json':
        return 'サーバーに接続できません。';
    }
    if (e.status >= 500) return 'サーバーで問題が起きました。しばらくしてからもう一度お試しください。';
    return _jp(e.message, '処理できませんでした。');
  }
  return '予期しない問題が起きました。もう一度お試しください。';
}

/// サーバーのメッセージが日本語ならそのまま、英語や空なら既定の文にする。
/// サーバーは利用者向けに日本語で返す約束だが、認証や内部の失敗は英語のまま
/// 残っているものがある。それを画面に出さない。
String _jp(String msg, String fallback) {
  if (msg.isEmpty) return fallback;
  final hasJapanese = RegExp(r'[぀-ヿ一-鿿]').hasMatch(msg);
  return hasJapanese ? msg : fallback;
}

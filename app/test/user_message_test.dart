import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/core/api_client.dart';
import 'package:hinamichi/core/location_service.dart';
import 'package:hinamichi/core/user_message.dart';

void main() {
  group('例外を利用者の言葉にする', () {
    test('サーバーが日本語で返した理由はそのまま出す', () {
      expect(userMessage(ApiException(403, 'forbidden', '友だちではありません'), action: '送信'), '送信できませんでした。友だちではありません');
    });

    test('英語や内部の文言は画面に出さない', () {
      // 以前は "ApiException(500 error): ..." がそのまま利用者に見えていた。
      final m = userMessage(ApiException(500, 'error', 'TypeError: Cannot read properties of undefined'));
      expect(m, isNot(contains('TypeError')));
      expect(m, contains('サーバーで問題'));
    });

    test('通信断は接続の言葉になる', () {
      expect(userMessage(const SocketException('x'), action: '保存'), '保存できませんでした。インターネットに接続できません。');
    });

    test('タイムアウトは待ち時間の数字を出さない', () {
      final m = userMessage(TimeoutException('after 0:00:45.000000'));
      expect(m, isNot(contains('0:00:45')));
      expect(m, contains('応答が遅い'));
    });

    test('回数制限はサーバーの案内をそのまま出す', () {
      expect(userMessage(ApiException(429, 'rate_limited', '少し待ってからもう一度お試しください')), '少し待ってからもう一度お試しください');
    });

    test('位置が無いときは位置の言葉になる', () {
      expect(userMessage(const LocationUnavailable()), '位置が取得できていません。');
    });

    test('アプリ内で意図して投げた日本語はそのまま', () {
      expect(userMessage('避難誘導中ではありません'), '避難誘導中ではありません');
    });
  });
}

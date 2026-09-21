import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/domain/weather.dart';

/// セナヴィが天気について言えるのは**1時間先まで**。
/// 雨の有無はレーダー(降水ナウキャスト)の0〜60分から出していて、
/// それ以上先は見ていない。見ていない範囲を断定させないための固定。
void main() {
  RainNowcast w({double now = 0, double max = 0, int? starts, int? stops, int? cloud}) =>
      RainNowcast(nowMmh: now, maxMmh: max, startsInMin: starts, stopsInMin: stops, cloudPct: cloud);

  group('平時の一言', () {
    test('取れなかったときに天気を断定しない', () {
      final line = weatherLine(null);
      expect(line, isNot(contains('おだやか')));
      expect(line, isNot(contains('降')), reason: '見ていないのに雨の話をしている: $line');
    });

    test('雨が無いときは「1時間」と範囲を言う', () {
      for (final n in [weatherLine(w(cloud: 10)), weatherLine(w()), weatherLine(w(cloud: 90))]) {
        expect(n, contains('1時間'), reason: '見ている範囲を言っていない: $n');
      }
    });

    test('「しばらく」のような範囲の曖昧な語を使わない', () {
      for (final n in [weatherLine(null), weatherLine(w(cloud: 10)), weatherLine(w()), weatherLine(w(cloud: 90))]) {
        expect(n, isNot(contains('しばらく')), reason: '範囲が曖昧: $n');
      }
    });

    test('降り出しは分で言う(レーダーから出せる範囲)', () {
      expect(weatherLine(w(max: 3, starts: 5)), contains('あと5分'));
    });

    test('降っているとき、止む時刻が読めるならそれを言う', () {
      expect(weatherLine(w(now: 3, max: 3, stops: 15)), contains('あと15分'));
    });

    test('止む時刻が読めないときは「1時間は続きそう」と言う', () {
      // 60分以内に止まないので stopsInMin は null。黙るより、続くと言う方が役に立つ。
      // 文言そのものではなく「続くと言っている」ことを見る。口調は変わりうる。
      expect(weatherLine(w(now: 3, max: 5)), contains('続き'));
      expect(weatherLine(w(now: 15, max: 20)), allOf(contains('強い雨'), contains('続く')));
    });

    test('あいさつで文字数を使わない', () {
      for (final n in [weatherLine(null), weatherLine(w()), weatherLine(w(cloud: 10)), weatherLine(w(max: 3, starts: 5)), weatherLine(w(now: 3, max: 3))]) {
        expect(n, isNot(contains('いってらっしゃい')), reason: n);
        expect(n, isNot(contains('気をつけて')), reason: n);
        expect(n.length, lessThanOrEqualTo(20), reason: '長い: $n');
      }
    });

    // かわいさで実用情報を潰さない。傘を持つかの判断材料は残す。
    test('雨のときは強さと時間の情報が残っている', () {
      expect(weatherLine(w(max: 3, starts: 5)), contains('5分'));
      expect(weatherLine(w(max: 18, starts: 10)), allOf(contains('10分'), contains('強い雨')));
      expect(weatherLine(w(now: 15, max: 20)), contains('強い雨'));
    });
  });
}

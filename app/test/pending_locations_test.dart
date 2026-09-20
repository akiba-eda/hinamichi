import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/core/pending_locations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 圏外で測った位置を捨てないことが、この機能の前提。
/// ここが壊れると「最後にいた場所」が丸ごと消える。
void main() {
  late PendingLocations q;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    q = PendingLocations(await SharedPreferences.getInstance());
  });

  Map<String, dynamic> fix(int i) => {'lat': 35.0 + i / 1000, 'lng': 139.0, 'at': DateTime.utc(2026, 1, 1, 0, i).toIso8601String()};

  test('積んだ順に取り出せる', () async {
    for (var i = 0; i < 3; i++) {
      await q.add(fix(i));
    }
    final list = q.load();
    expect(list, hasLength(3));
    expect(list.first['at'], fix(0)['at'], reason: '古いものが先頭');
    expect(list.last['at'], fix(2)['at']);
  });

  test('送れた分だけ先頭から消える', () async {
    for (var i = 0; i < 5; i++) {
      await q.add(fix(i));
    }
    await q.drop(2);
    final list = q.load();
    expect(list, hasLength(3));
    expect(list.first['at'], fix(2)['at'], reason: '送れた2件のあとから残る');
  });

  test('全部送れたら空になる', () async {
    await q.add(fix(0));
    await q.drop(5); // 件数より多く指定しても壊れない
    expect(q.load(), isEmpty);
  });

  test('上限を超えたら古いものから捨てる', () async {
    for (var i = 0; i < PendingLocations.max + 10; i++) {
      await q.add(fix(i));
    }
    final list = q.load();
    expect(list, hasLength(PendingLocations.max));
    // 残るのは新しい方。救助に効くのは直近の位置なので。
    expect(list.last['at'], fix(PendingLocations.max + 9)['at']);
    expect(list.first['at'], fix(10)['at']);
  });

  test('壊れた行があっても他を巻き添えにしない', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pendingLocations', ['{壊れたJSON', '{"lat":35.0,"lng":139.0,"at":"2026-01-01T00:00:00Z"}']);
    final list = PendingLocations(prefs).load();
    expect(list, hasLength(1));
    expect(list.first['lat'], 35.0);
  });
}

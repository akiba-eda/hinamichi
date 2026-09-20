import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/core/api_client.dart';
import 'package:hinamichi/core/location_uploader.dart';
import 'package:hinamichi/core/pending_locations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 圏外→復帰の流れを、通信を差し替えて確かめる。
/// 途中で失敗したときに順序が壊れないことがいちばん大事。
class _FakeApi implements ApiClient {
  final List<DateTime> sent = [];

  /// この回数だけ成功し、それ以降は失敗する。
  int failAfter;
  _FakeApi({this.failAfter = 1 << 30});

  @override
  Future<Map<String, dynamic>> reportLocation({
    required double lat,
    required double lng,
    required DateTime at,
    double? accuracyM,
    int? batteryPct,
  }) async {
    if (sent.length >= failAfter) throw ApiException(503, 'offline', 'no network');
    sent.add(at);
    return const {'ok': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late PendingLocations q;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    q = PendingLocations(await SharedPreferences.getInstance());
  });

  Map<String, dynamic> fix(int minute) => {
        'lat': 35.6588,
        'lng': 139.9013,
        'at': DateTime.utc(2026, 1, 1, 0, minute).toIso8601String(),
        'accuracyM': 12.0,
        'batteryPct': 50,
      };

  test('繋がったら溜めた分を古い順に送り、キューを空にする', () async {
    for (final m in [0, 1, 2]) {
      await q.add(fix(m));
    }
    final api = _FakeApi();
    await LocationUploader(api, q).flush();

    expect(api.sent.map((d) => d.minute).toList(), [0, 1, 2], reason: '観測時刻の古い順');
    expect(q.load(), isEmpty);
  });

  test('途中で失敗したら、そこから先を次の機会に持ち越す', () async {
    for (final m in [0, 1, 2, 3]) {
      await q.add(fix(m));
    }
    final api = _FakeApi(failAfter: 2);
    await LocationUploader(api, q).flush();

    expect(api.sent.map((d) => d.minute).toList(), [0, 1]);
    // 送れた 2 件だけ消え、残りは順序のまま残る
    final left = q.load();
    expect(left, hasLength(2));
    expect(DateTime.parse(left.first['at'] as String).minute, 2);
    expect(DateTime.parse(left.last['at'] as String).minute, 3);
  });

  test('一件も送れなければ何も失わない', () async {
    await q.add(fix(0));
    final api = _FakeApi(failAfter: 0);
    await LocationUploader(api, q).flush();

    expect(api.sent, isEmpty);
    expect(q.load(), hasLength(1));
  });
}

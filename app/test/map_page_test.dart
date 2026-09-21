import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/app/theme/hina_theme.dart';
import 'package:hinamichi/domain/models.dart';
import 'package:hinamichi/features/map/map_page.dart';
import 'package:hinamichi/mock/mock_backend.dart';
import 'package:hinamichi/state/providers.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _here = LatLng(35.6588, 139.9013); // 南行徳駅(AppConfig のデモ既定値と同じ)

void main() {
  setUp(() {
    // demoProvider / LocationService が SharedPreferences を読むので先に用意する。
    SharedPreferences.setMockInitialValues({});
  });

  // マップ画面が使うのは nearbyProvider だけ。タイルはテスト環境で引けないので、
  // 「開いたのにリストが空」を検出できれば目的を果たす。
  testWidgets('近隣情報は周辺の避難場所を件数付きで並べる', (tester) async {
    final shelters = MockBackend.sheltersAround(_here);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nearbyProvider.overrideWith((ref) async => (shelters: shelters, hazard: MockBackend.hazardHere)),
        // 近隣情報はフレンド・合流を出さない(ホームに集約した)ので上書き不要。
      ],
      child: MaterialApp(theme: hinaTheme(), home: const MapPage()),
    ));
    await tester.pump();

    expect(find.text('近隣情報'), findsOneWidget);
    expect(find.text('周辺の避難場所'), findsOneWidget);
    expect(find.text('${shelters.length}件'), findsOneWidget);
    // ListView は見えている分しか組み立てないので、先頭だけ確かめる。
    // 並び順と件数そのものは下のユニットテストで押さえる。
    expect(find.text(shelters.first.name), findsOneWidget, reason: '先頭の避難所がリストに無い');
    expect(find.textContaining('徒歩 ${shelters.first.walkMin}分'), findsWidgets);
  });

  testWidgets('避難場所が無くても空の画面にはせず、セナヴィが理由を言う', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nearbyProvider.overrideWith((ref) async => (shelters: <ShelterInfo>[], hazard: null)),
      ],
      child: MaterialApp(theme: hinaTheme(), home: const MapPage()),
    ));
    await tester.pump();
    expect(find.textContaining('見つからなかった'), findsOneWidget);
  });

  // 避難所は固定座標ではなく現在地からの相対で作る。固定にすると端末の位置が
  // 変わった瞬間に全部画面外へ出て「何も出ない」ように見える。
  test('避難所は現在地の周りに生成され、徒歩分が距離と整合する', () {
    final shelters = MockBackend.sheltersAround(_here);
    expect(shelters, hasLength(5));
    const d = Distance();
    for (final s in shelters) {
      expect(d(_here, s.point), lessThan(1500), reason: '${s.name} が探索半径(1.5km)の外');
      expect(s.walkMin, (s.distanceM / 80).round().clamp(1, 999), reason: '${s.name} の徒歩分が距離と合わない');
    }
  });

  test('満員指定は full と混雑100%の両方に効く', () {
    final full = MockBackend.sheltersAround(_here, fullIds: {'sh_fukuei_es'});
    final target = full.firstWhere((s) => s.id == 'sh_fukuei_es');
    expect(target.full, isTrue);
    expect(target.crowdPct, 100);
    // 指定していない避難所は素の混雑率のまま
    expect(full.firstWhere((s) => s.id == 'sh_dai7_jhs').full, isFalse);
  });
}

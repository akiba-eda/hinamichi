import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/core/location_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// テスト環境では Geolocator のプラグインが無いので、resolve() の GPS 経路は
/// 必ず例外になり、その先(キャッシュ → 仮の現在地 → 失敗)を通る。
/// ここで固定したいのは「取れなかったときに勝手な地点へ落ちない」ことそのもの。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('GPS も仮の現在地も無ければ、既定地点に落ちずに失敗する', () async {
    await expectLater(LocationService.resolve(), throwsA(isA<LocationUnavailable>()));
  });

  test('仮の現在地を入れてあれば、そこを使う', () async {
    await LocationService.setManual(const LatLng(35.6812, 139.7671), '東京都千代田区丸の内一丁目９番');
    final r = await LocationService.resolve();
    expect(r.source, 'manual');
    expect(r.point.latitude, closeTo(35.6812, 1e-6));
    expect(r.point.longitude, closeTo(139.7671, 1e-6));
    expect(await LocationService.manualLabel(), '東京都千代田区丸の内一丁目９番');
  });

  test('既定では GPS より優先しない(受け皿として持つだけ)', () async {
    await LocationService.setManual(const LatLng(35.0, 135.0), 'どこか');
    expect(await LocationService.manualForced(), isFalse);
  });

  test('リハーサル用に指定したときだけ、GPS より優先する', () async {
    await LocationService.setManual(const LatLng(35.0, 135.0), 'どこか', force: true);
    expect(await LocationService.manualForced(), isTrue);
  });

  test('解除すると何も残らず、また失敗に戻る', () async {
    await LocationService.setManual(const LatLng(35.0, 135.0), 'どこか');
    await LocationService.clearManual();
    expect(await LocationService.manualPoint(), isNull);
    expect(await LocationService.manualLabel(), isNull);
    await expectLater(LocationService.resolve(), throwsA(isA<LocationUnavailable>()));
  });
}

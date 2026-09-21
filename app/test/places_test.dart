import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/domain/social.dart';
import 'package:hinamichi/mock/mock_backend.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const here = LatLng(35.6812, 139.7671);

  group('よく行く場所の保存', () {
    test('id が空なら新規として増える', () {
      final b = MockBackend();
      b.savePlace(const SavedPlace(id: '', name: '自宅', point: here, kind: PlaceKind.home));
      expect(b.state.places.length, 1);
      expect(b.state.places.first.name, '自宅');
      expect(b.state.places.first.id, isNotEmpty);
    });

    test('同じ id なら増えずに差し替わる', () {
      // 追加と編集を同じ入口にしているので、ここが増える側に倒れると
      // 編集のたびに二重登録され、通知が二回飛ぶ。
      final b = MockBackend();
      b.savePlace(const SavedPlace(id: 'p1', name: '自宅', point: here, kind: PlaceKind.home));
      b.savePlace(const SavedPlace(id: 'p1', name: 'じぶんの家', point: here, radiusM: 300, kind: PlaceKind.home));
      expect(b.state.places.length, 1);
      expect(b.state.places.first.name, 'じぶんの家');
      expect(b.state.places.first.radiusM, 300);
    });

    test('削除すると消える', () {
      final b = MockBackend();
      b.savePlace(const SavedPlace(id: 'p1', name: '学校', point: here, kind: PlaceKind.school));
      b.removePlace('p1');
      expect(b.state.places, isEmpty);
    });
  });

  group('サーバーへ送る形', () {
    test('名前・座標・半径・種類を送る', () {
      const p = SavedPlace(id: 'p1', name: 'ひなたの学校', point: here, radiusM: 200, kind: PlaceKind.school);
      expect(p.toJson(), {
        'name': 'ひなたの学校',
        'lat': here.latitude,
        'lng': here.longitude,
        'radiusM': 200,
        'kind': 'school',
      });
    });

    test('既定の半径は150m', () {
      // 集合住宅の敷地と測位誤差を吸収する幅。サーバー側の既定と揃える。
      const p = SavedPlace(id: '', name: '自宅', point: here);
      expect(p.radiusM, 150);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/domain/social.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('合流地点までの徒歩分', () {
    // メンバーの徒歩分は経路 API を人数分叩かず、直線 80m/分で概算する。
    // 待たせないことを優先した判断なので、目安であることが前提。
    const here = LatLng(35.6812, 139.7671); // 東京駅付近

    test('400m 離れていれば 5 分', () {
      const d = Distance();
      final to = d.offset(here, 400, 0); // 真北へ 400m
      expect(Meetup.walkMinutes(here, to), 5);
    });

    test('同じ地点でも 0 分にはしない', () {
      // 0 分と出ると「もう着いている」と読めてしまう。最低 1 分に丸める。
      expect(Meetup.walkMinutes(here, here), 1);
    });

    test('端数は切り上げる', () {
      const d = Distance();
      final to = d.offset(here, 81, 0); // 80m/分 をわずかに超える
      expect(Meetup.walkMinutes(here, to), 2);
    });
  });

  group('合流の中身', () {
    test('災害から作った合流は fromIncident が立ち、色と文言が変わる', () {
      final m = Meetup(
        id: 'x',
        name: '浦安公園',
        point: const LatLng(35.65, 139.9),
        memberUids: const ['me', 'a'],
        createdAt: DateTime.now(),
        fromIncident: true,
      );
      expect(m.fromIncident, isTrue);
      expect(m.memberUids, contains('me'));
    });

    test('既定は平時の待ち合わせ', () {
      final m = Meetup(id: 'x', name: '駅前', point: const LatLng(35.65, 139.9), memberUids: const ['me', 'a'], createdAt: DateTime.now());
      expect(m.fromIncident, isFalse);
    });
  });
}

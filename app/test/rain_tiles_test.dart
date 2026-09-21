import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/core/rain_tiles.dart';

void main() {
  group('雨雲タイル', () {
    final f = RainFrame('20260921063000', '20260921063000', DateTime.utc(2026, 9, 21, 6, 30));

    test('URL に観測時刻が入る', () {
      expect(
        f.urlTemplate,
        'https://www.jma.go.jp/bosai/jmatile/data/nowc/20260921063000/none/20260921063000/surf/hrpns/{z}/{x}/{y}.png',
      );
    });

    test('配信は z=10 まで。これを超えると空タイルが返るので引き伸ばす', () {
      expect(RainFrame.maxNativeZoom, 10);
    });
  });
}

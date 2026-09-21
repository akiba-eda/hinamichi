import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/core/api_client.dart';
import 'package:hinamichi/core/my_area.dart';

void main() {
  final area = MyArea(ApiClient());

  group('警報を自分宛てに絞る', () {
    test('対象が空なら全国向け(地震)なので、市区町村が分からなくても通す', () {
      expect(area.matches(const []), isTrue);
    });

    test('市区町村がまだ引けていないとき、その土地限定の警報では動かさない', () {
      // 誤って全国に鳴らすより、鳴らさない方を選ぶ。
      expect(area.matches(const ['1220300']), isFalse);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/domain/models.dart';
import 'package:hinamichi/domain/senavi.dart';
import 'package:hinamichi/domain/weather.dart';
import 'package:hinamichi/ui/atoms/atoms.dart';
import 'package:hinamichi/ui/molecules/molecules.dart';

void main() {
  test('state → mood/line mapping', () {
    expect(moodFor(IncidentState.guiding), SenaviMood.running);
    expect(moodFor(IncidentState.arrived), SenaviMood.smile);
    expect(lineFor(IncidentState.proposing, shelter: '南行徳小学校', walkMin: 8), contains('南行徳小学校'));
    expect(lineFor(IncidentState.fallbackGuiding), contains('安全ルール'));
  });

  // 表情シート(docs/senavi_sheet_v2.png)の 8 枚には状態ラベルが直接振られている。
  // 絵と状態がずれると「避難提案なのに伏せている」ような食い違いが出るので固定する。
  test('mood matches the expression sheet labels', () {
    expect(moodFor(IncidentState.proposing), SenaviMood.lookback, reason: '避難提案 = 呼びかける絵');
    expect(moodFor(IncidentState.notRelevant), SenaviMood.lying, reason: '対象外 = 様子を見る絵');
    expect(moodFor(IncidentState.monitoringStay), SenaviMood.lying);
    expect(moodFor(IncidentState.fallbackGuiding), SenaviMood.troubled, reason: 'AI応答なし = 困り顔');
    // 8 枚とも使われていること(使われない絵があるなら割り当て漏れ)
    final used = IncidentState.values.map(moodFor).toSet();
    expect(used.length, SenaviMood.values.length);
  });

  // 平時のホームはこの判定だけで決まる。閾値がずれると
  // 「強い雨が降ってる」のに「お出かけ日和」と言い出す。
  test('rain nowcast → outlook and line', () {
    const clear = RainNowcast(nowMmh: 0, maxMmh: 0, cloudPct: 8);
    expect(clear.outlook, RainOutlook.clear);
    expect(weatherLine(clear), contains('晴れ'));

    const soon = RainNowcast(nowMmh: 0, maxMmh: 3.4, startsInMin: 25);
    expect(soon.outlook, RainOutlook.rainSoon);
    expect(weatherLine(soon), contains('25分'));

    // 10mm/h 以上は気象庁でいう「やや強い雨」。ここから警戒側の文面に変える。
    const strongSoon = RainNowcast(nowMmh: 0, maxMmh: 18.0, startsInMin: 10);
    expect(strongSoon.outlook, RainOutlook.strongRainSoon);
    expect(weatherLine(strongSoon), contains('強い雨'));

    const strongNow = RainNowcast(nowMmh: 14.5, maxMmh: 22.0, stopsInMin: 55);
    expect(strongNow.outlook, RainOutlook.strongRainNow);
    expect(moodForWeather(strongNow), SenaviMood.troubled);

    // 取れなかったときも平時のホームは成立する。
    expect(weatherLine(null), isNotEmpty);
    expect(weatherSub(null), isNull);
    // 雨に動きがなければ補足はハザード側に譲る。
    expect(weatherSub(clear), isNull);
  });

  // 「ホームに戻る」は state を closed にするだけ。closed を isFinished で
  // まとめて扱うと、閉じてもカードが 30 分居座る(実際にそうなっていた)。
  test('closed は finished だが、active ではない', () {
    expect(IncidentState.closed.isFinished, isTrue);
    expect(IncidentState.closed.isActive, isFalse);
    // 到着はしばらく残す側
    expect(IncidentState.arrived.isFinished, isTrue);
    expect(IncidentState.arrived.isActive, isTrue);
  });

  // 避難先を出す前に「まず身の安全」を伝えるかどうかの判定。
  // 揺れている最中に外へ出るのは危険で、順序を間違えると人が死ぬ。
  test('強い揺れ・津波では身の安全を先に伝える', () {
    Incident inc({DisasterType type = DisasterType.earthquake, int? intensity, List<String> warnings = const []}) => Incident(
          id: 'x', state: IncidentState.assessing, alertTitle: '', type: type,
          reasons: const [], userMessage: '', validatedBy: 'none', costUsd: 0, llmCalls: 0,
          locationSource: 'gps', intensity: intensity, warnings: warnings,
        );

    expect(inc(intensity: 6).isStrongShaking, isTrue);
    expect(inc(intensity: 4).isStrongShaking, isFalse, reason: '震度4では避難先の案内でよい');
    expect(inc(type: DisasterType.tsunami).hasTsunamiWarning, isTrue);
    expect(inc(warnings: const ['津波警報']).hasTsunamiWarning, isTrue);
    expect(inc(type: DisasterType.heavyRain, intensity: 6).isStrongShaking, isFalse, reason: '震度は地震のときだけ');

    // 津波は揺れより優先。高さの話になる
    final t = immediateSafetyFor(tsunami: true, strongShaking: true, intensityLabel: '6弱');
    expect(t!.line, contains('高いところ'));

    final q = immediateSafetyFor(tsunami: false, strongShaking: true, intensityLabel: '6弱');
    expect(q!.sub, contains('6弱'));

    // 該当しなければ通常の案内に任せる
    expect(immediateSafetyFor(tsunami: false, strongShaking: false, intensityLabel: null), isNull);
  });

  test('IncidentState parsing', () {
    expect(IncidentState.parse('fallback_guiding'), IncidentState.fallbackGuiding);
    expect(IncidentState.parse('fallback_guiding').isGuiding, isTrue);
    expect(IncidentState.parse('closed').isActive, isFalse);
    expect(PublicStatus.parse('safe_zone').label, '安全地帯');
  });

  // 到着カードの「判断の記録 / ホームに戻る」は Expanded で横半分になる。
  // ラベルを Text 直置きにしていた頃はここで 36px はみ出していた。
  testWidgets('HinaButton keeps a long label inside a narrow slot', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 326, // 実機のカード内幅(390 - 画面余白 32 - カード余白 32)
            child: Row(children: [
              Expanded(child: HinaButton.secondary('判断の記録を見る', icon: Icons.receipt_long_outlined, onPressed: () {})),
              const SizedBox(width: 8),
              Expanded(child: HinaButton.primary('ホームに戻る', onPressed: () {})),
            ]),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('StatusChip shows all five labels', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [for (final s in PublicStatus.values) StatusChip(s)]))));
    for (final s in PublicStatus.values) {
      expect(find.text(s.label), findsOneWidget);
    }
  });

  testWidgets('CountdownButton fires onTimeout once', (tester) async {
    var fired = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CountdownButton(label: '行く', seconds: 1, onTap: () {}, onTimeout: () => fired++))));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(fired, 1);
  });

  testWidgets('HinaButton disabled when loading', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HinaButton.primary('x', loading: true, onPressed: () => taps++))));
    await tester.tap(find.byType(FilledButton));
    expect(taps, 0);
  });
}

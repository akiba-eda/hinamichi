import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinamichi/domain/models.dart';
import 'package:hinamichi/domain/senavi.dart';
import 'package:hinamichi/ui/atoms/atoms.dart';
import 'package:hinamichi/ui/molecules/molecules.dart';

void main() {
  test('state → mood/line mapping', () {
    expect(moodFor(IncidentState.guiding), SenaviMood.running);
    expect(moodFor(IncidentState.arrived), SenaviMood.smile);
    expect(lineFor(IncidentState.proposing, shelter: '南行徳小学校', walkMin: 8), contains('南行徳小学校'));
    expect(lineFor(IncidentState.fallbackGuiding), contains('安全ルール'));
  });

  test('IncidentState parsing', () {
    expect(IncidentState.parse('fallback_guiding'), IncidentState.fallbackGuiding);
    expect(IncidentState.parse('fallback_guiding').isGuiding, isTrue);
    expect(IncidentState.parse('closed').isActive, isFalse);
    expect(PublicStatus.parse('safe_zone').label, '安全地帯');
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

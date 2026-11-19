import 'package:finsight/design/financial_score_ring.dart';
import 'package:finsight/diagnosis/report_share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'score and type can be removed independently from the shared image preview',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      tester.platformDispatcher.textScaleFactorTestValue = 1.7;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        const MaterialApp(
          home: ReportShareCard(
            month: '2026-10',
            badge: '부채부담형',
            score: 57,
            scoreChange: 13,
          ),
        ),
      );
      final card = find.byWidgetPredicate(
        (widget) => widget is RepaintBoundary && widget.key is GlobalKey,
      );
      Finder inside(String value) =>
          find.descendant(of: card, matching: find.text(value));

      Future<void> toggle(String label) async {
        await tester.tap(find.byTooltip('카드 표시 설정'));
        await tester.pumpAndSettle();
        final control = find.text(label);
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        await tester.tap(control);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '확인'));
        await tester.pumpAndSettle();
      }

      final ring = find.descendant(
        of: card,
        matching: find.byType(FinancialScoreRing),
      );
      expect(inside('57'), findsOneWidget);
      expect(inside('지난달보다 13점 높아졌어요'), findsOneWidget);
      expect(ring, findsOneWidget);
      expect(inside('부채부담형'), findsOneWidget);
      await toggle('점수 가리기');
      expect(inside('57'), findsNothing);
      expect(inside('지난달보다 13점 높아졌어요'), findsNothing);
      expect(tester.widget<FinancialScoreRing>(ring).score, isNull);
      expect(inside('부채부담형'), findsOneWidget);

      await toggle('유형 가리기');
      expect(inside('부채부담형'), findsNothing);
      expect(inside('2026.10 · FINANCIAL MIND REPORT'), findsOneWidget);

      await toggle('점수 가리기');
      expect(inside('57'), findsOneWidget);
      expect(inside('부채부담형'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/diagnosis/monthly_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ReportApi extends AppApi {
  final months = <String>[];

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    final month = Uri.parse(path).queryParameters['month']!;
    final request = RequestOptions(path: path);
    months.add(month);
    if (months.length == 1) throw DioException(requestOptions: request);
    const score = {'numerator': 54, 'denominator': 1};
    final payload = <String, dynamic>{
      'month': month,
      'available': month == months.first,
      'diagnosisCount': 2,
      'guideViews': 7,
      'guideCompletions': 1,
      'firstScore': 50,
      'scoreChange': 4,
      'result': {
        'total': score,
        'perceivedStress': score,
        'rankedPressures': [
          {'pressure': 'EMERGENCY_FUND', 'score': score},
        ],
        'resources': [
          {'resource': 'SELF_EFFICACY', 'score': score},
        ],
      },
    };
    return Response(requestOptions: request, data: payload as T);
  }
}

void main() {
  testWidgets('a narrow monthly report retries and keeps month navigation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final api = _ReportApi();
    addTearDown(api.close);
    var historyOpens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MonthlyReportScreen(
          api: api,
          badgeName: (_) => '비상자금취약형',
          openHistory: () => historyOpens++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('첫 진단 50점 · 마지막 진단 54점'), findsOneWidget);
    expect(find.text('변화 +4점'), findsOneWidget);

    Future<void> reach(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      expect(finder.hitTestable(), findsOneWidget);
    }

    await reach(find.text('공유 카드 확인'));
    await reach(find.byTooltip('이전 달'));
    await tester.tap(find.byTooltip('이전 달'));
    await tester.pumpAndSettle();
    expect(find.text('이 달의 리포트가 없어요'), findsOneWidget);
    final history = find.text('진단 기록 확인');
    await reach(history);
    await tester.tap(history);
    expect(historyOpens, 1);
    await reach(find.byTooltip('다음 달'));
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();
    expect(api.months, [
      api.months.first,
      api.months.first,
      api.months[2],
      api.months.first,
    ]);
    expect(api.months[2], isNot(api.months.first));
    expect(tester.takeException(), isNull);
  });
}

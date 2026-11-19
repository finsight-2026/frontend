import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/diagnosis/home_widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _WidgetApi extends AppApi {
  final queries = <Map<String, String>>[];
  bool preparing = false;
  bool emptyNews = false;
  int editorialRequests = 0;

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    final uri = Uri.parse(path);
    expect(method, 'GET');
    if (uri.path == '/api/v1/guides/widget') {
      editorialRequests++;
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        data:
            {
                  'attemptId': 'attempt',
                  'id': 'guide-1',
                  'revision': 2,
                  'state': 'AVAILABLE',
                  'title': '자동결제 목록을 확인해보세요.',
                }
                as T,
      );
    }
    if (uri.path == '/api/v1/news') {
      editorialRequests++;
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        data:
            {
                  'today': '2026-11-12',
                  'preparing': preparing,
                  'articles': [
                    if (!emptyNews)
                      {
                        'id': 'article-1',
                        'title': '금리 뉴스는 내 대출에 왜 중요할까요?',
                        'editionDate': preparing ? '2026-11-11' : '2026-11-12',
                        'revision': 1,
                      },
                  ],
                }
                as T,
      );
    }
    expect(uri.path, '/api/v1/diagnosis/attempts/widget');
    queries.add(uri.queryParameters);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data:
          <String, dynamic>{
                'streakMonths': 3,
                'lastDiagnosisDate': '2026-11-01',
                'nextDiagnosisDate': '2026-12-01',
                'daysUntilNext': 20,
                if (uri.queryParameters['showScore'] == 'true') 'score': 72,
                if (uri.queryParameters['showType'] == 'true')
                  'representativeType': 'DEBT',
                if (uri.queryParameters['showScore'] == 'true' &&
                    uri.queryParameters['showType'] == 'true')
                  'maximumPressureScore': 75,
              }
              as T,
    );
  }
}

void main() {
  testWidgets('record preview fits larger text on a narrow viewport', (
    tester,
  ) async {
    final api = _WidgetApi();
    addTearDown(api.close);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: HomeWidgetScreen(api: api, openDiagnosis: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('다음 진단까지 D-20'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('3개월째 기록 중'), findsOneWidget);
    expect(find.text('72'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview hides private fields and toggles them independently', (
    tester,
  ) async {
    final api = _WidgetApi();
    const channel = MethodChannel('finsight/home_widget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(api.close);
    tester.view.physicalSize = const Size(320, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeWidgetScreen(api: api, openDiagnosis: () async {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.queries.single, isEmpty);
    expect(find.text('다음 진단까지 D-20'), findsOneWidget);
    expect(find.text('3개월째 기록 중'), findsOneWidget);
    expect(find.text('72'), findsNothing);
    await tester.tap(find.byTooltip('진단 요약'));
    await tester.pumpAndSettle();
    expect(find.text('나의 금융 마음'), findsOneWidget);
    expect(find.text('맞춤 가이드 보기 ›'), findsOneWidget);
    expect(find.text('가장 큰 금융 압박'), findsNothing);
    expect(find.text('72'), findsNothing);
    expect(find.text('부채부담형'), findsNothing);

    final score = find.text('점수 표시');
    await changeWidgetOption(tester, score);
    expect(api.queries.last, {'showScore': 'true'});
    expect(find.text('72'), findsOneWidget);
    expect(find.text('부채부담형'), findsNothing);

    final type = find.text('유형 표시');
    await changeWidgetOption(tester, type);
    expect(api.queries.last, {'showScore': 'true', 'showType': 'true'});
    expect(find.text('부채부담형'), findsOneWidget);
    expect(find.text('가장 큰 금융 압박'), findsOneWidget);
    expect(find.text('부채'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .75,
    );

    await changeWidgetOption(tester, score);
    expect(api.queries.last, {'showType': 'true'});
    expect(find.text('72'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editorial cards hide content until explicitly enabled and remove it when disabled',
    (tester) async {
      final api = _WidgetApi();
      addTearDown(api.close);
      tester.view.physicalSize = const Size(440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeWidgetScreen(api: api, openDiagnosis: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('경제 뉴스'));
      await tester.pumpAndSettle();
      expect(find.text('새 경제 소식을 확인해보세요'), findsOneWidget);
      expect(api.editorialRequests, 0);
      final toggle = find.text('개인화 뉴스·행동 표시');
      await changeWidgetOption(tester, toggle);
      expect(find.text('금리 뉴스는 내 대출에 왜 중요할까요?'), findsOneWidget);
      await tester.tap(find.byTooltip('오늘의 행동'));
      await tester.pumpAndSettle();
      expect(find.text('자동결제 목록을 확인해보세요.'), findsOneWidget);
      api.preparing = true;
      await changeWidgetOption(tester, find.text('점수 표시'));
      await tester.tap(find.byTooltip('경제 뉴스'));
      await tester.pumpAndSettle();
      expect(find.text('경제 한 장 · 2026-11-11'), findsOneWidget);
      api.emptyNews = true;
      await changeWidgetOption(tester, find.text('점수 표시'));
      expect(find.text('경제 소식을 준비하고 있어요'), findsOneWidget);
      expect(find.text('금리 뉴스는 내 대출에 왜 중요할까요?'), findsNothing);
      await changeWidgetOption(tester, toggle);
      expect(find.text('새 경제 소식을 확인해보세요'), findsOneWidget);
    },
  );
}

Future<void> changeWidgetOption(WidgetTester tester, Finder option) async {
  await tester.tap(find.byTooltip('위젯 표시 설정'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
  final save = find.widgetWithText(FilledButton, '저장');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

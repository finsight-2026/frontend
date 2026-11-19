import 'dart:async';

import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/design/finsight_theme.dart';
import 'package:finsight/design/tokens.dart';
import 'package:finsight/diagnosis/diagnosis_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDiagnosisApi extends AppApi {
  final calls = <String>[];
  final milestones = <Object?>[];
  Completer<Map<String, dynamic>>? assignment;
  final exposures = <Object?>[];
  Object? submission;
  Object? abortion;
  bool noDiagnosis = false;
  bool zeroPressureResult = false;
  bool longSurvey = false;
  bool failHistoryOnce = false;
  bool failSubmissionOnce = false;
  bool saveBeforeDisconnect = false;
  int widgetGuideRevision = 2;
  final attemptedSubmissions = <Object?>[];

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    calls.add('$method $path');
    if (method == 'GET' && path.endsWith('/attempts') && failHistoryOnce) {
      failHistoryOnce = false;
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: path),
        reason: 'offline',
      );
    }
    if (path.endsWith('/test-attempt/result') && submission == null) {
      final options = RequestOptions(path: path);
      throw DioException.badResponse(
        statusCode: 404,
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
      );
    }
    if (path.endsWith('/submit')) {
      attemptedSubmissions.add(data);
      if (failSubmissionOnce) {
        failSubmissionOnce = false;
        if (saveBeforeDisconnect) submission = data;
        throw DioException.connectionError(
          requestOptions: RequestOptions(path: path),
          reason: 'offline',
        );
      }
    }
    if (path.endsWith('/assign') && assignment != null) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        data: await assignment!.future as T,
      );
    }
    if (path.endsWith('/exposure')) exposures.add(data);
    if (path.endsWith('/views')) {
      return Response<T>(requestOptions: RequestOptions(path: path));
    }
    const score = {'numerator': 100, 'denominator': 2};
    final uri = Uri.parse(path);
    final payload = switch ((method, uri.pathSegments.last)) {
      ('GET', 'settings') => {
        'email': 'long.account.address.for.layout@example.test',
        'emailVerified': true,
        'lastLoginAt': '2026-11-10T16:00:00Z',
        'profile': {'age': '19_22', 'situation': 'EMPLOYED'},
      },
      ('GET', 'news') => {'preparing': true, 'articles': []},
      ('GET', 'current') => {
        'questions': List.generate(
          30,
          (index) => {
            'text': longSurvey
                ? '갑작스러운 지출이 생겼을 때 현재의 비상자금으로 생활비를 충당할 수 있다.'
                : '문항 ${index + 1}',
            'options': longSurvey
                ? [
                    {'value': 1, 'label': '매우낮음'},
                    {'value': 2, 'label': '낮음'},
                    {'value': 3, 'label': '보통'},
                    {'value': 4, 'label': '높음'},
                    {'value': 5, 'label': '매우높음'},
                  ]
                : [
                    {'value': 3, 'label': '보통'},
                  ],
          },
        ),
      },
      ('POST', 'attempts') => {'id': 'test-attempt'},
      ('POST', 'view') when uri.path.startsWith('/api/v1/guides/') => {
        'guide': {
          'id': 'DEBT-1',
          'version': widgetGuideRevision,
          'heading': '위젯에 표시된 가이드',
          'action': '자동결제 목록 확인하기',
          'steps': ['목록 읽기'],
        },
        'completed': false,
      },
      ('GET', 'trend') => [
        {
          'id': 'new-id',
          'attemptId': 'new-attempt',
          'completedAt': DateTime.now().toUtc().toIso8601String(),
          'score': 70,
          'representativeType': 'INCOME',
        },
      ],
      ('GET', 'attempts') => {
        'items': noDiagnosis
            ? <Map<String, dynamic>>[]
            : [
                if (uri.queryParameters.isEmpty)
                  {
                    'id': 'new-id',
                    'attemptId': 'new-attempt',
                    'completedAt': '2026-11-10T16:00:00Z',
                    'score': 70,
                    'representativeType': 'INCOME',
                  }
                else
                  {
                    'id': 'old-id',
                    'attemptId': 'old-attempt',
                    'completedAt': '2026-11-09T16:00:00Z',
                    'score': 50,
                    'representativeType': 'DEBT',
                  },
              ],
        'hasMore': !noDiagnosis && uri.queryParameters.isEmpty,
      },
      ('POST', 'submit') || ('GET', 'result') => {
        'completedAt': '2026-11-11T16:00:00Z',
        'result': {
          'formulaVersion': 'yfsi-v1',
          'total': zeroPressureResult
              ? {'numerator': 0, 'denominator': 26}
              : score,
          'representativeType': 'DEBT',
          'perceivedStress': score,
          'overallStress': '보통',
          'rankedPressures': [
            if (!zeroPressureResult) {'pressure': 'DEBT', 'score': score},
            if (zeroPressureResult)
              for (final pressure in [
                'DEBT',
                'INCOME',
                'EMERGENCY_FUND',
                'FIXED_COST',
                'FUTURE',
                'FAMILY',
              ])
                {
                  'pressure': pressure,
                  'score': {'numerator': 0, 'denominator': 3},
                },
          ],
          'resources': [],
        },
      },
      _ => null,
    };
    if (path.endsWith('/question-events')) milestones.add(data);
    if (path.endsWith('/submit')) submission = data;
    if (path.endsWith('/abort')) abortion = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: payload as T?,
    );
  }
}

void main() {
  testWidgets(
    'action widget opens its displayed revision and hides a replacement',
    (tester) async {
      final api = FakeDiagnosisApi();
      addTearDown(api.close);
      const channel = MethodChannel('finsight/home_widget');
      final messenger = tester.binding.defaultBinaryMessenger;
      const attempt = '00000000-0000-0000-0000-000000000001';
      const url = 'action?attemptId=$attempt&id=DEBT-1&revision=2';
      String? pending = url;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'peekOpen') return pending != null;
        if (call.method != 'consumeOpen') return null;
        final target = pending;
        pending = null;
        return target;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(MaterialApp(home: DiagnosisHome(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('자동결제 목록 확인하기'), findsOneWidget);
      expect(
        api.calls,
        contains(
          'POST /api/v1/guides/DEBT-1/view?attemptId=$attempt&revision=2',
        ),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      api.widgetGuideRevision = 3;
      pending = url;
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('open')),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.text('위젯에 표시된 행동을 지금은 볼 수 없어요.'), findsOneWidget);
      expect(find.text('자동결제 목록 확인하기'), findsNothing);
      expect(find.text('가이드 목록으로'), findsOneWidget);
      expect(api.calls, isNot(contains('GET /api/v1/guides/widget')));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'a second widget tap opens while its first destination remains open',
    (tester) async {
      final api = FakeDiagnosisApi()..noDiagnosis = true;
      addTearDown(api.close);
      const channel = MethodChannel('finsight/home_widget');
      final messenger = tester.binding.defaultBinaryMessenger;
      String? pending = 'diagnosis';
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'peekOpen') return pending != null;
        if (call.method != 'consumeOpen') return null;
        final target = pending;
        pending = null;
        return target;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(MaterialApp(home: DiagnosisHome(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('나의 금융 스트레스를\n살펴볼까요?'), findsOneWidget);

      pending = 'news';
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('open')),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('오늘의 경제'), findsOneWidget);
      expect(find.text('오늘의 뉴스를 준비하고 있어요.'), findsOneWidget);
      expect(pending, isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'completed home wraps the full email and opens the latest result',
    (tester) async {
      tester.view.physicalSize = const Size(320, 650);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      tester.platformDispatcher.textScaleFactorTestValue = 1.7;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      const email = 'long.account.address.for.layout@example.test';
      final api = FakeDiagnosisApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: finsightTheme(),
          home: DiagnosisHome(api: api, email: email),
        ),
      );
      await tester.pumpAndSettle();

      final greeting = find.byWidgetPredicate(
        (widget) => widget is Text && widget.semanticsLabel == '$email님',
      );
      final renderedEmail = tester.widget<Text>(greeting).data!;
      expect(renderedEmail.replaceAll('\u200B', ''), '$email님');
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: greeting, matching: find.byType(RichText)),
      );
      final lines = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: renderedEmail.length),
      );
      expect(lines.map((box) => box.top).toSet().length, greaterThan(1));
      expect(lines.last.right, lessThanOrEqualTo(paragraph.size.width));
      expect(paragraph.didExceedMaxLines, isFalse);

      final score = find.widgetWithText(InkWell, '나의 금융 스트레스');
      await tester.ensureVisible(score);
      await tester.tap(score);
      await tester.pumpAndSettle();
      expect(find.text('익명 비교 보기'), findsNothing);
      expect(find.text('내 맞춤 가이드 보기'), findsOneWidget);
      expect(
        api.calls,
        contains('GET /api/v1/diagnosis/attempts/new-attempt/result'),
      );
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();

      final report = find.text('월간 리포트');
      final insights = find.text('익명 인사이트');
      expect(
        tester.getTopLeft(report).dy,
        greaterThan(tester.getTopLeft(insights).dy),
      );
      await tester.ensureVisible(find.text('홈 위젯'));
      await tester.pumpAndSettle();
      expect(find.text('홈 위젯').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account security scrolls with large text and keeps app navigation',
    (tester) async {
      final api = FakeDiagnosisApi()..noDiagnosis = true;
      addTearDown(api.close);
      tester.view.physicalSize = const Size(320, 650);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(
        MaterialApp(
          theme: finsightTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.7)),
            child: child!,
          ),
          home: DiagnosisHome(api: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('MY'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('계정 보안'));
      await tester.pumpAndSettle();
      expect(
        find.text('long.account.address.for.layout@example.test'),
        findsOneWidget,
      );
      expect(find.text('인증 완료'), findsOneWidget);
      expect(find.text('2026-11-11 01:00 (한국시간)'), findsOneWidget);
      expect(tester.getTopLeft(find.text('계정 보안')).dy, greaterThan(44));

      await tester.scrollUntilVisible(find.text('회원 탈퇴 요청 →'), 150);
      expect(find.text('회원 탈퇴 요청 →').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      await tester.tap(find.text('홈'));
      await tester.pumpAndSettle();
      expect(find.text('계정 보안'), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
    },
  );

  testWidgets('home recovers from offline and keeps empty results separate', (
    tester,
  ) async {
    final api = FakeDiagnosisApi()
      ..noDiagnosis = true
      ..failHistoryOnce = true;
    addTearDown(api.close);
    tester.view.physicalSize = const Size(320, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: DiagnosisHome(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('인터넷 연결 오류'), findsOneWidget);
    expect(find.text('첫 진단을 시작해볼까요?'), findsNothing);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('첫 진단을 시작해볼까요?'), findsOneWidget);
    expect(find.text('나의 금융 스트레스'), findsNothing);
    final destinations = tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .destinations;
    expect(
      destinations.cast<NavigationDestination>().map((item) => item.label),
      ['홈', '뉴스', '기록', 'MY'],
    );
    final emptyResult = find.text('내 결과 확인');
    await tester.ensureVisible(emptyResult);
    await tester.tap(emptyResult);
    await tester.pumpAndSettle();
    expect(find.text('아직 확인할 결과가 없어요'), findsOneWidget);
    await tester.tap(find.text('홈으로'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'the assigned diagnosis entry order is rendered before exposure',
    (tester) async {
      final api = FakeDiagnosisApi()
        ..assignment = Completer<Map<String, dynamic>>();
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: DiagnosisHome(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('자가진단 하기'));
      await tester.pumpAndSettle();
      final summary = find.text('30문항');
      final restart = find.text('중단한 뒤에는 첫 문항부터 다시 시작해요.');
      expect(
        tester.getTopLeft(summary).dy,
        lessThan(tester.getTopLeft(restart).dy),
      );
      expect(api.exposures, isEmpty);

      api.assignment!.complete({
        'experimentId': 'experiment-one',
        'screenId': 'B_006',
        'variantId': 'RESTART_FIRST',
      });
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(restart).dy,
        lessThan(tester.getTopLeft(summary).dy),
      );
      expect(
        api.calls,
        contains('POST /api/v1/experiments/experiment-one/exposure'),
      );
      expect(api.exposures.single, containsPair('variantId', 'RESTART_FIRST'));
    },
  );

  for (final committed in [false, true]) {
    testWidgets(
      committed
          ? 'a lost submission response recovers the saved result'
          : 'answers persist when going back and retrying the same submission',
      (tester) async {
        final api = FakeDiagnosisApi()
          ..failSubmissionOnce = true
          ..saveBeforeDisconnect = committed;
        addTearDown(api.close);
        await tester.pumpWidget(MaterialApp(home: DiagnosisHome(api: api)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('자가진단 하기'));
        await tester.pumpAndSettle();
        final start = find.text('진단 시작하기');
        await tester.scrollUntilVisible(start, 140);
        await tester.ensureVisible(start);
        await tester.tap(start);
        await tester.pumpAndSettle();
        final next = find.widgetWithText(FilledButton, '다음으로');
        expect(tester.widget<FilledButton>(next).onPressed, isNull);
        await tester.tap(find.byType(ChoiceChip));
        await tester.pumpAndSettle();
        await tester.tap(next);
        await tester.pumpAndSettle();
        await tester.tap(find.text('이전'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ChoiceChip>(find.byType(ChoiceChip)).selected,
          isTrue,
        );
        for (var i = 0; i < 30; i++) {
          if (i > 0) {
            await tester.tap(find.byType(ChoiceChip));
            await tester.pumpAndSettle();
          }
          await tester.tap(i == 29 ? find.text('제출') : next);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('제출하기'));
        await tester.pump();
        expect(find.text('나의 금융 스트레스를\n분석하고 있어요'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.text('인터넷 연결 오류'), findsOneWidget);
        if (!committed) expect(api.submission, isNull);
        await tester.tap(find.text('다시 시도'));
        await tester.pumpAndSettle();
        expect(
          api.calls.where((path) => path.endsWith('/submit')),
          List.filled(
            committed ? 1 : 2,
            'POST /api/v1/diagnosis/attempts/test-attempt/submit',
          ),
        );
        expect(
          api.attemptedSubmissions,
          List.filled(committed ? 1 : 2, {'answers': List.filled(30, 3)}),
        );
        final events = api.milestones.cast<Map<String, dynamic>>();
        expect(
          events.any(
            (event) => event['kind'] == 'VIEWED' && event['questionNo'] == 1,
          ),
          isTrue,
        );
        expect(
          events.any(
            (event) =>
                event['kind'] == 'COMPLETED' && event['questionNo'] == 15,
          ),
          isTrue,
        );
        expect(
          events.any(
            (event) =>
                event['kind'] == 'COMPLETED' && event['questionNo'] == 30,
          ),
          isTrue,
        );
        expect(events.every((event) => !event.containsKey('answer')), isTrue);
        expect(
          api.calls.where(
            (path) =>
                path.contains('/test-attempt/') &&
                (path.endsWith('/submit') || path.endsWith('/result')),
          ),
          [
            'POST /api/v1/diagnosis/attempts/test-attempt/submit',
            'GET /api/v1/diagnosis/attempts/test-attempt/result',
            if (!committed)
              'POST /api/v1/diagnosis/attempts/test-attempt/submit',
          ],
        );
        expect(api.submission, {'answers': List.filled(30, 3)});
        await tester.tap(find.text('결과 확인하기'));
        await tester.pumpAndSettle();
        expect(find.text('50'), findsOneWidget);
        expect(find.bySemanticsLabel('부채부담형'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'abort asks for confirmation and reports only the last question',
    (tester) async {
      final api = FakeDiagnosisApi();
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: DiagnosisHome(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('자가진단 하기'));
      await tester.pumpAndSettle();
      final start = find.text('진단 시작하기');
      await tester.scrollUntilVisible(start, 140);
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('설문 나가기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('계속하기'));
      await tester.pumpAndSettle();
      expect(api.calls.where((path) => path.endsWith('/abort')), isEmpty);
      await tester.tap(find.byTooltip('설문 나가기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('나가기'));
      await tester.pumpAndSettle();
      expect(api.calls.where((path) => path.endsWith('/abort')), hasLength(1));
      expect(api.abortion, {'lastQuestion': 1});
      expect(api.submission, isNull);
      expect(find.text('자가진단 하기'), findsOneWidget);
    },
  );

  testWidgets('diagnosis stays usable with large text and safe areas', (
    tester,
  ) async {
    final api = FakeDiagnosisApi()
      ..noDiagnosis = true
      ..longSurvey = true;
    addTearDown(api.close);
    tester.view.physicalSize = const Size(320, 650);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      MaterialApp(
        theme: finsightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.7)),
          child: child!,
        ),
        home: DiagnosisHome(api: api),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.text('첫 자가진단 시작하기');
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    final start = find.text('진단 시작하기');
    await tester.scrollUntilVisible(start, 150);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(start), alignment: .5);
    await tester.pumpAndSettle();
    expect(start.hitTestable(), findsOneWidget);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Q01 / 30')).dy, greaterThan(44));
    final choice = find.widgetWithText(ChoiceChip, '매우높음');
    await tester.scrollUntilVisible(choice, 120);
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    final next = find.widgetWithText(FilledButton, '다음으로');
    expect(next.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(next).dy, lessThan(650 - 34));
    await tester.tap(find.byTooltip('설문 나가기'));
    await tester.pumpAndSettle();
    final resume = find.text('계속하기');
    await tester.scrollUntilVisible(resume, 100);
    await tester.ensureVisible(resume);
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(choice).selected, isTrue);
    expect(
      tester.widget<Text>(find.text('매우높음')).style?.color,
      FinsightColors.white,
    );

    final progress = find.byType(LinearProgressIndicator);
    expect(tester.widget<LinearProgressIndicator>(progress).value, 1 / 30);
    await tester.tap(next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final intermediate = tester.widget<LinearProgressIndicator>(progress);
    expect(intermediate.value, allOf(greaterThan(1 / 30), lessThan(2 / 30)));
    expect(intermediate.semanticsValue, '7%');
    await tester.pumpAndSettle();
    expect(tester.widget<LinearProgressIndicator>(progress).value, 2 / 30);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '이전'));
    await tester.pump();
    expect(tester.widget<LinearProgressIndicator>(progress).value, 1 / 30);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero pressure shows one leading area and retains six details', (
    tester,
  ) async {
    final api = FakeDiagnosisApi()..zeroPressureResult = true;
    addTearDown(api.close);
    tester.view.physicalSize = const Size(320, 650);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      MaterialApp(
        theme: finsightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.7)),
          child: child!,
        ),
        home: DiagnosisHome(api: api),
      ),
    );
    await tester.pumpAndSettle();
    final card = find.widgetWithText(InkWell, '나의 금융 스트레스');
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
    expect(find.text('진단일 · 2026.11.12'), findsOneWidget);
    expect(find.textContaining('외부 부담 6개 영역이 모두 낮아요'), findsOneWidget);
    expect(find.text('부채'), findsNWidgets(2));
    expect(find.text('가족부양'), findsOneWidget);
    final details = find.text('외부 부담 6개 영역');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text('가족부양'), findsNothing);
    final guide = find.text('내 맞춤 가이드 보기');
    await tester.ensureVisible(guide);
    await tester.pumpAndSettle();
    expect(guide.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'trend uses daily points and keeps paginated individual results',
    (tester) async {
      final api = FakeDiagnosisApi();
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: DiagnosisHome(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기록'));
      await tester.pumpAndSettle();
      final trend = find.widgetWithText(ListTile, '변화 기록');
      await tester.ensureVisible(trend);
      await tester.tap(trend);
      await tester.pumpAndSettle();
      expect(find.text('금융 스트레스 추이'), findsOneWidget);
      expect(find.textContaining('직전 진단 대비'), findsNothing);
      expect(api.calls, contains('GET /api/v1/diagnosis/attempts/trend'));
      final more = find.text('기록 더 보기');
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('50점 · 부채부담형'), findsOneWidget);
      expect(find.text('직전 진단 대비 +20점'), findsOneWidget);
      expect(
        api.calls.where(
          (path) => path == 'GET /api/v1/diagnosis/attempts/trend',
        ),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history loads another page and opens the chosen historical result',
    (tester) async {
      final api = FakeDiagnosisApi();
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: DiagnosisHome(api: api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기록'));
      await tester.pumpAndSettle();
      expect(find.text('70점 · 소득불안형'), findsOneWidget);
      final all = find.text('더보기');
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(find.text('2026-11-11 01:00'), findsOneWidget);
      await tester.tap(find.text('기록 더 보기'));
      await tester.pumpAndSettle();
      expect(find.text('70점 · 소득불안형'), findsOneWidget);
      expect(find.text('기록 더 보기'), findsNothing);
      expect(api.calls.any((call) => call.contains('beforeId=new-id')), isTrue);
      await tester.tap(find.text('50점 · 부채부담형'));
      await tester.pumpAndSettle();
      expect(api.calls.where((call) => call.contains('/old-attempt/')), [
        'GET /api/v1/diagnosis/attempts/old-attempt/result',
        'POST /api/v1/diagnosis/attempts/old-attempt/views',
      ]);
      expect(find.text('50'), findsOneWidget);
    },
  );
}

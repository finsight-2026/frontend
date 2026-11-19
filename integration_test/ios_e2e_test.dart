import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:finsight/account/app_login.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/account/data_export_flow.dart';
import 'package:finsight/account/password_reset.dart';
import 'package:finsight/account/policy_documents.dart';
import 'package:finsight/account/signup_layout.dart';
import 'package:finsight/design/content_skeleton.dart';
import 'package:finsight/design/finsight_theme.dart';
import 'package:finsight/design/tokens.dart';
import 'package:finsight/diagnosis/guide_screen.dart';
import 'package:finsight/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

const _email = String.fromEnvironment('FINSIGHT_E2E_EMAIL');
const _mailbox = String.fromEnvironment('FINSIGHT_E2E_MAILBOX');
const _publishedNews = bool.fromEnvironment('FINSIGHT_E2E_PUBLISHED_NEWS');
const _publishedInsight = bool.fromEnvironment(
  'FINSIGHT_E2E_PUBLISHED_INSIGHT',
);
const _expiredSignup = bool.fromEnvironment('FINSIGHT_E2E_EXPIRED_SIGNUP');
const _notifications = bool.fromEnvironment('FINSIGHT_E2E_NOTIFICATIONS');
const _password = 'FinsightE2eLocal29';
const _newPassword = 'FinsightE2eReset53';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS signup, diagnosis, guides, widget and privacy flows',
    (tester) async {
      expect(_email, matches(RegExp(r'^ios-e2e-[a-f0-9]{12}@example\.test$')));
      expect(Uri.parse(_mailbox).host, '127.0.0.1');
      final network = _Connectivity(
        Uri.parse(const String.fromEnvironment('FINSIGHT_API_URL')).port,
      );
      HttpOverrides.global = network;
      addTearDown(() => HttpOverrides.global = null);

      Future<void> settle() => tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 18),
      );

      Future<void> waitFor(Finder finder) async {
        final elapsed = Stopwatch()..start();
        while (finder.evaluate().isEmpty &&
            elapsed.elapsed < const Duration(seconds: 12)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(finder, findsWidgets);
        await settle();
      }

      Future<void> show(Finder finder) async {
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            finder,
            190,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(finder);
        await tester.pump();
        if (finder.hitTestable().evaluate().isEmpty) {
          await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
          await settle();
        }
        expect(finder.hitTestable(), findsOneWidget);
      }

      Future<void> tap(Finder finder) async {
        await show(finder);
        await tester.tap(finder);
        await settle();
      }

      Future<void> enter(Finder field, String text) async {
        await show(field);
        await tester.enterText(field, text);
        await tester.pump();
      }

      Future<void> back() async => tap(find.byType(BackButton).first);

      Future<void> shot(String name) async {
        await tester.pump();
        expect(tester.takeException(), isNull);
        await binding.takeScreenshot(name);
      }

      Future<void> waitForImage(Finder image) => waitFor(
        find.descendant(
          of: image,
          matching: find.byWidgetPredicate(
            (widget) => widget is RawImage && widget.image != null,
          ),
        ),
      );

      Finder assetImage(String name) => find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/illustrations/$name.png',
      );

      final loadingApi = _WaitingExportApi();
      try {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: finsightTheme(),
            home: const SizedBox.shrink(),
            initialRoute: '/export',
            routes: {'/export': (_) => DataExportFlow(api: loadingApi)},
          ),
        );
        await waitFor(find.byType(ContentSkeleton));
        await shot('F_001-loading');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        loadingApi.release.complete();
        loadingApi.close();
      }
      if (const bool.fromEnvironment('FINSIGHT_E2E_SKELETON_ONLY')) return;
      app.main();

      final primary = find.byType(FilledButton);
      await waitFor(
        find.byWidgetPredicate(
          (widget) => widget is app.WelcomeScreen || widget is AppLogin,
        ),
      );
      final expiredLogin = find.byType(AppLogin);
      if (expiredLogin.evaluate().isNotEmpty) {
        GoRouter.of(tester.element(expiredLogin)).go('/');
        await settle();
      }
      await waitFor(find.text('시작하기'));
      await shot('A_002');
      await tap(find.text('시작하기'));
      await shot('A_009');
      final credentials = find.byType(TextFormField);
      await enter(credentials.at(0), _email);
      await enter(credentials.at(1), _password);
      await enter(credentials.at(2), _password);
      await shot('A_009-filled');
      await tap(find.widgetWithText(FilledButton, '다음'));
      await shot('A_010');

      final profile = find.byType(DropdownButtonFormField<String>);
      for (final (index, value) in [
        '만 19세 ~ 22세',
        '직장인',
        '응답하지 않음',
        '부모·가족과 함께 거주',
        '정기적인 근로소득이 있음',
        '없음',
        '전적으로 본인이 부담함',
      ].indexed) {
        await tap(profile.at(index));
        await tap(find.text(value).last);
      }
      await shot('A_010-filled');
      await tap(find.widgetWithText(FilledButton, '다음'));
      final terms = find.byTooltip('(필수) 이용약관 자세히 보기');
      await waitFor(terms);
      await shot('A_011');
      expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNWidgets(3));
      expect(find.text('보기'), findsNothing);
      await tap(terms);
      await waitFor(find.textContaining('local-preview-v1'));
      await shot('A_017');
      await tap(find.text('확인했어요'));
      await tap(find.text('(필수) 이용약관'));
      await tap(find.text('(필수) 개인정보 수집 및 이용'));
      await shot('A_011-required-selected');
      await tap(find.text('동의하고 계속'));
      await shot('A_013');
      var code = await _signupCode();
      await enter(find.byType(EditableText).first, code);
      final progress = find.byType(SignupProgress);
      final progressPosition = tester.getRect(progress);
      await shot('A_012');
      if (_expiredSignup) {
        await _localFixture('expire-signup');
        await tap(find.text('인증 완료'));
        await waitFor(find.text('인증번호가 만료됐어요.'));
        await shot('A_014-cooldown');
        final resend = find.widgetWithText(TextButton, '인증번호 다시 보내기');
        final cooldown = Stopwatch()..start();
        while (tester.widget<TextButton>(resend).onPressed == null &&
            cooldown.elapsed < const Duration(seconds: 65)) {
          await Future<void>.delayed(const Duration(seconds: 1));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.widget<TextButton>(resend).onPressed, isNotNull);
        await shot('A_014');
        await tap(resend);
        await waitFor(find.text('메일로 보낸 인증 번호를 확인해주세요.'));
        final previous = code;
        code = await _signupCode();
        expect(code, isNot(previous));
        final input = find.byType(EditableText);
        await tap(find.byType(TextField));
        expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
        await enter(input, code);
        await tester.pumpAndSettle();
        expect(progress.hitTestable(), findsOneWidget);
        expect(tester.getRect(progress), progressPosition);
        await shot('A_012-resend');
        expect(
          tester.widget<EditableText>(input).controller.text == code,
          isTrue,
        );
      }
      final verify = find.widgetWithText(FilledButton, '인증 완료');
      expect(tester.widget<FilledButton>(verify).onPressed, isNotNull);
      await tap(verify);
      await waitFor(find.text('FINSIGHT 가입이 완료됐어요.'));
      await shot('A_016');
      await tap(find.text('지금 시작하기'));

      Future<void> login([String password = _newPassword]) async {
        final fields = find.byType(TextField);
        await enter(fields.at(0), _email);
        await enter(fields.at(1), password);
        await tap(find.widgetWithText(FilledButton, '로그인'));
      }

      await waitFor(find.text('첫 진단을 시작해볼까요?'));
      await shot('B_001');
      await show(find.text('가이드 받기'));
      await shot('B_001-steps');
      await tap(find.text('내 결과 확인'));
      await waitFor(find.text('아직 확인할 결과가 없어요'));
      await shot('C_01');
      await tap(find.text('홈으로'));
      if (_notifications) {
        await tap(find.byTooltip('알림'));
        await waitFor(find.text('아직 알림이 없어요'));
        await shot('B_004');
        await tap(find.text('알림 설정하기'));
        final guide = find.widgetWithText(SwitchListTile, '맞춤 가이드 행동 알림');
        final master = find.widgetWithText(SwitchListTile, '전체 푸시 알림');
        await waitFor(guide);
        expect(tester.widget<SwitchListTile>(master).value, isFalse);
        expect(tester.widget<SwitchListTile>(guide).value, isFalse);
        await shot('B_005');
        await tap(guide);
        await back();
        await tap(find.text('알림 설정하기'));
        await waitFor(guide);
        expect(tester.widget<SwitchListTile>(master).value, isFalse);
        expect(tester.widget<SwitchListTile>(guide).value, isTrue);
        await shot('B_005-preference-saved');

        final client = HttpClient();
        try {
          final request = await client.postUrl(
            Uri.parse('$_mailbox/seed-notifications'),
          );
          final response = await request.close();
          expect(response.statusCode, 204);
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }

        await back();
        await back();
        final unreadBell = find.byTooltip('알림 · 읽지 않은 항목 있음');
        await waitFor(unreadBell);
        await tap(unreadBell);
        final reminder = find.text('다시 진단할 시간이에요');
        await waitFor(reminder);
        expect(find.text('오늘'), findsOneWidget);
        expect(find.text('지난 알림'), findsOneWidget);
        await shot('B_003');

        await tap(find.text('가이드'));
        await waitFor(find.text('아직 알림이 없어요'));
        await shot('B_004-filter');
        await tap(find.text('진단'));
        await waitFor(reminder);
        expect(find.text('지난 알림'), findsNothing);
        await tap(reminder);
        await waitFor(find.text('진단 시작하기'));
        await back();
        await waitFor(reminder);
        await tap(find.text('홈').last);
        await waitFor(find.text('첫 진단을 시작해볼까요?'));
        // The server persists read_at after the app marks the item read.
        await waitFor(find.byTooltip('알림'));
        expect(unreadBell, findsNothing);
      }
      await tap(find.text('기록'));
      await waitFor(find.text('진단 기록'));
      await tap(find.text('월간 리포트'));
      await waitFor(find.text('아직 이번 달 리포트가 없어요'));
      await shot('D_04');
      await tap(find.text('진단 기록 확인'));
      await waitFor(find.text('진단 기록'));
      await tap(find.text('홈'));
      await tap(find.text('첫 자가진단 시작하기'));
      await shot('B_006');
      await tap(find.text('진단 시작하기'));
      await waitFor(find.byType(ChoiceChip));
      await tap(find.byTooltip('설문 나가기'));
      await waitFor(find.text('진단을 그만둘까요?'));
      await shot('B_008');
      await tap(find.text('나가기'));
      await waitFor(find.text('첫 자가진단 시작하기'));
      await tap(find.text('첫 자가진단 시작하기'));
      await tap(find.text('진단 시작하기'));
      await waitFor(find.text('Q01 / 30'));
      await tap(find.byTooltip('설문 나가기'));
      await tap(find.text('계속하기'));
      await waitFor(find.text('Q01 / 30'));
      for (var index = 0; index < 30; index++) {
        if (index == 0 || index == 29) {
          await shot('B_007-question-${index + 1}');
        }
        final answers = find.byType(ChoiceChip);
        expect(answers, findsNWidgets(5));
        for (final label in ['매우낮음', '낮음', '보통', '높음', '매우높음']) {
          expect(find.text(label), findsOneWidget);
        }
        await tap(answers.at(2));
        if (index == 0) await shot('B_007-question-1-selected');
        await tap(
          find.widgetWithText(FilledButton, index == 29 ? '제출' : '다음으로'),
        );
      }
      await shot('survey-submit');
      final submit = find.widgetWithText(FilledButton, '제출하기');
      await show(submit);
      final submitAction = tester.widget<FilledButton>(submit).onPressed;
      expect(submitAction, isNotNull);
      // Capture the transient loading state without the test binding's touch overlay.
      submitAction!();
      await tester.pump();
      expect(find.text('나의 금융 스트레스를\n분석하고 있어요'), findsOneWidget);
      await binding.takeScreenshot('B_009');
      await waitFor(find.text('결과 확인하기'));
      await shot('B_010');
      await tap(find.text('결과 확인하기'));
      expect(find.text('50'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.semanticLabel == '부채부담형',
        ),
        findsOneWidget,
      );
      await shot('C_03');
      await show(find.text('가족부양'));
      await shot('C_03-pressure-details');
      await show(find.text('전반적으로 느끼는 금융 스트레스'));
      expect(find.text('보통'), findsOneWidget);
      expect(find.text('익명 비교 보기'), findsNothing);
      await shot('C_03-overall-stress');
      await back();
      await waitFor(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.semanticsLabel == '$_email님',
        ),
      );
      await shot('B_002');
      await tap(find.widgetWithText(InkWell, '나의 금융 스트레스'));
      await waitFor(find.text('50'));
      await back();
      await show(find.text('홈 위젯'));
      await shot('B_002-shortcuts');

      await tap(find.text('맞춤 가이드 보기'));
      await waitFor(find.text('맞춤 가이드'));
      await waitFor(find.text('50점 · 부채부담형 맞춤 가이드'));
      await shot('C_007');
      expect(find.byType(ListTile), findsNWidgets(4));
      await tap(find.widgetWithText(ChoiceChip, '알아보기'));
      expect(find.byType(ListTile), findsOneWidget);
      await tap(find.widgetWithText(ChoiceChip, '시작하기'));
      expect(find.byType(ListTile), findsNWidgets(3));
      await tap(find.text('추천 행동 자세히 보기'));
      await waitFor(find.text('TODAY’S ACTION'));
      final displayedGuide = tester.widget<GuideDetail>(
        find.byType(GuideDetail),
      );
      await shot('C_008');
      expect(find.text('확인했어요'), findsNothing);
      expect(find.text('완료 · 확인 취소'), findsNothing);
      await tap(find.text('더 많은 가이드 보기'));
      await waitFor(find.text('맞춤 가이드'));
      await back();

      Future<void> openWidget({bool stale = false}) => _localFixture(
        Uri(
          path: 'open-action-widget',
          queryParameters: {
            'attemptId': displayedGuide.attemptId,
            'id': displayedGuide.id,
            if (stale) 'stale': 'true',
          },
        ).toString(),
      );
      await openWidget();
      await waitFor(find.text('TODAY’S ACTION'));
      final openedGuide = tester.widget<GuideDetail>(find.byType(GuideDetail));
      expect(openedGuide.id, displayedGuide.id);
      expect(openedGuide.attemptId, displayedGuide.attemptId);
      expect(openedGuide.revision, isPositive);
      await shot('D_005-action-open');
      await back();
      await openWidget(stale: true);
      await waitFor(find.text('위젯에 표시된 행동을 지금은 볼 수 없어요.'));
      expect(find.text('TODAY’S ACTION'), findsNothing);
      await shot('D_005-action-revision-changed');
      await tap(find.text('가이드 목록으로'));
      await waitFor(find.text('맞춤 가이드'));
      await back();

      await tap(find.text('또래 비교'));
      await waitFor(find.text('익명 비교 안내'));
      await shot('C_04');
      await tap(find.text('익명 비교 확인'));
      await waitFor(find.text('인사이트가 모이는 중이에요'));
      expect(find.textContaining('집계 인원'), findsNothing);
      expect(find.textContaining('집계 기간'), findsNothing);
      await shot('C_02');
      await tap(find.text('내 맞춤 가이드 보기'));
      await waitFor(find.text('맞춤 가이드'));
      await back();
      await tap(find.text('익명 비교 안내로'));
      await back();
      await tap(find.text('익명 인사이트'));
      await waitFor(find.text('인사이트가 모이는 중이에요'));
      await shot('C_02-insights');
      await tap(find.text('돌아가기'));

      if (_publishedInsight) {
        await _localFixture('publish-insight');
        await tap(find.text('또래 비교'));
        await tap(find.text('익명 비교 확인'));
        await waitFor(find.text('부채'));
        expect(find.text('60점'), findsOneWidget);
        expect(find.text('39점'), findsNothing);
        await tap(find.text('공개 인사이트 보기'));
        final card = find.text('한 달 생활비부터 적어보기');
        await waitFor(card);
        await shot('C_05');
        await tap(find.widgetWithText(ChoiceChip, '대응자원'));
        await waitFor(find.text('인사이트가 모이는 중이에요'));
        await shot('C_02-topic-empty');
        await tap(find.widgetWithText(ChoiceChip, '전체'));
        await waitFor(card);
        await tap(card);
        final helpful = find.text('도움됐어요');
        final selectedHelpful = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.selected == true &&
              widget.child is OutlinedButton,
        );
        await waitFor(helpful);
        await shot('C_06');
        await tap(helpful);
        await waitFor(selectedHelpful);
        await back();
        await waitFor(find.text('도움 1'));
        await tap(card);
        await waitFor(selectedHelpful);
        await tap(find.text('잘 모르겠어요'));
        expect(selectedHelpful, findsNothing);
        await tap(find.text('홈'));
        await waitFor(find.text('맞춤 가이드 보기'));
        await tap(find.text('또래 비교'));
        await tap(find.text('익명 비교 확인'));
        await waitFor(find.text('공개 인사이트 보기'));
        await tap(find.text('공개 인사이트 보기'));
        await waitFor(card);
        await tap(card);
        await waitFor(helpful);
        await _localFixture('revoke-insight');
        await tap(helpful);
        await waitFor(find.text('지금 공개된 인사이트가 아니에요.'));
        expect(card, findsNothing);
        expect(find.textContaining('집계 인원'), findsNothing);
        await shot('C_06-unpublished');
        await tap(find.text('목록으로 돌아가기'));
        await waitFor(find.text('인사이트가 모이는 중이에요'));
        await tap(find.text('돌아가기'));
        await waitFor(find.text('현재 공개된 비교 결과가 없어요.'));
        await tap(find.text('익명 비교 안내로'));
        await back();
      }

      await tap(find.text('월간 리포트'));
      await waitFor(find.text('한 달 동안 확인한 변화'));
      expect(find.textContaining('첫 진단 '), findsNothing);
      await shot('D_03');
      final shareCard = find.text('공유 카드 확인');
      await show(shareCard);
      await shot('D_03-activity');
      await tap(shareCard);
      await waitFor(find.text('나의 금융 마음 점수'));
      expect(find.text('50'), findsOneWidget);
      await shot('D_06');
      await tap(find.byTooltip('카드 표시 설정'));
      for (final label in ['점수 가리기', '유형 가리기']) {
        final control = find.widgetWithText(SwitchListTile, label);
        await waitFor(control);
        await tap(control);
        expect(tester.widget<SwitchListTile>(control).value, isTrue);
      }
      final confirmCardOptions = find.widgetWithText(FilledButton, '확인');
      await waitFor(confirmCardOptions);
      await tap(confirmCardOptions);
      expect(find.text('50'), findsNothing);
      expect(find.text('부채부담형'), findsNothing);
      await shot('D_06-hidden');
      await tap(find.text('홈 화면으로 돌아가기'));
      await waitFor(find.text('맞춤 가이드 보기'));

      await tap(find.text('홈 위젯'));
      await waitFor(find.text('1개월째 기록 중'));
      await shot('D_005');
      await tap(find.byTooltip('진단 요약'));
      expect(find.text('나의 금융 마음'), findsOneWidget);
      expect(find.text('50'), findsNothing);
      await shot('D_005-summary-hidden');

      Future<void> changeWidgetVisibility() async {
        await tap(find.byTooltip('위젯 표시 설정'));
        for (final label in ['점수 표시', '유형 표시', '개인화 뉴스·행동 표시']) {
          await tap(find.text(label));
        }
        await tap(find.widgetWithText(FilledButton, '저장'));
      }

      await changeWidgetVisibility();
      await waitFor(find.text('50'));
      expect(find.text('부채부담형'), findsOneWidget);
      await shot('D_005-summary');
      await tap(find.byTooltip('경제 뉴스'));
      expect(find.text('MORNING BRIEF'), findsOneWidget);
      if (_publishedNews) {
        await waitForImage(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is MemoryImage &&
                widget.width == 95 &&
                widget.height == 95,
          ),
        );
        expect(find.text('은행 대출금리 4.40% 한 달 새 0.13%p 올랐어요'), findsOneWidget);
        await _localFixture('widget-photo-present');
      } else {
        await waitForImage(assetImage('widget-news'));
      }
      await shot('D_005-news');
      await tap(find.byTooltip('오늘의 행동'));
      expect(find.text('TODAY’S ACTION'), findsOneWidget);
      await shot('D_005-action');
      await changeWidgetVisibility();
      await waitFor(find.text('오늘의 작은 행동'));
      if (_publishedNews) {
        await _localFixture('widget-photo-hidden');
        await tap(find.byTooltip('경제 뉴스'));
        await waitForImage(assetImage('widget-news'));
        expect(find.text('은행 대출금리 4.40% 한 달 새 0.13%p 올랐어요'), findsNothing);
        await shot('D_005-news-hidden');
      }
      await back();

      await tap(find.text('뉴스'));
      await waitFor(find.textContaining('오늘의 경제'));
      if (_publishedNews) {
        await waitFor(find.text('은행 대출금리 4.40% 한 달 새 0.13%p 올랐어요'));
        await shot('D_01');
        await tap(find.text('1분 요약 보기 →'));
        await waitFor(find.text('한눈에 보기'));
        final articleImage = find.byWidgetPredicate(
          (widget) => widget is Image && widget.semanticLabel == '기사 이미지',
        );
        await waitForImage(articleImage);
        expect(articleImage.hitTestable(), findsOneWidget);
        await shot('D_02');
        final action = find.text('오늘의 작은 행동');
        await show(action);
        await Scrollable.ensureVisible(tester.element(action), alignment: .9);
        await settle();
        expect(articleImage.hitTestable(), findsOneWidget);
        await waitForImage(assetImage('news-connection'));
        await waitForImage(assetImage('news-small-action'));
        expect(
          find.text('내 대출의 금리 방식과 다음 상환 일정을 확인하는 것이 중요해요.'),
          findsOneWidget,
        );
        await shot('D_02-action');
        final client = HttpClient();
        try {
          final request = await client.postUrl(
            Uri.parse('$_mailbox/expire-news'),
          );
          final response = await request.close();
          expect(response.statusCode, HttpStatus.noContent);
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
        await tap(find.text('기사 원문 보기'));
        await waitFor(find.text('현재 공개된 기사가 아니에요.'));
        await shot('D_02-expired');
        await tap(find.text('목록으로 돌아가기'));
      }
      await waitFor(find.textContaining('오늘의 뉴스를 준비'));
      await shot('D_01-preparing');
      await tap(find.text('기록'));
      await waitFor(find.text('진단 기록'));
      await tap(find.text('홈'));

      await tap(find.text('자가진단 하기'));
      await tap(find.text('진단 시작하기'));
      await waitFor(find.text('Q01 / 30'));
      for (var index = 0; index < 30; index++) {
        final answers = find.byType(ChoiceChip);
        expect(answers, findsNWidgets(5));
        await tap(answers.at(index == 0 ? 4 : 2));
        await tap(
          find.widgetWithText(FilledButton, index == 29 ? '제출' : '다음으로'),
        );
      }
      network.offline = true;
      try {
        await tap(find.text('제출하기'));
        await waitFor(find.text('인터넷 연결 오류'));
        await shot('F_009');
      } finally {
        network.offline = false;
      }
      await tap(find.text('다시 시도'));
      await waitFor(find.text('결과 확인하기'));
      await back();
      await tap(find.text('기록'));
      await waitFor(find.text('금융 스트레스 변화'));
      await shot('E_002');
      await tap(find.text('변화 기록'));
      await waitFor(find.text('금융 스트레스 추이'));
      expect(find.text('직전 진단 대비 +2점'), findsOneWidget);
      await shot('E_001');
      await tap(find.text('50점 · 부채부담형'));
      await waitFor(find.text('50'));
      await back();
      await back();

      await tap(find.text('MY'));
      await shot('E_003');
      await tap(find.text('이용약관'));
      await waitFor(find.byType(PolicyList));
      final policyRow = find
          .descendant(
            of: find.byType(PolicyList),
            matching: find.byType(ListTile),
          )
          .first;
      await waitFor(find.textContaining('local-preview-v1'));
      await shot('E_005');
      await tap(policyRow);
      await waitFor(find.textContaining('local-preview-v1'));
      await shot('E_006');
      await tap(find.text('약관 목록으로'));
      await waitFor(find.byType(PolicyList));
      await back();
      await tap(find.text('도움말 · 자주 묻는 질문'));
      final scoreFaq = find.text('YFSI 점수는 무엇을 뜻하나요?');
      await waitFor(scoreFaq);
      await shot('E_009');
      await tap(scoreFaq);
      await waitFor(find.textContaining('점수가 높을수록'));
      await tap(find.text('위젯에서 점수를 숨길 수 있나요?'));
      await waitFor(find.textContaining('‘위젯 추가하기’를 열고'));
      await back();
      await tap(find.text('서비스 정보'));
      await waitFor(find.textContaining('앱 버전 '));
      await shot('E_010');
      await back();
      await tap(find.text('개인정보 · 동의 관리'));
      final consent = find.widgetWithText(SwitchListTile, '연구 활용 동의');
      await waitFor(consent);
      expect(tester.widget<SwitchListTile>(consent).value, isFalse);
      await shot('E_004');
      Finder consentValue(bool value) => find.byWidgetPredicate(
        (widget) =>
            widget is SwitchListTile &&
            widget.value == value &&
            widget.title is Text &&
            (widget.title! as Text).data == '연구 활용 동의',
      );
      await tap(consent);
      await waitFor(consentValue(true));
      await tap(consent);
      await waitFor(consentValue(false));
      await back();
      await tap(find.text('내 정보 수정'));
      await waitFor(find.text('내 정보를 수정해요'));
      await shot('E_007');
      final age = find.byType(DropdownButtonFormField<String>).first;
      await tap(age);
      await tap(find.text('만 23세 ~ 25세').last);
      await tap(find.text('저장하기'));
      await waitFor(find.text('계정 보안'));
      final profileSaved = find.text('기본 정보를 저장했어요.');
      await waitFor(profileSaved);
      await tester.pump(const Duration(seconds: 4));
      await settle();
      expect(profileSaved, findsNothing);
      await tap(find.text('내 정보 수정'));
      await waitFor(find.text('내 정보를 수정해요'));
      expect(find.text('만 23세 ~ 25세'), findsOneWidget);
      await back();
      await waitFor(find.text('계정 보안'));
      await tap(find.text('계정 보안'));
      expect(find.text(_email), findsOneWidget);
      await shot('E_008');
      await tap(find.text('데이터 내보내기'));
      await waitFor(find.text('본인 확인'));
      await shot('F_001');
      await enter(find.byType(TextField), _password);
      await tap(find.text('본인 확인'));
      await waitFor(find.text('내보내기 요청'));
      await tap(find.text('내보내기 요청'));
      await shot('F_002');
      for (
        var check = 0;
        find.text('ZIP 다운로드').evaluate().isEmpty && check < 25;
        check++
      ) {
        await tester.pump(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(find.text('ZIP 다운로드'), findsOneWidget);
      await settle();
      expect(
        tester.widget<Text>(find.text('내보내기가 완료되었습니다.')).style?.color,
        FinsightColors.noticeText,
      );
      await shot('F_003');
      await back();
      await back();
      await tap(find.text('데이터 삭제'));
      await shot('F_004');
      await tap(find.text('내보내기 먼저 받기'));
      await waitFor(find.text('ZIP 다운로드'));
      await back();
      await tap(find.text('삭제 요청 계속하기'));
      await enter(find.byType(TextField), _password);
      await tap(find.text('본인 확인'));
      await waitFor(find.text('삭제하기'));
      await waitForImage(assetImage('data-deletion-trash'));
      await shot('F_005');
      await tap(find.text('삭제하기'));
      for (
        var check = 0;
        find.text('진단 기록과 설문 응답을 삭제했어요.').evaluate().isEmpty && check < 25;
        check++
      ) {
        await tester.pump(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(find.text('진단 기록과 설문 응답을 삭제했어요.'), findsOneWidget);
      await tap(primary);
      await waitFor(find.text('첫 진단을 시작해볼까요?'));

      final logoutEntry = find.text('로그아웃');
      final confirmLogout = find.widgetWithText(FilledButton, '로그아웃 하기');
      await tap(find.text('MY'));
      await tap(logoutEntry);
      await waitFor(find.text('로그아웃할까요?'));
      await shot('F_006');
      await tap(find.text('취소'));
      expect(find.text('로그아웃할까요?'), findsNothing);
      await tap(logoutEntry);
      await tap(confirmLogout);
      await waitFor(find.text('시작하기'));
      await tap(find.textContaining('로그인하기', findRichText: true));
      await shot('A_003');
      await tap(find.text('비밀번호 재설정'));
      await shot('A_005');
      await enter(find.byType(TextField), _email);
      await tap(find.text('재설정 메일 보내기'));
      await waitFor(find.textContaining('i***@***'));
      expect(find.text(_email), findsNothing);
      await shot('A_006');
      await tap(find.text('새 비밀번호 설정하기'));
      expect(find.text('메일에서 재설정 링크 열기'), findsOneWidget);
      await tap(find.text('확인'));
      await _openResetLink();
      await waitFor(find.byType(PasswordResetComplete));
      final resetFields = find.byType(TextField);
      await show(resetFields.first);
      await shot('A_007');

      Future<void> changePassword() async {
        await enter(resetFields.at(0), _newPassword);
        await enter(resetFields.at(1), _newPassword);
        await tap(find.text('비밀번호 변경하기'));
      }

      await changePassword();
      await waitFor(find.text('비밀번호가 재설정되었어요'));
      await shot('A_008');
      await tap(find.text('로그인하기'));
      expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
      await _openResetLink();
      await waitFor(find.byType(PasswordResetComplete));
      await changePassword();
      await waitFor(find.text('사용할 수 없는 링크예요. 재설정 메일을 다시 요청해주세요.'));
      await shot('A_007-used-link');
      await tap(find.byType(BackButton).first);
      final loginButton = find.widgetWithText(FilledButton, '로그인');
      final resetButton = find.widgetWithText(FilledButton, '비밀번호 재설정');
      await show(loginButton);
      final loginPosition = tester.getRect(loginButton);
      final resetPosition = tester.getRect(resetButton);
      await login(_password);
      final credentialHeading = find.text('로그인 정보를\n확인해주세요');
      await waitFor(credentialHeading);
      final loginFields = find.byType(EditableText);
      expect(
        tester.widget<EditableText>(loginFields.first).controller.text,
        _email,
      );
      expect(
        tester.widget<EditableText>(loginFields.last).controller.text,
        isEmpty,
      );
      expect(tester.widget<EditableText>(loginFields.last).obscureText, isTrue);
      expect(find.text('소셜 아이디로 시작하기').hitTestable(), findsNothing);
      expect(
        tester.getRect(find.widgetWithText(FilledButton, '다시 로그인하기')),
        loginPosition,
      );
      expect(
        tester.getRect(find.widgetWithText(FilledButton, '비밀번호 재설정하기')),
        resetPosition,
      );
      await shot('A_004');
      await tap(find.text('비밀번호 재설정하기'));
      await waitFor(find.text('비밀번호를\n재설정할게요'));
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        _email,
      );
      await back();
      await waitFor(credentialHeading);
      await enter(loginFields.last, _newPassword);
      await tap(find.text('다시 로그인하기'));
      await waitFor(find.text('첫 진단을 시작해볼까요?'));

      await tap(find.text('MY'));
      await waitFor(find.text('계정 보안'));
      await tap(find.text('계정 보안'));
      await tap(find.text('회원 탈퇴 요청 →'));
      await shot('F_007-reauth');
      await enter(find.byType(TextField), _newPassword);
      await tap(find.text('본인 확인'));
      await waitFor(find.text('탈퇴하시겠어요?'));
      await waitForImage(assetImage('withdrawal-trash'));
      await shot('F_007');
      await tap(find.text('탈퇴하기'));
      await waitFor(find.text('탈퇴 요청이 접수됐어요.'));
      await waitForImage(assetImage('withdrawal-receipt'));
      await shot('F_008');
      await tap(find.widgetWithText(FilledButton, '확인'));
      await tap(find.textContaining('로그인하기', findRichText: true));
      await login();
      await waitFor(find.text('탈퇴 취소'));
      await enter(find.byType(TextField), _newPassword);
      await tap(find.text('탈퇴 취소 확인'));
      await waitFor(find.text('탈퇴 요청을 취소했어요. 다시 로그인해주세요.'));
      await login();
      await waitFor(find.text('첫 진단을 시작해볼까요?'));
      await tap(find.text('MY'));
      await tap(logoutEntry);
      await tap(confirmLogout);
      await waitFor(find.text('시작하기'));
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}

class _WaitingExportApi extends AppApi {
  final release = Completer<void>();

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    await release.future;
    return Response<T>(requestOptions: RequestOptions(path: path));
  }
}

class _Connectivity extends HttpOverrides {
  _Connectivity(this.apiPort);
  final int apiPort;
  bool offline = false;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (uri) =>
            offline && uri.host == '127.0.0.1' && uri.port == apiPort
            ? 'PROXY 127.0.0.1:1'
            : 'DIRECT';
}

Future<String> _signupCode() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(_mailbox));
    final response = await request.close().timeout(const Duration(seconds: 12));
    expect(response.statusCode, 200);
    final code = String.fromCharCodes(
      await response.expand((bytes) => bytes).toList(),
    );
    expect(code, matches(RegExp(r'^\d{6}$')));
    return code;
  } finally {
    client.close(force: true);
  }
}

Future<void> _localFixture(String action) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$_mailbox/$action'));
    final response = await request.close().timeout(const Duration(seconds: 10));
    expect(response.statusCode, 204);
    await response.drain<void>();
  } finally {
    client.close(force: true);
  }
}

Future<void> _openResetLink() async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$_mailbox/open-reset'));
    final response = await request.close().timeout(const Duration(seconds: 15));
    await response.drain<void>();
    expect(response.statusCode, 204);
  } finally {
    client.close(force: true);
  }
}

import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/design/finsight_theme.dart';
import 'package:finsight/diagnosis/guide_screen.dart';
import 'package:finsight/diagnosis/insight_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _title = '이번 달 꼭 필요한 생활비부터 한 줄씩 적어보는 작은 실천';
const _body = '매달 달라지는 지출과 꼭 필요한 고정지출을 구분하고, 금액과 납부일을 한 줄씩 확인해 보세요.';

class _EditorialApi extends AppApi {
  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    const guide = {
      'id': 'DEBT-1',
      'order': 1,
      'version': 1,
      'category': 'START',
      'title': _title,
      'heading': '실천을 시작하기 전에 생활비를 살펴봐요',
      'body': _body,
      'action': '이번 달 생활비 적기',
      'steps': [_body, '월별 예산을 표시해요.', '다음 달에 다시 확인해요.'],
    };
    const insight = {
      'id': 'insight-one',
      'revision': 1,
      'title': _title,
      'summary': _body,
      'topic': 'EXTERNAL_AREA_MEAN',
      'helpfulCount': 0,
    };
    final uri = Uri.parse(path);
    final result = switch (uri.path) {
      '/api/v1/guides' => {
        'diagnosis': {'attemptId': 'attempt-one', 'score': 50, 'type': 'DEBT'},
        'guides': [guide],
      },
      '/api/v1/guides/DEBT-1/view' => {'guide': guide, 'completed': false},
      '/api/v1/insights' => {
        'diagnosed': true,
        'items': [insight],
      },
      '/api/v1/insights/insight-one' => {
        'card': insight,
        'body': _body,
        'explanation': _body,
        'from': '2026-10-01',
        'to': '2026-10-31',
        'sampleSize': 30,
        'formulaVersion': 'yfsi-v1',
        'metric': {'DEBT': 60},
        'helpful': false,
      },
      _ => null,
    };
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: result as T?,
    );
  }
}

void main() {
  for (final insight in [true, false]) {
    testWidgets(
      '${insight ? 'insight' : 'guide'} preserves long content and actions with large text',
      (tester) async {
        final api = _EditorialApi();
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
            home: insight
                ? InsightScreen(api: api)
                : GuideScreen(api: api, badgeName: (_) => '부채부담형'),
          ),
        );
        await tester.pumpAndSettle();
        final title = find.text(_title);
        await tester.scrollUntilVisible(title.hitTestable(), 150);
        await tester.ensureVisible(title);
        await tester.pumpAndSettle();
        expect(title.hitTestable(), findsOneWidget);
        await tester.tap(title);
        await tester.pumpAndSettle();

        final action = find.text(insight ? '도움됐어요' : '더 많은 가이드 보기');
        if (insight) {
          await tester.scrollUntilVisible(action, 150);
        } else {
          expect(find.text('확인했어요'), findsNothing);
          expect(find.text('완료 · 확인 취소'), findsNothing);
        }
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getBottomRight(action).dy, lessThan(650 - 34));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

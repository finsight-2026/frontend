import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/diagnosis/insight_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class InsightApi extends AppApi {
  final writes = <Object?>[];
  bool helpful = false;
  bool failNext = true;
  bool published = true;

  Map<String, dynamic> get card => {
    'id': 'insight-1',
    'revision': 1,
    'title': '함께 보는 부담',
    'summary': '요약',
    'topic': 'EXTERNAL_AREA_MEAN',
    'publishedAt': '2026-11-11T05:00:00Z',
    'helpfulCount': helpful ? 1 : 0,
  };

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    final request = RequestOptions(path: path);
    if (method == 'PUT') {
      writes.add(data);
      if (failNext) {
        failNext = false;
        throw DioException(requestOptions: request);
      }
      helpful = (data as Map)['helpful'] == true;
    }
    final url = Uri.parse(path).path;
    final payload = switch (url) {
      '/api/v1/insights' => {
        'diagnosed': true,
        'items': [if (published) card],
        'hasMore': false,
      },
      '/api/v1/insights/insight-1' || '/api/v1/insights/insight-1/helpful' => {
        'card': card,
        'body': '본문',
        'explanation': '공개 집계 설명',
        'from': '2026-10-11',
        'to': '2026-11-10',
        'sampleSize': 30,
        'formulaVersion': 'yfsi-v1',
        'metric': {'DEBT': 60},
        'helpful': helpful,
      },
      _ => null,
    };
    return Response<T>(requestOptions: request, data: payload as T?);
  }
}

void main() {
  testWidgets(
    'failed helpful leaves the prior state and a successful write refreshes the list',
    (tester) async {
      final api = InsightApi();
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: InsightScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.textContaining('도움 0'), findsOneWidget);
      await tester.tap(find.text('함께 보는 부담'));
      await tester.pumpAndSettle();
      final evidence = find.text('익명으로 집계된 행동과 승인된 지표만 표시해요.');
      await tester.ensureVisible(evidence);
      await tester.tap(evidence);
      await tester.pumpAndSettle();
      expect(find.text('부채 60점'), findsOneWidget);
      await tester.tap(evidence);
      await tester.pumpAndSettle();
      final help = find.text('도움됐어요');
      await tester.ensureVisible(help);
      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(help, findsOneWidget);
      expect(find.text('요청을 완료하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.selected == true &&
              widget.child is OutlinedButton,
        ),
        findsOneWidget,
      );
      expect(api.writes, [
        {'revision': 1, 'helpful': true},
        {'revision': 1, 'helpful': true},
      ]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('도움 1'), findsOneWidget);
    },
  );
}

import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/design/finsight_theme.dart';
import 'package:finsight/diagnosis/comparison_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('comparison displays metrics only for an available publication', (
    tester,
  ) async {
    final api = _ComparisonApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: finsightTheme(),
        home: ComparisonScreen(api: api),
      ),
    );
    expect(find.text('익명 비교 안내'), findsOneWidget);
    expect(api.requests, 0);

    final check = find.text('익명 비교 확인');
    await tester.ensureVisible(check);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.text('연결을 확인하고 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('인사이트가 모이는 중이에요'), findsNothing);

    api.fail = false;
    final retry = find.text('다시 시도');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('인사이트가 모이는 중이에요'), findsOneWidget);
    expect(find.textContaining('집계 기간'), findsNothing);
    expect(find.textContaining('집계 인원'), findsNothing);
    expect(find.text('87점'), findsNothing);
    expect(find.text('내 맞춤 가이드 보기'), findsOneWidget);

    api.available = true;
    await tester.tap(find.text('익명 비교 안내로'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(check);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.text('집계 인원 23명'), findsOneWidget);
    expect(find.text('87점'), findsOneWidget);
    expect(find.text('99점'), findsNothing);
    expect(find.text('공개 인사이트 보기'), findsOneWidget);
  });
}

class _ComparisonApi extends AppApi {
  bool fail = true;
  bool available = false;
  int requests = 0;

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    requests++;
    final options = RequestOptions(path: path);
    if (fail) throw DioException(requestOptions: options);
    return Response<T>(
      requestOptions: options,
      data:
          <String, dynamic>{
                'available': available,
                'reason': 'NOT_PUBLISHED',
                'sampleSize': 23,
                'from': '2026-10-01',
                'to': '2026-10-31',
                'metrics': {'YFSI_MEAN': 87, 'INTERNAL_ONLY': 99},
              }
              as T,
    );
  }
}

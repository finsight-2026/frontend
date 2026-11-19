import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/account/data_deletion_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeletionApi extends AppApi {
  final requests = <String>[];
  final submittedIds = <String>[];
  bool receiptAvailable = true;
  bool pendingReceipt = false;

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    requests.add('$method $path');
    final options = RequestOptions(path: path);
    if (path.endsWith('/reauth')) return Response(requestOptions: options);
    if (method == 'POST') {
      submittedIds.add((data as Map)['requestId'] as String);
      if (submittedIds.length == 1) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      }
    } else if (!receiptAvailable || path.endsWith('/data-deletion')) {
      throw DioException.badResponse(
        statusCode: 404,
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 404),
      );
    }
    return Response(
      requestOptions: options,
      data:
          {
                'requestId': submittedIds.singleOrNull ?? submittedIds.last,
                'status': pendingReceipt ? 'PENDING' : 'COMPLETED',
                'completedAt': pendingReceipt
                    ? null
                    : '2026-11-11T21:00:00+09:00',
              }
              as T,
    );
  }
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.text('삭제 요청 계속하기'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'local-password');
  await tester.tap(find.text('본인 확인'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('삭제하기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('large text and keyboard preserve the separate confirmation', (
    tester,
  ) async {
    final api = _DeletionApi();
    addTearDown(api.close);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: DataDeletionFlow(
          api: api,
          bottomNavigationBar: const SizedBox(height: 48, child: Text('MY')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('삭제 대상'), findsOneWidget);
    final proceed = find.text('삭제 요청 계속하기');
    expect(
      tester.getRect(proceed).bottom,
      lessThan(tester.getRect(find.text('MY')).top),
    );
    await tester.tap(proceed);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'local-password');
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    final verify = find.text('본인 확인');
    await tester.ensureVisible(verify);
    await tester.tap(verify);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.text('정말 삭제하시겠어요?'), findsOneWidget);
    expect(find.text('삭제하기'), findsOneWidget);
    expect(api.submittedIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepted deletion waits for the worker receipt', (tester) async {
    final api = _DeletionApi()..pendingReceipt = true;
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(home: DataDeletionFlow(api: api)));
    await _confirm(tester);
    expect(find.text('처리 상태 확인'), findsOneWidget);
    expect(find.text('진단 기록과 설문 응답을 삭제했어요.'), findsNothing);

    api.pendingReceipt = false;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(api.submittedIds, hasLength(1));
    expect(find.text('진단 기록과 설문 응답을 삭제했어요.'), findsOneWidget);
  });

  testWidgets(
    'lost response reads the receipt and system back reports completion',
    (tester) async {
      final api = _DeletionApi();
      addTearDown(api.close);
      bool? deleted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    deleted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => DataDeletionFlow(api: api),
                      ),
                    );
                  },
                  child: const Text('삭제 흐름 열기'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('삭제 흐름 열기'));
      await tester.pumpAndSettle();
      await _confirm(tester);

      expect(api.submittedIds, hasLength(1));
      expect(
        api.requests.last,
        'GET /api/v1/account/data-deletion/${api.submittedIds.single}',
      );
      expect(find.text('진단 기록과 설문 응답을 삭제했어요.'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
      expect(find.text('삭제 흐름 열기'), findsOneWidget);
    },
  );

  testWidgets(
    'missing receipt stays unconfirmed and retry uses the same request ID',
    (tester) async {
      final api = _DeletionApi()..receiptAvailable = false;
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: DataDeletionFlow(api: api)));
      await _confirm(tester);

      expect(find.text('진단 기록과 설문 응답을 삭제했어요.'), findsNothing);
      expect(find.text('요청 결과를 확인하지 못했어요. 다시 시도해주세요.'), findsOneWidget);
      await tester.tap(find.text('다시 확인하기'));
      await tester.pumpAndSettle();
      expect(api.submittedIds, hasLength(2));
      expect(api.submittedIds.toSet(), hasLength(1));
      expect(find.text('진단 기록과 설문 응답을 삭제했어요.'), findsOneWidget);
    },
  );
}

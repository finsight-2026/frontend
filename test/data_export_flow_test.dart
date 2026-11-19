import 'dart:async';

import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/account/data_export_flow.dart';
import 'package:finsight/design/content_skeleton.dart';
import 'package:finsight/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ExportApi extends AppApi {
  final calls = <String>[];
  bool requested = false;
  final initial = Completer<void>();

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    calls.add('$method $path');
    final options = RequestOptions(path: path);
    if (path.endsWith('/reauth')) return Response<T>(requestOptions: options);
    if (method == 'GET' && !requested) {
      await initial.future;
      throw DioException.badResponse(
        statusCode: 404,
        requestOptions: options,
        response: Response<void>(requestOptions: options, statusCode: 404),
      );
    }
    final now = DateTime.now().toUtc();
    requested = true;
    final job = <String, dynamic>{
      'id': 'test-export',
      'status': method == 'POST' ? 'PENDING' : 'COMPLETED',
      'requestedAt': now.toIso8601String(),
      if (method == 'GET')
        'expiresAt': now.add(const Duration(hours: 24)).toIso8601String(),
    };
    return Response<T>(requestOptions: options, data: job as T);
  }
}

void main() {
  testWidgets('export requires a separate request and checks for completion', (
    tester,
  ) async {
    final api = _ExportApi();
    addTearDown(api.close);
    const navigation = SizedBox(height: 48, child: Text('MY'));
    await tester.pumpWidget(
      MaterialApp(
        home: DataExportFlow(api: api, bottomNavigationBar: navigation),
      ),
    );
    final skeleton = find.byType(ContentSkeleton);
    expect(skeleton, findsOneWidget);
    expect(find.text('본인 확인'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SkeletonRows), findsOneWidget);
    api.initial.complete();
    await tester.pumpAndSettle();
    expect(skeleton, findsNothing);
    expect(find.text('MY DATA'), findsOneWidget);
    expect(find.text('CSV 2개 · ZIP 압축'), findsOneWidget);
    final verify = find.text('본인 확인');
    await tester.ensureVisible(verify);
    await tester.pumpAndSettle();
    final verifyPosition = tester.getTopLeft(verify);
    await tester.tap(verify);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('비밀번호를 입력해주세요.')).style?.color,
      FinsightColors.error,
    );
    expect(tester.getTopLeft(verify), verifyPosition);
    await tester.enterText(find.byType(TextField), 'Finsight123');
    await tester.ensureVisible(find.text('본인 확인'));
    await tester.tap(find.text('본인 확인'));
    await tester.pumpAndSettle();
    expect(api.calls, [
      'GET /api/v1/account/export',
      'POST /api/v1/account/reauth',
    ]);
    await tester.tap(find.text('내보내기 요청'));
    await tester.pumpAndSettle();
    expect(find.textContaining('파일을 준비하고 있어요'), findsOneWidget);
    final pending = find.widgetWithText(FilledButton, '데이터를 내보내고 있어요…');
    expect(tester.widget<FilledButton>(pending).onPressed, isNull);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('ZIP 다운로드'), findsOneWidget);
    final notice = find.text('내보내기가 완료되었습니다.');
    expect(tester.widget<Text>(notice).style?.color, FinsightColors.noticeText);
    final card = find.ancestor(
      of: notice,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                FinsightColors.noticeSurface,
      ),
    );
    expect(card, findsOneWidget);
    expect(tester.getSize(card).height, greaterThanOrEqualTo(45));
    expect(
      tester.getRect(find.text('ZIP 다운로드')).bottom,
      lessThan(tester.getTopLeft(find.byWidget(navigation)).dy),
    );
    expect(api.calls.last, 'GET /api/v1/account/export');
  });

  testWidgets(
    'export verification scrolls above the keyboard with large text',
    (tester) async {
      final api = _ExportApi()..initial.complete();
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
          home: DataExportFlow(
            api: api,
            bottomNavigationBar: const SizedBox(height: 48),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Finsight123');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      final verify = find.text('본인 확인');
      await tester.ensureVisible(verify);
      await tester.pumpAndSettle();
      expect(tester.getRect(verify).bottom, lessThanOrEqualTo(380));
      await tester.tap(verify);
      await tester.pumpAndSettle();
      expect(find.text('내보내기 요청'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

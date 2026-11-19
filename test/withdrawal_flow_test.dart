import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/account/withdrawal_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _WithdrawalApi extends AppApi {
  final paths = <String>[];
  bool cleared = false;

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    paths.add(path);
    final receipt = {'dueAt': '2026-11-24T12:30:00Z'};
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: path.endsWith('/withdrawal') ? receipt as T : null,
    );
  }

  @override
  void clearSession() => cleared = true;
}

void main() {
  testWidgets('reauthentication alone does not request withdrawal', (
    tester,
  ) async {
    final api = _WithdrawalApi();
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(home: WithdrawalFlow(api: api)));
    await tester.enterText(find.byType(TextField), 'Finsight123');
    await tester.tap(find.text('본인 확인'));
    await tester.pumpAndSettle();
    expect(api.paths, ['/api/v1/account/reauth']);
    expect(api.cleared, isFalse);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('탈퇴하기'));
    await tester.pumpAndSettle();
    expect(api.paths.last, '/api/v1/account/withdrawal');
    expect(api.cleared, isTrue);
    expect(find.text('탈퇴 요청이 접수됐어요.'), findsOneWidget);
    expect(find.textContaining('14일 안에 다시 로그인하시면'), findsOneWidget);
  });
}

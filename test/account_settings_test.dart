import 'package:dio/dio.dart';
import 'package:finsight/account/account_settings.dart';
import 'package:finsight/account/app_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SettingsApi extends AppApi {
  final updates = <Object?>[];
  bool research = false;
  int logoutRequests = 0;

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    final options = RequestOptions(path: path);
    if (method == 'POST' && path == '/api/v1/auth/logout') {
      logoutRequests++;
      if (logoutRequests == 1) {
        throw DioException(requestOptions: options);
      }
      return Response<T>(requestOptions: options);
    }
    if (path == '/api/v1/policies') {
      return Response<T>(
        requestOptions: options,
        data:
            <String, dynamic>{
                  'activeVersion': 'local-preview-v1',
                  'documents': [
                    <String, dynamic>{
                      'id': 'research',
                      'title': '연구 활용 안내',
                      'version': 'local-preview-v1',
                      'status': 'PREVIEW',
                    },
                  ],
                }
                as T,
      );
    }
    if (path.endsWith('/settings')) {
      return Response<T>(
        requestOptions: options,
        data:
            {
                  'email': 'qa@example.test',
                  'emailVerified': true,
                  'profile': {'age': '19_22', 'situation': 'EMPLOYED'},
                }
                as T,
      );
    }
    if (method == 'PUT' && path.endsWith('/research')) {
      updates.add(data);
      research = (data as Map)['granted'] as bool;
      return Response<T>(requestOptions: options);
    }
    if (path.endsWith('/consents')) {
      return Response<T>(
        requestOptions: options,
        data:
            <dynamic>[
                  {
                    'kind': 'RESEARCH',
                    'version': 'local-preview-v1',
                    'granted': research,
                    'method': 'APP_SETTINGS',
                    'recordedAt': '2026-11-10T12:00:00Z',
                  },
                ]
                as T,
      );
    }
    throw StateError('Unexpected account request $method $path');
  }
}

void main() {
  testWidgets('logout sheet fits large text and requires confirmation', (
    tester,
  ) async {
    final api = _SettingsApi();
    addTearDown(api.close);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    bool? loggedOut;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(bottom: 34),
            textScaler: const TextScaler.linear(1.7),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                loggedOut = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => AccountSettings(api: api)),
                );
              },
              child: const Text('설정 열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();

    Future<void> openSheet() async {
      final entry = find.text('로그아웃');
      await tester.scrollUntilVisible(entry, 200);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
    }

    await openSheet();
    final cancel = find.text('취소');
    expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(568 - 34));
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(api.logoutRequests, 0);

    await openSheet();
    final confirm = find.text('로그아웃 하기');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.logoutRequests, 1);
    expect(loggedOut, isNull);
    expect(find.text('로그아웃을 완료하지 못했어요. 다시 시도해주세요.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await openSheet();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(api.logoutRequests, 2);
    expect(loggedOut, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('masks the account email and saves research consent explicitly', (
    tester,
  ) async {
    final api = _SettingsApi();
    addTearDown(api.close);
    await tester.pumpWidget(MaterialApp(home: AccountSettings(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('q***@example.test'), findsOneWidget);
    expect(find.text('qa@example.test'), findsNothing);
    await tester.tap(find.text('계정 보안'));
    await tester.pumpAndSettle();
    expect(find.text('qa@example.test'), findsOneWidget);
    expect(find.text('데이터 내보내기'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('개인정보 · 동의 관리'));
    await tester.pumpAndSettle();
    final toggle = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(toggle).value, false);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(api.updates, [
      {'version': 'local-preview-v1', 'granted': true},
    ]);
    expect(tester.widget<SwitchListTile>(toggle).value, true);
  });
}

import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/design/finsight_theme.dart';
import 'package:finsight/notification/app_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'iOS requests permission after explaining why and saves only on success',
    (tester) async {
      const channel = MethodChannel('finsight/notification_permissions');
      var permission = 'notDetermined';
      final deviceCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        deviceCalls.add(call.method);
        switch (call.method) {
          case 'request':
            return permission = 'denied';
          case 'openSettings':
            permission = 'allowed';
            return true;
          default:
            return permission;
        }
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });

      final api = _PreferencesApi();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(home: NotificationPreferences(api: api)),
      );
      await tester.pumpAndSettle();
      final master = find.widgetWithText(SwitchListTile, '전체 푸시 알림');
      final guide = find.widgetWithText(SwitchListTile, '맞춤 가이드 행동 알림');
      expect(deviceCalls, ['status']);
      expect(tester.widget<SwitchListTile>(master).value, isFalse);
      expect(tester.widget<SwitchListTile>(guide).value, isTrue);

      await tester.tap(master);
      await tester.pumpAndSettle();
      expect(find.text('알림 수신 안내'), findsOneWidget);
      expect(deviceCalls, isNot(contains('request')));
      await tester.tap(find.text('계속'));
      await tester.pumpAndSettle();
      expect(deviceCalls, contains('request'));
      expect(find.text('차단됨'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(master).value, isFalse);
      expect(api.writes, isEmpty);

      await tester.tap(find.text('기기 설정 열기'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(deviceCalls, contains('openSettings'));
      await tester.scrollUntilVisible(find.text('허용됨'), 180);
      expect(find.text('허용됨'), findsOneWidget);
      await tester.ensureVisible(master);
      await tester.pumpAndSettle();

      api.reject = true;
      await tester.tap(master);
      await tester.pumpAndSettle();
      expect(find.text('알림 설정을 저장하지 못했어요. 다시 시도해주세요.'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(master).value, isFalse);

      api.reject = false;
      await tester.tap(master);
      await tester.pumpAndSettle();
      expect(api.writes.last, {'setting': 'ENABLED', 'enabled': true});
      expect(tester.widget<SwitchListTile>(master).value, isTrue);
      await tester.tap(master);
      await tester.pumpAndSettle();
      expect(api.writes.last, {'setting': 'ENABLED', 'enabled': false});
      expect(tester.widget<SwitchListTile>(guide).value, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('notification preferences fit large text and iOS safe areas', (
    tester,
  ) async {
    final api = _PreferencesApi();
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
        home: NotificationPreferences(api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('전체 푸시 알림')).dy, greaterThan(44));
    final economy = find.widgetWithText(SwitchListTile, '아침 경제 요약');
    await tester.scrollUntilVisible(economy, 130);
    await tester.ensureVisible(economy);
    await tester.pumpAndSettle();
    expect(economy.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PreferencesApi extends AppApi {
  final writes = <Object?>[];
  bool reject = false;
  bool enabled = false;

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    final options = RequestOptions(path: path);
    if (method == 'PUT') {
      writes.add(data);
      if (reject) throw DioException(requestOptions: options);
      enabled = (data as Map<String, Object?>)['enabled'] as bool;
    }
    return Response<T>(
      requestOptions: options,
      data: <String, dynamic>{'enabled': enabled, 'guide': true} as T,
    );
  }
}

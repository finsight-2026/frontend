import 'dart:async';

import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/account/foreground_activity.dart';
import 'package:finsight/notification/notification_device.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sync registers only when both permissions are on and clears on logout',
    () async {
      const channel = MethodChannel('finsight/notification_permissions');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var permission = 'allowed';
      messenger.setMockMethodCallHandler(channel, (_) async => permission);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final source = _RegistrationSource();
      addTearDown(() => unawaited(source.events.close()));
      final calls = <RequestOptions>[];
      var enabled = true;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            calls.add(request);
            final data = switch (request.path) {
              '/api/v1/auth/login' => {
                'accessToken': 'access',
                'refreshToken': 'refresh',
              },
              '/api/v1/notifications/preferences' => {'enabled': enabled},
              _ => null,
            };
            handler.resolve(Response(requestOptions: request, data: data));
          },
        ),
      );
      final api = AppApi(http: dio, registrationSource: source);
      addTearDown(api.close);
      await api.login('example@example.test', 'local-password');
      const path = '/api/v1/notifications/device';
      await api.syncNotificationDevice();
      expect(calls.last.method, 'PUT');
      expect(calls.last.path, path);
      expect(calls.last.data, {'provider': 'LOCAL', 'token': 'device-1'});
      expect(calls.last.headers['Authorization'], 'Bearer access');

      enabled = false;
      await api.syncNotificationDevice();
      expect(calls.last.method, 'DELETE');
      expect(calls.last.path, path);
      expect(source.token, isNull);

      enabled = true;
      await api.syncNotificationDevice();
      expect(calls.last.data, {'provider': 'LOCAL', 'token': 'device-2'});
      permission = 'denied';
      final beforeDenial = calls.length;
      await api.syncNotificationDevice();
      expect(calls.skip(beforeDenial).map((call) => call.method), ['DELETE']);
      expect(source.token, isNull);

      permission = 'allowed';
      await api.syncNotificationDevice();
      await api.logout();
      expect(source.token, isNull);
      final afterLogout = calls.length;
      await api.syncNotificationDevice();
      expect(calls.length, afterLogout);
    },
  );
  testWidgets('a token change updates only the active session registration', (
    tester,
  ) async {
    const permissions = MethodChannel('finsight/notification_permissions');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permissions, (_) async => 'allowed');
    addTearDown(() => messenger.setMockMethodCallHandler(permissions, null));

    final source = _RegistrationSource();
    addTearDown(() => unawaited(source.events.close()));
    final puts = <RequestOptions>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (request.path == '/api/v1/notifications/device' &&
              request.method == 'PUT') {
            puts.add(request);
          }
          final data = switch (request.path) {
            '/api/v1/auth/login' => {
              'accessToken': 'active-access',
              'refreshToken': 'refresh',
            },
            '/api/v1/notifications/preferences' => {'enabled': true},
            '/api/v1/account/activity' => {'date': '2026-11-11'},
            _ => null,
          };
          handler.resolve(Response(requestOptions: request, data: data));
        },
      ),
    );
    final api = AppApi(http: dio, registrationSource: source);
    addTearDown(api.close);
    await tester.runAsync(
      () => api.login('example@example.test', 'local-password'),
    );
    await tester.pumpWidget(
      ForegroundActivity(api: api, child: const SizedBox()),
    );
    await tester.pumpAndSettle();
    expect(puts.single.data, {'provider': 'LOCAL', 'token': 'device-1'});

    source.token = 'rotated-device';
    source.events.add(null);
    await tester.pumpAndSettle();
    expect(puts.last.data, {'provider': 'LOCAL', 'token': 'rotated-device'});
    expect(puts.last.headers['Authorization'], 'Bearer active-access');

    await tester.runAsync(api.logout);
    source.events.add(null);
    await tester.pumpAndSettle();
    expect(puts, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });
}

class _RegistrationSource implements NotificationRegistrationSource {
  @override
  Stream<void> get changes => events.stream;

  final events = StreamController<void>.broadcast();

  String? token;
  int _created = 0;

  @override
  Future<DeviceRegistration> registration() async =>
      (provider: 'LOCAL', token: token ??= 'device-${++_created}');

  @override
  void clear() => token = null;
}

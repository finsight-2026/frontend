import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/design/finsight_theme.dart';
import 'package:finsight/notification/app_notifications.dart';
import 'package:finsight/diagnosis/diagnosis_flow.dart';
import 'package:finsight/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _InboxApi extends AppApi {
  _InboxApi({this.noticeTarget, this.denyRead = false});

  final bool denyRead;

  final calls = <String>[];
  final Map<String, dynamic>? noticeTarget;

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    calls.add('$method $path');
    final options = RequestOptions(path: path);
    if (path.endsWith('/read')) {
      if (denyRead) {
        throw DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 404),
        );
      }
      return Response<T>(requestOptions: options);
    }
    if (path.startsWith('/api/v1/diagnosis/attempts')) {
      return Response<T>(
        requestOptions: options,
        data: <String, dynamic>{'items': []} as T,
      );
    }
    if (Uri.parse(path).queryParameters['filter'] == 'GUIDE') {
      return Response<T>(
        requestOptions: options,
        data: <String, dynamic>{'items': [], 'unread': true} as T,
      );
    }
    final payload = path.endsWith('/target')
        ? noticeTarget ??
              <String, dynamic>{
                'kind': 'EXPORT',
                'resource': null,
                'available': false,
              }
        : <String, dynamic>{
            'unread': true,
            'items': [
              {
                'id': 'notice',
                'kind': noticeTarget == null ? 'EXPORT' : 'NOTICE',
                'title': noticeTarget == null ? '파일 준비' : 'FINSIGHT 이용 안내',
                'body': '파일을 확인해주세요.',
                'createdAt': '2026-11-10T12:00:00Z',
                'read': false,
              },
            ],
          };
    return Response<T>(requestOptions: options, data: payload as T);
  }
}

void main() {
  testWidgets(
    'native tap starts at login and opens the owned destination afterward',
    (tester) async {
      const channel = MethodChannel('finsight/notification_opens');
      const notification = '02a06562-40cd-40bb-8e0b-1c76cc8c61db';
      String? pending = notification;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'peek') return pending != null;
        if (call.method != 'take') return null;
        final id = pending;
        pending = null;
        return id;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final api = _InboxApi(
        noticeTarget: {
          'kind': 'NOTICE',
          'available': true,
          'notice': {
            'title': '시스템 점검 안내',
            'summary': '요약',
            'body': '서버에서 확인한 본문',
          },
        },
      );
      addTearDown(api.close);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const WelcomeScreen()),
          GoRoute(
            path: '/login',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => context.push('/home'),
                child: const Text('테스트 로그인 완료'),
              ),
            ),
          ),
          GoRoute(
            path: '/home',
            builder: (_, _) => DiagnosisHome(api: api),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('테스트 로그인 완료'), findsOneWidget);
      expect(pending, notification);
      expect(api.calls, isEmpty);

      await tester.tap(find.text('테스트 로그인 완료'));
      await tester.pumpAndSettle();
      expect(find.text('시스템 점검 안내'), findsOneWidget);
      expect(find.text('서버에서 확인한 본문'), findsOneWidget);
      expect(pending, isNull);
      expect(api.calls.where((call) => call.contains(notification)), [
        'PUT /api/v1/notifications/$notification/read',
        'GET /api/v1/notifications/$notification/target',
      ]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('a stale or foreign push stays in the inbox', (tester) async {
    final api = _InboxApi(denyRead: true);
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => NotificationEntry.openInbox(
                context,
                api: api,
                notificationId: 'unavailable',
                openTarget: (_, _) async =>
                    fail('Unavailable notification navigated'),
              ),
              child: const Text('테스트 알림 열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('테스트 알림 열기'));
    await tester.pumpAndSettle();
    expect(find.text('이미 삭제되었거나 보관 기간이 지난 알림이에요.'), findsOneWidget);
    expect(api.calls.where((call) => call.endsWith('/target')), isEmpty);
  });

  testWidgets('inbox resolves the target after marking a notification read', (
    tester,
  ) async {
    final api = _InboxApi();
    addTearDown(api.close);
    Map<String, dynamic>? destination;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationEntry(
            api: api,
            openTarget: (_, target) async => destination = target,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('알림 · 읽지 않은 항목 있음'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('읽지 않음')), findsOneWidget);
    await tester.tap(find.text('파일 준비'));
    await tester.pumpAndSettle();

    expect(api.calls.sublist(api.calls.length - 2), [
      'PUT /api/v1/notifications/notice/read',
      'GET /api/v1/notifications/notice/target',
    ]);
    expect(destination, {
      'kind': 'EXPORT',
      'resource': null,
      'available': false,
    });
    expect(find.bySemanticsLabel(RegExp('읽지 않음')), findsNothing);
  });

  testWidgets('inbox and empty filters fit large text with safe areas', (
    tester,
  ) async {
    final api = _InboxApi();
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
        home: Scaffold(
          body: NotificationEntry(api: api, openTarget: (_, _) async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('알림 · 읽지 않은 항목 있음'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('놓치지 않도록 알려드릴게요')).dy, greaterThan(44));
    expect(find.text('파일 준비').hitTestable(), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '가이드'));
    await tester.pumpAndSettle();
    final settings = find.text('알림 설정하기');
    await tester.scrollUntilVisible(settings, 160);
    await tester.ensureVisible(settings);
    await tester.pumpAndSettle();
    expect(settings.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(settings).dy, lessThan(650 - 34));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an owned service notice opens in a scrollable sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 460));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _InboxApi(
      noticeTarget: {
        'kind': 'NOTICE',
        'available': true,
        'notice': {
          'title': '서비스 점검 일정',
          'summary': '점검 시간 안내',
          'body': List.filled(30, '서비스 점검 중 일부 기능이 제한됩니다.').join('\n'),
        },
      },
    );
    addTearDown(api.close);
    await _openNotice(tester, api);
    expect(find.text('서비스 점검 일정'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('공지 닫기'));
    await tester.pumpAndSettle();
    expect(find.text('FINSIGHT 이용 안내'), findsOneWidget);
  });

  testWidgets('an expired service notice keeps the inbox open', (tester) async {
    final api = _InboxApi(
      noticeTarget: {'kind': 'NOTICE', 'available': false, 'reason': 'EXPIRED'},
    );
    addTearDown(api.close);
    await _openNotice(tester, api);
    expect(find.text('게시 기간이 끝난 공지예요.'), findsOneWidget);
    expect(find.text('FINSIGHT 이용 안내'), findsOneWidget);
    expect(find.byTooltip('공지 닫기'), findsNothing);
  });
}

Future<void> _openNotice(WidgetTester tester, _InboxApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotificationEntry(
          api: api,
          openTarget: (_, _) async => fail('Notice must stay in the inbox'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('알림 · 읽지 않은 항목 있음'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('FINSIGHT 이용 안내'));
  await tester.pumpAndSettle();
}

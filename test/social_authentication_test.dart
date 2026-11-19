import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/account/social_authentication.dart';
import 'package:finsight/account/social_login.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('finsight/social_authentication');
const _state = '0000000000000000000000000000000000000000000';
const _verifier = '1111111111111111111111111111111111111111111';

class _SocialApi extends AppApi {
  _SocialApi({this.verifiedEmail});

  final String? verifiedEmail;
  final calls = <({String method, String path, Object? data})>[];

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    calls.add((method: method, path: path, data: data));
    final body = switch (path) {
      '/api/v1/auth/social/providers' => ['NAVER', 'APPLE', 'KAKAO'],
      '/api/v1/account/social/start' ||
      '/api/v1/auth/social/start' => <String, dynamic>{
        'authorizationUrl': 'https://kauth.kakao.com/oauth/authorize',
        'state': _state,
        'verifier': _verifier,
      },
      '/api/v1/account/social/finish' => <String, dynamic>{
        'status': 'REAUTHENTICATED',
      },
      '/api/v1/auth/social/finish' => <String, dynamic>{
        'status': 'ONBOARDING',
        'onboardingToken': _verifier,
        'verifiedEmail': verifiedEmail,
      },
      '/api/v1/policies' => <String, dynamic>{
        'activeVersion': 'release-2',
        'documents': [
          for (final id in [
            'terms',
            'privacy-policy',
            'privacy-consent',
            'research',
          ])
            {
              'id': id,
              'title': id,
              'version': 'release-2',
              'status': 'CURRENT',
              'effectiveDate': '2026-11-10',
            },
        ],
      },
      '/api/v1/auth/social/register' => <String, dynamic>{
        'status': 'CREATED',
        'tokens': <String, dynamic>{
          'accessToken': 'access',
          'refreshToken': 'refresh',
        },
      },
      _ => throw StateError('Unexpected request $path'),
    };
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: body as T,
    );
  }
}

class _SignupEntry extends StatefulWidget {
  const _SignupEntry(this.connection, this.provider);

  final AppApi connection;
  final SocialProvider provider;

  @override
  State<_SignupEntry> createState() => _SignupEntryState();
}

class _SignupEntryState extends SocialLoginState<_SignupEntry> {
  @override
  AppApi get api => widget.connection;

  @override
  void onExistingSocialAccount(PendingSocialLink link) =>
      throw StateError('Unexpected existing account');

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () => loginWithProvider(widget.provider),
          child: Text(widget.provider.label),
        ),
        if (authError case final error?) Text(error),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  for (final provider in SocialProvider.values) {
    testWidgets(
      '${provider.name} consent leads directly to signup completion',
      (tester) async {
        const email = 'verified@example.test';
        final api = _SocialApi(verifiedEmail: email);
        messenger.setMockMethodCallHandler(
          _channel,
          (_) async => 'finsight-social://auth/complete?state=$_state',
        );
        await tester.pumpWidget(MaterialApp(home: _SignupEntry(api, provider)));
        await tester.tap(find.text(provider.label));
        await tester.pumpAndSettle();
        expect(find.text('조금만 더 알려주세요'), findsOneWidget);

        final fields = find.byType(DropdownButtonFormField<String>);
        for (final (index, label) in [
          (0, '만 19세 ~ 22세'),
          (1, '직장인'),
          (2, '남자'),
          (3, '자가'),
          (4, '정기적인 근로소득이 있음'),
          (5, '없음'),
          (6, '전적으로 본인이 부담함'),
        ]) {
          await tester.ensureVisible(fields.at(index));
          await tester.tap(fields.at(index));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
        }

        final next = find.text('다음');
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        await tester.tap(find.text('(필수) 이용약관'));
        await tester.tap(find.text('(필수) 개인정보 수집 및 이용'));
        await tester.pumpAndSettle();
        final agree = find.text('동의하고 계속');
        await tester.ensureVisible(agree);
        await tester.tap(agree);
        await tester.pumpAndSettle();

        expect(find.text('FINSIGHT 가입이 완료됐어요.'), findsOneWidget);
        expect(find.text('지금 시작하기'), findsOneWidget);
        expect(api.calls.map((call) => call.path), [
          '/api/v1/auth/social/start',
          '/api/v1/auth/social/finish',
          '/api/v1/policies',
          '/api/v1/auth/social/register',
        ]);
        final start = api.calls.first.data as Map<String, dynamic>;
        expect(start['provider'], provider.id);
        final registration = api.calls.last.data as Map<String, dynamic>;
        expect(registration['email'], email);
        expect(registration.containsKey('code'), isFalse);
      },
    );
  }

  testWidgets('missing verified email shows guidance without sending a code', (
    tester,
  ) async {
    final api = _SocialApi();
    messenger.setMockMethodCallHandler(
      _channel,
      (_) async => 'finsight-social://auth/complete?state=$_state',
    );
    await tester.pumpWidget(
      MaterialApp(home: _SignupEntry(api, SocialProvider.kakao)),
    );
    await tester.tap(find.text('카카오'));
    await tester.pumpAndSettle();
    expect(find.textContaining('확인된 이메일을 받지 못했어요'), findsOneWidget);
    expect(api.calls.map((call) => call.path), [
      '/api/v1/auth/social/start',
      '/api/v1/auth/social/finish',
    ]);
  });

  test('iOS shows only Kakao and Apple in the Figma order', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final api = _SocialApi();
    addTearDown(api.close);
    expect(await SocialAuthentication(api).providers(), [
      SocialProvider.kakao,
      SocialProvider.apple,
    ]);
  });

  test('reauthentication finishes only with the matching callback', () async {
    final api = _SocialApi();
    addTearDown(api.close);
    messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'authenticate');
      expect(call.arguments, {
        'url': 'https://kauth.kakao.com/oauth/authorize',
        'reauthenticate': true,
      });
      return 'finsight-social://auth/complete?state=$_state';
    });
    final result = await SocialAuthentication(
      api,
    ).authenticate(SocialProvider.kakao, SocialPurpose.reauth);
    expect(result?['status'], 'REAUTHENTICATED');
    expect(api.calls.last.method, 'POST');
    expect(api.calls.last.path, '/api/v1/account/social/finish');
    expect(api.calls.last.data, {'state': _state, 'verifier': _verifier});
  });

  test(
    'canceling or supplying another state never submits the app verifier',
    () async {
      final api = _SocialApi();
      addTearDown(api.close);
      final social = SocialAuthentication(api);
      messenger.setMockMethodCallHandler(_channel, (_) async => null);
      expect(
        await social.authenticate(SocialProvider.kakao, SocialPurpose.reauth),
        isNull,
      );
      messenger.setMockMethodCallHandler(
        _channel,
        (_) async => 'finsight-social://auth/complete?state=wrong',
      );
      await expectLater(
        social.authenticate(SocialProvider.kakao, SocialPurpose.reauth),
        throwsFormatException,
      );
      expect(api.calls.map((call) => call.path), [
        '/api/v1/account/social/start',
        '/api/v1/account/social/start',
      ]);
    },
  );
}

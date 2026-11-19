import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/status_message.dart';
import '../design/tokens.dart';
import '../diagnosis/diagnosis_flow.dart';
import '../diagnosis/home_widget_platform.dart';
import 'app_api.dart';
import 'app_session_store.dart';
import 'foreground_activity.dart';
import 'social_authentication.dart';
import 'social_signup.dart';

typedef PendingSocialLink = ({String email, String token});

abstract class SocialLoginState<T extends StatefulWidget> extends State<T> {
  @protected
  final api = AppApi(sessionStore: appSessionStore);
  late final _social = SocialAuthentication(api);
  @protected
  late final socialProviders = _social.providers();

  @protected
  PendingSocialLink? pendingLink;
  @protected
  bool authBusy = false;
  @protected
  String? authError;

  @protected
  void onExistingSocialAccount(PendingSocialLink link);

  @override
  void dispose() {
    api.close();
    super.dispose();
  }

  @protected
  Future<void> loginWithProvider(SocialProvider provider) async {
    if (authBusy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      authBusy = true;
      authError = null;
    });
    try {
      final result = await _social.authenticate(provider, SocialPurpose.login);
      if (!mounted || result == null || result['status'] == 'CANCELED') return;
      switch (result['status']) {
        case 'ONBOARDING':
          final email = result['verifiedEmail'] as String?;
          if (email == null || email.isEmpty) {
            authError =
                '${provider.label}에서 확인된 이메일을 받지 못했어요. 이메일 공유에 동의하거나 다른 소셜 계정으로 가입해주세요.';
            return;
          }
          final token = result['onboardingToken'] as String;
          final signup = await openSocialSignup(context, _social, token, email);
          if (!mounted || signup == null) return;
          if (signup['status'] == 'EXISTING_ACCOUNT') {
            onExistingSocialAccount((email: email, token: token));
            return;
          }
          await api.acceptSession(signup['tokens'] as Map<String, dynamic>);
          if (!mounted) return;
          unawaited(HomeWidgetPlatform.instance.clear());
          final start = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => SocialSignupComplete(email: email),
            ),
          );
          if (start == true) {
            await openHome(email);
          } else {
            await api.logout();
          }
        case 'AUTHENTICATED':
          await api.acceptSession(result['tokens'] as Map<String, dynamic>);
          if (!mounted) return;
          unawaited(HomeWidgetPlatform.instance.clear());
          if (pendingLink != null) {
            final identity = await api.request<Map<String, dynamic>>(
              'GET',
              '/api/v1/account/settings',
            );
            final email = identity.data!['email'] as String;
            await finishPendingLink(email, () async {
              final verified = await _social.authenticate(
                provider,
                SocialPurpose.reauth,
              );
              return verified?['status'] == 'REAUTHENTICATED';
            });
            await openHome(email);
          } else {
            await openHome();
          }
        case 'WITHDRAWAL_PENDING':
          final date = DateTime.parse(
            result['withdrawalDueAt'] as String,
          ).toLocal();
          final confirmed = await _confirm(
            '탈퇴 취소',
            '${date.year}년 ${date.month}월 ${date.day}일까지 탈퇴를 취소할 수 있어요. ${provider.label} 인증으로 본인을 확인할게요.',
            '탈퇴 취소 확인',
          );
          if (confirmed && mounted) {
            final canceled = await _social.authenticate(
              provider,
              SocialPurpose.cancelWithdrawal,
            );
            if (mounted && canceled?['status'] == 'WITHDRAWAL_CANCELED') {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(statusSnackBar('탈퇴 요청을 취소했어요. 다시 로그인해주세요.'));
            } else if (canceled != null && canceled['status'] != 'CANCELED') {
              authError = '탈퇴 취소를 처리하지 못했어요. 다시 시도해주세요.';
            }
          }
        default:
          authError = '소셜 로그인을 확인하지 못했어요. 다시 시도해주세요.';
      }
    } on DioException catch (error) {
      authError = error.response?.statusCode == 429
          ? '로그인 요청이 너무 많아요. 잠시 후 다시 시도해주세요.'
          : '소셜 로그인에 연결하지 못했어요. 다시 시도해주세요.';
    } on Exception {
      authError = '소셜 로그인을 완료하지 못했어요. 다시 시도해주세요.';
    } finally {
      if (mounted) setState(() => authBusy = false);
    }
  }

  @protected
  Future<void> finishPendingLink(
    String email,
    Future<bool> Function() verify,
  ) async {
    final pending = pendingLink;
    if (!mounted ||
        pending == null ||
        email.toLowerCase() != pending.email.toLowerCase()) {
      return;
    }
    pendingLink = null;
    try {
      if (!await verify() || !mounted) return;
      if (!await _confirm(
            '소셜 계정을 연결할까요?',
            '이후 연결한 소셜 계정으로도 로그인할 수 있어요.',
            '연결하기',
          ) ||
          !mounted) {
        return;
      }
      final result = await _social.linkMatchingEmail(pending.token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        statusSnackBar(
          result == 'LINKED'
              ? '소셜 계정을 연결했어요.'
              : '계정을 연결하지 못했어요. 계정 보안에서 다시 시도해주세요.',
          tone: result == 'LINKED' ? StatusTone.notice : StatusTone.error,
        ),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        statusSnackBar('계정 연결을 완료하지 못했어요. 다시 시도해주세요.', tone: StatusTone.error),
      );
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('닫기'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  @protected
  Future<void> openHome([String? email]) async {
    if (!mounted) return;
    final withdrawn = await openAuthenticatedHome(context, api, email: email);
    if (withdrawn == true && mounted) context.go('/');
  }
}

class SocialLoginButtons extends StatelessWidget {
  const SocialLoginButtons({
    required this.providers,
    required this.onPressed,
    this.labelStyle = FinsightTypography.bodyR14,
    this.labelSpacing = 16,
    super.key,
  });

  final List<SocialProvider> providers;
  final ValueChanged<SocialProvider>? onPressed;
  final TextStyle labelStyle;
  final double labelSpacing;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('소셜 아이디로 시작하기', textAlign: TextAlign.center, style: labelStyle),
      SizedBox(height: labelSpacing),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 22,
        runSpacing: 8,
        children: [
          for (final provider in providers)
            IconButton(
              tooltip: '${provider.label}로 로그인',
              padding: EdgeInsets.zero,
              onPressed: onPressed == null ? null : () => onPressed!(provider),
              icon: Opacity(
                opacity: onPressed == null ? 0.48 : 1,
                child: Image.asset(
                  'assets/social/${provider.name}.png',
                  width: 54,
                  height: 54,
                  excludeFromSemantics: true,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

Future<bool?> openAuthenticatedHome(
  BuildContext context,
  AppApi api, {
  String? email,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute(
    builder: (_) => ForegroundActivity(
      api: api,
      child: DiagnosisHome(api: api, email: email),
    ),
  ),
);

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/finsight_wordmark.dart';
import '../design/status_message.dart';
import '../design/tokens.dart';
import '../diagnosis/home_widget_platform.dart';
import 'social_authentication.dart';
import 'social_login.dart';
import 'withdrawal_flow.dart';

export 'social_login.dart' show openAuthenticatedHome;

class AppLogin extends StatefulWidget {
  const AppLogin({this.initialLink, super.key});

  final PendingSocialLink? initialLink;

  @override
  State<AppLogin> createState() => _AppLoginState();
}

class _AppLoginState extends SocialLoginState<AppLogin> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _recheckingCredentials = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLink case final link?) onExistingSocialAccount(link);
  }

  @override
  void onExistingSocialAccount(PendingSocialLink link) {
    _email.text = link.email;
    pendingLink = link;
    authError = '이 이메일로 가입한 계정이 있어요. 기존 방법으로 로그인한 뒤 연결을 확인해주세요.';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (authBusy) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => authError = '이메일과 비밀번호를 입력해주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      authBusy = true;
      authError = null;
    });
    try {
      final email = _email.text.trim();
      final password = _password.text;
      final due = await api.login(email, password);
      unawaited(HomeWidgetPlatform.instance.clear());
      if (!mounted) return;
      _password.clear();
      _recheckingCredentials = false;
      if (due != null) {
        final restored = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => WithdrawalFlow(api: api, email: email, dueAt: due),
          ),
        );
        if (restored == true && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(statusSnackBar('탈퇴 요청을 취소했어요. 다시 로그인해주세요.'));
        }
        return;
      }
      await finishPendingLink(email, () async {
        await api.request<void>(
          'POST',
          '/api/v1/account/reauth',
          data: {'password': password},
        );
        return true;
      });
      await openHome(email);
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      if (status == 400 || status == 401) {
        _recheckingCredentials = true;
        _password.clear();
      } else {
        authError = status == 429
            ? '로그인 요청이 너무 많아요. 잠시 후 다시 시도해주세요.'
            : '연결을 확인하고 다시 시도해주세요.';
      }
    } on Exception {
      if (mounted) authError = '이 기기에 로그인 정보를 저장하지 못했어요. 다시 시도해주세요.';
    } finally {
      if (mounted) setState(() => authBusy = false);
    }
  }

  void _returnToLogin() {
    if (authBusy) return;
    FocusScope.of(context).unfocus();
    _password.clear();
    setState(() {
      _recheckingCredentials = false;
      authError = null;
    });
  }

  void _resetPassword() =>
      context.push('/password-reset/request', extra: _email.text.trim());

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      appBar: AppBar(
        centerTitle: true,
        scrolledUnderElevation: 0,
        leading: _recheckingCredentials
            ? BackButton(onPressed: _returnToLogin)
            : null,
        title: const FinsightWordmark(width: 98),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  IndexedStack(
                    index: _recheckingCredentials ? 1 : 0,
                    alignment: AlignmentDirectional.topStart,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('로그인', style: FinsightTypography.displaySb28),
                          SizedBox(height: 8),
                          StatusMessage.notice('다시 오신 걸 환영해요'),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Image.asset(
                            'assets/illustrations/security-shield.png',
                            width: 32,
                            height: 32,
                            excludeFromSemantics: true,
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            header: true,
                            child: const Text(
                              '로그인 정보를\n확인해주세요',
                              style: FinsightTypography.displaySb28,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const StatusMessage(
                            '이메일 또는 비밀번호가 일치하지 않아요.\n입력한 정보를 다시 확인해주세요.',
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _LoginFieldLabel('이메일'),
                  Semantics(
                    label: '이메일',
                    child: TextField(
                      controller: _email,
                      enabled: !authBusy,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                      autofillHints: const [AutofillHints.email],
                      decoration: _loginFieldDecoration('example@email.com'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _LoginFieldLabel('비밀번호'),
                  Semantics(
                    label: '비밀번호',
                    child: TextField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      enabled: !authBusy,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      decoration: _loginFieldDecoration('••••••••'),
                      onSubmitted: (_) => _login(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  StatusMessage(authError, reservedLines: 3),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: authBusy ? null : _login,
                    child: Text(_recheckingCredentials ? '다시 로그인하기' : '로그인'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      alignment: _recheckingCredentials
                          ? Alignment.center
                          : AlignmentDirectional.centerEnd,
                      backgroundColor: _recheckingCredentials
                          ? FinsightColors.gray900
                          : Colors.transparent,
                      foregroundColor: FinsightColors.gray300,
                    ),
                    onPressed: authBusy ? null : _resetPassword,
                    child: Text(
                      _recheckingCredentials ? '비밀번호 재설정하기' : '비밀번호 재설정',
                    ),
                  ),
                  Visibility(
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    visible: !_recheckingCredentials,
                    child: FutureBuilder(
                      future: socialProviders,
                      builder: (context, snapshot) {
                        final providers =
                            snapshot.data ?? const <SocialProvider>[];
                        if (providers.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: SocialLoginButtons(
                            providers: providers,
                            onPressed: authBusy ? null : loginWithProvider,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: !_recheckingCredentials,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _recheckingCredentials) _returnToLogin();
      },
      child: page,
    );
  }
}

class _LoginFieldLabel extends StatelessWidget {
  const _LoginFieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: FinsightTypography.bodyR14),
    ),
  );
}

InputDecoration _loginFieldDecoration(String hint) {
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
    borderSide: BorderSide(color: FinsightColors.gray800),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: FinsightTypography.bodyR14.copyWith(
      color: FinsightColors.gray500,
    ),
    filled: true,
    fillColor: FinsightColors.gray900,
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: FinsightColors.primary),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
  );
}

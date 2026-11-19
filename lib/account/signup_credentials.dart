import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/status_message.dart';
import '../design/tokens.dart';
import 'signup_layout.dart';
import 'social_login.dart';

class SignupCredentials extends StatefulWidget {
  const SignupCredentials({this.onContinue, super.key});

  final void Function(String email, String password)? onContinue;

  @override
  State<SignupCredentials> createState() => _SignupCredentialsState();
}

class _SignupCredentialsState extends SocialLoginState<SignupCredentials> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final onContinue = widget.onContinue;
    if (onContinue != null && !authBusy && _form.currentState!.validate()) {
      FocusScope.of(context).unfocus();
      onContinue(_email.text.trim(), _password.text);
    }
  }

  @override
  void onExistingSocialAccount(PendingSocialLink link) {
    context.push('/login', extra: link);
  }

  String? _validatePassword(String? value) {
    if (value == null ||
        value.length < 8 ||
        value.length > 64 ||
        !RegExp(r'[a-zA-Z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value) ||
        RegExp(r'\s').hasMatch(value)) {
      return '공백 없이 영문과 숫자를 포함해 8~64자로 입력해주세요.';
    }
    return null;
  }

  InputDecoration _credentialsDecoration(String label, String hint) {
    final decoration = signupInputDecoration(
      label,
      hint: hint,
    ).copyWith(helper: signupValidationSpace);
    if (widget.onContinue != null) return decoration;
    const muted = TextStyle(color: FinsightColors.gray700);
    return decoration.copyWith(
      floatingLabelStyle: muted,
      hintStyle: muted,
      disabledBorder: decoration.enabledBorder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final emailSignupEnabled = widget.onContinue != null;
    final canEnterCredentials = emailSignupEnabled && !authBusy;
    final page = Scaffold(
      appBar: AppBar(title: const Text('로그인/가입'), scrolledUnderElevation: 0),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  minHeight: viewport.maxHeight,
                ),
                child: Form(
                  key: _form,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      8,
                      24,
                      emailSignupEnabled ? 32 : 22,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SignupProgress(1),
                            const SizedBox(height: 44),
                            Text(
                              '가입하기',
                              style: Theme.of(context).textTheme.displaySmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '계정을 만들어주세요',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _email,
                              enabled: canEnterCredentials,
                              decoration: _credentialsDecoration(
                                '이메일',
                                'example@email.com',
                              ),
                              errorBuilder: signupValidationError,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  _passwordFocus.requestFocus(),
                              autocorrect: false,
                              validator: (value) =>
                                  RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(value?.trim() ?? '')
                                  ? null
                                  : '이메일 주소를 확인해주세요.',
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _password,
                              enabled: canEnterCredentials,
                              focusNode: _passwordFocus,
                              decoration: _credentialsDecoration(
                                '비밀번호',
                                '영문, 숫자 포함 8자 이상',
                              ),
                              errorBuilder: signupValidationError,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  _confirmationFocus.requestFocus(),
                              validator: _validatePassword,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              focusNode: _confirmationFocus,
                              enabled: canEnterCredentials,
                              decoration: _credentialsDecoration(
                                '비밀번호 확인',
                                '다시 입력해주세요',
                              ),
                              errorBuilder: signupValidationError,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              onFieldSubmitted: (_) => _submit(),
                              validator: (value) => value == _password.text
                                  ? null
                                  : '비밀번호가 일치하지 않아요.',
                            ),
                            FutureBuilder(
                              future: socialProviders,
                              builder: (context, snapshot) {
                                final providers = snapshot.data;
                                if (providers == null || providers.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return SocialLoginButtons(
                                  providers: providers,
                                  labelStyle: FinsightTypography.labelR12
                                      .copyWith(color: FinsightColors.gray500),
                                  labelSpacing: 30,
                                  onPressed: authBusy
                                      ? null
                                      : loginWithProvider,
                                );
                              },
                            ),
                            if (!emailSignupEnabled) ...[
                              const SizedBox(height: 8),
                              const StatusMessage.notice(
                                '현재 이메일 기능이 테스트 중이에요.\n카카오 혹은 애플로 가입해주세요.',
                              ),
                            ],
                            if (authError case final message?)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: StatusMessage(
                                  message,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            SizedBox(height: emailSignupEnabled ? 28 : 8),
                          ],
                        ),
                        FilledButton(
                          style: emailSignupEnabled
                              ? null
                              : FilledButton.styleFrom(
                                  disabledBackgroundColor:
                                      FinsightColors.gray900,
                                  disabledForegroundColor:
                                      FinsightColors.gray400,
                                ),
                          onPressed: canEnterCredentials ? _submit : null,
                          child: const Text('다음'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return PopScope(canPop: !authBusy, child: page);
  }
}

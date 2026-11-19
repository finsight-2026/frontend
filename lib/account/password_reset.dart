import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/finsight_wordmark.dart';
import '../design/status_message.dart';
import '../design/tokens.dart';
import 'app_api.dart';
import 'signup_layout.dart';

const _endpoint = '/api/v1/auth/password-reset';

class PasswordResetRequest extends StatefulWidget {
  const PasswordResetRequest({this.initialEmail, super.key});

  final String? initialEmail;

  @override
  State<PasswordResetRequest> createState() => _PasswordResetRequestState();
}

class _PasswordResetRequestState extends State<PasswordResetRequest> {
  final _api = AppApi();
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _sent = false;
  bool _busy = false;
  String? _error;
  Timer? _cooldown;

  Future<void> _send() async {
    if (_busy || _cooldown?.isActive == true) return;
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        email.length > 254) {
      setState(() => _error = '이메일 형식을 확인해주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.request<void>(
        'POST',
        '$_endpoint/request',
        data: {'email': email},
      );
      if (!mounted) return;
      _sent = true;
      _cooldown = Timer(const Duration(seconds: 60), () {
        if (mounted) setState(() {});
      });
    } on DioException catch (error) {
      _error = switch (error.response?.statusCode) {
        400 => '이메일 형식을 확인해주세요.',
        429 => '요청이 너무 많아요. 잠시 후 다시 시도해주세요.',
        _ => '연결을 확인하고 다시 시도해주세요.',
      };
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _explainLink() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('메일에서 재설정 링크 열기'),
      content: const Text(
        '가입할 때 사용한 이메일의 받은편지함을 열고, FINSIGHT 메일에 있는 재설정 링크를 눌러주세요.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _cooldown?.cancel();
    _api.close();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResetPage(
    children: [
      _ResetHeading(
        icon: _sent ? Icons.mark_email_read_outlined : null,
        title: _sent ? '이메일을\n확인해주세요.' : '비밀번호를\n재설정할게요',
        description: _sent
            ? '${_email.text.trim().characters.first}***@*** 주소가 가입된 계정이면 재설정 링크를 보내드려요. 메일함에서 링크를 확인해주세요.'
            : '가입할 때 입력한 이메일로 인증 링크를 보내드려요.',
      ),
      if (_sent) ...[
        const SizedBox(height: 68),
        FilledButton(onPressed: _explainLink, child: const Text('새 비밀번호 설정하기')),
        const StatusMessage.notice(
          '메일이 보이지 않으면 스팸함을 확인해주세요. 링크는 15분 동안 사용할 수 있어요.',
        ),
        TextButton(
          onPressed: _busy || _cooldown?.isActive == true ? null : _send,
          child: const Text('재발송'),
        ),
      ] else
        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          decoration: signupInputDecoration(
            '등록 이메일',
            hint: 'example@email.com',
          ),
          onSubmitted: (_) => _send(),
        ),
      StatusMessage(_error, reservedLines: 3),
      if (!_sent)
        FilledButton(
          onPressed: _busy || _cooldown?.isActive == true ? null : _send,
          child: const Text('재설정 메일 보내기'),
        ),
      TextButton(
        onPressed: () => context.go('/login'),
        child: const Text('로그인으로 돌아가기'),
      ),
    ],
  );
}

class PasswordResetComplete extends StatefulWidget {
  const PasswordResetComplete({required this.token, super.key});
  final String? token;

  @override
  State<PasswordResetComplete> createState() => _PasswordResetCompleteState();
}

class _PasswordResetCompleteState extends State<PasswordResetComplete> {
  final _api = AppApi();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _confirmationFocus = FocusNode();
  bool _busy = false;
  bool _expired = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy) return;
    final password = _password.text;
    if (password.runes.length < 8 ||
        password.runes.length > 64 ||
        !RegExp(r'^(?=.*[A-Za-z])(?=.*[0-9])[^\s]+$').hasMatch(password) ||
        password != _confirmation.text) {
      setState(() => _error = '비밀번호 조건과 확인 입력을 확인해주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.request<void>(
        'POST',
        '$_endpoint/complete',
        data: {'token': widget.token, 'password': password},
      );
      if (mounted) context.go('/password-reset/done');
    } on DioException catch (error) {
      _expired = error.response?.statusCode == 410;
      _error = '비밀번호를 변경하지 못했어요. 다시 시도해주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _api.close();
    _password.dispose();
    _confirmation.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(widget.token ?? '');
    return _ResetPage(
      children: [
        const _ResetHeading(
          icon: Icons.key_outlined,
          title: '새 비밀번호를\n설정해주세요.',
          description: '영문과 숫자를 포함해 8자 이상 입력해주세요.',
        ),
        if (valid) ...[
          TextField(
            controller: _password,
            enabled: !_busy && !_expired,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _confirmationFocus.requestFocus(),
            autofillHints: const [AutofillHints.newPassword],
            decoration: signupInputDecoration('새 비밀번호', hint: '새 비밀번호'),
          ),
          TextField(
            controller: _confirmation,
            focusNode: _confirmationFocus,
            enabled: !_busy && !_expired,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            decoration: signupInputDecoration(
              '새 비밀번호 확인',
              hint: '비밀번호를 다시 입력해주세요',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
        StatusMessage(
          _expired || !valid ? '사용할 수 없는 링크예요. 재설정 메일을 다시 요청해주세요.' : _error,
          reservedLines: 3,
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : _expired || !valid
              ? () => context.go('/password-reset/request')
              : _submit,
          child: Text(_expired || !valid ? '재설정 메일 요청' : '비밀번호 변경하기'),
        ),
      ],
    );
  }
}

class PasswordResetDone extends StatelessWidget {
  const PasswordResetDone({super.key});

  static const _background = Color(0xFF0A0A0A);
  static const _assets = 'assets/illustrations/password-reset';

  @override
  Widget build(BuildContext context) {
    void openLogin() => context.go('/login');

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 44,
        leadingWidth: 44,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: openLogin,
          icon: Transform.translate(
            offset: const Offset(0, -4),
            child: Image.asset(
              '$_assets-chevron-left.png',
              width: 24,
              height: 24,
              excludeFromSemantics: true,
            ),
          ),
        ),
        title: Transform.translate(
          offset: const Offset(-9, -4),
          child: Image.asset(
            '$_assets-wordmark.png',
            width: 97.33,
            semanticLabel: 'FINSIGHT',
          ),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 129, 24, 24),
              children: [
                Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Transform.translate(
                      offset: const Offset(-12, 0),
                      child: Image.asset(
                        '$_assets-unlocked.png',
                        width: 124,
                        height: 124,
                        excludeFromSemantics: true,
                      ),
                    ),
                    Positioned(
                      top: 13,
                      right: 8,
                      child: Image.asset(
                        '$_assets-chevron-down.png',
                        width: 16,
                        height: 16,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 41),
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Column(
                    children: [
                      Text(
                        '비밀번호가 재설정되었어요',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: FinsightTypography.family,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          height: 40.6 / 24,
                          letterSpacing: -1.6,
                          color: Color(0xFFF7F7F7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '새로운 비밀번호로 로그인 해 주세요.',
                        textAlign: TextAlign.center,
                        style: FinsightTypography.bodyR14.copyWith(
                          height: 24 / 14,
                          color: FinsightColors.gray400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  style: FilledButton.styleFrom(
                    textStyle: FinsightTypography.bodyM16,
                  ),
                  onPressed: openLogin,
                  child: const Text('로그인하기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResetPage extends StatelessWidget {
  const _ResetPage({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const FinsightWordmark(),
      scrolledUnderElevation: 0,
      leading: BackButton(
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/login');
          }
        },
      ),
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(24),
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ResetHeading extends StatelessWidget {
  const _ResetHeading({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData? icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon case final icon?)
          Icon(icon, color: theme.colorScheme.primary)
        else
          Image.asset(
            'assets/illustrations/security-shield.png',
            width: 32,
            height: 32,
            excludeFromSemantics: true,
          ),
        const SizedBox(height: 12),
        Text(title, style: theme.textTheme.displaySmall),
        const SizedBox(height: 14),
        StatusMessage.notice(description),
      ],
    );
  }
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/finsight_wordmark.dart';
import '../design/status_message.dart';
import '../design/tokens.dart';
import 'app_api.dart';
import 'app_login.dart';
import 'app_session_store.dart';
import '../diagnosis/home_widget_platform.dart';
import 'signup_consent.dart';
import 'signup_layout.dart';

class SignupVerification extends StatefulWidget {
  const SignupVerification({
    required this.email,
    required this.password,
    required this.profile,
    required this.consent,
    required this.onDone,
    required this.onSessionEnded,
    super.key,
  });

  final String email;
  final String password;
  final Map<String, String> profile;
  final SignupConsent consent;
  final VoidCallback onDone;
  final VoidCallback onSessionEnded;

  @override
  State<SignupVerification> createState() => _SignupVerificationState();
}

class _SignupVerificationState extends State<SignupVerification> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final _api = AppApi(sessionStore: appSessionStore);
  final _cancel = CancelToken();
  final _http = Dio(
    BaseOptions(
      baseUrl: apiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );
  DateTime? _expires;
  DateTime? _resend;
  late final Timer _timer;
  bool _busy = false;
  bool _created = false;
  bool _policyChanged = false;
  late var _consent = widget.consent;
  String? _error;

  bool get _valid => _expires?.isAfter(DateTime.now()) ?? false;
  bool get _canSend => !(_resend?.isAfter(DateTime.now()) ?? false);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    _request();
  }

  @override
  void dispose() {
    _api.close();
    _timer.cancel();
    _cancel.cancel();
    _code.dispose();
    _codeFocus.dispose();
    _http.close(force: true);
    super.dispose();
  }

  Widget _codeField(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_code, _codeFocus]),
      builder: (context, _) => Stack(
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                for (var index = 0; index < 6; index++) ...[
                  if (index > 0) const SizedBox(width: 6),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: FinsightColors.gray900,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              _codeFocus.hasFocus && index == _code.text.length
                              ? theme.colorScheme.primary
                              : FinsightColors.gray900,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          index < _code.text.length ? _code.text[index] : ' ',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: Semantics(
              label: '인증번호 6자리',
              child: TextField(
                controller: _code,
                focusNode: _codeFocus,
                enabled: !_busy && _valid,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: const TextStyle(color: Colors.transparent),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
                showCursor: false,
                onSubmitted: (_) => _verify(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final due = await _api.login(widget.email, widget.password);
      if (!mounted) return;
      if (due != null) {
        widget.onDone();
        return;
      }
      unawaited(HomeWidgetPlatform.instance.clear());
      final ended = await openAuthenticatedHome(
        context,
        _api,
        email: widget.email,
      );
      if (mounted && ended == true) widget.onSessionEnded();
    } on Exception {
      if (mounted) _error = '가입은 완료됐어요. 연결을 확인하고 다시 시도하거나 로그인해주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    if (_busy || !_canSend) return;
    final resend = _expires != null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await _http.post<Map<String, dynamic>>(
        '/api/v1/auth/signup/code',
        data: {'email': widget.email},
        cancelToken: _cancel,
      );
      if (!mounted) return;
      final data = response.data!;
      _expires = DateTime.parse(data['expiresAt'] as String);
      _resend = DateTime.parse(data['resendAt'] as String);
      _code.clear();
      if (resend) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_busy && _valid) _codeFocus.requestFocus();
        });
      }
    } on DioException catch (error) {
      if (!mounted) return;
      _error = error.response?.statusCode == 429
          ? '요청이 너무 많아요. 잠시 후 다시 시도해주세요.'
          : '인증번호를 요청하지 못했어요. 연결을 확인해주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || _policyChanged || !_valid || _code.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _http.post<void>(
        '/api/v1/auth/signup/verify',
        data: {
          'email': widget.email,
          'password': widget.password,
          'code': _code.text,
          'profile': widget.profile,
          'terms': true,
          'privacy': true,
          'research': _consent.research,
          'documentVersion': _consent.version,
        },
        cancelToken: _cancel,
      );
      if (!mounted) return;
      _created = true;
      _timer.cancel();
      _code.clear();
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      if (status == 410) {
        _expires = DateTime.now();
        _code.clear();
        _codeFocus.unfocus();
      }
      if (status == 412) _policyChanged = true;
      _error = switch (status) {
        400 => '가입 정보를 확인해주세요.',
        409 => '이미 가입된 이메일이에요.',
        410 => '인증번호를 다시 요청해주세요.',
        412 => '약관이 변경됐어요. 현재 문서를 다시 확인해주세요.',
        422 => '인증번호를 확인해주세요.',
        _ => '가입을 완료하지 못했어요. 연결을 확인해주세요.',
      };
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewPolicies() async {
    final consent = await showSignupConsent(context);
    if (!mounted || consent == null) return;
    setState(() {
      _consent = consent;
      _policyChanged = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (_expires?.difference(DateTime.now()).inSeconds ?? 0).clamp(
      0,
      300,
    );
    final countdown =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final expired = _expires != null && !_valid;
    final resend = TextButton(
      style: expired
          ? TextButton.styleFrom(foregroundColor: FinsightColors.error)
          : null,
      onPressed: !_busy && _canSend ? _request : null,
      child: const Text('인증번호 다시 보내기'),
    );
    return Scaffold(
      appBar: AppBar(
        title: _created
            ? const FinsightWordmark(width: 98)
            : const Text('로그인/가입'),
        centerTitle: true,
        scrolledUnderElevation: 0,
        bottom: _created
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 488),
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                      child: SignupProgress(3),
                    ),
                  ),
                ),
              ),
      ),
      bottomNavigationBar: _created
          ? SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(24, 8, 24, 50),
              child: Align(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : _start,
                        child: const Text('지금 시작하기'),
                      ),
                      if (_error != null)
                        TextButton(
                          onPressed: widget.onDone,
                          child: const Text('로그인으로'),
                        ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(24, _created ? 8 : 0, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_created) ...[
                    SignupCompleteContent(email: widget.email),
                    if (_busy) const LinearProgressIndicator(),
                    StatusMessage(_error),
                  ] else ...[
                    const SizedBox(height: 68),
                    Image.asset(
                      'assets/illustrations/signup-envelope.png',
                      height: 124,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '이메일 인증',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 10),
                    StatusMessage(
                      _valid
                          ? '메일로 보낸 인증 번호를 확인해주세요.'
                          : _expires == null
                          ? '이메일 인증번호를 요청해주세요.'
                          : '인증번호가 만료됐어요.',
                      tone: expired ? StatusTone.warning : StatusTone.notice,
                      textAlign: TextAlign.center,
                      reservedLines: 2,
                    ),
                    const SizedBox(height: 24),
                    _codeField(context),
                    Visibility(
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      visible: _valid,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          countdown,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 4,
                      child: _busy ? const LinearProgressIndicator() : null,
                    ),
                    StatusMessage(_error, reservedLines: 3),
                    const SizedBox(height: 16),
                    ValueListenableBuilder(
                      valueListenable: _code,
                      builder: (context, input, _) => FilledButton(
                        onPressed:
                            !_busy &&
                                !_policyChanged &&
                                _valid &&
                                input.text.length == 6
                            ? _verify
                            : null,
                        child: const Text('인증 완료'),
                      ),
                    ),
                    resend,
                    if (_policyChanged)
                      TextButton(
                        onPressed: _reviewPolicies,
                        child: const Text('약관 다시 확인'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

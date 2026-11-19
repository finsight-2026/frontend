import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../design/status_message.dart';
import '../design/tokens.dart';
import 'app_api.dart';
import 'social_authentication.dart';
import 'social_reauthentication.dart';
import '../diagnosis/home_widget_platform.dart';

const _path = '/api/v1/account';

class WithdrawalFlow extends StatefulWidget {
  const WithdrawalFlow({required this.api, this.email, this.dueAt, super.key});

  final AppApi api;
  final String? email;
  final DateTime? dueAt;

  @override
  State<WithdrawalFlow> createState() => _WithdrawalFlowState();
}

class _WithdrawalFlowState extends State<WithdrawalFlow> {
  final _password = TextEditingController();
  bool _verified = false;
  bool _busy = false;
  DateTime? _receipt;
  String? _error;

  bool get _cancelling => widget.dueAt != null;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _advance({SocialProvider? provider}) async {
    if (_busy) return;
    if (!_verified && provider == null && _password.text.isEmpty) {
      setState(() => _error = '비밀번호를 입력해주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_cancelling) {
        await widget.api.cancelWithdrawal(widget.email!, _password.text);
        if (mounted) Navigator.of(context).pop(true);
      } else if (!_verified) {
        if (provider == null) {
          await widget.api.request<void>(
            'POST',
            '$_path/reauth',
            data: {'password': _password.text},
          );
        } else if (!await verifyWithSocialProvider(widget.api, provider)) {
          return;
        }
        if (!mounted) return;
        _password.clear();
        _verified = true;
      } else {
        final response = await widget.api.request<Map<String, dynamic>>(
          'POST',
          '$_path/withdrawal',
        );
        await widget.api.forgetSession();
        unawaited(HomeWidgetPlatform.instance.clear());
        _receipt = DateTime.parse(response.data!['dueAt'] as String);
      }
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      if (_verified && status == 403) {
        _verified = false;
        _error = '본인 확인 시간이 지났어요. 다시 인증해주세요.';
      } else {
        _error = switch (status) {
          400 ||
          401 => _cancelling ? '비밀번호 또는 탈퇴 취소 기한을 확인해주세요.' : '비밀번호를 확인해주세요.',
          429 => '요청이 너무 많아요. 잠시 후 다시 시도해주세요.',
          _ => '요청을 완료하지 못했어요. 연결을 확인해주세요.',
        };
      }
    } on StateError {
      _error = '연결한 소셜 계정으로 다시 인증해주세요.';
    } on Exception {
      _error = '본인 확인을 완료하지 못했어요. 다시 시도해주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _kst(DateTime value) {
    final time = value.toUtc().add(const Duration(hours: 9)).toIso8601String();
    return '${time.substring(0, 10)} ${time.substring(11, 16)} KST';
  }

  Widget _statusPage({required bool received}) => PopScope(
    canPop: !_busy && !received,
    child: Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              (constraints.maxHeight * .23).clamp(64, 182).toDouble(),
              24,
              24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (received)
                      Image.asset(
                        'assets/illustrations/withdrawal-receipt.png',
                        height: 90,
                        excludeFromSemantics: true,
                      )
                    else
                      SizedBox(
                        height: 90,
                        child: Center(
                          child: Image.asset(
                            'assets/illustrations/withdrawal-trash.png',
                            width: 56,
                            height: 56,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      received ? '탈퇴 요청이 접수됐어요.' : '탈퇴하시겠어요?',
                      textAlign: TextAlign.center,
                      style: FinsightTypography.displaySb22,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      received
                          ? '14일 안에 다시 로그인하시면\n탈퇴를 취소할 수 있어요'
                          : '탈퇴 시 진단 기록과 맞춤 데이터가\n모두 삭제되며 복구할 수 없어요.',
                      textAlign: TextAlign.center,
                      style: FinsightTypography.bodyR14.copyWith(
                        color: FinsightColors.gray400,
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      style: received
                          ? null
                          : FilledButton.styleFrom(
                              backgroundColor: FinsightColors.error,
                              foregroundColor: FinsightColors.black,
                            ),
                      onPressed: _busy
                          ? null
                          : received
                          ? () => Navigator.of(context).pop(true)
                          : _advance,
                      child: Text(received ? '확인' : '탈퇴하기'),
                    ),
                    if (!received) ...[
                      const SizedBox(height: 10),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          backgroundColor: FinsightColors.gray800,
                          foregroundColor: FinsightColors.gray300,
                        ),
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('취소'),
                      ),
                      StatusMessage(_error, reservedLines: 2),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    final due = widget.dueAt;
    if (receipt != null || _verified && !_cancelling) {
      return _statusPage(received: receipt != null);
    }
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !_busy,
          title: Text(_cancelling ? '탈퇴 취소' : '회원탈퇴'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      due != null
                          ? '탈퇴 취소 마감은 ${_kst(due)}예요. 비밀번호를 다시 입력하고 취소를 확인해주세요.'
                          : '탈퇴를 요청하면 모든 기기에서 로그아웃돼요. 14일 동안 취소할 수 있으며, 이후 계정과 데이터가 영구 삭제돼요.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '비밀번호'),
                      onSubmitted: (_) {
                        if (!_cancelling) _advance();
                      },
                    ),
                    StatusMessage(_error, reservedLines: 3),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _advance,
                      child: Text(_cancelling ? '탈퇴 취소 확인' : '본인 확인'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(_cancelling ? '로그인으로 돌아가기' : '취소'),
                    ),
                    if (!_cancelling)
                      SocialReauthOptions(
                        api: widget.api,
                        enabled: !_busy,
                        onPressed: (provider) => _advance(provider: provider),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

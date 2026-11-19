import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../design/status_message.dart';
import '../design/tokens.dart';
import '../diagnosis/home_widget_platform.dart';
import '../shared/request_id.dart';
import 'app_api.dart';
import 'data_export_flow.dart';
import 'social_authentication.dart';
import 'social_reauthentication.dart';

class DataDeletionFlow extends StatefulWidget {
  const DataDeletionFlow({
    required this.api,
    this.bottomNavigationBar,
    super.key,
  });

  final AppApi api;
  final Widget? bottomNavigationBar;

  @override
  State<DataDeletionFlow> createState() => _DataDeletionFlowState();
}

enum _Step {
  introduction,
  reauthentication,
  confirmation,
  pending,
  failed,
  completed,
}

class _DataDeletionFlowState extends State<DataDeletionFlow> {
  final _password = TextEditingController();
  late var _requestId = newRequestId();
  Timer? _pollTimer;
  var _step = _Step.introduction;
  bool _busy = false;
  bool _receiptUncertain = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_resumePending());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _password.dispose();
    super.dispose();
  }

  Future<void> _advance({SocialProvider? provider}) async {
    if (_busy) return;
    if (_step == _Step.introduction) {
      setState(() => _step = _Step.reauthentication);
      return;
    }
    if (_step == _Step.completed) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_step == _Step.reauthentication &&
        provider == null &&
        _password.text.isEmpty) {
      setState(() => _error = '비밀번호를 입력해주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_step == _Step.reauthentication) {
        if (provider == null) {
          await widget.api.request<void>(
            'POST',
            '/api/v1/account/reauth',
            data: {'password': _password.text},
          );
        } else if (!await verifyWithSocialProvider(widget.api, provider)) {
          return;
        }
        if (!mounted) return;
        FocusScope.of(context).unfocus();
        _password.clear();
        _step = _Step.confirmation;
      } else if (_step == _Step.pending || _step == _Step.failed) {
        if (!await _checkReceipt()) {
          _error = '요청 결과를 확인하지 못했어요. 다시 시도해주세요.';
        }
      } else {
        if (_receiptUncertain && await _checkReceipt()) return;
        await _submitDeletion();
      }
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (_step == _Step.confirmation && status == 403) {
        _step = _Step.reauthentication;
        _error = '본인 확인 시간이 지났어요. 다시 인증해주세요.';
      } else {
        _error = switch (status) {
          401 => '세션이 만료됐어요. 다시 로그인해주세요.',
          422 => '비밀번호를 확인해주세요.',
          429 => '요청이 너무 많아요. 잠시 후 다시 시도해주세요.',
          _ => '요청 결과를 확인하지 못했어요. 다시 시도해주세요.',
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

  Future<void> _submitDeletion() async {
    try {
      final response = await widget.api.request<Map<String, dynamic>>(
        'POST',
        '/api/v1/account/data-deletion',
        data: {'requestId': _requestId},
      );
      if (!mounted) return;
      if (await _showReceipt(response.data)) return;
      _receiptUncertain = true;
      _error = '삭제 완료를 확인하지 못했어요. 다시 시도해주세요.';
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (!mounted ||
          (status != null && status < 500) ||
          error.type == DioExceptionType.cancel) {
        rethrow;
      }
      _receiptUncertain = true;
      if (!await _checkReceipt()) rethrow;
    }
  }

  Future<bool> _checkReceipt() async {
    try {
      final response = await widget.api.request<Map<String, dynamic>>(
        'GET',
        '/api/v1/account/data-deletion/$_requestId',
      );
      return await _showReceipt(response.data);
    } on DioException {
      return false;
    }
  }

  Future<void> _resumePending() async {
    try {
      final response = await widget.api.request<Map<String, dynamic>>(
        'GET',
        '/api/v1/account/data-deletion',
      );
      if (mounted && _step == _Step.introduction && !_busy) {
        await _showReceipt(response.data);
      }
    } on DioException {
      // A missing pending request leaves the normal introduction available.
    }
  }

  Future<bool> _showReceipt(Map<String, dynamic>? data) async {
    if (!mounted || data?['requestId'] is! String) return false;
    final receiptId = data!['requestId'] as String;
    final next = switch (data['status']) {
      'PENDING' => _Step.pending,
      'FAILED' => _Step.failed,
      'COMPLETED'
          when receiptId == _requestId && data['completedAt'] is String =>
        _Step.completed,
      _ => null,
    };
    if (next == null) return false;
    if (_step != _Step.pending && _step != _Step.failed) {
      await HomeWidgetPlatform.instance.clear(keepOptions: true);
    }
    if (!mounted) return true;
    setState(() {
      _requestId = receiptId;
      _step = next;
      _error = null;
    });
    _pollTimer?.cancel();
    if (next == _Step.pending) {
      _pollTimer = Timer(const Duration(seconds: 3), _poll);
    }
    return true;
  }

  Future<void> _poll() async {
    if (!mounted || _step != _Step.pending) return;
    if (!_busy) {
      _busy = true;
      final known = await _checkReceipt();
      _busy = false;
      if (known) return;
    }
    if (mounted && _step == _Step.pending) {
      _pollTimer = Timer(const Duration(seconds: 3), _poll);
    }
  }

  @override
  Widget build(BuildContext context) {
    final introduction = _step == _Step.introduction;
    final reauthentication = _step == _Step.reauthentication;
    final confirmation = _step == _Step.confirmation;
    final label = switch (_step) {
      _Step.introduction => '삭제 요청 계속하기',
      _Step.reauthentication => '본인 확인',
      _Step.confirmation => _receiptUncertain ? '다시 확인하기' : '삭제하기',
      _Step.pending || _Step.failed => '처리 상태 확인',
      _Step.completed => '확인',
    };
    final description = switch (_step) {
      _Step.introduction =>
        '진단 기록과 설문 응답을 삭제하면 복구할 수 없어요. 계정, 프로필과 동의 이력은 유지돼요.',
      _Step.reauthentication => '계속하려면 비밀번호를 다시 입력해주세요.',
      _Step.confirmation =>
        '삭제된 데이터는 복구할 수 없어요.\n진단 기록, 설문 응답과 가이드 실천 기록이 모두 삭제됩니다.',
      _Step.pending =>
        '삭제 요청을 접수했어요. 기존 기록은 지금부터 조회할 수 없으며 삭제는 최대 24시간 내에 처리돼요.',
      _Step.failed => '삭제 작업을 확인하고 있어요. 기존 기록은 계속 조회할 수 없어요.',
      _Step.completed => '진단 기록과 설문 응답을 삭제했어요.',
    };
    final accepted =
        _step == _Step.pending ||
        _step == _Step.failed ||
        _step == _Step.completed;
    final navigation = accepted ? null : widget.bottomNavigationBar;
    final primary = FilledButton(
      style: introduction || confirmation
          ? FilledButton.styleFrom(
              backgroundColor: FinsightColors.error,
              foregroundColor: FinsightColors.black,
            )
          : null,
      onPressed: _busy ? null : _advance,
      child: Text(label, textAlign: TextAlign.center),
    );
    final cancel = FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: FinsightColors.gray800,
        foregroundColor: FinsightColors.gray300,
      ),
      onPressed: _busy
          ? null
          : () => Navigator.of(context).pop(accepted ? true : null),
      child: Text(accepted ? '닫기' : '취소'),
    );
    const supporting = TextStyle(color: FinsightColors.gray400);
    return PopScope<bool>(
      canPop: !_busy && !accepted,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && accepted) {
          Navigator.of(context).pop(true);
        }
      },
      child: Scaffold(
        appBar: confirmation
            ? null
            : AppBar(
                title: const Text('데이터 삭제 요청'),
                centerTitle: true,
                scrolledUnderElevation: 0,
              ),
        bottomNavigationBar: introduction || navigation != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (introduction)
                    SafeArea(
                      top: false,
                      bottom: navigation == null,
                      minimum: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                      child: Center(
                        heightFactor: 1,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              primary,
                              const SizedBox(height: 10),
                              cancel,
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (navigation != null)
                    IgnorePointer(ignoring: _busy, child: navigation),
                ],
              )
            : null,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 440,
                    minHeight: confirmation
                        ? (viewport.maxHeight - 48).clamp(0.0, double.infinity)
                        : 0,
                  ),
                  child: Column(
                    mainAxisAlignment: confirmation
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (introduction) ...[
                        const Text(
                          '데이터를 삭제할까요?',
                          style: FinsightTypography.displaySb28,
                        ),
                        const SizedBox(height: 8),
                        const Text('삭제 범위와 처리 방법을 확인해주세요.', style: supporting),
                        const SizedBox(height: 16),
                        Card(
                          margin: EdgeInsets.zero,
                          color: FinsightColors.gray900,
                          shape: RoundedRectangleBorder(
                            side: const BorderSide(
                              color: FinsightColors.gray800,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '삭제 대상',
                                  style: FinsightTypography.bodySb14,
                                ),
                                const SizedBox(height: 8),
                                Text(description, style: supporting),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DataExportFlow(
                                api: widget.api,
                                bottomNavigationBar: navigation,
                              ),
                            ),
                          ),
                          child: const Text('내보내기 먼저 받기'),
                        ),
                      ] else ...[
                        if (confirmation) ...[
                          Center(
                            child: Image.asset(
                              'assets/illustrations/data-deletion-trash.png',
                              width: 56,
                              height: 56,
                              excludeFromSemantics: true,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '정말 삭제하시겠어요?',
                            textAlign: TextAlign.center,
                            style: FinsightTypography.displaySb22,
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          description,
                          style: supporting,
                          textAlign: confirmation ? TextAlign.center : null,
                        ),
                        const SizedBox(height: 20),
                        if (reauthentication) ...[
                          TextField(
                            controller: _password,
                            obscureText: true,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: '비밀번호',
                            ),
                            onSubmitted: (_) => _advance(),
                          ),
                          const SizedBox(height: 12),
                        ],
                        primary,
                        if (reauthentication)
                          SocialReauthOptions(
                            api: widget.api,
                            enabled: !_busy,
                            onPressed: (provider) =>
                                _advance(provider: provider),
                          ),
                        if (_step != _Step.completed) ...[
                          const SizedBox(height: 10),
                          cancel,
                        ],
                        StatusMessage(_error, reservedLines: 3),
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
  }
}

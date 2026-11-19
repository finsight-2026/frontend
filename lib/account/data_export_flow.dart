import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/content_skeleton.dart';
import '../design/status_message.dart';
import '../design/tokens.dart';
import 'app_api.dart';
import 'social_authentication.dart';
import 'social_reauthentication.dart';

const _exportPath = '/api/v1/account/export';

class DataExportFlow extends StatefulWidget {
  const DataExportFlow({
    required this.api,
    this.exportId,
    this.bottomNavigationBar,
    super.key,
  });

  final AppApi api;
  final String? exportId;
  final Widget? bottomNavigationBar;

  @override
  State<DataExportFlow> createState() => _DataExportFlowState();
}

class _DataExportFlowState extends State<DataExportFlow> {
  final _password = TextEditingController();
  Timer? _poll;
  Map<String, dynamic>? _job;
  bool _busy = true;
  bool _initialLoading = true;
  bool _verified = false;
  late String? _target = widget.exportId;
  bool _missingTarget = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(
      _load().whenComplete(() {
        if (mounted) setState(() => _initialLoading = false);
      }),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _password.dispose();
    super.dispose();
  }

  void _accept(Map<String, dynamic>? job) {
    _job = job;
    _poll?.cancel();
    if (job?['status'] == 'PENDING') {
      _poll = Timer(const Duration(seconds: 5), _load);
    }
  }

  Future<void> _load() => _run(() async {
    if (_target case final target?) {
      try {
        final response = await widget.api.request<Map<String, dynamic>>(
          'GET',
          '$_exportPath/$target',
        );
        if (mounted) _accept(response.data);
        return;
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) rethrow;
        _target = null;
        _missingTarget = true;
      }
    }
    try {
      final response = await widget.api.request<Map<String, dynamic>>(
        'GET',
        _exportPath,
      );
      if (mounted) _accept(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      if (mounted) _accept(null);
    }
  });

  Future<void> _verify() async {
    if (_password.text.isEmpty) {
      setState(() => _error = '비밀번호를 입력해주세요.');
      return;
    }
    await _run(() async {
      await widget.api.request<void>(
        'POST',
        '/api/v1/account/reauth',
        data: {'password': _password.text},
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      _password.clear();
      _verified = true;
    });
  }

  Future<void> _request() => _run(() async {
    final response = await widget.api.request<Map<String, dynamic>>(
      'POST',
      _exportPath,
    );
    if (!mounted) return;
    _verified = false;
    _target = null;
    _missingTarget = false;
    _accept(response.data);
  });

  Future<void> _verifySocial(SocialProvider provider) => _run(() async {
    try {
      if (await verifyWithSocialProvider(widget.api, provider) && mounted) {
        _password.clear();
        _verified = true;
      }
    } on Exception {
      _error = '연결한 소셜 계정으로 다시 인증해주세요.';
    } on StateError {
      _error = '연결한 소셜 계정으로 다시 인증해주세요.';
    }
  });

  Future<void> _download() => _run(() async {
    final response = await widget.api.request<Map<String, dynamic>>(
      'POST',
      '$_exportPath/${_job!['id']}/link',
    );
    if (!mounted) return;
    final relative = Uri.parse(response.data!['path'] as String);
    if (relative.hasScheme ||
        relative.hasAuthority ||
        relative.path != '$_exportPath/download/${_job!['id']}') {
      _error = '다운로드 주소를 확인하지 못했어요.';
      return;
    }
    final url = Uri.parse(apiUrl).resolveUri(relative);
    if (!await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    )) {
      _error = '다운로드를 열지 못했어요.';
    }
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      if (status == 403) _verified = false;
      if (status == 404) _accept(null);
      _error = switch (status) {
        401 => '세션이 만료됐어요. 다시 로그인해주세요.',
        403 => '본인 확인을 다시 진행해주세요.',
        404 => '파일이 만료되었거나 삭제됐어요. 다시 요청해주세요.',
        422 => '비밀번호를 확인해주세요.',
        429 => '요청이 너무 많아요. 잠시 후 다시 시도해주세요.',
        _ => '서버에 연결하지 못했어요. 다시 시도해주세요.',
      };
    } on PlatformException {
      if (mounted) _error = '다운로드를 열지 못했어요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _kst(Object? value) {
    final time = DateTime.parse(
      value as String,
    ).toUtc().add(const Duration(hours: 9)).toIso8601String();
    return '${time.substring(0, 10)} ${time.substring(11, 16)} KST';
  }

  @override
  Widget build(BuildContext context) {
    final state = _job?['status'];
    final expires = DateTime.tryParse(_job?['expiresAt'] as String? ?? '');
    final ready =
        state == 'COMPLETED' && (expires?.isAfter(DateTime.now()) ?? false);
    final pending = state == 'PENDING';
    final requested = DateTime.tryParse(_job?['requestedAt'] as String? ?? '');
    final delayed =
        requested != null &&
        DateTime.now().difference(requested).inMinutes >= 10;
    final navigation = widget.bottomNavigationBar;
    final footer = ready || pending || (_verified && !_initialLoading);
    return Scaffold(
      appBar: AppBar(
        title: const Text('데이터 내보내기'),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      bottomNavigationBar: footer || navigation != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (footer)
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
                            if (ready) ...[
                              const StatusMessage.notice('내보내기가 완료되었습니다.'),
                              const SizedBox(height: 12),
                            ],
                            FilledButton(
                              onPressed: _busy || pending
                                  ? null
                                  : ready
                                  ? _download
                                  : _request,
                              child: Text(
                                ready
                                    ? 'ZIP 다운로드'
                                    : pending
                                    ? '데이터를 내보내고 있어요…'
                                    : '내보내기 요청',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ?navigation,
              ],
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'MY DATA',
                    style: TextStyle(
                      color: FinsightColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '내 기록을\n확인할 수 있게',
                    style: FinsightTypography.displaySb28,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '진단 점수와 이전 기록을 한 번에 확인하고 파일로 받을 수 있어요.',
                    style: TextStyle(color: FinsightColors.gray400),
                  ),
                  const SizedBox(height: 24),
                  if (!_initialLoading) ...[
                    const _ExportContents(),
                    const SizedBox(height: 16),
                  ],
                  if (_missingTarget)
                    const StatusMessage(
                      '알림의 파일이 삭제되었거나 보관 기간이 지났어요.',
                      tone: StatusTone.warning,
                    ),
                  if (_initialLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: ContentSkeleton(
                        label: '내보내기 상태 불러오는 중',
                        child: SkeletonRows(count: 2),
                      ),
                    )
                  else if (pending) ...[
                    Text('요청 시각  ${_kst(_job!['requestedAt'])}'),
                    if (delayed)
                      const StatusMessage(
                        '예상보다 오래 걸리고 있어요. 잠시 후 상태를 다시 확인해주세요.',
                        tone: StatusTone.warning,
                      )
                    else
                      const StatusMessage.notice(
                        '파일을 준비하고 있어요. 이 화면을 나가도 계속 처리돼요.',
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              _poll?.cancel();
                              _load();
                            },
                      child: const Text('상태 새로고침'),
                    ),
                  ] else if (ready) ...[
                    Text('파일이 준비됐어요. 보관 기한은 ${_kst(_job!['expiresAt'])}예요.'),
                  ] else ...[
                    if (state == 'FAILED')
                      const StatusMessage('파일을 준비하지 못했어요. 다시 요청해주세요.'),
                    if (state == 'COMPLETED')
                      const StatusMessage(
                        '파일 보관 기한이 지났어요.',
                        tone: StatusTone.warning,
                      ),
                    const SizedBox(height: 16),
                    if (!_verified) ...[
                      TextField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '비밀번호'),
                        onSubmitted: (_) {
                          if (!_busy) _verify();
                        },
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _verify,
                        child: const Text('본인 확인'),
                      ),
                      SocialReauthOptions(
                        api: widget.api,
                        onPressed: _verifySocial,
                        enabled: !_busy,
                      ),
                    ],
                  ],
                  if (_busy && !_initialLoading)
                    const LinearProgressIndicator(),
                  StatusMessage(_error),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExportContents extends StatelessWidget {
  const _ExportContents();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FinsightColors.gray900,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: FinsightColors.gray800),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        children: [
          for (final (index, (label, detail)) in const [
            ('진단 이력', '완료일·점수·유형'),
            ('설문 및 가이드', '문항별 응답·실천 기록'),
            ('파일 형식', 'CSV 2개 · ZIP 압축'),
          ].indexed) ...[
            if (index > 0)
              const Divider(height: 1, color: FinsightColors.gray800),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(label, style: FinsightTypography.bodySb14),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      detail,
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: FinsightColors.gray400),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

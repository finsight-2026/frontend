import 'package:flutter/material.dart';

import '../design/status_message.dart';
import 'app_api.dart';
import 'policy_documents.dart';
import 'social_authentication.dart';
import 'social_reauthentication.dart';

class SocialConnections extends StatefulWidget {
  const SocialConnections({
    required this.api,
    required this.available,
    required this.identity,
    super.key,
  });

  final AppApi api;
  final List<SocialProvider> available;
  final Map<String, dynamic> identity;

  @override
  State<SocialConnections> createState() => _SocialConnectionsState();
}

class _SocialConnectionsState extends State<SocialConnections> {
  late final _social = SocialAuthentication(widget.api);
  late Map<String, dynamic> _identity = widget.identity;
  bool _busy = false;
  String? _message;

  List<dynamic> get _connected =>
      _identity['socialProviders'] as List<dynamic>? ?? [];

  var _messageTone = StatusTone.error;

  Future<void> _change(SocialProvider provider, bool linked) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _messageTone = StatusTone.error;
    });
    try {
      final verified = await showDialog<bool>(
        context: context,
        builder: (_) => _ConnectionVerification(
          api: widget.api,
          passwordEnabled: _identity['passwordEnabled'] != false,
        ),
      );
      if (verified != true || !mounted) return;
      final action = linked ? '연결 해제' : '연결';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('${provider.label} 계정 $action'),
          content: Text(
            linked
                ? '연결을 해제하면 이 소셜 계정으로 로그인할 수 없어요.'
                : '선택한 소셜 계정을 인증하고 로그인에 사용할 수 있도록 연결해요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(action),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final status = linked
          ? await _social.unlink(provider)
          : (await _social.authenticate(
              provider,
              SocialPurpose.link,
            ))?['status'];
      if (status == null || status == 'CANCELED') return;
      if (status == 'LINKED' || status == 'UNLINKED') {
        final updated = await widget.api.request<Map<String, dynamic>>(
          'GET',
          '/api/v1/account/settings',
        );
        _identity = updated.data!;
        _messageTone = StatusTone.notice;
      }
      _message = switch (status) {
        'LINKED' => '소셜 계정을 연결했어요.',
        'UNLINKED' => '소셜 계정 연결을 해제했어요.',
        'LAST_CREDENTIAL' => '로그인 방법을 하나 이상 유지해야 해요.',
        'IDENTITY_IN_USE' => '이미 연결된 소셜 계정이에요.',
        'REAUTH_REQUIRED' => '본인 확인 시간이 지났어요. 다시 인증해주세요.',
        _ => '소셜 계정 변경을 완료하지 못했어요.',
      };
    } on Exception {
      _message = '소셜 계정 변경을 완료하지 못했어요. 다시 시도해주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AccountInfoPage(
    title: '소셜 계정 관리',
    centerTitle: true,
    contentPadding: const EdgeInsets.all(24),
    children: [
      const Text('연결한 소셜 계정으로도 핀사이트에 로그인할 수 있어요.'),
      const SizedBox(height: 16),
      for (final provider in SocialProvider.values)
        if (widget.available.contains(provider) ||
            _connected.contains(provider.id))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(provider.label),
            subtitle: Text(_connected.contains(provider.id) ? '연결됨' : '연결 가능'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy
                ? null
                : () => _change(provider, _connected.contains(provider.id)),
          ),
      if (_busy) const LinearProgressIndicator(),
      StatusMessage(_message, tone: _messageTone),
    ],
  );
}

class _ConnectionVerification extends StatefulWidget {
  const _ConnectionVerification({
    required this.api,
    required this.passwordEnabled,
  });

  final AppApi api;
  final bool passwordEnabled;

  @override
  State<_ConnectionVerification> createState() =>
      _ConnectionVerificationState();
}

class _ConnectionVerificationState extends State<_ConnectionVerification> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _verify({SocialProvider? provider}) async {
    if (_busy) return;
    if (provider == null && _password.text.isEmpty) {
      setState(() => _error = '비밀번호를 입력해주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (provider == null) {
        await widget.api.request<void>(
          'POST',
          '/api/v1/account/reauth',
          data: {'password': _password.text},
        );
      } else if (!await verifyWithSocialProvider(widget.api, provider)) {
        return;
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      _error = '현재 계정의 로그인 방법으로 다시 인증해주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('본인 확인'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.passwordEnabled) ...[
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: '비밀번호'),
            onSubmitted: (_) => _verify(),
          ),
          FilledButton(
            onPressed: _busy ? null : _verify,
            child: const Text('비밀번호 확인'),
          ),
        ],
        SocialReauthOptions(
          api: widget.api,
          onPressed: (provider) => _verify(provider: provider),
          enabled: !_busy,
        ),
        StatusMessage(_error, reservedLines: 3),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('취소'),
      ),
    ],
  );
}

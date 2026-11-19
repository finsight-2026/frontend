import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/content_skeleton.dart';
import '../design/finsight_wordmark.dart';
import '../design/status_message.dart';
import '../design/tokens.dart';
import '../notification/app_notifications.dart';
import '../diagnosis/home_widget_platform.dart';
import 'account_information.dart';
import 'app_api.dart';
import 'data_deletion_flow.dart';
import 'data_export_flow.dart';
import 'policy_documents.dart';
import 'signup_profile.dart';
import 'social_authentication.dart';
import 'social_connections.dart';
import 'withdrawal_flow.dart';

const _settings = '/api/v1/account/settings';

class AccountSettings extends StatefulWidget {
  const AccountSettings({
    required this.api,
    this.onDataDeleted,
    this.securityNavigationBar,
    this.notification,
    this.embedded = false,
    super.key,
  });
  final AppApi api;
  final VoidCallback? onDataDeleted;
  final WidgetBuilder? securityNavigationBar;
  final Widget? notification;
  final bool embedded;

  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  late var _identity = _load();
  bool _loggingOut = false;

  Future<Response<Map<String, dynamic>>> _load() =>
      widget.api.request<Map<String, dynamic>>('GET', _settings);

  Future<void> _logout() async {
    if (_loggingOut) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: FinsightColors.sheetSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: const Text(
                  '로그아웃할까요?',
                  textAlign: TextAlign.center,
                  style: FinsightTypography.displaySb22,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '다시 로그인하면 기록을 확인할 수 있어요.',
                textAlign: TextAlign.center,
                style: FinsightTypography.bodyR14.copyWith(
                  color: FinsightColors.gray400,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.pop(sheet, true),
                child: const Text('로그아웃 하기'),
              ),
              const SizedBox(height: 12),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: FinsightColors.gray400,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => Navigator.pop(sheet),
                child: const Text('취소'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || confirmed != true || _loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await widget.api.logout();
      unawaited(HomeWidgetPlatform.instance.clear());
      if (mounted) Navigator.pop(context, true);
    } on Exception {
      if (!mounted) return;
      setState(() => _loggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        statusSnackBar('로그아웃을 완료하지 못했어요. 다시 시도해주세요.', tone: StatusTone.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AccountInfoPage(
    title: '마이페이지',
    titleWidget: widget.embedded ? const FinsightWordmark(width: 98) : null,
    centerTitle: widget.embedded ? false : null,
    actions: widget.notification == null ? null : [widget.notification!],
    automaticallyImplyLeading: !widget.embedded,
    children: [
      FutureBuilder(
        future: _identity,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ContentSkeleton(
              label: '계정 정보 불러오는 중',
              child: SkeletonRows(showLeading: true),
            );
          }
          if (snapshot.hasError) {
            return TextButton(
              onPressed: () => setState(() {
                _identity = _load();
              }),
              child: const Text('계정 정보를 다시 불러오기'),
            );
          }
          final identity = snapshot.data!.data!;
          final email = identity['email'] as String;
          final separator = email.lastIndexOf('@');
          final masked = separator > 0
              ? '${email.characters.first}***${email.substring(separator)}'
              : '***';
          final profile = Map<String, String>.from(identity['profile'] as Map);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: FinsightColors.gray900,
                  foregroundColor: FinsightColors.gray400,
                  child: Icon(Icons.person_outline),
                ),
                title: Text(masked),
                subtitle: Text(profileSummary(profile)),
              ),
              ListTile(
                title: const Text('내 정보 수정'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (editor) => SignupProfile(
                        initialProfile: profile,
                        email: email,
                        bottomNavigationBar: widget.securityNavigationBar?.call(
                          editor,
                        ),
                        onContinue: (values) async {
                          await widget.api.request<void>(
                            'PUT',
                            '$_settings/profile',
                            data: values,
                          );
                          if (editor.mounted) Navigator.pop(editor, true);
                        },
                      ),
                    ),
                  );
                  if (saved == true && context.mounted) {
                    setState(() {
                      _identity = _load();
                    });
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(statusSnackBar('기본 정보를 저장했어요.'));
                  }
                },
              ),
              ListTile(
                title: const Text('계정 보안'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final withdrawn = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (security) => _Security(
                        api: widget.api,
                        identity: identity,
                        bottomNavigationBar: widget.securityNavigationBar?.call(
                          security,
                        ),
                      ),
                    ),
                  );
                  if (withdrawn == true && context.mounted) {
                    Navigator.pop(context, true);
                  }
                },
              ),
            ],
          );
        },
      ),
      ListTile(
        title: const Text('개인정보 · 동의 관리'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (consent) => _ConsentSettings(
              api: widget.api,
              bottomNavigationBar: widget.securityNavigationBar?.call(consent),
            ),
          ),
        ),
      ),
      ListTile(
        title: const Text('알림 설정'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _push(context, NotificationPreferences(api: widget.api)),
      ),
      ListTile(
        title: const Text('데이터 삭제'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final deleted = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (deletion) => DataDeletionFlow(
                api: widget.api,
                bottomNavigationBar: widget.securityNavigationBar?.call(
                  deletion,
                ),
              ),
            ),
          );
          if (deleted == true && context.mounted) {
            if (widget.onDataDeleted case final returnHome?) {
              returnHome();
            } else {
              Navigator.pop(context);
            }
          }
        },
      ),
      ListTile(
        title: const Text('이용약관'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _push(
          context,
          PolicyList(
            api: widget.api,
            navigationBar: widget.securityNavigationBar,
          ),
        ),
      ),
      ListTile(
        title: const Text('도움말 · 자주 묻는 질문'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _push(
          context,
          AccountHelp(
            navigationBar: widget.securityNavigationBar,
            openNotifications: () {
              Navigator.pop(context);
              _push(context, NotificationPreferences(api: widget.api));
            },
            openDataManagement: () => Navigator.pop(context),
          ),
        ),
      ),
      ListTile(
        title: const Text('서비스 정보'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _push(
          context,
          ServiceInformation(
            api: widget.api,
            navigationBar: widget.securityNavigationBar,
          ),
        ),
      ),
      TextButton(
        onPressed: _loggingOut ? null : _logout,
        child: const Text('로그아웃'),
      ),
    ],
  );
}

class _Security extends StatefulWidget {
  const _Security({
    required this.api,
    required this.identity,
    this.bottomNavigationBar,
  });
  final AppApi api;
  final Map<String, dynamic> identity;
  final Widget? bottomNavigationBar;

  @override
  State<_Security> createState() => _SecurityState();
}

class _SecurityState extends State<_Security> {
  AppApi get api => widget.api;
  Map<String, dynamic> get identity => widget.identity;
  late final _socialProviders = SocialAuthentication(api).providers();

  @override
  Widget build(BuildContext context) => AccountInfoPage(
    title: '계정 보안',
    bottomNavigationBar: widget.bottomNavigationBar,
    contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    scrolledUnderElevation: 0,
    children: [
      const SizedBox(height: 12),
      const Text('로그인 정보를\n안전하게 관리해요', style: FinsightTypography.displaySb28),
      const SizedBox(height: 8),
      Text('가입 계정과 인증 상태를 확인할 수 있어요.', style: _supportingStyle),
      const SizedBox(height: 12),
      Card(
        margin: EdgeInsets.zero,
        color: FinsightColors.gray900,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              _securityDetail('이메일', identity['email'] as String),
              const Divider(color: FinsightColors.gray750, height: 1),
              _securityDetail(
                '인증 상태',
                identity['emailVerified'] == true ? '인증 완료' : '인증 이력 없음',
                highlighted: identity['emailVerified'] == true,
              ),
              const Divider(color: FinsightColors.gray750, height: 1),
              _securityDetail(
                '최근 로그인',
                _formatKst(identity['lastLoginAt'] as String?),
              ),
            ],
          ),
        ),
      ),
      if (identity['passwordEnabled'] != false)
        _securityAction(
          '비밀번호 변경',
          '재설정 메일로 비밀번호를 변경합니다.',
          onTap: () => context.push(
            '/password-reset/request',
            extra: identity['email'] as String,
          ),
        ),
      FutureBuilder(
        future: _socialProviders,
        builder: (context, snapshot) {
          final available = snapshot.data ?? const <SocialProvider>[];
          final connected = identity['socialProviders'] as List<dynamic>? ?? [];
          if (available.isEmpty && connected.isEmpty) {
            return const SizedBox.shrink();
          }
          return _securityAction(
            '소셜 계정 관리',
            '로그인에 사용할 소셜 계정을 연결하거나 해제합니다.',
            onTap: () => _push(
              context,
              SocialConnections(
                api: api,
                available: available,
                identity: identity,
              ),
            ),
          );
        },
      ),
      _securityAction(
        '개인정보 및 연구 동의',
        '선택 동의 항목을 확인합니다.',
        onTap: () => _push(context, _ConsentSettings(api: api)),
      ),
      _securityAction(
        '데이터 내보내기',
        '저장된 기록의 내보내기 절차를 확인합니다.',
        onTap: () => _push(
          context,
          DataExportFlow(
            api: api,
            bottomNavigationBar: widget.bottomNavigationBar,
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Divider(color: FinsightColors.gray750),
      const SizedBox(height: 12),
      const Text(
        '계정 탈퇴',
        style: TextStyle(
          color: FinsightColors.red300,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '진단 기록 및 서비스 이용정보 처리 안내를 확인한 뒤 탈퇴를 요청할 수 있어요. 데이터 삭제와 계정 탈퇴는 별개입니다.',
        style: _supportingStyle,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          style: TextButton.styleFrom(foregroundColor: FinsightColors.red300),
          onPressed: () async {
            final withdrawn = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => WithdrawalFlow(api: api)),
            );
            if (withdrawn == true && context.mounted) {
              Navigator.pop(context, true);
            }
          },
          child: const Text('회원 탈퇴 요청 →'),
        ),
      ),
    ],
  );

  static final _supportingStyle = FinsightTypography.bodyR14.copyWith(
    color: FinsightColors.gray500,
  );

  Widget _securityDetail(
    String label,
    String value, {
    bool highlighted = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: FinsightTypography.bodySb14)),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: _supportingStyle.copyWith(
              color: highlighted ? FinsightColors.neonLime500 : null,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _securityAction(
    String title,
    String detail, {
    required VoidCallback onTap,
  }) => Card(
    margin: const EdgeInsets.only(top: 8),
    color: FinsightColors.gray900,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      title: Text(title, style: FinsightTypography.bodySb14),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(detail, style: _supportingStyle),
      ),
      trailing: const Icon(Icons.chevron_right, color: FinsightColors.gray500),
      onTap: onTap,
    ),
  );
}

class _ConsentSettings extends StatefulWidget {
  const _ConsentSettings({required this.api, this.bottomNavigationBar});
  final AppApi api;
  final Widget? bottomNavigationBar;

  @override
  State<_ConsentSettings> createState() => _ConsentSettingsState();
}

class _ConsentSettingsState extends State<_ConsentSettings> {
  late var _history = _load();
  late var _catalog = PolicyCatalog.load(widget.api);
  bool _saving = false;
  String? _error;

  Future<Response<List<dynamic>>> _load() =>
      widget.api.request<List<dynamic>>('GET', '$_settings/consents');

  Future<void> _update(bool granted, String? version) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.request<void>(
        'PUT',
        '$_settings/consents/research',
        data: {'granted': granted, 'version': version},
      );
      if (mounted) _history = _load();
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 412) {
        _catalog = PolicyCatalog.load(widget.api);
        _error = '연구 안내가 변경됐어요. 현재 문서를 다시 확인해주세요.';
      } else {
        _error = '동의 설정을 저장하지 못했어요. 다시 시도해주세요.';
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPrivacy() async {
    try {
      final document = (await _catalog).active(PolicyId.privacyPolicy);
      if (!mounted) return;
      if (document != null) {
        await openPolicyDocument(context, widget.api, document);
        return;
      }
    } on DioException {
      // The policy list has its own retry for a failed catalog request.
    }
    if (mounted) await _push(context, PolicyList(api: widget.api));
  }

  @override
  Widget build(BuildContext context) => AccountInfoPage(
    title: '개인정보 · 동의 관리',
    bottomNavigationBar: widget.bottomNavigationBar,
    contentPadding: const EdgeInsets.all(24),
    scrolledUnderElevation: 0,
    children: [
      const Text('동의 내역을\n확인하고 관리해요', style: FinsightTypography.displaySb28),
      const SizedBox(height: 10),
      const Text('선택 동의는 서비스 기본 이용과 분리해서 관리합니다.'),
      const SizedBox(height: 16),
      FutureBuilder(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ContentSkeleton(
              label: '동의 내역 불러오는 중',
              child: SkeletonRows(),
            );
          }
          if (snapshot.hasError) {
            return TextButton(
              onPressed: () => setState(() {
                _history = _load();
              }),
              child: const Text('동의 이력을 다시 불러오기'),
            );
          }
          final history = snapshot.data!.data!.cast<Map<String, dynamic>>();
          final latest = history
              .where((item) => item['kind'] == 'RESEARCH')
              .firstOrNull;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                margin: EdgeInsets.zero,
                color: FinsightColors.gray900,
                child: Column(
                  children: [
                    const ListTile(
                      title: Text(
                        '서비스 필수 개인정보',
                        style: FinsightTypography.bodySb14,
                      ),
                      subtitle: Text('서비스 제공과 계정 관리에 필요한 정보'),
                      trailing: Text(
                        '필수',
                        style: TextStyle(color: FinsightColors.primary),
                      ),
                    ),
                    const Divider(height: 1, color: FinsightColors.gray800),
                    FutureBuilder(
                      future: _catalog,
                      builder: (context, snapshot) {
                        final document =
                            snapshot.connectionState == ConnectionState.done
                            ? snapshot.data?.active(PolicyId.research)
                            : null;
                        final activeConsent =
                            latest?['granted'] == true &&
                            document != null &&
                            latest?['version'] == document.version;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (document != null) ...[
                              ListTile(
                                title: Text(document.title),
                                subtitle: Text(document.version),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => openPolicyDocument(
                                  context,
                                  widget.api,
                                  document,
                                ),
                              ),
                              SwitchListTile(
                                title: const Text('연구 활용 동의'),
                                subtitle: const Text(
                                  '선택 동의이며 철회해도 진단을 계속 이용할 수 있어요.',
                                ),
                                value: activeConsent,
                                onChanged: _saving
                                    ? null
                                    : (granted) =>
                                          _update(granted, document.version),
                              ),
                            ],
                            if (latest?['granted'] == true && !activeConsent)
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => _update(
                                        false,
                                        latest?['version'] as String?,
                                      ),
                                child: const Text('이전 연구 동의 철회'),
                              ),
                            if (snapshot.hasError)
                              TextButton(
                                onPressed: () => setState(() {
                                  _catalog = PolicyCatalog.load(widget.api);
                                }),
                                child: const Text('연구 안내 다시 불러오기'),
                              ),
                          ],
                        );
                      },
                    ),
                    const Divider(height: 1, color: FinsightColors.gray800),
                    ListTile(
                      title: const Text(
                        '알림 설정',
                        style: FinsightTypography.bodySb14,
                      ),
                      subtitle: const Text('맞춤 알림과 기기 권한을 관리해요.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _push(
                        context,
                        NotificationPreferences(api: widget.api),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                color: FinsightColors.gray900,
                child: ListTile(
                  title: const Text(
                    '개인정보처리방침 확인',
                    style: FinsightTypography.bodySb14,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openPrivacy,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                color: FinsightColors.gray900,
                child: ListTile(
                  title: const Text(
                    '내 기록 내려받기',
                    style: FinsightTypography.bodySb14,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(
                    context,
                    DataExportFlow(
                      api: widget.api,
                      bottomNavigationBar: widget.bottomNavigationBar,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('동의 이력', style: FinsightTypography.bodySb16),
              StatusMessage(_error, reservedLines: 3),
              const Divider(),
              for (final item in history)
                ListTile(
                  title: Text(switch (item['kind']) {
                    'TERMS' => '이용약관',
                    'PRIVACY' => '개인정보 수집 및 이용',
                    _ => '연구 활용',
                  }),
                  subtitle: Text(
                    '${item['granted'] == true
                        ? '동의'
                        : item['method'] == 'APP_SETTINGS'
                        ? '철회'
                        : '미동의'} · ${item['version']}\n'
                    '${_formatKst(item['recordedAt'] as String?)} · ${item['method'] == 'APP_SETTINGS' ? '마이페이지' : '이메일 가입'}',
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

String _formatKst(String? value) {
  if (value == null) return '이력 없음';
  final kst = DateTime.parse(value).toUtc().add(const Duration(hours: 9));
  return '${kst.toIso8601String().substring(0, 16).replaceFirst('T', ' ')} (한국시간)';
}

Future<void> _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

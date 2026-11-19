import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design/content_skeleton.dart';
import '../design/tokens.dart';
import 'app_api.dart';
import 'signup_layout.dart';

const _root = '/api/v1/policies';
const _previewEnabled = bool.fromEnvironment(
  'FINSIGHT_POLICY_PREVIEW',
  defaultValue: !kReleaseMode,
);

enum PolicyId {
  terms('terms'),
  privacyPolicy('privacy-policy'),
  privacyConsent('privacy-consent'),
  research('research');

  const PolicyId(this.key);
  final String key;
}

class PolicyDocument {
  const PolicyDocument({
    required this.id,
    required this.title,
    required this.version,
    required this.effectiveDate,
    required this.status,
  });

  factory PolicyDocument.fromJson(Map<String, dynamic> json) => PolicyDocument(
    id: PolicyId.values.firstWhere((id) => id.key == json['id']),
    title: json['title'] as String,
    version: json['version'] as String,
    effectiveDate: json['effectiveDate'] as String?,
    status: json['status'] as String,
  );

  final PolicyId id;
  final String title;
  final String version;
  final String? effectiveDate;
  final String status;

  bool get preview => status == 'PREVIEW';

  String get dateLabel => switch ((effectiveDate, status)) {
    (null, _) => '시행일 미정',
    (final date?, 'SCHEDULED') => '$date 시행 예정',
    (final date?, 'HISTORICAL') => '$date 시행 · 이전 버전',
    (final date?, _) => '$date 시행',
  };

  Future<({PolicyDocument document, String body})> loadDetail(
    AppApi api,
  ) async {
    final path = '$_root/${id.key}/${Uri.encodeComponent(version)}';
    final response = await api.request<Map<String, dynamic>>('GET', path);
    final data = response.data!;
    return (
      document: PolicyDocument.fromJson(
        data['document'] as Map<String, dynamic>,
      ),
      body: data['body'] as String,
    );
  }
}

class PolicyCatalog {
  const PolicyCatalog(this.activeVersion, this.documents);

  final String? activeVersion;
  final List<PolicyDocument> documents;

  static Future<PolicyCatalog> load(AppApi api) async {
    final response = await api.request<Map<String, dynamic>>('GET', _root);
    final data = response.data!;
    final activeVersion = data['activeVersion'] as String?;
    final documents = (data['documents'] as List)
        .cast<Map<String, dynamic>>()
        .map(PolicyDocument.fromJson)
        .where((document) => _previewEnabled || !document.preview)
        .toList(growable: false);
    return PolicyCatalog(activeVersion, documents);
  }

  PolicyDocument? active(PolicyId id) => documents
      .where(
        (document) => document.id == id && document.version == activeVersion,
      )
      .firstOrNull;
}

Future<void> openPolicyDocument(
  BuildContext context,
  AppApi api,
  PolicyDocument document, {
  WidgetBuilder? navigationBar,
  bool signup = false,
  bool fromList = false,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => _PolicyDetail(
      api: api,
      document: document,
      navigationBar: navigationBar,
      signup: signup,
      fromList: fromList,
    ),
  ),
);

class PolicyList extends StatefulWidget {
  const PolicyList({required this.api, this.navigationBar, super.key});
  final AppApi api;
  final WidgetBuilder? navigationBar;

  @override
  State<PolicyList> createState() => _PolicyListState();
}

class _PolicyListState extends State<PolicyList> {
  late var _catalog = PolicyCatalog.load(widget.api);
  bool _showPrevious = false;

  @override
  Widget build(BuildContext context) => AccountInfoPage(
    title: '개인정보 · 동의 관리',
    centerTitle: true,
    bottomNavigationBar: widget.navigationBar?.call(context),
    contentPadding: const EdgeInsets.all(24),
    children: [
      const _PolicyHeading('이용약관', '핀사이트 이용에 관한 약관과 정책을 확인할 수 있어요.'),
      const SizedBox(height: 20),
      const Divider(height: 1, color: FinsightColors.gray800),
      FutureBuilder(
        future: _catalog,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ContentSkeleton(
              label: '약관 목록 불러오는 중',
              child: SkeletonRows(showSubtitle: false),
            );
          }
          if (snapshot.hasError) {
            return TextButton(
              onPressed: () => setState(() {
                _catalog = PolicyCatalog.load(widget.api);
              }),
              child: const Text('문서 목록 다시 불러오기'),
            );
          }
          final catalog = snapshot.data!;
          final documents = catalog.documents.where(
            (document) => document.id != PolicyId.privacyConsent,
          );
          if (documents.isEmpty) return const Text('현재 열람할 수 있는 문서가 없어요.');
          final visible = [
            ...documents.where(
              (document) => document.version == catalog.activeVersion,
            ),
            ...documents.where((document) => document.status == 'SCHEDULED'),
            if (_showPrevious)
              ...documents.where((document) => document.status == 'HISTORICAL'),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (documents.any((document) => document.status == 'HISTORICAL'))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('이전 버전 보기'),
                  value: _showPrevious,
                  onChanged: (value) => setState(() => _showPrevious = value),
                ),
              for (final document in visible) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(document.title),
                  subtitle: Text('${document.version} · ${document.dateLabel}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openPolicyDocument(
                    context,
                    widget.api,
                    document,
                    navigationBar: widget.navigationBar,
                    fromList: true,
                  ),
                ),
                const Divider(height: 1, color: FinsightColors.gray800),
              ],
            ],
          );
        },
      ),
    ],
  );
}

class _PolicyDetail extends StatefulWidget {
  const _PolicyDetail({
    required this.api,
    required this.document,
    required this.navigationBar,
    required this.signup,
    required this.fromList,
  });
  final AppApi api;
  final PolicyDocument document;
  final WidgetBuilder? navigationBar;
  final bool signup;
  final bool fromList;

  @override
  State<_PolicyDetail> createState() => _PolicyDetailState();
}

class _PolicyDetailState extends State<_PolicyDetail> {
  late var _detail = widget.document.loadDetail(widget.api);

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    return AccountInfoPage(
      title: widget.signup ? '로그인/가입' : document.title,
      centerTitle: true,
      contentPadding: const EdgeInsets.all(24),
      bottomNavigationBar: widget.navigationBar?.call(context),
      footer: FilledButton(
        onPressed: () => Navigator.pop(context),
        child: Text(
          widget.signup
              ? '확인했어요'
              : widget.fromList
              ? '약관 목록으로'
              : '돌아가기',
        ),
      ),
      children: [
        if (widget.signup) ...[
          const SignupProgress(2),
          const SizedBox(height: 28),
        ],
        _PolicyHeading(
          document.title,
          widget.signup ? '가입하기 전에 문서 내용을 확인해주세요.' : '핀사이트의 문서 내용을 확인할 수 있어요.',
        ),
        const SizedBox(height: 20),
        FutureBuilder(
          future: _detail,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const ContentSkeleton(
                label: '약관 본문 불러오는 중',
                child: SkeletonRows(count: 3),
              );
            }
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('문서를 불러오지 못했어요.'),
                  TextButton(
                    onPressed: () => setState(() {
                      _detail = document.loadDetail(widget.api);
                    }),
                    child: const Text('다시 시도'),
                  ),
                ],
              );
            }
            final (document: updated, :body) = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${updated.version} · ${updated.dateLabel}'),
                if (updated.preview) const Text('로컬 개발용 미리보기'),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: FinsightColors.gray900,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(body),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PolicyHeading extends StatelessWidget {
  const _PolicyHeading(this.title, this.description);
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: FinsightTypography.displaySb28),
      const SizedBox(height: 8),
      Text(description, style: const TextStyle(color: FinsightColors.gray400)),
    ],
  );
}

class AccountInfoPage extends StatelessWidget {
  const AccountInfoPage({
    required this.title,
    required this.children,
    this.automaticallyImplyLeading = true,
    this.bottomNavigationBar,
    this.contentPadding = const EdgeInsets.all(16),
    this.scrolledUnderElevation,
    this.centerTitle,
    this.titleWidget,
    this.footer,
    this.actions,
    super.key,
  });
  final String title;
  final List<Widget> children;
  final bool automaticallyImplyLeading;
  final Widget? bottomNavigationBar;
  final EdgeInsetsGeometry contentPadding;
  final double? scrolledUnderElevation;
  final bool? centerTitle;
  final Widget? titleWidget;
  final Widget? footer;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: bottomNavigationBar,
    appBar: AppBar(
      title: titleWidget ?? Text(title),
      centerTitle: centerTitle,
      actions: actions,
      automaticallyImplyLeading: automaticallyImplyLeading,
      scrolledUnderElevation: scrolledUnderElevation,
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(padding: contentPadding, children: children),
              ),
              if (footer case final action?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: action,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

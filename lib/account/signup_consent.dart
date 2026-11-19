import 'package:flutter/material.dart';

import '../design/content_skeleton.dart';
import '../design/finsight_checkbox_tile.dart';
import '../design/tokens.dart';
import 'app_api.dart';
import 'policy_documents.dart';

typedef SignupConsent = ({String version, bool research});

Future<SignupConsent?> showSignupConsent(
  BuildContext context, {
  AppApi? api,
}) async {
  final connection = api ?? AppApi();
  try {
    return await showModalBottomSheet<SignupConsent>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _SignupConsentSheet(api: connection),
    );
  } finally {
    if (api == null) connection.close();
  }
}

class _SignupConsentSheet extends StatefulWidget {
  const _SignupConsentSheet({required this.api});
  final AppApi api;

  @override
  State<_SignupConsentSheet> createState() => _SignupConsentSheetState();
}

class _SignupConsentSheetState extends State<_SignupConsentSheet> {
  bool _terms = false;
  bool _privacy = false;
  bool _research = false;
  late var _catalog = PolicyCatalog.load(widget.api);

  Widget _agreement(
    PolicyDocument? document,
    String label,
    bool checked,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 52),
      child: Row(
        children: [
          Expanded(
            child: FinsightCheckboxTile(
              label: label,
              value: checked,
              onChanged: document == null ? null : onChanged,
              labelStyle: FinsightTypography.bodyR14,
            ),
          ),
          IconButton(
            tooltip: '$label 자세히 보기',
            alignment: AlignmentDirectional.centerEnd,
            padding: EdgeInsets.zero,
            color: FinsightColors.gray600,
            onPressed: document == null
                ? null
                : () => openPolicyDocument(
                    context,
                    widget.api,
                    document,
                    signup: true,
                  ),
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _catalog,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: ContentSkeleton(
            label: '가입 동의 항목 불러오는 중',
            child: SkeletonRows(showLeading: true, showSubtitle: false),
          ),
        );
      }
      if (snapshot.hasError) {
        return SafeArea(
          child: TextButton(
            onPressed: () => setState(() {
              _catalog = PolicyCatalog.load(widget.api);
            }),
            child: const Text('가입 약관 다시 불러오기'),
          ),
        );
      }
      return _agreements(snapshot.data!);
    },
  );

  Widget _agreements(PolicyCatalog catalog) {
    final terms = catalog.active(PolicyId.terms);
    final privacyPolicy = catalog.active(PolicyId.privacyPolicy);
    final privacy = catalog.active(PolicyId.privacyConsent);
    final research = catalog.active(PolicyId.research);
    final version = catalog.activeVersion;
    final available =
        terms != null &&
        privacyPolicy != null &&
        privacy != null &&
        research != null;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'FINSIGHT 이용시 동의가 필요합니다.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (!available || terms.preview)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Text(
                  available
                      ? '로컬 개발용 문안으로 가입과 동의 절차를 확인할 수 있어요.'
                      : '현재 가입에 필요한 문서를 열람할 수 없어요.',
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FinsightCheckboxTile(
                    label: '모두 동의',
                    value: _terms && _privacy && _research,
                    onChanged: !available
                        ? null
                        : (checked) => setState(() {
                            _terms = checked;
                            _privacy = checked;
                            _research = checked;
                          }),
                  ),
                  Text(
                    '아래 필수 및 선택 항목에 모두 동의합니다.',
                    style: FinsightTypography.labelR12.copyWith(
                      color: FinsightColors.gray600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _agreement(
              terms,
              '(필수) 이용약관',
              _terms,
              (value) => setState(() => _terms = value),
            ),
            _agreement(
              privacy,
              '(필수) 개인정보 수집 및 이용',
              _privacy,
              (value) => setState(() => _privacy = value),
            ),
            _agreement(
              research,
              '(선택) 연구데이터 활용 동의',
              _research,
              (value) => setState(() => _research = value),
            ),
            if (privacyPolicy != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => openPolicyDocument(
                    context,
                    widget.api,
                    privacyPolicy,
                    signup: true,
                  ),
                  child: const Text('개인정보 처리방침'),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: available && version != null && _terms && _privacy
                  ? () => Navigator.of(
                      context,
                    ).pop((version: version, research: _research))
                  : null,
              child: const Text('동의하고 계속'),
            ),
          ],
        ),
      ),
    );
  }
}

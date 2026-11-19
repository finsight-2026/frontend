import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../design/finsight_wordmark.dart';
import '../design/status_message.dart';
import '../design/tokens.dart';
import 'app_api.dart';
import 'policy_documents.dart';

const _supportEmail = 'emfpdlzj@gmail.com';

class AccountHelp extends StatelessWidget {
  const AccountHelp({
    required this.openNotifications,
    required this.openDataManagement,
    this.navigationBar,
    super.key,
  });

  final VoidCallback openNotifications;
  final VoidCallback openDataManagement;
  final WidgetBuilder? navigationBar;

  @override
  Widget build(BuildContext context) => AccountInfoPage(
    title: '도움말 · 자주 묻는 질문',
    centerTitle: true,
    contentPadding: const EdgeInsets.all(24),
    bottomNavigationBar: navigationBar?.call(context),
    children: [
      const Text('무엇을 도와드릴까요?', style: FinsightTypography.displaySb28),
      const SizedBox(height: 8),
      const Text(
        '핀사이트 이용 중 궁금한 내용을 확인해보세요.',
        style: TextStyle(color: FinsightColors.gray400),
      ),
      const SizedBox(height: 20),
      const _Question(
        'YFSI 점수는 무엇을 뜻하나요?',
        '점수가 높을수록 설문에서 나타난 금융 스트레스 부담이 큽니다. 본인의 응답을 바탕으로 한 자기 점검 결과이며 의료 진단이나 신용 등급이 아닙니다.',
        summary: '내 금융 스트레스 수준을 이해하는 지표예요.',
      ),
      const _Question(
        '또래 평균은 왜 보이지 않나요?',
        '같은 대표 유형의 익명 집계가 최소 표본과 공개 조건을 충족해 승인된 경우에만 비교가 표시됩니다. 비교 데이터가 없으면 내 점수의 높고 낮음을 뜻하지 않습니다.',
        summary: '개인정보 보호 기준에 따라 공개 범위가 달라져요.',
      ),
      const _Question(
        '위젯에서 점수를 숨길 수 있나요?',
        '기록 탭에서 ‘위젯 추가하기’를 열고 ‘점수 표시’를 끄면 돼요. 점수는 기본으로 숨겨져 있어요.',
        summary: '위젯 설정에서 점수 표시를 바꿀 수 있어요.',
      ),
      _Question(
        '진단 데이터를 내보내거나 삭제할 수 있나요?',
        '계정 보안에서 내보내기를 요청하고, 마이페이지의 데이터 삭제에서 진단과 관련 기록을 삭제할 수 있어요.',
        summary: '마이페이지에서 진단 데이터를 관리할 수 있어요.',
        action: TextButton(
          onPressed: openDataManagement,
          child: const Text('마이페이지로 이동'),
        ),
      ),
      const _Question(
        '대표 유형은 어떻게 정하나요?',
        '부채, 소득, 비상자금, 고정비, 미래, 부양의 여섯 부담 영역 중 가장 높은 영역을 대표 유형으로 보여줍니다.',
      ),
      _Question(
        '알림은 어디서 바꾸나요?',
        '앱의 알림 설정에서 전체 알림과 알림 종류를 관리할 수 있어요.',
        action: TextButton(
          onPressed: openNotifications,
          child: const Text('알림 설정 열기'),
        ),
      ),
      const ListTile(
        title: Text('문의'),
        subtitle: SelectableText(_supportEmail),
      ),
    ],
  );
}

class _Question extends StatelessWidget {
  const _Question(this.question, this.answer, {this.summary, this.action});
  final String question;
  final String answer;
  final String? summary;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    color: FinsightColors.gray900,
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
            ),
      title: Text(question, style: FinsightTypography.bodySb16),
      subtitle: summary == null ? null : Text(summary!),
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(answer), ?action],
    ),
  );
}

class ServiceInformation extends StatefulWidget {
  const ServiceInformation({required this.api, this.navigationBar, super.key});
  final AppApi api;
  final WidgetBuilder? navigationBar;

  @override
  State<ServiceInformation> createState() => _ServiceInformationState();
}

class _ServiceInformationState extends State<ServiceInformation> {
  late var _package = PackageInfo.fromPlatform();
  late var _policies = PolicyCatalog.load(widget.api);

  Future<void> _contact() async {
    try {
      if (await launchUrl(Uri(scheme: 'mailto', path: _supportEmail))) return;
    } on Exception {
      // The address remains selectable if no email application is available.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      statusSnackBar(
        '메일 앱을 열 수 없어요. 화면에 표시된 주소를 사용해주세요.',
        tone: StatusTone.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AccountInfoPage(
    title: '서비스 정보',
    centerTitle: true,
    contentPadding: const EdgeInsets.all(24),
    bottomNavigationBar: widget.navigationBar?.call(context),
    children: [
      const SizedBox(height: 36),
      const Center(child: FinsightWordmark(width: 150)),
      const SizedBox(height: 24),
      const Text(
        '청년의 금융 마음을\n더 가까이 이해해요',
        style: FinsightTypography.displaySb28,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      const Text(
        '핀사이트에서 금융 스트레스를 살펴보고,\n나에게 맞는 정보를 확인할 수 있어요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: FinsightColors.gray400),
      ),
      const SizedBox(height: 16),
      FutureBuilder(
        future: _package,
        builder: (context, snapshot) {
          final package = snapshot.data;
          if (snapshot.hasError ||
              (package != null && package.version.isEmpty)) {
            return ListTile(
              title: const Text('앱 버전을 확인하지 못했어요.'),
              trailing: TextButton(
                onPressed: () => setState(() {
                  _package = PackageInfo.fromPlatform();
                }),
                child: const Text('다시 시도'),
              ),
            );
          }
          if (package == null) return const LinearProgressIndicator();
          final version = package.buildNumber.isEmpty
              ? package.version
              : '${package.version} (${package.buildNumber})';
          return Center(
            child: Chip(
              label: Text('앱 버전 $version'),
              backgroundColor: FinsightColors.gray900,
              side: BorderSide.none,
            ),
          );
        },
      ),
      const SizedBox(height: 24),
      const Divider(height: 1, color: FinsightColors.gray800),
      FutureBuilder(
        future: _policies,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TextButton(
              onPressed: () => setState(() {
                _policies = PolicyCatalog.load(widget.api);
              }),
              child: const Text('약관 링크 다시 불러오기'),
            );
          }
          return Column(
            children: [
              for (final id in [PolicyId.terms, PolicyId.privacyPolicy])
                if (snapshot.data?.active(id) case final document?) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(document.title),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openPolicyDocument(
                      context,
                      widget.api,
                      document,
                      navigationBar: widget.navigationBar,
                    ),
                  ),
                  const Divider(height: 1, color: FinsightColors.gray800),
                ],
            ],
          );
        },
      ),
      const ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('운영주체'),
        subtitle: Text('핀사이트 2026'),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('문의'),
        subtitle: const SelectableText(_supportEmail),
        trailing: IconButton(
          tooltip: '메일 작성',
          onPressed: _contact,
          icon: const Icon(Icons.mail_outline),
        ),
      ),
    ],
  );
}

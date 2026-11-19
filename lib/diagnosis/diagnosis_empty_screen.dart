import 'package:flutter/material.dart';

import '../design/finsight_wordmark.dart';
import '../design/tokens.dart';

class DiagnosisEmptyScreen extends StatelessWidget {
  const DiagnosisEmptyScreen.result({
    required this.onPressed,
    this.notification,
    this.navigationBar,
    this.footer,
    super.key,
  }) : title = '아직 확인할 결과가 없어요',
       message = '첫 자가진단을 완료하면\n점수와 유형, 맞춤 가이드를 볼 수 있어요.',
       illustration = 'diagnosis-empty',
       action = '첫 진단 시작하기',
       filters = null;

  const DiagnosisEmptyScreen.insight({
    required this.onPressed,
    this.notification,
    this.navigationBar,
    this.footer,
    this.filters,
    this.message = '아직 행동 데이터가 충분하지 않아\n다른 사람의 선택을 모으고 있어요.',
    super.key,
  }) : title = '인사이트가 모이는 중이에요',
       illustration = 'insight-empty',
       action = '내 맞춤 가이드 보기';

  final String title;
  final String message;
  final String illustration;
  final String action;
  final VoidCallback onPressed;
  final Widget? notification;
  final Widget? navigationBar;
  final Widget? footer;
  final Widget? filters;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const FinsightWordmark(width: 96),
      centerTitle: false,
      automaticallyImplyLeading: navigationBar == null,
      actions: [?notification],
      scrolledUnderElevation: 0,
    ),
    bottomNavigationBar: navigationBar,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              children: [
                ?filters,
                SizedBox(height: (constraints.maxHeight * 0.23).clamp(24, 180)),
                Image.asset(
                  'assets/illustrations/$illustration.png',
                  height: 148,
                  excludeFromSemantics: true,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: FinsightTypography.displaySb22,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: FinsightTypography.bodyR14.copyWith(
                    color: FinsightColors.gray400,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: onPressed, child: Text(action)),
                ?footer,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

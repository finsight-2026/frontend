import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../account/app_api.dart';
import '../design/content_skeleton.dart';
import '../design/tokens.dart';
import 'diagnosis_badge.dart';
import 'guide_screen.dart';
import 'report_share_card.dart';

class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({
    required this.api,
    required this.badgeName,
    required this.openHistory,
    this.navigationBar,
    super.key,
  });

  final AppApi api;
  final String Function(Object?) badgeName;
  final VoidCallback openHistory;
  final Widget Function(ValueChanged<int>)? navigationBar;

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  static const _areaNames = {
    'DEBT': '부채',
    'INCOME': '소득',
    'EMERGENCY_FUND': '비상자금',
    'FIXED_COST': '고정비',
    'FUTURE': '미래',
    'FAMILY': '가족부양',
    'FINANCIAL_LITERACY': '금융 이해력',
    'MONEY_MANAGEMENT': '재무 관리 역량',
    'SELF_EFFICACY': '금융 자기효능감',
  };
  final _current = DateTime.now().toUtc().add(const Duration(hours: 9));
  late var _month = DateTime.utc(_current.year, _current.month);
  late var _report = _load(_month);

  bool get _isCurrent =>
      _month.year == _current.year && _month.month == _current.month;

  Future<Response<Map<String, dynamic>>> _load(DateTime date) {
    final month = date.toIso8601String().substring(0, 7);
    return widget.api.request<Map<String, dynamic>>(
      'GET',
      '/api/v1/diagnosis/monthly-report?month=$month',
    );
  }

  void _selectMonth(DateTime month) {
    final report = _load(month)..ignore();
    setState(() {
      _month = month;
      _report = report;
    });
  }

  void _move(int delta) =>
      _selectMonth(DateTime.utc(_month.year, _month.month + delta));

  String _closeTime(String value) {
    final local = DateTime.parse(
      value,
    ).toUtc().add(const Duration(hours: 9)).toIso8601String();
    return '${local.substring(0, 10)} ${local.substring(11, 16)} KST';
  }

  int _score(Object? value) {
    final data = value as Map<String, dynamic>;
    final numerator = data['numerator'] as int;
    final denominator = data['denominator'] as int;
    return (2 * numerator + denominator) ~/ (2 * denominator);
  }

  List<Map<String, dynamic>> _rows(Object? value) =>
      (value as List).cast<Map<String, dynamic>>();

  List<Widget> _areas(List<Map<String, dynamic>> rows, String key) => [
    for (final row in rows)
      _ReportRow(
        label: _areaNames[row[key]] ?? row[key].toString(),
        value: '${_score(row['score'])}점',
      ),
  ];

  Future<void> _showCard(
    Map<String, dynamic> report,
    String badge,
    int score,
  ) async {
    final destination = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (cardContext) => ReportShareCard(
          month: report['month'] as String,
          badge: badge,
          score: score,
          scoreChange: report['scoreChange'] as int?,
          navigationBar: widget.navigationBar?.call(
            (tab) => Navigator.of(cardContext).pop(tab),
          ),
        ),
      ),
    );
    if (destination != null && mounted) {
      Navigator.of(context).pop(destination);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('월간 리포트'),
      centerTitle: true,
      scrolledUnderElevation: 0,
    ),
    bottomNavigationBar: widget.navigationBar?.call(
      (tab) => Navigator.of(context).pop(tab),
    ),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_month.year}년 ${_month.month}월',
                        style: FinsightTypography.labelM12.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '이전 달',
                      onPressed: _month.year == 1 && _month.month == 1
                          ? null
                          : () => _move(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      tooltip: '다음 달',
                      onPressed: _isCurrent ? null : () => _move(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                FutureBuilder(
                  future: _report,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const ContentSkeleton(
                        label: '월간 리포트 불러오는 중',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 16),
                            SkeletonBlock(height: 142, radius: 12),
                            SizedBox(height: 20),
                            SkeletonLine(.42, fontSize: 18),
                            SizedBox(height: 12),
                            SkeletonRows(count: 2, showLeading: true),
                          ],
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Column(
                        children: [
                          const Text('리포트를 불러오지 못했어요.'),
                          TextButton(
                            onPressed: () => _selectMonth(_month),
                            child: const Text('다시 시도'),
                          ),
                        ],
                      );
                    }
                    final report = snapshot.data!.data!;
                    return report['available'] == true
                        ? _available(report)
                        : _empty();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.only(top: 64, bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Image.asset(
            'assets/illustrations/monthly-report-empty.png',
            width: 144,
            height: 144,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(height: 48),
        Text(
          _isCurrent ? '아직 이번 달 리포트가 없어요' : '이 달의 리포트가 없어요',
          textAlign: TextAlign.center,
          style: FinsightTypography.displaySb22,
        ),
        const SizedBox(height: 12),
        const Text(
          '진단 기록이 쌓이면 내 금융 마음의 변화를 확인할 수 있어요.',
          textAlign: TextAlign.center,
          style: _muted,
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: widget.openHistory,
          child: const Text('진단 기록 확인'),
        ),
      ],
    ),
  );

  Widget _available(Map<String, dynamic> report) {
    final result = report['result'] as Map<String, dynamic>;
    final latest = _score(result['total']);
    final badge = widget.badgeName(result['representativeType']);
    final change = report['scoreChange'] as int?;
    final pressures = _rows(result['rankedPressures']);
    final resources = _rows(result['resources']);
    final stress = _score(result['perceivedStress']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isCurrent ? '이번 달도,\n수고했어요' : '이 달의 금융 마음 기록',
          style: FinsightTypography.displaySb22,
        ),
        const SizedBox(height: 8),
        const Text('진단과 실천으로 이어온 변화를 확인해보세요.', style: _muted),
        const SizedBox(height: 24),
        _ReportPanel(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('이 달의 금융 스트레스', style: _muted),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  text: '$latest',
                  style: FinsightTypography.displaySb38.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  children: const [TextSpan(text: ' /100', style: _muted)],
                ),
                semanticsLabel: '$latest점, 100점 만점',
              ),
              DiagnosisBadge(result['representativeType'], label: badge),
              if (change != null) ...[
                const SizedBox(height: 8),
                Text('첫 진단 ${report['firstScore']}점 · 마지막 진단 $latest점'),
                Text('변화 ${reportScoreChange(change)}'),
              ],
              if (report['closesAt'] case final String closesAt) ...[
                const SizedBox(height: 10),
                Text(
                  report['provisional'] == true
                      ? '잠정 집계 · ${_closeTime(closesAt)} 마감 예정'
                      : '마감 · ${_closeTime(closesAt)}',
                  style: _muted,
                ),
              ],
            ],
          ),
        ),
        const _ReportHeading('한 달 동안 확인한 변화'),
        _ReportPanel(
          child: Column(
            children: [
              if (pressures.firstOrNull case final strongest?)
                _ReportRow(
                  label: '가장 큰 압박 요인',
                  value:
                      _areaNames[strongest['pressure']] ??
                      strongest['pressure'].toString(),
                ),
              _ReportRow(label: '체감 스트레스', value: '$stress점'),
              ExpansionTile(
                title: const Text('외부 부담'),
                children: _areas(pressures, 'pressure'),
              ),
              ExpansionTile(
                title: const Text('개인 대응역량'),
                children: _areas(resources, 'resource'),
              ),
            ],
          ),
        ),
        const _ReportHeading('이 달의 활동 기록'),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final minimum = MediaQuery.textScalerOf(context).scale(95);
            final columns =
                ((constraints.maxWidth + spacing) / (minimum + spacing))
                    .floor()
                    .clamp(1, 3);
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final activity in [
                  _Activity('완료 진단', '${report['diagnosisCount']}회'),
                  _Activity('가이드 확인', '${report['guideViews']}개'),
                  _Activity('실천 완료', '${report['guideCompletions']}개'),
                ])
                  SizedBox(width: width, child: activity),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _ReportPanel(
          child: ListTile(
            title: const Text('다음 달 추천 행동'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GuideScreen(
                  api: widget.api,
                  badgeName: widget.badgeName,
                  attemptId: report['attemptId'] as String,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _showCard(report, badge, latest),
          child: const Text('공유 카드 확인'),
        ),
      ],
    );
  }
}

const _muted = TextStyle(color: FinsightColors.gray400, fontSize: 14);

class _ReportHeading extends StatelessWidget {
  const _ReportHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(label, style: FinsightTypography.bodySb16),
    ),
  );
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
    borderRadius: BorderRadius.circular(12),
    color: FinsightColors.gray900,
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        Expanded(child: Text(label, style: _muted)),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}

class _Activity extends StatelessWidget {
  const _Activity(this.label, this.count);
  final String label;
  final String count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $count',
    excludeSemantics: true,
    child: _ReportPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            count,
            style: FinsightTypography.titleSb18.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Text(label, style: _muted),
        ],
      ),
    ),
  );
}

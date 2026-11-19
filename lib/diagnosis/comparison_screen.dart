import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../account/app_api.dart';
import '../design/status_message.dart';
import '../design/tokens.dart';
import 'comparison_labels.dart';
import 'diagnosis_empty_screen.dart';
import 'guide_screen.dart';
import 'insight_screen.dart';

class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({
    required this.api,
    this.emptyNavigationBar,
    this.emptyNotification,
    super.key,
  });

  final AppApi api;
  final WidgetBuilder? emptyNavigationBar;
  final Widget Function()? emptyNotification;

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  Map<String, dynamic>? _data;
  bool _loading = false;
  bool _failed = false;
  bool _requested = false;

  Future<void> _load() async {
    setState(() {
      _requested = true;
      _loading = true;
      _failed = false;
      _data = null;
    });
    try {
      final response = await widget.api.request<Map<String, dynamic>>(
        'GET',
        '/api/v1/comparison',
      );
      _data = response.data;
    } on DioException {
      _failed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Widget> _metrics(Map<String, dynamic> metrics) {
    return [
      for (final MapEntry(:key, :value) in metrics.entries)
        if (comparisonMetricLabels.containsKey(key)) ...[
          if (value is num)
            ListTile(
              title: Text(comparisonMetricLabels[key]!),
              trailing: Text('$value점'),
            ),
          if (value is Map<String, dynamic>) ...[
            Text(
              comparisonMetricLabels[key]!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final entry in value.entries)
              if (comparisonMetricLabels.containsKey(entry.key) &&
                  entry.value is num)
                ListTile(
                  title: Text(comparisonMetricLabels[entry.key]!),
                  trailing: Text('${entry.value}점'),
                ),
          ],
        ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data != null && data['available'] != true) {
      return DiagnosisEmptyScreen.insight(
        navigationBar: widget.emptyNavigationBar?.call(context),
        notification: widget.emptyNotification?.call(),
        message: switch (data['reason']) {
          'REBUILDING' => '공개 집계를 다시 준비하고 있어요.',
          'EXPIRED' => '공개 기간이 끝났어요.',
          _ => '현재 공개된 비교 결과가 없어요.',
        },
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => GuideScreen(
              api: widget.api,
              badgeName: diagnosisBadgeName,
              navigationBar: widget.emptyNavigationBar,
            ),
          ),
        ),
        footer: TextButton(
          onPressed: () => setState(() {
            _requested = false;
            _data = null;
          }),
          child: const Text('익명 비교 안내로'),
        ),
      );
    }
    final navigation = widget.emptyNavigationBar?.call(context);
    return Scaffold(
      bottomNavigationBar: data == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SafeArea(
                  top: false,
                  bottom: navigation == null,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_loading) const LinearProgressIndicator(),
                            if (_failed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: const StatusMessage(
                                  '연결을 확인하고 다시 시도해주세요.',
                                ),
                              ),
                            FilledButton(
                              onPressed: _loading ? null : _load,
                              child: Text(_requested ? '다시 시도' : '익명 비교 확인'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                ?navigation,
              ],
            )
          : navigation,
      appBar: AppBar(
        title: const Text('익명 비교 안내'),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (data == null) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      Icons.analytics_outlined,
                      color: FinsightColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '나의 위치는\n어떻게 비교되나요?',
                    style: FinsightTypography.displaySb28,
                  ),
                  const SizedBox(height: 10),
                  const Text('내 최신 진단과 대표 유형이 같은 집단의 공개 집계를 보여드려요.'),
                  const SizedBox(height: 24),
                  const _ComparisonExplanation(
                    title: '안전한 비교 원칙',
                    description:
                        '승인된 집계의 공개 기간, 표본 기준과 지표를 확인해요. 개인의 응답이나 정보는 공개하지 않아요.',
                  ),
                  const SizedBox(height: 12),
                  const _ComparisonExplanation(
                    title: '높은 점수의 의미',
                    description:
                        '금융 스트레스 점수가 높을수록 부담이 커요. 대응자원은 점수가 높을수록 충분해요.',
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  Text('집계 기간 ${data['from']} ~ ${data['to']}'),
                  Text('집계 인원 ${data['sampleSize']}명'),
                  ..._metrics(data['metrics'] as Map<String, dynamic>),
                  FilledButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (insights) => InsightScreen(
                            api: widget.api,
                            openComparison: () => Navigator.of(insights).pop(),
                            emptyNavigationBar: widget.emptyNavigationBar,
                            emptyNotification: widget.emptyNotification,
                          ),
                        ),
                      );
                      if (mounted) await _load();
                    },
                    child: const Text('공개 인사이트 보기'),
                  ),
                  TextButton(onPressed: _load, child: const Text('새로고침')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComparisonExplanation extends StatelessWidget {
  const _ComparisonExplanation({
    required this.title,
    required this.description,
  });
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FinsightColors.gray900,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: FinsightTypography.bodySb16),
          const SizedBox(height: 8),
          Text(description),
        ],
      ),
    ),
  );
}

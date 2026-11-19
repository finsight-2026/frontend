import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/app_api.dart';
import '../account/policy_documents.dart';
import '../design/financial_score_ring.dart';
import '../design/status_message.dart';
import '../design/tokens.dart';
import 'comparison_labels.dart';
import 'home_widget_content.dart';
import 'home_widget_platform.dart';

class HomeWidgetSummary {
  HomeWidgetSummary(Map<String, dynamic> json)
    : streak = json['streakMonths'] as int,
      last = json['lastDiagnosisDate'] as String?,
      next = json['nextDiagnosisDate'] as String?,
      days = json['daysUntilNext'] as int?,
      score = json['score'] as int?,
      maximumPressureScore = json['maximumPressureScore'] as int?,
      type = json['representativeType'] as String?;

  final int streak;
  final String? last;
  final String? next;
  final int? days;
  final int? score;
  final int? maximumPressureScore;
  final String? type;

  String? get pressure => comparisonMetricLabels[type];

  static Future<HomeWidgetSummary> load(
    AppApi api,
    WidgetOptions options,
  ) async {
    final path = Uri(
      path: '/api/v1/diagnosis/attempts/widget',
      queryParameters: {
        if (options.showScore) 'showScore': 'true',
        if (options.showType) 'showType': 'true',
      },
    );
    final response = await api.request<Map<String, dynamic>>(
      'GET',
      path.toString(),
    );
    return HomeWidgetSummary(response.data!);
  }

  String get title {
    final value = days;
    if (value == null) return '첫 진단을 시작해보세요';
    if (value < 0) return '다시 점검해볼까요?';
    return value == 0 ? '다음 진단 D-day' : '다음 진단 D-$value';
  }

  String get recordTitle {
    if (last == null) return '첫 기록을 시작해보세요';
    return streak == 0 ? '다시 기록해볼까요' : '$streak개월째 기록 중';
  }

  String? get recordSubtitle {
    if (last == null) return '약 5분이면 돼요';
    final value = days;
    if (value == null) return null;
    if (value > 0) return '다음 진단까지 D-$value';
    return value == 0 ? '오늘 다시 점검해볼까요' : '다시 점검해볼까요';
  }

  Map<String, Object?> get nativeData => {
    'streakMonths': streak,
    'lastDiagnosisDate': last,
    'nextDiagnosisDate': next,
    if (score != null) 'score': score,
    'maximumPressureScore': maximumPressureScore,
    if (type != null) 'type': diagnosisBadgeName(type),
    'pressure': pressure,
  };
}

Future<void> refreshHomeWidget(AppApi api) async {
  final platform = HomeWidgetPlatform.instance;
  final generation = platform.nextRefresh();
  try {
    final options = await platform.options();
    if (options == null) return;
    final summary = await HomeWidgetSummary.load(api, options);
    final content = options.showContent
        ? await HomeWidgetContent.load(api)
        : const HomeWidgetContent();
    await platform.publish(generation, {
      ...summary.nativeData,
      ...content.nativeData,
    });
  } on DioException catch (error) {
    if (error.response?.statusCode == 401 ||
        error.response?.statusCode == 403) {
      await platform.clearIfCurrent(generation);
    }
  } on PlatformException {
    // The app remains usable when the platform cannot update its widget.
  }
}

class HomeWidgetScreen extends StatefulWidget {
  const HomeWidgetScreen({
    required this.api,
    required this.openDiagnosis,
    this.bottomNavigationBar,
    super.key,
  });
  final AppApi api;
  final Future<void> Function() openDiagnosis;
  final Widget? bottomNavigationBar;

  @override
  State<HomeWidgetScreen> createState() => _HomeWidgetScreenState();
}

class _HomeWidgetScreenState extends State<HomeWidgetScreen> {
  final _platform = HomeWidgetPlatform.instance;
  WidgetOptions _options = HomeWidgetPlatform.hidden;
  bool _nativeReady = false;
  bool _busy = true;
  _WidgetPreview _selected = _WidgetPreview.record;
  HomeWidgetSummary? _summary;
  HomeWidgetContent _content = const HomeWidgetContent();
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({WidgetOptions? configure}) async {
    setState(() {
      _busy = true;
      _error = null;
      _summary = null;
    });
    try {
      if (configure != null) {
        if (_nativeReady) await _platform.configure(configure);
        _options = configure;
      } else {
        final stored = await _platform.options();
        if (stored != null) {
          _options = stored;
          _nativeReady = true;
        }
      }
      final generation = _platform.nextRefresh();
      final summary = await HomeWidgetSummary.load(widget.api, _options);
      final content = _options.showContent
          ? await HomeWidgetContent.load(widget.api)
          : const HomeWidgetContent();
      if (_nativeReady) {
        await _platform.publish(generation, {
          ...summary.nativeData,
          ...content.nativeData,
        });
      }
      _summary = summary;
      _content = content;
    } on DioException {
      _error = '위젯에 표시할 기록을 불러오지 못했어요.';
    } on PlatformException {
      _error = '기기의 위젯 설정을 불러오지 못했어요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('홈 화면에 추가'),
        content: const Text(
          '홈 화면의 빈 곳을 길게 누르고 편집에서 위젯을 추가하세요. FINSIGHT를 검색한 뒤 원하는 위젯을 고르세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _changePreview(int step) {
    final previews = _WidgetPreview.values;
    setState(
      () => _selected = previews[(_selected.index + step) % previews.length],
    );
  }

  Future<void> _displayOptions() async {
    var draft = _options;
    final options = await showModalBottomSheet<WidgetOptions>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  title: const Text('점수 표시'),
                  value: draft.showScore,
                  onChanged: (value) => update(
                    () => draft = (
                      showScore: value,
                      showType: draft.showType,
                      showContent: draft.showContent,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('유형 표시'),
                  value: draft.showType,
                  onChanged: (value) => update(
                    () => draft = (
                      showScore: draft.showScore,
                      showType: value,
                      showContent: draft.showContent,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('개인화 뉴스·행동 표시'),
                  value: draft.showContent,
                  onChanged: (value) => update(
                    () => draft = (
                      showScore: draft.showScore,
                      showType: draft.showType,
                      showContent: value,
                    ),
                  ),
                ),
                if (_nativeReady)
                  const Text('잠금 화면 위젯은 진단을 떠올릴 수 있는 일반 안내만 표시해요.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet, draft),
                  child: const Text('저장'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted && options != null && options != _options) {
      await _load(configure: options);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final theme = Theme.of(context);
    return AccountInfoPage(
      title: '위젯',
      bottomNavigationBar: widget.bottomNavigationBar,
      centerTitle: true,
      actions: [
        IconButton(
          onPressed: _busy ? null : _displayOptions,
          tooltip: '위젯 표시 설정',
          icon: const Icon(Icons.tune, size: 20),
        ),
      ],
      contentPadding: const EdgeInsets.fromLTRB(24, 44, 24, 24),
      scrolledUnderElevation: 0,
      children: [
        Text('배경화면에서\n나의 경제 습관을 관리하세요', style: theme.textTheme.displaySmall),
        const SizedBox(height: 42),
        if (_busy) const LinearProgressIndicator(),
        if (_error case final error?) ...[
          StatusMessage(error),
          TextButton(onPressed: _load, child: const Text('다시 시도')),
        ],
        if (summary != null) ...[
          GestureDetector(
            onHorizontalDragEnd: (drag) {
              final speed = drag.primaryVelocity ?? 0;
              if (speed.abs() > 50) _changePreview(speed < 0 ? 1 : -1);
            },
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _selected.medium ? 352 : 214,
                  minHeight: _selected.medium ? 174 : 214,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: FinsightColors.gray900),
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: .8,
                      colors: [
                        FinsightColors.neonLime900.withValues(alpha: .34),
                        FinsightColors.gray1000,
                        FinsightColors.gray1000,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: FinsightColors.black.withValues(alpha: .4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_selected == _WidgetPreview.summary)
                          _DiagnosisSummaryPreview(summary: summary)
                        else if (_selected == _WidgetPreview.news)
                          _NewsPreview(
                            content: _content,
                            showContent: _options.showContent,
                          )
                        else if (_selected == _WidgetPreview.action)
                          _ActionPreview(
                            action: _content.action,
                            showContent: _options.showContent,
                          )
                        else ...[
                          ExcludeSemantics(
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.asset(
                                    'assets/illustrations/widget-calendar.png',
                                    width: 90,
                                    height: 90,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '● ● ●',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            summary.recordTitle,
                            textAlign: TextAlign.center,
                            style: FinsightTypography.displaySb22,
                          ),
                          if (summary.recordSubtitle case final subtitle?)
                            Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final preview in _WidgetPreview.values)
                Semantics(
                  selected: _selected == preview,
                  child: IconButton(
                    tooltip: preview.label,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => setState(() => _selected = preview),
                    icon: AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      width: _selected == preview ? 22 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _selected == preview
                            ? theme.colorScheme.primary
                            : FinsightColors.gray750,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (summary.last == null)
            TextButton(
              onPressed: () async {
                await widget.openDiagnosis();
                if (mounted) await _load();
              },
              child: const Text('첫 자가진단 시작하기'),
            ),
        ],
        if (_nativeReady)
          FilledButton(
            onPressed: _busy ? null : _add,
            child: const Text('홈 화면에 추가하러 가기'),
          ),
        if (!_nativeReady) const Text('이 환경에서는 위젯 미리보기를 확인할 수 있어요.'),
      ],
    );
  }
}

enum _WidgetPreview {
  record('진단 기록', false),
  summary('진단 요약', true),
  news('경제 뉴스', true),
  action('오늘의 행동', false);

  const _WidgetPreview(this.label, this.medium);
  final String label;
  final bool medium;
}

class _NewsPreview extends StatelessWidget {
  const _NewsPreview({required this.content, required this.showContent});
  final HomeWidgetContent content;
  final bool showContent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final article = showContent ? content.news : null;
    final bytes = article?.image;
    const placeholder = AssetImage('assets/illustrations/widget-news.png');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MORNING BRIEF',
                style: FinsightTypography.labelM12.copyWith(
                  color: theme.colorScheme.primary,
                  letterSpacing: .6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                article?.title ??
                    (showContent ? '경제 소식을 준비하고 있어요' : '새 경제 소식을 확인해보세요'),
                style: theme.textTheme.titleLarge,
              ),
              if (article != null)
                Text(
                  article.today
                      ? '오늘의 경제 한 장'
                      : '경제 한 장 · ${article.publishedDate ?? article.edition}',
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image(
            image: bytes == null ? placeholder : MemoryImage(bytes),
            width: 95,
            height: 95,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
      ],
    );
  }
}

class _ActionPreview extends StatelessWidget {
  const _ActionPreview({required this.action, required this.showContent});
  final WidgetAction? action;
  final bool showContent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lime = theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TODAY’S ACTION',
          style: FinsightTypography.labelM12.copyWith(
            color: lime,
            letterSpacing: .6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          showContent
              ? action?.title ?? widgetActionFallback(action?.state)
              : '오늘의 작은 행동',
          style: FinsightTypography.displaySb22,
        ),
        const SizedBox(height: 4),
        if (!showContent) const Text('앱에서 확인해보세요'),
        Align(
          alignment: Alignment.centerRight,
          child: ClipOval(
            child: Image.asset(
              'assets/illustrations/widget-action.png',
              width: 46,
              height: 46,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _DiagnosisSummaryPreview extends StatelessWidget {
  const _DiagnosisSummaryPreview({required this.summary});

  final HomeWidgetSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lime = theme.colorScheme.primary;
    final score = summary.score;
    final ring = FinancialScoreRing(score: score, size: 108);
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.type case final type?)
          DecoratedBox(
            decoration: BoxDecoration(
              color: lime.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                diagnosisBadgeName(type),
                style: TextStyle(color: lime),
              ),
            ),
          ),
        if (summary.pressure case final pressure?) ...[
          const SizedBox(height: 6),
          Text(
            '가장 큰 금융 압박',
            style: FinsightTypography.labelR12.copyWith(
              color: FinsightColors.gray400,
            ),
          ),
          Text(pressure, style: FinsightTypography.displaySb22),
          if (summary.maximumPressureScore case final score?) ...[
            LinearProgressIndicator(
              value: score / 100,
              borderRadius: BorderRadius.circular(8),
              minHeight: 5,
              trackGap: 0,
              color: FinsightColors.primary,
              backgroundColor: FinsightColors.gray750,
              stopIndicatorRadius: 0,
              semanticsLabel: '가장 큰 금융 압박 $score점',
            ),
            if (score == 0) const Text('모든 영역의 부담이 낮아요'),
          ],
        ] else ...[
          Text(
            summary.last == null ? summary.title : '나의 금융 마음',
            style: theme.textTheme.titleLarge,
          ),
          if (summary.last != null && summary.score == null)
            const Text('앱에서 확인하기'),
        ],
        if (summary.last != null) ...[
          const SizedBox(height: 8),
          Text(
            '맞춤 가이드 보기 ›',
            style: FinsightTypography.labelM12.copyWith(color: lime),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 240 ||
            MediaQuery.textScalerOf(context).scale(16) > 22) {
          return Column(
            children: [ring, const SizedBox(height: 12), information],
          );
        }
        return Row(
          children: [
            ring,
            const SizedBox(width: 16),
            Expanded(child: information),
          ],
        );
      },
    );
  }
}

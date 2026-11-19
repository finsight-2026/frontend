import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../account/app_api.dart';
import '../content/content_exposure.dart';
import '../design/content_skeleton.dart';
import '../design/status_message.dart';
import '../design/tokens.dart';
import '../shared/request_id.dart';
import 'comparison_labels.dart';
import 'diagnosis_empty_screen.dart';
import 'guide_screen.dart';

const _path = '/api/v1/insights';
const _topics = {
  'YFSI_MEAN': '금융 스트레스',
  'EXTERNAL_AREA_MEAN': '외부 부담',
  'RESOURCE_DOMAIN_MEAN': '대응자원',
  'PERCEIVED_STRESS_MEAN': '체감 스트레스',
};

class InsightScreen extends StatefulWidget {
  const InsightScreen({
    required this.api,
    this.openDiagnosis,
    this.openComparison,
    this.emptyNavigationBar,
    this.emptyNotification,
    super.key,
  });
  final AppApi api;
  final Future<void> Function(BuildContext)? openDiagnosis;
  final VoidCallback? openComparison;
  final WidgetBuilder? emptyNavigationBar;
  final Widget Function()? emptyNotification;

  @override
  State<InsightScreen> createState() => _InsightScreenState();
}

class _InsightScreenState extends State<InsightScreen> {
  final _cards = <Map<String, dynamic>>[];
  String _viewSession = newRequestId();
  String? _topic;
  bool _diagnosed = true;
  bool _busy = true;
  bool _hasMore = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool next = false}) async {
    final previous = next ? _cards.last : null;
    setState(() {
      _busy = true;
      _error = false;
      if (!next) _cards.clear();
    });
    try {
      final response = await widget.api.request<Map<String, dynamic>>(
        'GET',
        Uri(
          path: _path,
          queryParameters: {
            'topic': ?_topic,
            'before': ?previous?['publishedAt'] as String?,
            'beforeId': ?previous?['id'] as String?,
          },
        ).toString(),
      );
      if (!mounted) return;
      final data = response.data!;
      _diagnosed = data['diagnosed'] == true;
      _hasMore = data['hasMore'] == true;
      _cards.addAll((data['items'] as List).cast<Map<String, dynamic>>());
    } on DioException {
      _error = true;
      if (!next) _hasMore = false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> card) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _InsightDetail(
          api: widget.api,
          id: card['id'] as String,
          navigationBar: widget.emptyNavigationBar,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Widget _filters() => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final entry in {'': '전체', ..._topics}.entries)
        ChoiceChip(
          label: Text(entry.value),
          showCheckmark: false,
          shape: const StadiumBorder(),
          backgroundColor: FinsightColors.gray900,
          selectedColor: FinsightColors.primary,
          labelStyle: TextStyle(
            color: (_topic ?? '') == entry.key
                ? FinsightColors.gray1000
                : FinsightColors.gray300,
          ),
          side: BorderSide.none,
          selected: (_topic ?? '') == entry.key,
          onSelected: _busy
              ? null
              : (selected) {
                  if (!selected) return;
                  setState(() {
                    _topic = entry.key.isEmpty ? null : entry.key;
                    _viewSession = newRequestId();
                  });
                  _load();
                },
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (!_busy && !_error && !_diagnosed && widget.openDiagnosis != null) {
      return DiagnosisEmptyScreen.result(
        navigationBar: widget.emptyNavigationBar?.call(context),
        notification: widget.emptyNotification?.call(),
        onPressed: () async {
          await widget.openDiagnosis!(context);
          if (mounted) await _load();
        },
        footer: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('홈으로'),
        ),
      );
    }
    if (!_busy && !_error && _cards.isEmpty && _diagnosed) {
      return DiagnosisEmptyScreen.insight(
        navigationBar: widget.emptyNavigationBar?.call(context),
        notification: widget.emptyNotification?.call(),
        filters: _topic == null ? null : _filters(),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('돌아가기'),
        ),
      );
    }
    return _InsightPage(
      title: '익명 행동 인사이트',
      navigationBar: widget.emptyNavigationBar?.call(context),
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Icon(Icons.touch_app_outlined, color: FinsightColors.primary),
        ),
        const Text(
          '비슷한 청년들은\n어떤 행동을 할까요?',
          style: FinsightTypography.displaySb28,
        ),
        const Text('공개된 집계와 연결된 작은 행동을 살펴보세요.'),
        if (_diagnosed) ...[
          const Text('관심 주제', style: FinsightTypography.bodySb16),
          _filters(),
        ],
        if (_cards.isNotEmpty)
          const Text('많이 선택한 작은 행동', style: FinsightTypography.bodySb16),
        if (_busy)
          _cards.isEmpty
              ? const ContentSkeleton(
                  label: '인사이트 불러오는 중',
                  child: SkeletonRows(),
                )
              : const LinearProgressIndicator(),
        if (_error) ...[
          const StatusMessage('인사이트를 불러오지 못했어요.'),
          TextButton(
            onPressed: _busy ? null : () => _load(next: _cards.isNotEmpty),
            child: const Text('다시 시도'),
          ),
        ],
        if (!_busy && !_error && !_diagnosed)
          const StatusMessage.notice('먼저 자가진단을 완료해 주세요.'),
        for (final card in _cards)
          ContentExposure(
            key: ValueKey((card['id'], card['revision'], _viewSession)),
            onVisible: () =>
                _event(widget.api, card, viewSession: _viewSession),
            child: _InsightPanel(
              onTap: _busy ? null : () => _open(card),
              children: [
                _InsightLabel(_topics[card['topic']] ?? '공개 인사이트'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        card['title'] as String,
                        style: FinsightTypography.bodySb16,
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
                const SizedBox(height: 6),
                Text(card['summary'] as String),
                const SizedBox(height: 10),
                Text(
                  '도움 ${card['helpfulCount']}',
                  style: FinsightTypography.labelM12,
                ),
              ],
            ),
          ),
        if (_hasMore && !_error)
          TextButton(
            onPressed: _busy ? null : () => _load(next: true),
            child: const Text('더 보기'),
          ),
        if (_cards.isNotEmpty && widget.openComparison != null)
          FilledButton(
            onPressed: _busy ? null : widget.openComparison,
            child: const Text('익명 비교 확인'),
          ),
      ],
    );
  }
}

class _InsightDetail extends StatefulWidget {
  const _InsightDetail({
    required this.api,
    required this.id,
    this.navigationBar,
  });
  final AppApi api;
  final String id;
  final WidgetBuilder? navigationBar;

  @override
  State<_InsightDetail> createState() => _InsightDetailState();
}

class _InsightDetailState extends State<_InsightDetail>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  bool _busy = true;
  bool _missing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_busy &&
        ModalRoute.isCurrentOf(context) == true) {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({bool? helpful}) async {
    final previous = _data;
    setState(() {
      _busy = true;
      _missing = false;
      _error = null;
    });
    try {
      final card = previous?['card'] as Map<String, dynamic>?;
      final path = '$_path/${widget.id}';
      final response = await widget.api.request<Map<String, dynamic>>(
        helpful != null ? 'PUT' : 'GET',
        helpful != null ? '$path/helpful' : path,
        data: helpful != null
            ? {'revision': card!['revision'], 'helpful': helpful}
            : null,
      );
      if (mounted) _data = response.data;
    } on DioException catch (error) {
      if (!mounted) return;
      _missing = error.response?.statusCode == 404;
      final updated = error.response?.statusCode == 409;
      if (_missing || updated) _data = null;
      _error = _missing
          ? '지금 공개된 인사이트가 아니에요.'
          : updated
          ? '인사이트가 수정됐어요. 새 내용을 불러와 주세요.'
          : '요청을 완료하지 못했어요. 다시 시도해 주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final card = data?['card'] as Map<String, dynamic>?;
    final metric = data?['metric'];
    return _InsightPage(
      title: '행동 인사이트',
      navigationBar: widget.navigationBar?.call(context),
      children: [
        if (data != null && card != null) ...[
          _InsightLabel('${_topics[card['topic']] ?? '공개'} · 익명 행동'),
          Text(card['title'] as String, style: FinsightTypography.displaySb28),
          Text(
            '비슷한 고민에서 시작한 작은 행동',
            style: FinsightTypography.bodyR14.copyWith(
              color: FinsightColors.gray400,
            ),
          ),
          ContentExposure(
            key: ValueKey((widget.id, card['revision'])),
            impression: false,
            onVisible: () => _event(widget.api, card),
            child: _InsightPanel(
              children: [
                Text(
                  '어떻게 실천하나요?',
                  style: FinsightTypography.titleSb18.copyWith(
                    color: FinsightColors.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  card['summary'] as String,
                  style: FinsightTypography.bodySb16,
                ),
                const SizedBox(height: 8),
                Text(
                  data['body'] as String,
                  style: FinsightTypography.bodyR14.copyWith(
                    color: FinsightColors.gray300,
                  ),
                ),
              ],
            ),
          ),
          const Text('이 행동이 도움이 되었나요?', style: FinsightTypography.bodySb16),
          Row(
            children: [
              Expanded(
                child: _reaction(
                  '도움됐어요',
                  true,
                  selected: data['helpful'] == true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _reaction('잘 모르겠어요', false)),
            ],
          ),
          _InsightPanel(
            children: [
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(
                  Icons.info_outline,
                  size: 18,
                  color: FinsightColors.gray400,
                ),
                title: Text(
                  '익명으로 집계된 행동과 승인된 지표만 표시해요.',
                  style: FinsightTypography.labelR12.copyWith(
                    color: FinsightColors.gray400,
                  ),
                ),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comparisonMetricLabels[card['topic']] ?? '공개 지표',
                    style: FinsightTypography.bodySb14,
                  ),
                  if (metric is num) Text('$metric점'),
                  if (metric is Map<String, dynamic>)
                    for (final entry in metric.entries)
                      if (comparisonMetricLabels[entry.key] case final label?)
                        Text('$label ${entry.value}점'),
                  const SizedBox(height: 6),
                  Text(data['explanation'] as String),
                  Text('집계 기간 ${data['from']} ~ ${data['to']}'),
                  Text(
                    '집계 인원 ${data['sampleSize']}명 · 산식 ${data['formulaVersion']}',
                  ),
                ],
              ),
            ],
          ),
        ],
        if (_busy)
          data == null
              ? const ContentSkeleton(
                  label: '행동 인사이트 불러오는 중',
                  child: SkeletonRows(count: 2),
                )
              : const LinearProgressIndicator(),
        if (_error case final error?) ...[
          StatusMessage(error),
          if (data == null)
            TextButton(
              onPressed: _missing
                  ? () => Navigator.of(context).pop()
                  : () => _load(),
              child: Text(_missing ? '목록으로 돌아가기' : '다시 불러오기'),
            ),
        ],
      ],
    );
  }

  Widget _reaction(
    String label,
    bool helpful, {
    bool selected = false,
  }) => Semantics(
    selected: selected,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: selected
            ? FinsightColors.primary
            : FinsightColors.white,
        backgroundColor: FinsightColors.gray900,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        side: BorderSide(
          color: selected ? FinsightColors.primary : FinsightColors.gray750,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: _busy ? null : () => _load(helpful: helpful),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (helpful) ...[
            Icon(selected ? Icons.thumb_up : Icons.thumb_up_outlined, size: 16),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: FinsightTypography.labelM12,
            ),
          ),
        ],
      ),
    ),
  );
}

class _InsightPage extends StatelessWidget {
  const _InsightPage({
    required this.title,
    required this.children,
    this.navigationBar,
  });
  final String title;
  final List<Widget> children;
  final Widget? navigationBar;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title, style: FinsightTypography.bodySb16),
      centerTitle: true,
      scrolledUnderElevation: 0,
    ),
    bottomNavigationBar: navigationBar,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _InsightLabel extends StatelessWidget {
  const _InsightLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: FinsightTypography.labelM12.copyWith(color: FinsightColors.primary),
  );
}

class _InsightPanel extends StatelessWidget {
  const _InsightPanel({required this.children, this.onTap});
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: FinsightColors.gray900,
    borderRadius: BorderRadius.circular(10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

Future<void> _event(
  AppApi api,
  Map<String, dynamic> card, {
  String? viewSession,
}) => recordContentEvent(
  api,
  '$_path/${card['id']}/events',
  revision: card['revision'] as int,
  viewSessionId: viewSession,
);

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../account/app_api.dart';
import '../content/content_exposure.dart';
import '../design/content_skeleton.dart';
import '../design/status_message.dart';
import '../design/tokens.dart';
import '../shared/request_id.dart';
import 'diagnosis_badge.dart';
import 'home_widget_screen.dart';
import 'rendered_diagnosis_view.dart';

const _guidesPath = '/api/v1/guides';

class GuideScreen extends StatefulWidget {
  const GuideScreen({
    required this.api,
    required this.badgeName,
    this.attemptId,
    this.navigationBar,
    super.key,
  });

  final AppApi api;
  final String Function(Object?) badgeName;
  final String? attemptId;
  final WidgetBuilder? navigationBar;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  late Future<Response<Map<String, dynamic>>> _load = _fetch();
  final _viewSession = newRequestId();
  int _filter = 0;

  Future<Response<Map<String, dynamic>>> _fetch() =>
      widget.api.request<Map<String, dynamic>>(
        'GET',
        Uri(
          path: _guidesPath,
          queryParameters: {'attemptId': ?widget.attemptId},
        ).toString(),
      );

  Future<void> _open(Map<String, dynamic> guide, String attemptId) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => GuideDetail(
            api: widget.api,
            attemptId: attemptId,
            id: guide['id'] as String,
            navigationBar: widget.navigationBar,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _load,
    builder: (context, snapshot) {
      Widget page(Widget child, {Widget? footer}) => _GuidePage(
        title: '맞춤 가이드',
        navigationBar: widget.navigationBar?.call(context),
        footer: footer,
        child: child,
      );
      if (snapshot.connectionState != ConnectionState.done) {
        return page(
          const ContentSkeleton(
            label: '맞춤 가이드 불러오는 중',
            child: SkeletonRows(count: 4, showLeading: true),
          ),
        );
      }
      if (snapshot.hasError) {
        final error = snapshot.error;
        final missing =
            error is DioException && error.response?.statusCode == 404;
        return page(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(missing ? '먼저 진단을 완료해주세요.' : '가이드를 불러오지 못했어요.'),
              TextButton(
                onPressed: missing
                    ? () => Navigator.of(context).pop()
                    : () => setState(() => _load = _fetch()),
                child: Text(missing ? '돌아가기' : '다시 시도'),
              ),
            ],
          ),
        );
      }
      final data = snapshot.data!.data!;
      final diagnosis = data['diagnosis'] as Map<String, dynamic>;
      final guides = (data['guides'] as List).cast<Map<String, dynamic>>();
      final filtered = guides
          .where(
            (guide) =>
                _filter == 0 ||
                _filter == (guide['category'] == 'LEARN' ? 2 : 1),
          )
          .toList();
      final badge = widget.badgeName(diagnosis['type']);
      final attemptId = diagnosis['attemptId'] as String;
      return page(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: DiagnosisBadge(diagnosis['type'], label: badge),
            ),
            const SizedBox(height: 10),
            Text(
              '${diagnosis['score']}점 · $badge 맞춤 가이드',
              style: FinsightTypography.titleSb18,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final (index, label) in ['전체', '시작하기', '알아보기'].indexed)
                  ChoiceChip(
                    label: Text(label),
                    showCheckmark: false,
                    shape: const StadiumBorder(),
                    side: BorderSide.none,
                    selectedColor: FinsightColors.primary,
                    backgroundColor: FinsightColors.gray900,
                    labelStyle: TextStyle(
                      color: _filter == index
                          ? FinsightColors.gray1000
                          : FinsightColors.gray300,
                    ),
                    selected: _filter == index,
                    onSelected: (_) => setState(() => _filter = index),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty) const Text('지금 볼 수 있는 가이드가 없어요.'),
            for (final guide in filtered) ...[
              ContentExposure(
                key: ValueKey((guide['id'], guide['version'])),
                onVisible: () async {
                  final version = guide['version'];
                  if (version is! int) return;
                  await recordContentEvent(
                    widget.api,
                    Uri(
                      path: '$_guidesPath/${guide['id']}/events',
                      queryParameters: {
                        'attemptId': diagnosis['attemptId'] as String,
                      },
                    ).toString(),
                    revision: version,
                    viewSessionId: _viewSession,
                  );
                },
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: DecoratedBox(
                    decoration: BoxDecoration(
                      color: FinsightColors.neonLime900,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Image.asset(
                        'assets/illustrations/guide-order-${switch (guide['order']) {
                          1 || 2 || 3 => guide['order'],
                          _ => 4,
                        }}.png',
                        width: 24,
                        height: 24,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  title: Text(
                    guide['title'] as String,
                    style: FinsightTypography.bodySb16,
                  ),
                  subtitle: Text(guide['heading'] as String),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(guide, attemptId),
                ),
              ),
              const Divider(height: 1, color: FinsightColors.gray800),
            ],
          ],
        ),
        footer: filtered.isEmpty
            ? null
            : FilledButton(
                onPressed: () => _open(filtered.first, attemptId),
                child: const Text('추천 행동 자세히 보기'),
              ),
      );
    },
  );
}

class GuideDetail extends StatefulWidget {
  const GuideDetail({
    required this.api,
    required this.attemptId,
    required this.id,
    this.revision,
    this.openList,
    this.navigationBar,
    super.key,
  });

  final AppApi api;
  final String attemptId;
  final String id;
  final int? revision;
  final void Function(BuildContext)? openList;
  final WidgetBuilder? navigationBar;

  @override
  State<GuideDetail> createState() => _GuideDetailState();
}

class _GuideDetailState extends State<GuideDetail> {
  Map<String, dynamic>? _guide;
  bool _missing = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _request();
  }

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
      _missing = false;
    });
    final path = Uri(
      path: '$_guidesPath/${widget.id}/view',
      queryParameters: {
        'attemptId': widget.attemptId,
        if (widget.revision case final int revision)
          'revision': revision.toString(),
      },
    ).toString();
    try {
      final response = await widget.api.request<Map<String, dynamic>>(
        'POST',
        path,
      );
      if (!mounted) return;
      final guide = response.data!['guide'] as Map<String, dynamic>;
      if (widget.revision != null && guide['version'] != widget.revision) {
        _showUnavailableWidgetGuide();
        return;
      }
      _guide = guide;
    } on DioException catch (error) {
      if (!mounted) return;
      _missing = error.response?.statusCode == 404;
      final updated = error.response?.statusCode == 409;
      if (widget.revision != null && (_missing || updated)) {
        _showUnavailableWidgetGuide();
        return;
      }
      if (updated) {
        _guide = null;
        _error = '가이드가 수정됐어요. 새 내용을 다시 불러와 주세요.';
        return;
      }
      if (_missing) _guide = null;
      _error = _missing ? '지금은 이 가이드를 볼 수 없어요.' : '요청을 완료하지 못했어요. 다시 시도해주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showUnavailableWidgetGuide() {
    _guide = null;
    _missing = true;
    _error = '위젯에 표시된 행동을 지금은 볼 수 없어요.';
    unawaited(refreshHomeWidget(widget.api));
  }

  void _openList() {
    if (widget.openList case final open?) {
      open(context);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _GuidePage(
      title: '추천 행동 상세',
      navigationBar: widget.navigationBar?.call(context),
      footer: _guide == null
          ? null
          : FilledButton(
              onPressed: _busy ? null : _openList,
              child: const Text('더 많은 가이드 보기'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_guide case final guide?) ...[
            Text(
              'ACTION GUIDE · 작은 실천',
              style: FinsightTypography.labelM12.copyWith(
                color: FinsightColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              guide['heading'] as String,
              style: FinsightTypography.displaySb28,
            ),
            if (guide['body'] case final String body
                when body != guide['heading']) ...[
              const SizedBox(height: 12),
              Text(
                body,
                style: FinsightTypography.bodyR14.copyWith(
                  color: FinsightColors.gray400,
                ),
              ),
            ],
            const SizedBox(height: 30),
            _GuidePanel(
              children: [
                Text(
                  'TODAY’S ACTION',
                  style: FinsightTypography.labelM12.copyWith(
                    color: FinsightColors.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  guide['action'] as String,
                  semanticsLabel: '오늘의 행동: ${guide['action']}',
                  style: FinsightTypography.bodySb16,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _GuidePanel(
              children: [
                const Text(
                  '내가 할 수 있는 다음 행동',
                  style: FinsightTypography.bodySb16,
                ),
                const SizedBox(height: 8),
                for (final (index, step) in (guide['steps'] as List).indexed)
                  Text(
                    '${index < 5 ? const ['①', '②', '③', '④', '⑤'][index] : '${index + 1}.'} $step',
                    style: FinsightTypography.bodyR14.copyWith(
                      color: FinsightColors.gray300,
                    ),
                  ),
              ],
            ),
          ],
          if (_busy)
            _guide == null
                ? const ContentSkeleton(
                    label: '추천 행동 불러오는 중',
                    child: SkeletonRows(count: 2),
                  )
                : const LinearProgressIndicator(),
          if (_error case final message?) ...[
            StatusMessage(message),
            if (_guide == null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        if (!_missing) {
                          _request();
                        } else {
                          _openList();
                        }
                      },
                child: Text(_missing ? '가이드 목록으로' : '다시 시도'),
              ),
          ],
        ],
      ),
    );

    if (_guide == null) return page;
    return RenderedDiagnosisView(
      api: widget.api,
      attemptId: widget.attemptId,
      key: ValueKey(_guide!['version']),
      contentId: widget.id,
      contentRevision: _guide!['version'] as int?,
      child: page,
    );
  }
}

class _GuidePage extends StatelessWidget {
  const _GuidePage({
    required this.title,
    required this.child,
    this.navigationBar,
    this.footer,
  });

  final String title;
  final Widget child;
  final Widget? navigationBar;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title, style: FinsightTypography.bodySb16),
      centerTitle: true,
      scrolledUnderElevation: 0,
    ),
    bottomNavigationBar: footer == null
        ? navigationBar
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SafeArea(
                top: false,
                bottom: navigationBar == null,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 56),
                      child: SizedBox(width: double.infinity, child: footer),
                    ),
                  ),
                ),
              ),
              ?navigationBar,
            ],
          ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class _GuidePanel extends StatelessWidget {
  const _GuidePanel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: FinsightColors.gray900,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: FinsightColors.gray800),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
}

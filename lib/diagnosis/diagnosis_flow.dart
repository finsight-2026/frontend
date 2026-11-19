import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../account/account_settings.dart';
import '../account/app_api.dart';
import '../account/data_export_flow.dart';
import '../design/content_skeleton.dart';
import '../design/status_message.dart';
import '../design/finsight_wordmark.dart';
import '../design/tokens.dart';
import '../notification/notification_device.dart';
import '../notification/app_notifications.dart';
import '../shared/request_id.dart';

import '../news/news_screen.dart';
import 'comparison_screen.dart';
import 'comparison_labels.dart';
import 'diagnosis_badge.dart';
import 'diagnosis_empty_screen.dart';
import 'guide_screen.dart';
import 'home_widget_platform.dart';
import 'home_widget_screen.dart';
import 'insight_screen.dart';
import 'monthly_report_screen.dart';
import 'report_share_card.dart' show reportScoreChange;
import 'rendered_diagnosis_view.dart';

const _attempts = '/api/v1/diagnosis/attempts';

class DiagnosisHome extends StatefulWidget {
  const DiagnosisHome({required this.api, this.email, super.key});
  final AppApi api;
  final String? email;

  @override
  State<DiagnosisHome> createState() => _DiagnosisHomeState();
}

class _DiagnosisHomeState extends State<DiagnosisHome>
    with WidgetsBindingObserver {
  int _tab = 0;
  bool _openingResult = false;
  String? _resultError;
  late var _latest = _load();
  StreamSubscription<void>? _widgetOpens;
  bool _checkingWidget = false;
  StreamSubscription<void>? _notificationOpens;
  bool _checkingNotification = false;
  int _inboxRevision = 0;

  @override
  void initState() {
    super.initState();
    final platform = HomeWidgetPlatform.instance;
    if (!platform.isNative) return;
    WidgetsBinding.instance.addObserver(this);
    _widgetOpens = platform.opens.listen((_) => _openFromWidget());
    _notificationOpens = NotificationOpens.instance.opens.listen(
      (_) => _openFromNotification(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(refreshHomeWidget(widget.api));
      unawaited(_openFromWidget());
      unawaited(_openFromNotification());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetOpens?.cancel();
    _notificationOpens?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(refreshHomeWidget(widget.api));
    unawaited(_openFromWidget());
    unawaited(_openFromNotification());
  }

  Future<void> _openFromNotification() async {
    if (!mounted || _checkingNotification) return;
    _checkingNotification = true;
    try {
      while (mounted) {
        final id = await NotificationOpens.instance.take();
        if (id == null || !mounted) return;
        await NotificationEntry.openInbox(
          context,
          api: widget.api,
          openTarget: _openNotificationTarget,
          notificationId: id,
          inboxNavigationBar: _inboxNavigationBar,
        );
        if (mounted) setState(() => _inboxRevision++);
      }
    } finally {
      _checkingNotification = false;
    }
  }

  Future<void> _openFromWidget() async {
    if (!mounted || _checkingWidget) return;
    _checkingWidget = true;
    final platform = HomeWidgetPlatform.instance;
    try {
      final open = await platform.consumeOpen();
      if (open == null || !mounted) return;
      final (destination: destination, article: article, guide: guide) = open;
      if (destination == HomeWidgetDestination.diagnosis) {
        unawaited(_openEntry());
        return;
      }
      if (destination == HomeWidgetDestination.news) {
        unawaited(
          _push(
            article == null
                ? NewsScreen(api: widget.api)
                : NewsDetail(
                    api: widget.api,
                    id: article.id,
                    edition: article.edition,
                    revision: article.revision,
                  ),
          ),
        );
        return;
      }
      if (guide != null) {
        unawaited(
          _push(
            _guideDetail(guide.attemptId, guide.id, revision: guide.revision),
          ),
        );
        return;
      }
      Map<String, dynamic>? latest;
      try {
        latest = await _load();
      } on DioException {
        // The diagnosis intro offers a retry when the device is offline.
      }
      if (!mounted) return;
      if (latest == null) {
        unawaited(_openEntry());
      } else {
        unawaited(
          _push(GuideScreen(api: widget.api, badgeName: diagnosisBadgeName)),
        );
      }
    } finally {
      _checkingWidget = false;
      if (mounted && await platform.peekOpen()) unawaited(_openFromWidget());
    }
  }

  Future<Map<String, dynamic>?> _load() async {
    final response = await widget.api.request<Map<String, dynamic>>(
      'GET',
      _attempts,
    );
    final items = (response.data!['items'] as List)
        .cast<Map<String, dynamic>>();
    return items.firstOrNull;
  }

  void _refresh() {
    setState(() {
      _resultError = null;
      _latest = _load();
    });
    unawaited(refreshHomeWidget(widget.api));
  }

  void _selectTab(int tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
  }

  Future<void> _openEntry() async {
    await _push(
      _DiagnosisEntry(
        api: widget.api,
        navigationBar: (entry) => _bottomNavigationBar((tab) {
          Navigator.of(entry).pop();
          _selectTab(tab);
        }, selectedIndex: 0),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _push(Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

  Future<void> _openResult(Map<String, dynamic> latest) async {
    if (_openingResult) return;
    setState(() {
      _openingResult = true;
      _resultError = null;
    });
    final attemptId = latest['attemptId'] as String;
    try {
      final response = await widget.api.request<Map<String, dynamic>>(
        'GET',
        '$_attempts/$attemptId/result',
      );
      if (!mounted || _tab != 0) return;
      await _push(
        _Result(
          api: widget.api,
          attemptId: attemptId,
          diagnosis: response.data!,
        ),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 404) {
        _selectTab(2);
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          statusSnackBar('삭제되었거나 볼 수 없는 진단 결과예요.', tone: StatusTone.warning),
        );
      } else {
        _resultError = '진단 결과를 불러오지 못했어요. 다시 눌러주세요.';
      }
    } finally {
      if (mounted) setState(() => _openingResult = false);
    }
  }

  Future<void> _openEmptyResult() async {
    final start = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (empty) => DiagnosisEmptyScreen.result(
          notification: _notification(),
          navigationBar: _emptyNavigationBar(empty),
          onPressed: () => Navigator.of(empty).pop(true),
          footer: TextButton(
            onPressed: () {
              Navigator.of(empty).pop();
              _selectTab(0);
            },
            child: const Text('홈으로'),
          ),
        ),
      ),
    );
    if (start == true && mounted) {
      _selectTab(0);
      await _openEntry();
    }
  }

  Widget _emptyNavigationBar(BuildContext screen, {int selectedIndex = 2}) =>
      _bottomNavigationBar((tab) {
        final home = ModalRoute.of(context);
        final navigator = Navigator.of(screen);
        if (home == null) {
          navigator.pop();
        } else {
          navigator.popUntil((route) => identical(route, home));
        }
        _selectTab(tab);
      }, selectedIndex: selectedIndex);

  Future<void> _openComparison() => _push(
    ComparisonScreen(
      api: widget.api,
      emptyNavigationBar: _emptyNavigationBar,
      emptyNotification: _notification,
    ),
  );

  Widget _notification() => NotificationEntry(
    key: ValueKey(_inboxRevision),
    api: widget.api,
    compact: true,
    openTarget: _openNotificationTarget,
    inboxNavigationBar: _inboxNavigationBar,
  );

  Widget _inboxNavigationBar(BuildContext inbox) => _bottomNavigationBar((tab) {
    Navigator.of(inbox).pop();
    _selectTab(tab);
  });

  GuideDetail _guideDetail(String attemptId, String id, {int? revision}) =>
      GuideDetail(
        api: widget.api,
        attemptId: attemptId,
        id: id,
        revision: revision,
        navigationBar: _emptyNavigationBar,
        openList: (detail) => Navigator.of(detail).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => GuideScreen(
              api: widget.api,
              attemptId: revision == null ? attemptId : null,
              badgeName: diagnosisBadgeName,
              navigationBar: _emptyNavigationBar,
            ),
          ),
        ),
      );

  Future<void> _openNotificationTarget(
    BuildContext inbox,
    Map<String, dynamic> destination,
  ) async {
    final kind = destination['kind'];
    final resource = destination['resource'] as String?;
    final attemptId = destination['attemptId'] as String?;
    if (destination['available'] == false) {
      final message = kind == 'EXPORT'
          ? '파일이 삭제되었거나 보관 기간이 지났어요.'
          : '지금은 이 콘텐츠를 볼 수 없어요.';
      ScaffoldMessenger.of(
        inbox,
      ).showSnackBar(statusSnackBar(message, tone: StatusTone.warning));
    }
    final Widget? target = switch (kind) {
      'GUIDE' when resource != null && attemptId != null => _guideDetail(
        attemptId,
        resource,
      ),
      'GUIDE' => GuideScreen(
        api: widget.api,
        badgeName: diagnosisBadgeName,
        navigationBar: _emptyNavigationBar,
      ),
      'ECONOMY' => NewsScreen(api: widget.api, edition: resource),
      'EXPORT' => DataExportFlow(
        api: widget.api,
        exportId: resource,
        bottomNavigationBar: _emptyNavigationBar(inbox, selectedIndex: 3),
      ),
      _ => null,
    };
    await Navigator.of(inbox).push(
      MaterialPageRoute<void>(
        builder: (_) => target ?? _DiagnosisEntry(api: widget.api),
      ),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: switch (_tab) {
      1 => NewsScreen(
        api: widget.api,
        embedded: true,
        notification: _notification(),
        detailNavigationBar: (detail) => _bottomNavigationBar((tab) {
          if (tab == _tab) return;
          Navigator.of(detail).pop();
          _selectTab(tab);
        }),
      ),
      2 => _DiagnosisHistory(
        api: widget.api,
        onHome: () => _selectTab(0),
        notification: _notification(),
        onEmptyResult: _openEmptyResult,
        onDiagnosis: _openEntry,
        trendNavigationBar: _emptyNavigationBar,
        onReportTab: _selectTab,
        reportNavigationBar: _reportNavigationBar,
        widgetNavigationBar: _widgetNavigationBar,
      ),
      3 => AccountSettings(
        api: widget.api,
        notification: _notification(),
        securityNavigationBar: (accountPage) => _bottomNavigationBar((tab) {
          if (tab == _tab) return;
          final shell = ModalRoute.of(context);
          final navigator = Navigator.of(accountPage);
          if (shell == null) {
            navigator.pop();
          } else {
            navigator.popUntil((route) => identical(route, shell));
          }
          _selectTab(tab);
        }),
        onDataDeleted: () {
          _selectTab(0);
          _refresh();
        },
        embedded: true,
      ),
      _ => _home(context),
    },
    bottomNavigationBar: _bottomNavigationBar(_selectTab),
  );

  Widget _reportNavigationBar(ValueChanged<int> select) =>
      _bottomNavigationBar(select, selectedIndex: 2);

  Widget _widgetNavigationBar(BuildContext preview) =>
      _bottomNavigationBar((tab) {
        Navigator.of(preview).pop();
        _selectTab(tab);
      }, selectedIndex: 2);

  Widget _bottomNavigationBar(
    ValueChanged<int> onDestinationSelected, {
    int? selectedIndex,
  }) => NavigationBarTheme(
    data: NavigationBarThemeData(
      labelTextStyle: WidgetStatePropertyAll(
        FinsightTypography.labelR12.copyWith(color: FinsightColors.gray400),
      ),
    ),
    child: NavigationBar(
      backgroundColor: FinsightColors.gray1000,
      indicatorColor: Colors.transparent,
      selectedIndex: selectedIndex ?? _tab,
      onDestinationSelected: onDestinationSelected,
      height:
          57 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 24),
      destinations: [
        for (final (name, label, size) in const [
          ('home', '홈', 24.0),
          ('news', '뉴스', 20.0),
          ('records', '기록', 19.0),
          ('my', 'MY', 21.0),
        ])
          NavigationDestination(
            icon: _navigationIcon(name, 'off', size),
            selectedIcon: _navigationIcon(name, 'on', size),
            label: label,
          ),
      ],
    ),
  );

  Widget _navigationIcon(String name, String state, double size) =>
      SizedBox.square(
        dimension: 24,
        child: Center(
          child: Image.asset(
            'assets/navigation/$name-$state.png',
            width: size,
            height: size,
            excludeFromSemantics: true,
          ),
        ),
      );

  Widget _home(BuildContext context) {
    return _Page(
      title: 'FINSIGHT',
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleWidget: const FinsightWordmark(width: 98),
      actions: [_notification()],
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      scrolledUnderElevation: 0,
      children: [
        FutureBuilder(
          future: _latest,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const ContentSkeleton(
                label: '홈 정보 불러오는 중',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SkeletonLine(.22, fontSize: 12),
                    SizedBox(height: 8),
                    SkeletonLine(.62, fontSize: 22),
                    SizedBox(height: 24),
                    SkeletonBlock(height: 156, radius: 12),
                    SizedBox(height: 24),
                    SkeletonRows(showLeading: true),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              return _HomeLoadError(error: snapshot.error!, retry: _refresh);
            }
            final latest = snapshot.data;
            return latest == null
                ? _firstHome(context)
                : _completedHome(context, latest);
          },
        ),
      ],
    );
  }

  Widget _firstHome(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('반가워요!', style: _homeSupporting),
      const SizedBox(height: 4),
      const Text('첫 진단을 시작해볼까요?', style: FinsightTypography.displaySb22),
      const SizedBox(height: 24),
      _HomeCard(
        children: [
          Text(
            'WELCOME TO FINSIGHT',
            style: FinsightTypography.labelM12.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '내 금융 마음을\n처음 만나보는 약 5분',
            style: FinsightTypography.displaySb28,
          ),
          const SizedBox(height: 10),
          const Text(
            '지금 느끼는 금융 부담을 확인하고\n나에게 맞는 실천 정보를 받아보세요.',
            style: _homeSupporting,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openEntry, child: const Text('첫 자가진단 시작하기')),
        ],
      ),
      const SizedBox(height: 28),
      const _HomeHeading('이렇게 사용할 수 있어요'),
      _HomeStep(
        number: '①',
        label: '응답하기',
        description: '현재 상황과 느낌을 5점 척도로 답해요.',
        onTap: _openEntry,
      ),
      _HomeStep(
        number: '②',
        label: '내 결과 확인',
        description: '점수와 영역별 특징을 함께 살펴봐요.',
        onTap: _openEmptyResult,
      ),
      _HomeStep(
        number: '③',
        label: '가이드 받기',
        description: '부담이 큰 영역에서 시작할 행동을 알아봐요.',
        onTap: _openEmptyResult,
      ),
    ],
  );

  Widget _completedHome(BuildContext context, Map<String, dynamic> latest) {
    final primary = Theme.of(context).colorScheme.primary;
    final email = widget.email;
    final lastDiagnosis = DateTime.parse(
      latest['completedAt'] as String,
    ).toUtc().add(const Duration(hours: 9));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('안녕하세요', style: _homeSupporting),
        if (email != null) ...[
          const SizedBox(height: 4),
          Text(
            '${email.replaceAll('@', '@\u200B').replaceAll('.', '.\u200B')}님',
            style: FinsightTypography.displaySb22,
            semanticsLabel: '$email님',
          ),
        ],
        const SizedBox(height: 24),
        Semantics(
          label: '진단 결과 보기',
          child: _HomeCard(
            onTap: _openingResult ? null : () => _openResult(latest),
            children: [
              const Text('나의 금융 스트레스', style: _homeSupporting),
              const SizedBox(height: 18),
              Text.rich(
                TextSpan(
                  text: '${latest['score']}',
                  style: FinsightTypography.displaySb38.copyWith(
                    color: primary,
                  ),
                  children: const [
                    TextSpan(text: ' /100', style: _homeSupporting),
                  ],
                ),
                semanticsLabel: '${latest['score']}점, 100점 만점',
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: DiagnosisBadge(latest['representativeType']),
              ),
              const SizedBox(height: 12),
              Text(
                '마지막 진단 · ${lastDiagnosis.month}월 ${lastDiagnosis.day}일',
                style: _homeSupporting,
              ),
              StatusMessage(_resultError, reservedLines: 3),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _HomeLink(
          illustration: 'diagnosis',
          label: '자가진단 하기',
          description: '약 5분이면 충분해요',
          onTap: _openEntry,
        ),
        _HomeLink(
          illustration: 'guide',
          label: '맞춤 가이드 보기',
          description: '최근 진단 기반',
          onTap: () => _push(
            GuideScreen(
              api: widget.api,
              badgeName: diagnosisBadgeName,
              navigationBar: _emptyNavigationBar,
            ),
          ),
        ),
        _HomeLink(
          illustration: 'trend',
          label: '변화 추이 확인',
          description: '내 진단 기록 보기',
          onTap: () => _push(
            _DiagnosisHistory(
              api: widget.api,
              trend: true,
              onEmptyResult: _openEmptyResult,
              onDiagnosis: _openEntry,
              trendNavigationBar: _emptyNavigationBar,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const _HomeHeading('새로운 FINSIGHT'),
        _HomeTile(
          eyebrow: '오늘 아침 · 경제 한 장',
          label: '나에게 필요한 금융소식',
          description: '내 금융 상황에 맞춘 오늘의 읽을거리',
          onTap: () => _selectTab(1),
        ),
        const SizedBox(height: 8),
        _HomeTilePair(
          first: _HomeTile(
            icon: Icons.lightbulb_outline,
            label: '익명 인사이트',
            description: '비슷한 유형의 행동',
            onTap: () => _push(
              InsightScreen(
                api: widget.api,
                openDiagnosis: (_) => _openEntry(),
                openComparison: _openComparison,
                emptyNavigationBar: _emptyNavigationBar,
                emptyNotification: _notification,
              ),
            ),
          ),
          second: _HomeTile(
            icon: Icons.calendar_month_outlined,
            label: '월간 리포트',
            description: '한 달 기록 한눈에',
            onTap: () => _openMonthlyReport(
              context,
              widget.api,
              onTab: _selectTab,
              navigationBar: _reportNavigationBar,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const _HomeHeading('내 생활에 맞게 이어가기'),
        _HomeTilePair(
          first: _HomeTile(
            icon: Icons.group_outlined,
            label: '또래 비교',
            description: '또래의 금융 마음 살펴보기',
            onTap: _openComparison,
          ),
          second: _HomeTile(
            icon: Icons.widgets_outlined,
            label: '홈 위젯',
            description: '매일 만나는 금융 습관',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (preview) => HomeWidgetScreen(
                  api: widget.api,
                  openDiagnosis: _openEntry,
                  bottomNavigationBar: _widgetNavigationBar(preview),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeLoadError extends StatelessWidget {
  const _HomeLoadError({required this.error, required this.retry});
  final Object error;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    if (_isOffline(error)) return _ConnectionRetry(retry: retry);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StatusMessage('홈 정보를 불러오지 못했어요.'),
        FilledButton(onPressed: retry, child: const Text('다시 시도')),
      ],
    );
  }
}

bool _isOffline(Object error) =>
    error is DioException &&
    switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError => true,
      _ => false,
    };

class _ConnectionRetry extends StatelessWidget {
  const _ConnectionRetry({required this.retry, this.survey = false});
  final VoidCallback? retry;
  final bool survey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Image.asset(
        'assets/illustrations/connection-offline.png',
        height: 76,
        excludeFromSemantics: true,
      ),
      const SizedBox(height: 16),
      const Text(
        '인터넷 연결 오류',
        style: FinsightTypography.displaySb22,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        '네트워크 연결을 확인하고\n다시 시도해주세요.',
        textAlign: TextAlign.center,
        style: FinsightTypography.bodyR14.copyWith(
          color: FinsightColors.gray400,
        ),
      ),
      if (survey) ...[
        const SizedBox(height: 8),
        Text(
          '다시 시도할 때 입력한 답변이 유지돼요.',
          textAlign: TextAlign.center,
          style: FinsightTypography.labelR12.copyWith(
            color: FinsightColors.gray400,
          ),
        ),
      ],
      const SizedBox(height: 24),
      FilledButton(onPressed: retry, child: const Text('다시 시도')),
    ],
  );
}

const _homeSupporting = TextStyle(
  color: FinsightColors.gray400,
  fontSize: 12,
  height: 1.4,
);

class _HomeHeading extends StatelessWidget {
  const _HomeHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      header: true,
      child: Text(label, style: FinsightTypography.bodySb16),
    ),
  );
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.children, this.onTap});
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Material(
      color: FinsightColors.gray900,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: FinsightColors.gray800),
          gradient: LinearGradient(
            colors: [
              Color.alphaBlend(
                FinsightColors.primary.withValues(alpha: .07),
                FinsightColors.gray900,
              ),
              FinsightColors.gray900,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeStep extends StatelessWidget {
  const _HomeStep({
    required this.number,
    required this.label,
    required this.description,
    required this.onTap,
  });
  final String number;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _HomeTile(
      label: label,
      description: description,
      number: number,
      onTap: onTap,
    ),
  );
}

class _HomeLink extends StatelessWidget {
  const _HomeLink({
    required this.illustration,
    required this.label,
    required this.onTap,
    required this.description,
  });
  final String illustration;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: FinsightColors.gray900)),
    ),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 10,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: FinsightColors.neonLime900,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Image.asset(
            'assets/illustrations/home-$illustration.png',
            width: 30,
            height: 30,
            excludeFromSemantics: true,
          ),
        ),
      ),
      title: Text(label, style: FinsightTypography.bodySb14),
      subtitle: Text(description, style: _homeSupporting),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    ),
  );
}

class _HomeTilePair extends StatelessWidget {
  const _HomeTilePair({required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minimum = MediaQuery.textScalerOf(context).scale(140);
      final horizontal = constraints.maxWidth >= minimum * 2 + 8;
      return horizontal
          ? IntrinsicHeight(
              child: Row(
                spacing: 8,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: first),
                  Expanded(child: second),
                ],
              ),
            )
          : Column(
              spacing: 8,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, second],
            );
    },
  );
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.label,
    required this.description,
    required this.onTap,
    this.icon,
    this.eyebrow,
    this.number,
  });
  final String label;
  final String description;
  final VoidCallback onTap;
  final IconData? icon;
  final String? eyebrow;
  final String? number;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: FinsightColors.gray900,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon case final icon?) ...[
                      Icon(icon, size: 20, color: primary),
                      const SizedBox(height: 6),
                    ],
                    if (eyebrow case final eyebrow?) ...[
                      Text(
                        eyebrow,
                        style: FinsightTypography.labelM12.copyWith(
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (number case final number?) ...[
                          ExcludeSemantics(child: Text(number)),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            label,
                            style: FinsightTypography.bodySb14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(description, style: _homeSupporting),
                  ],
                ),
              ),
              if (eyebrow != null) const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiagnosisEntry extends StatefulWidget {
  const _DiagnosisEntry({required this.api, this.navigationBar});
  final AppApi api;
  final WidgetBuilder? navigationBar;

  @override
  State<_DiagnosisEntry> createState() => _DiagnosisEntryState();
}

class _DiagnosisEntryState extends State<_DiagnosisEntry>
    with WidgetsBindingObserver {
  final _journey = newRequestId();
  static const _experiments = '/api/v1/experiments';
  static const _screen = 'B_006';
  bool _busy = false;
  bool _exposurePending = false;
  bool _exposed = false;
  String? _experimentId;
  String? _variant;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.isCurrentOf(context) == true) {
        unawaited(_enter());
      }
    });
  }

  Future<void> _enter() async {
    try {
      await widget.api.request<void>(
        'POST',
        '$_attempts/journeys',
        data: {'journeyId': _journey},
      );
      if (!mounted || _busy || ModalRoute.isCurrentOf(context) != true) return;
      final response = await widget.api.request<Map<String, dynamic>>(
        'POST',
        '$_experiments/assign',
        data: {'screenId': _screen, 'journeyId': _journey},
      );
      if (!mounted || _busy || ModalRoute.isCurrentOf(context) != true) return;
      final assignment = response.data;
      final id = assignment?['experimentId'];
      final variant = assignment?['variantId'];
      if (id is String &&
          assignment?['screenId'] == _screen &&
          (variant == 'SUMMARY_FIRST' || variant == 'RESTART_FIRST')) {
        setState(() {
          _experimentId = id;
          _variant = variant as String;
        });
        _reportAfterFrame();
      }
    } on DioException {
      // Starting an attempt can register the same journey if this request fails.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _experimentId != null) {
      _reportAfterFrame();
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  void _reportAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _exposed || _exposurePending) return;
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed) return;
      if (ModalRoute.isCurrentOf(context) != true) return;
      final id = _experimentId;
      final variant = _variant;
      if (id != null && variant != null) {
        unawaited(_recordExposure(id, variant));
      }
    });
  }

  Future<void> _recordExposure(String id, String variant) async {
    _exposurePending = true;
    try {
      await widget.api.request<void>(
        'POST',
        '$_experiments/$id/exposure',
        data: {
          'screenId': _screen,
          'journeyId': _journey,
          'variantId': variant,
        },
      );
      _exposed = true;
    } on DioException {
      // The introduction and survey remain available if tracking fails.
    } finally {
      _exposurePending = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final catalog = await widget.api.request<Map<String, dynamic>>(
        'GET',
        '/api/v1/surveys/current',
      );
      final questions = (catalog.data!['questions'] as List)
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      final attempt = await widget.api.request<Map<String, dynamic>>(
        'POST',
        _attempts,
        data: {'journeyId': _journey},
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _Survey(
            api: widget.api,
            path: '$_attempts/${attempt.data!['id']}',
            questions: questions,
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } on DioException {
      _error = '진단을 시작하지 못했어요. 연결을 확인해주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('설문 형식', '5점 응답'),
      ('응답 기준', '각 문항에 표시된 기간'),
      ('문항 수', '30문항'),
    ];
    final summary = _DiagnosisPanel(
      children: [
        for (final (index, (label, value)) in rows.indexed) ...[
          if (index > 0)
            const Divider(height: 1, color: FinsightColors.gray800),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: FinsightTypography.bodySb14),
                ),
                Expanded(child: Text(value, textAlign: TextAlign.end)),
              ],
            ),
          ),
        ],
      ],
    );
    const instructions = _DiagnosisPanel(
      children: [
        Text('응답 전 확인해주세요', style: FinsightTypography.bodySb14),
        SizedBox(height: 10),
        Text('서두르지 않아도 괜찮아요. 모든 문항을 확인하고 응답을 마친 뒤 제출해주세요.'),
        Divider(height: 18, color: FinsightColors.gray800),
        Text('각 문항에 가장 가까운 답을 하나 선택해주세요.'),
        SizedBox(height: 6),
        Text('중단한 뒤에는 첫 문항부터 다시 시작해요.'),
      ],
    );
    return _SurveyPage(
      title: '진단',
      navigationBar: _busy ? null : widget.navigationBar?.call(context),
      children: [
        const SizedBox(height: 20),
        const Text(
          '나의 금융 스트레스를\n살펴볼까요?',
          style: FinsightTypography.displaySb28,
        ),
        const SizedBox(height: 8),
        const Text('각 문장을 읽고 현재 내 상황에 가장 가까운 답을 선택해주세요. 정답은 없어요.'),
        const SizedBox(height: 24),
        if (_variant == 'RESTART_FIRST') ...[
          instructions,
          const SizedBox(height: 8),
        ],
        summary,
        if (_variant != 'RESTART_FIRST') ...[
          const SizedBox(height: 8),
          instructions,
        ],
        const SizedBox(height: 12),
        Text(
          'SELF CHECK · 약 5분',
          style: FinsightTypography.labelM12.copyWith(
            color: FinsightColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        StatusMessage(_error, reservedLines: 3),
        FilledButton(
          onPressed: _busy ? null : _start,
          child: const Text('진단 시작하기'),
        ),
      ],
    );
  }
}

class _DiagnosisPanel extends StatelessWidget {
  const _DiagnosisPanel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: FinsightColors.gray900,
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

Future<void> _openMonthlyReport(
  BuildContext context,
  AppApi api, {
  bool fromHistory = false,
  ValueChanged<int>? onTab,
  Widget Function(ValueChanged<int>)? navigationBar,
}) async {
  final tab = await Navigator.of(context).push<int>(
    MaterialPageRoute<int>(
      builder: (reportContext) => MonthlyReportScreen(
        api: api,
        badgeName: diagnosisBadgeName,
        navigationBar: navigationBar,
        openHistory: () {
          if (onTab != null) {
            Navigator.of(reportContext).pop(2);
          } else if (fromHistory) {
            Navigator.of(reportContext).pop();
          } else {
            Navigator.of(reportContext).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => _DiagnosisHistory(api: api),
              ),
            );
          }
        },
      ),
    ),
  );
  if (tab == null || !context.mounted) return;
  if (onTab != null) {
    onTab(tab);
  } else if (tab == 0 && fromHistory) {
    Navigator.of(context).pop();
  }
}

class _DiagnosisHistory extends StatefulWidget {
  const _DiagnosisHistory({
    required this.api,
    this.trend = false,
    this.onHome,
    this.notification,
    this.onEmptyResult,
    this.onDiagnosis,
    this.trendNavigationBar,
    this.widgetNavigationBar,
    this.onReportTab,
    this.reportNavigationBar,
  });
  final VoidCallback? onHome;
  final Widget? notification;
  final VoidCallback? onEmptyResult;
  final Future<void> Function()? onDiagnosis;
  final WidgetBuilder? trendNavigationBar;
  final ValueChanged<int>? onReportTab;
  final Widget Function(ValueChanged<int>)? reportNavigationBar;
  final WidgetBuilder? widgetNavigationBar;
  final bool trend;
  final AppApi api;

  @override
  State<_DiagnosisHistory> createState() => _DiagnosisHistoryState();
}

class _DiagnosisHistoryState extends State<_DiagnosisHistory> {
  final _items = <Map<String, dynamic>>[];
  List<Map<String, dynamic>>? _daily;
  bool _busy = false;
  bool _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy || !_more) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final cursor = _items.lastOrNull;
    final path = cursor == null
        ? _attempts
        : Uri(
            path: _attempts,
            queryParameters: {
              'before': cursor['completedAt'] as String,
              'beforeId': cursor['id'] as String,
            },
          ).toString();
    try {
      if (widget.trend && _daily == null) {
        final response = await widget.api.request<List<dynamic>>(
          'GET',
          '$_attempts/trend',
        );
        if (!mounted) return;
        _daily = response.data!.cast<Map<String, dynamic>>();
      }
      final response = await widget.api.request<Map<String, dynamic>>(
        'GET',
        path,
      );
      if (!mounted) return;
      _items.addAll(
        (response.data!['items'] as List).cast<Map<String, dynamic>>(),
      );
      _more = response.data!['hasMore'] as bool;
    } on DioException {
      _error = '기록을 불러오지 못했어요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String attemptId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await widget.api.request<Map<String, dynamic>>(
        'GET',
        '$_attempts/$attemptId/result',
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _Result(
            api: widget.api,
            attemptId: attemptId,
            diagnosis: response.data!,
            backLabel: '진단 기록으로',
          ),
        ),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 404) {
        _items.removeWhere((item) => item['attemptId'] == attemptId);
        _error = '삭제되었거나 볼 수 없는 진단 결과예요.';
      } else {
        _error = '선택한 진단 결과를 불러오지 못했어요.';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(String value) {
    final kst = DateTime.parse(value).toUtc().add(const Duration(hours: 9));
    final day = kst.toIso8601String();
    return '${day.substring(0, 10)} ${day.substring(11, 16)}';
  }

  String _shortDate(String value) {
    final date = DateTime.parse(value).toUtc().add(const Duration(hours: 9));
    return '${date.month}월 ${date.day}일';
  }

  void _openTrend() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _DiagnosisHistory(
        api: widget.api,
        trend: true,
        onDiagnosis: widget.onDiagnosis,
        onEmptyResult: widget.onEmptyResult,
        trendNavigationBar: widget.trendNavigationBar,
      ),
    ),
  );

  void _openAllRecords() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _DiagnosisHistory(
        api: widget.api,
        onEmptyResult: widget.onEmptyResult,
        onDiagnosis: widget.onDiagnosis,
        trendNavigationBar: widget.trendNavigationBar,
        onReportTab: widget.onReportTab,
        reportNavigationBar: widget.reportNavigationBar,
        widgetNavigationBar: widget.widgetNavigationBar,
      ),
    ),
  );

  void _openReport() => _openMonthlyReport(
    context,
    widget.api,
    fromHistory: true,
    onTab: widget.onReportTab,
    navigationBar: widget.reportNavigationBar,
  );

  Widget _recordHome() {
    final latest = _items.firstOrNull;
    final change = _items.length > 1
        ? (_items.first['score'] as int) - (_items[1]['score'] as int)
        : null;
    return _Page(
      title: '기록',
      titleWidget: const FinsightWordmark(width: 98),
      centerTitle: false,
      childSpacing: 9,
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
      automaticallyImplyLeading: false,
      scrolledUnderElevation: 0,
      actions: [?widget.notification],
      children: [
        const Text('기록', style: FinsightTypography.displaySb28),
        const Text('내 금융 마음의 변화를 한눈에 확인해요', style: FinsightTypography.labelR12),
        if (latest != null) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FinsightColors.gray800),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF303519), FinsightColors.gray900],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '최근 진단 · ${_shortDate(latest['completedAt'] as String)}',
                    style: FinsightTypography.labelR12,
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${latest['score']}',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w600,
                            height: 1,
                            color: FinsightColors.primary,
                          ),
                        ),
                        const TextSpan(
                          text: ' /100',
                          style: FinsightTypography.bodyR14,
                        ),
                      ],
                    ),
                  ),
                  DiagnosisBadge(latest['representativeType'] as String),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      if (change != null)
                        Text(
                          '직전 진단 대비 ${reportScoreChange(change)}',
                          style: FinsightTypography.labelR12,
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _open(latest['attemptId'] as String),
                        child: const Text('최근 결과 자세히 보기 ›'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Text('금융 스트레스 변화', style: FinsightTypography.bodySb16),
          _RecordTrendPreview(items: _items),
          Material(
            color: FinsightColors.gray900,
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              leading: Image.asset(
                'assets/illustrations/home-trend.png',
                width: 32,
                excludeFromSemantics: true,
              ),
              title: const Text('변화 기록', style: FinsightTypography.bodySb14),
              subtitle: Text(
                change == null
                    ? '기록이 쌓이면 변화가 보여요'
                    : '최근 점수 변화 ${reportScoreChange(change)}',
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: _busy ? null : _openTrend,
            ),
          ),
          const Text('진단 기록', style: FinsightTypography.bodySb16),
          Material(
            color: FinsightColors.gray900,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                for (final (index, item) in _items.take(3).indexed) ...[
                  if (index > 0)
                    const Divider(height: 1, indent: 12, endIndent: 12),
                  ListTile(
                    dense: true,
                    title: Text(
                      _shortDate(item['completedAt'] as String),
                      style: FinsightTypography.bodySb14,
                    ),
                    subtitle: Text(
                      '${item['score']}점 · ${diagnosisBadgeName(item['representativeType'])}',
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: _busy
                        ? null
                        : () => _open(item['attemptId'] as String),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _openAllRecords,
            child: const Text('더보기'),
          ),
        ] else if (_busy) ...[
          const ContentSkeleton(
            label: '진단 기록 불러오는 중',
            child: Column(
              children: [
                SkeletonBlock(height: 112, radius: 8),
                SizedBox(height: 12),
                SkeletonBlock(height: 82, radius: 8),
                SizedBox(height: 12),
                SkeletonRows(count: 2),
              ],
            ),
          ),
        ] else if (_error == null) ...[
          const Text('진단 기록', style: FinsightTypography.bodySb16),
          const Text('아직 완료한 진단이 없어요.'),
          FilledButton(
            onPressed: widget.onEmptyResult,
            child: const Text('첫 진단 안내로'),
          ),
        ],
        Material(
          color: FinsightColors.gray900,
          borderRadius: BorderRadius.circular(8),
          child: ListTile(
            leading: const Icon(
              Icons.description_outlined,
              color: FinsightColors.primary,
            ),
            title: const Text('월간 리포트', style: FinsightTypography.labelM12),
            subtitle: const Text('이번 달 금융 마음의 변화를 확인해보세요'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _busy ? null : _openReport,
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _openWidgetPreview,
          child: const Text('위젯 추가하기'),
        ),
        if (_busy && latest != null) const LinearProgressIndicator(),
        StatusMessage(_error),
        if (_error != null && _more)
          TextButton(onPressed: _load, child: const Text('다시 불러오기')),
      ],
    );
  }

  Future<void> _diagnose() async {
    await widget.onDiagnosis?.call();
    if (!mounted) return;
    _items.clear();
    _daily = null;
    _more = true;
    await _load();
  }

  Future<void> _openWidgetPreview() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (preview) => HomeWidgetScreen(
          api: widget.api,
          bottomNavigationBar: widget.widgetNavigationBar?.call(preview),
          openDiagnosis: () => Navigator.of(preview).push<void>(
            MaterialPageRoute(builder: (_) => _DiagnosisEntry(api: widget.api)),
          ),
        ),
      ),
    );
    if (!mounted) return;
    _items.clear();
    _more = true;
    await _load();
  }

  @override
  Widget build(BuildContext context) => !widget.trend && widget.onHome != null
      ? _recordHome()
      : _Page(
          title: widget.trend ? '변화 기록' : '진단 기록',
          centerTitle: widget.trend ? true : null,
          scrolledUnderElevation: widget.trend ? 0 : null,
          bottomNavigationBar: widget.trend
              ? widget.trendNavigationBar?.call(context)
              : null,
          automaticallyImplyLeading: widget.onHome == null,
          children: [
            if (!widget.trend)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _openMonthlyReport(
                        context,
                        widget.api,
                        fromHistory: true,
                        onTab: widget.onReportTab,
                        navigationBar: widget.reportNavigationBar,
                      ),
                child: const Text('월간 리포트'),
              ),
            if (!widget.trend)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _DiagnosisHistory(
                            api: widget.api,
                            trend: true,
                            onDiagnosis: widget.onDiagnosis,
                            onEmptyResult: widget.onEmptyResult,
                            trendNavigationBar: widget.trendNavigationBar,
                          ),
                        ),
                      ),
                child: const Text('변화 기록'),
              ),
            if (!widget.trend)
              OutlinedButton(
                onPressed: _busy ? null : _openWidgetPreview,
                child: const Text('위젯 추가하기'),
              ),
            if (widget.trend && _daily?.isNotEmpty == true)
              _HistoryTrend(
                items: _daily!,
                change: _items.length > 1
                    ? (_items.first['score'] as int) -
                          (_items[1]['score'] as int)
                    : null,
              ),
            if (widget.trend && _items.isNotEmpty)
              const Text('진단 기록', style: FinsightTypography.bodySb16),
            if (!_busy && _items.isEmpty && _error == null) ...[
              const Text('아직 완료한 진단이 없어요.'),
              FilledButton(
                onPressed:
                    widget.onEmptyResult ?? () => Navigator.of(context).pop(),
                child: const Text('첫 진단 안내로'),
              ),
            ],
            for (final item in _items)
              ListTile(
                title: Text(
                  '${item['score']}점 · ${diagnosisBadgeName(item['representativeType'])}',
                ),
                subtitle: Text(_date(item['completedAt'] as String)),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_busy,
                onTap: () => _open(item['attemptId'] as String),
              ),
            if (widget.trend && _items.isNotEmpty && widget.onDiagnosis != null)
              TextButton(
                onPressed: _busy ? null : _diagnose,
                child: const Text('다시 진단하기'),
              ),
            if (_busy)
              _items.isEmpty
                  ? const ContentSkeleton(
                      label: '진단 기록 불러오는 중',
                      child: SkeletonRows(),
                    )
                  : const LinearProgressIndicator(),
            StatusMessage(_error, reservedLines: 3),
            if (!_busy && _more)
              OutlinedButton(
                onPressed: _load,
                child: Text(_items.isEmpty ? '다시 불러오기' : '기록 더 보기'),
              ),
          ],
        );
}

class _RecordTrendPreview extends StatelessWidget {
  const _RecordTrendPreview({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    final months = [
      for (var i = 3; i >= 0; i--) DateTime.utc(now.year, now.month - i),
    ];
    final scores = <DateTime, int>{};
    for (final item in items) {
      final date = DateTime.parse(
        item['completedAt'] as String,
      ).toUtc().add(const Duration(hours: 9));
      scores.putIfAbsent(
        DateTime.utc(date.year, date.month),
        () => item['score'] as int,
      );
    }
    final values = [for (final month in months) scores[month]];
    return _DiagnosisPanel(
      children: [
        const Align(
          alignment: Alignment.centerRight,
          child: Text('최근 4개월', style: FinsightTypography.labelR12),
        ),
        Semantics(
          label: [
            for (final (i, month) in months.indexed)
              '${month.month}월 ${values[i] == null ? '기록 없음' : '${values[i]}점'}',
          ].join(', '),
          child: ExcludeSemantics(
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: CustomPaint(painter: _RecordTrendLine(values)),
            ),
          ),
        ),
        Row(
          children: [
            for (final month in months)
              Expanded(
                child: Text(
                  '${month.month}월',
                  textAlign: TextAlign.center,
                  style: FinsightTypography.captionR10,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecordTrendLine extends CustomPainter {
  const _RecordTrendLine(this.values);

  final List<int?> values;

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      for (final (i, value) in values.indexed)
        if (value != null)
          (
            Offset(
              size.width * (i + .5) / values.length,
              17 + (1 - value / 100) * (size.height - 22),
            ),
            value,
          ),
    ];
    canvas.drawLine(
      Offset(0, size.height - 2),
      Offset(size.width, size.height - 2),
      Paint()..color = FinsightColors.gray750,
    );
    for (final (index, (point, score)) in points.indexed) {
      final isLatest = index == points.length - 1;
      final color = isLatest ? FinsightColors.primary : FinsightColors.gray400;
      if (index > 0) {
        canvas.drawLine(
          points[index - 1].$1,
          point,
          Paint()
            ..color = color
            ..strokeWidth = 1.5,
        );
      }
      canvas.drawCircle(point, 3.5, Paint()..color = color);
      final text = TextPainter(
        text: TextSpan(
          text: '$score',
          style: FinsightTypography.labelM12.copyWith(color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, point - Offset(text.width / 2, text.height + 4));
    }
  }

  @override
  bool shouldRepaint(_RecordTrendLine oldDelegate) =>
      !listEquals(values, oldDelegate.values);
}

class _HistoryTrend extends StatefulWidget {
  const _HistoryTrend({required this.items, required this.change});
  final List<Map<String, dynamic>> items;
  final int? change;

  @override
  State<_HistoryTrend> createState() => _HistoryTrendState();
}

class _HistoryTrendState extends State<_HistoryTrend> {
  DateTime? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    final points = widget.items.reversed
        .map(
          (item) => (
            DateTime.parse(
              item['completedAt'] as String,
            ).toUtc().add(const Duration(hours: 9)),
            item['score'] as int,
          ),
        )
        .toList();
    final lastPerMonth = <DateTime, int>{
      for (final (date, score) in points)
        DateTime.utc(date.year, date.month): score,
    };
    final months = [
      for (var i = 5; i >= 0; i--) DateTime.utc(now.year, now.month - i),
    ];
    final selected =
        _selectedMonth ??
        months.lastWhere(lastPerMonth.containsKey, orElse: () => months.last);
    final monthPoints = points
        .where(
          (point) =>
              point.$1.year == selected.year &&
              point.$1.month == selected.month,
        )
        .toList();

    return _DiagnosisPanel(
      children: [
        const Text('금융 스트레스 추이', style: FinsightTypography.bodySb16),
        const SizedBox(height: 8),
        const Text('최근 6개월 · 월별 마지막 기록', style: FinsightTypography.labelR12),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final month in months)
              Expanded(
                child: Semantics(
                  label:
                      '${month.year}년 ${month.month}월 · ${lastPerMonth[month] == null ? '기록 없음' : '${lastPerMonth[month]}점'}',
                  button: true,
                  selected: selected == month,
                  child: InkWell(
                    onTap: () => setState(() => _selectedMonth = month),
                    child: ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 65,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: double.infinity,
                                  height: lastPerMonth[month] == null
                                      ? 2
                                      : (lastPerMonth[month]! * 0.63)
                                            .clamp(4, 65)
                                            .toDouble(),
                                  decoration: BoxDecoration(
                                    color: selected == month
                                        ? FinsightColors.primary
                                        : FinsightColors.gray750,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${month.month}월',
                              textAlign: TextAlign.center,
                              style: FinsightTypography.labelR12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.change case final change?)
          Text('직전 진단 대비 ${change > 0 ? '+' : ''}$change점'),
        if (monthPoints.isEmpty)
          const Text('이 달에는 완료한 진단이 없어요.')
        else ...[
          Text(
            '${selected.month}월 · 일별 마지막 진단',
            style: FinsightTypography.labelM12,
          ),
          if (monthPoints.length > 1)
            ExcludeSemantics(
              child: SizedBox(
                height: 86,
                child: CustomPaint(
                  painter: _TrendLine(monthPoints, FinsightColors.primary),
                ),
              ),
            ),
          for (final (date, score) in monthPoints)
            Text(
              '${date.month}월 ${date.day}일 · $score점',
              style: FinsightTypography.labelR12,
            ),
        ],
      ],
    );
  }
}

class _TrendLine extends CustomPainter {
  const _TrendLine(this.points, this.color);
  final List<(DateTime, int)> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final span = points.last.$1.difference(points.first.$1).inMilliseconds;
    const inset = 5.0;
    final line = Path();
    final offsets = <Offset>[];
    for (final (date, score) in points) {
      final x =
          inset +
          date.difference(points.first.$1).inMilliseconds /
              (span == 0 ? 1 : span) *
              (size.width - inset * 2);
      final y = inset + (1 - score / 100) * (size.height - inset * 2);
      if (offsets.isEmpty) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
      offsets.add(Offset(x, y));
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    for (final offset in offsets) {
      canvas.drawCircle(offset, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendLine oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

class _Survey extends StatefulWidget {
  const _Survey({
    required this.api,
    required this.path,
    required this.questions,
  });
  final AppApi api;
  final String path;
  final List<Map<String, dynamic>> questions;

  @override
  State<_Survey> createState() => _SurveyState();
}

class _SurveyState extends State<_Survey> with WidgetsBindingObserver {
  late final _answers = List<int?>.filled(widget.questions.length, null);
  int _index = 0;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;
  bool _showResult = false;
  bool _analyzing = false;
  bool _retryingSubmission = false;

  final _questionClock = Stopwatch();
  late final _elapsed = List<int>.filled(widget.questions.length, 0);
  Future<void> _telemetry = Future.value();
  bool _visibleQuestion = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _trackView();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_visibleQuestion) {
        _resumeClock();
      } else if (_result == null) {
        _trackView();
      }
    } else {
      _questionClock.stop();
    }
  }

  void _resumeClock() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_busy &&
        !_retryingSubmission &&
        !_confirming &&
        _visibleQuestion &&
        _result == null &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        ModalRoute.isCurrentOf(context) == true) {
      _questionClock.start();
    }
  }

  void _trackView() {
    _visibleQuestion = false;
    final question = _index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _visibleQuestion ||
          _index != question ||
          _result != null) {
        return;
      }
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if ((lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          ModalRoute.isCurrentOf(context) != true) {
        return;
      }
      _visibleQuestion = true;
      _event('VIEWED', question + 1);
      _resumeClock();
    });
  }

  void _event(String kind, int question, {int? activeMs}) {
    final payload = {
      'eventId': newRequestId(),
      'kind': kind,
      'questionNo': question,
      'activeMs': ?activeMs,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
    };
    final api = widget.api;
    final path = '${widget.path}/question-events';
    _telemetry = _telemetry.then((_) async {
      try {
        await api.request<void>('POST', path, data: payload);
      } on DioException {
        // Analytics must not block survey completion.
      }
    });
  }

  void _saveElapsed() {
    _questionClock.stop();
    _elapsed[_index] += _questionClock.elapsedMilliseconds;
    _questionClock.reset();
  }

  void _finishQuestion() {
    _saveElapsed();
    _event('COMPLETED', _index + 1, activeMs: _elapsed[_index]);
    _elapsed[_index] = 0;
  }

  void _advance() {
    _finishQuestion();
    setState(() {
      _index++;
      _error = null;
    });
    _trackView();
  }

  void _previous() {
    _saveElapsed();
    setState(() {
      _index--;
      _error = null;
    });
    _trackView();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<bool> _confirm(String title, String body, String action) async {
    if (_confirming) return false;
    _confirming = true;
    _questionClock.stop();
    final confirmed =
        await showDialog<bool>(
          context: context,
          animationStyle: AnimationStyle.noAnimation,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('계속하기'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
    _confirming = false;
    if (!confirmed && mounted) _resumeClock();
    return confirmed;
  }

  Future<void> _abort() async {
    if (_busy || _confirming) return;
    _confirming = true;
    _questionClock.stop();
    final leave = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (confirmation) => _SurveyStatus(
          progress: _progress,
          image: 'survey-pause',
          heading: '진단을 그만둘까요?',
          description: '지금까지 응답은 저장되지 않아요. 다시 시작하면 첫 문항부터 답해야 해요.',
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(confirmation).pop(false),
              child: const Text('계속하기'),
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(
              style: _surveySecondaryButtonStyle,
              onPressed: () => Navigator.of(confirmation).pop(true),
              child: const Text('나가기'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    _confirming = false;
    if (leave != true) {
      _resumeClock();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.request<void>(
        'POST',
        '${widget.path}/abort',
        data: {'lastQuestion': _index + 1},
      );
      if (mounted) Navigator.of(context).pop();
    } on DioException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '중단 요청을 저장하지 못했어요. 다시 시도해주세요.';
        });
        _resumeClock();
      }
    }
  }

  Future<void> _submit() async {
    if (!await _confirm('답변을 제출할까요?', '제출 후 진단 결과를 확인할 수 있어요.', '제출하기') ||
        !mounted) {
      return;
    }
    await _sendAnswers();
  }

  Future<void> _sendAnswers({bool checkResult = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _analyzing = true;
      _error = null;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      Map<String, dynamic>? completed;
      if (checkResult) {
        try {
          completed = (await widget.api.request<Map<String, dynamic>>(
            'GET',
            '${widget.path}/result',
          )).data;
        } on DioException catch (error) {
          if (error.response?.statusCode != 404) rethrow;
        }
      }
      if (!mounted) return;
      completed ??= (await widget.api.request<Map<String, dynamic>>(
        'POST',
        '${widget.path}/submit',
        data: {'answers': _answers},
      )).data!;
      if (!mounted) return;
      _finishQuestion();
      _result = completed;
      unawaited(refreshHomeWidget(widget.api));
    } on DioException catch (error) {
      _retryingSubmission = _isOffline(error);
      if (!_retryingSubmission) {
        _error = '결과를 불러오지 못했어요. 답변은 유지되니 다시 제출해주세요.';
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _analyzing = false;
        });
        _resumeClock();
      }
    }
  }

  Future<void> _leavePendingSubmission() async {
    if (_busy) return;
    final leave = await _confirm(
      '제출 확인을 나갈까요?',
      '연결이 끊기기 전에 제출이 완료됐을 수도 있어요. 진단 기록에서 결과를 확인할 수 있어요.',
      '나가기',
    );
    if (leave && mounted) Navigator.of(context).pop();
  }

  double get _progress => (_index + 1) / _answers.length;

  @override
  Widget build(BuildContext context) {
    if (_analyzing) {
      return const PopScope(
        canPop: false,
        child: _SurveyStatus(
          progress: 1,
          image: null,
          heading: '나의 금융 스트레스를\n분석하고 있어요',
          description: '잠시만 기다려주세요',
          actions: [],
        ),
      );
    }
    if (_result case final result?) {
      if (_showResult) {
        return _Result(
          api: widget.api,
          attemptId: widget.path.split('/').last,
          diagnosis: result,
        );
      }
      return _SurveyStatus(
        progress: 1,
        image: 'survey-complete',
        heading: '분석이 완료되었어요',
        description: '지금 바로 결과를 확인해보세요',
        actions: [
          FilledButton(
            onPressed: () => setState(() => _showResult = true),
            child: const Text('결과 확인하기'),
          ),
        ],
      );
    }
    if (_retryingSubmission) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leavePendingSubmission();
        },
        child: _Page(
          title: '',
          leading: IconButton(
            tooltip: '제출 확인 나가기',
            onPressed: _busy ? null : _leavePendingSubmission,
            icon: const Icon(Icons.arrow_back),
          ),
          children: [
            const SizedBox(height: 92),
            _ConnectionRetry(
              retry: _busy ? null : () => _sendAnswers(checkResult: true),
              survey: true,
            ),
          ],
        ),
      );
    }
    final question = widget.questions[_index];
    final options = (question['options'] as List).cast<Map<String, dynamic>>();
    final last = _index == _answers.length - 1;
    final number = _index + 1;
    final (section, area) = switch (number) {
      <= 3 => ('Ⅰ. 외부적 금융 압박', '부채 부담'),
      <= 6 => ('Ⅰ. 외부적 금융 압박', '소득 불안'),
      <= 9 => ('Ⅰ. 외부적 금융 압박', '비상자금'),
      <= 12 => ('Ⅰ. 외부적 금융 압박', '고정비 압박'),
      <= 15 => ('Ⅰ. 외부적 금융 압박', '미래 불안'),
      <= 17 => ('Ⅰ. 외부적 금융 압박', '부양 부담'),
      <= 20 => ('Ⅱ. 대응자원', '금융이해'),
      <= 23 => ('Ⅱ. 대응자원', '재무관리'),
      <= 26 => ('Ⅱ. 대응자원', '자기효능감'),
      <= 29 => ('Ⅲ. 체감 금융 스트레스', '체감 스트레스'),
      _ => ('Ⅲ. 체감 금융 스트레스', '전반적 스트레스'),
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _abort();
      },
      child: _SurveyPage(
        title: '나의 금융 마음 진단',
        progress: _progress,
        leading: IconButton(
          tooltip: '설문 나가기',
          onPressed: _busy ? null : _abort,
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        ),
        bodyKey: ValueKey(number),
        footer: Row(
          children: [
            Expanded(
              child: FilledButton.tonal(
                style: _surveySecondaryButtonStyle,
                onPressed: _busy
                    ? null
                    : _index == 0
                    ? _abort
                    : _previous,
                child: const Text('이전'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _busy || _answers[_index] == null
                    ? null
                    : last
                    ? _submit
                    : _advance,
                child: Text(last ? '제출' : '다음으로'),
              ),
            ),
          ],
        ),
        children: [
          const SizedBox(height: 16),
          Text(section, style: FinsightTypography.labelM12),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: FinsightColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                child: Text(
                  area,
                  style: FinsightTypography.labelM12.copyWith(
                    color: FinsightColors.gray1000,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Q${number.toString().padLeft(2, '0')} / ${_answers.length}',
            style: FinsightTypography.labelR12,
          ),
          const SizedBox(height: 8),
          Text(
            question['text'] as String,
            style: FinsightTypography.displaySb22,
          ),
          const SizedBox(height: 20),
          Text(
            last ? '전반적인 스트레스는 어느 정도인가요?' : '어느 정도인가요?',
            style: FinsightTypography.bodySb14,
          ),
          const SizedBox(height: 8),
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SurveyChoice(
                value: option['value'] as int,
                label: option['label'] as String,
                selected: _answers[_index] == option['value'],
                onSelected: _busy
                    ? null
                    : (_) => setState(() {
                        _answers[_index] = option['value'] as int;
                      }),
              ),
            ),
          StatusMessage(_error),
        ],
      ),
    );
  }
}

final _surveySecondaryButtonStyle = FilledButton.styleFrom(
  backgroundColor: FinsightColors.gray900,
  foregroundColor: FinsightColors.gray300,
);

class _SurveyChoice extends StatelessWidget {
  const _SurveyChoice({
    required this.value,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final int value;
  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    selected: selected,
    onSelected: onSelected,
    showCheckmark: false,
    backgroundColor: FinsightColors.gray900,
    selectedColor: FinsightColors.neonLime900.withValues(alpha: 0.32),
    side: BorderSide(
      color: selected ? FinsightColors.primary : FinsightColors.gray800,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    label: Row(
      children: [
        ExcludeSemantics(
          child: CircleAvatar(
            radius: 14,
            backgroundColor: selected
                ? FinsightColors.primary
                : FinsightColors.gray800,
            foregroundColor: selected
                ? FinsightColors.gray1000
                : FinsightColors.white,
            child: FittedBox(
              child: Text('$value', style: FinsightTypography.labelM12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: FinsightTypography.bodyR16.copyWith(
              color: onSelected == null
                  ? FinsightColors.gray600
                  : selected
                  ? FinsightColors.white
                  : FinsightColors.gray300,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 20,
          color: selected ? FinsightColors.primary : FinsightColors.gray600,
        ),
      ],
    ),
  );
}

class _SurveyStatus extends StatelessWidget {
  const _SurveyStatus({
    required this.progress,
    required this.image,
    required this.heading,
    required this.description,
    required this.actions,
  });

  final double progress;
  final String? image;
  final String heading;
  final String description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => _SurveyPage(
    title: '진단 종료 확인',
    progress: progress,
    leading: image == null ? const SizedBox.shrink() : null,
    children: [
      SizedBox(
        height: (MediaQuery.sizeOf(context).height * .105).clamp(24.0, 90.0),
      ),
      if (image case final asset?)
        Image.asset(
          'assets/illustrations/$asset.png',
          height: 150,
          excludeFromSemantics: true,
        )
      else
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: SizedBox.square(
              dimension: 94,
              child: CircularProgressIndicator(
                strokeWidth: 6,
                trackGap: 0,
                backgroundColor: FinsightColors.gray800,
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
      Text(
        heading,
        textAlign: TextAlign.center,
        style: FinsightTypography.displaySb22,
      ),
      const SizedBox(height: 10),
      Text(description, textAlign: TextAlign.center),
      if (actions.isNotEmpty) const SizedBox(height: 20),
      ...actions,
    ],
  );
}

class _SurveyPage extends StatelessWidget {
  const _SurveyPage({
    required this.title,
    required this.children,
    this.progress,
    this.leading,
    this.footer,
    this.navigationBar,
    this.bodyKey,
  });

  final String title;
  final List<Widget> children;
  final double? progress;
  final Widget? leading;
  final Widget? footer;
  final Widget? navigationBar;
  final Key? bodyKey;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      scrolledUnderElevation: 0,
      leading: leading,
      toolbarHeight: (MediaQuery.textScalerOf(context).scale(16) * 2.8 + 12)
          .clamp(kToolbarHeight, double.infinity),
      title: Text(
        title,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: FinsightTypography.bodySb16,
      ),
    ),
    bottomNavigationBar: navigationBar,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              if (progress case final amount?)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TweenAnimationBuilder<double>(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    tween: Tween(end: amount),
                    curve: Curves.easeOut,
                    builder: (_, value, _) => LinearProgressIndicator(
                      value: value,
                      semanticsValue: '${(amount * 100).round()}%',
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(5),
                      backgroundColor: FinsightColors.gray800,
                      trackGap: 0,
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  key: bodyKey,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  children: children,
                ),
              ),
              if (footer case final buttons?)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: buttons,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Result extends StatelessWidget {
  const _Result({
    required this.api,
    required this.diagnosis,
    required this.attemptId,
    this.backLabel = '자가진단 홈으로',
  });
  final AppApi api;
  final String attemptId;
  final Map<String, dynamic> diagnosis;
  final String backLabel;

  static int _score(Map<String, dynamic> raw) {
    final numerator = raw['numerator'] as int;
    final denominator = raw['denominator'] as int;
    return (2 * numerator + denominator) ~/ (2 * denominator);
  }

  static int? _aggregate(List<Map<String, dynamic>> areas) {
    if (areas.isEmpty) return null;
    var numerator = 0;
    var denominator = 0;
    for (final area in areas) {
      final raw = area['score'] as Map<String, dynamic>;
      numerator += raw['numerator'] as int;
      denominator += raw['denominator'] as int;
    }
    return (2 * numerator + denominator) ~/ (2 * denominator);
  }

  List<Widget> _areas(
    Iterable<Map<String, dynamic>> items,
    String key,
    Color color,
  ) => [
    for (final area in items)
      _DiagnosisMeter(
        label: comparisonMetricLabels[area[key]] ?? '영역',
        score: _score(area['score'] as Map<String, dynamic>),
        color: color,
        inline: true,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final result = diagnosis['result'] as Map<String, dynamic>;
    final score = _score(result['total'] as Map<String, dynamic>);
    final pressures = (result['rankedPressures'] as List)
        .cast<Map<String, dynamic>>();
    final resources = (result['resources'] as List)
        .cast<Map<String, dynamic>>();
    final external = _aggregate(pressures);
    final response = _aggregate(resources);
    final allLow =
        pressures.isNotEmpty &&
        pressures.every(
          (area) => (area['score'] as Map<String, dynamic>)['numerator'] == 0,
        );
    final completed = DateTime.tryParse(
      diagnosis['completedAt'] as String? ?? '',
    )?.toUtc().add(const Duration(hours: 9));
    final theme = Theme.of(context);
    return RenderedDiagnosisView(
      api: api,
      attemptId: attemptId,
      child: _Page(
        title: '진단 결과',
        centerTitle: true,
        scrolledUnderElevation: 0,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FinsightColors.gray800),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF292D1A), FinsightColors.gray900],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (completed != null)
                    Text(
                      '진단일 · ${completed.year}.${completed.month}.${completed.day}',
                      style: theme.textTheme.labelMedium,
                    ),
                  const SizedBox(height: 10),
                  Semantics(
                    label: '금융 스트레스 점수 $score점',
                    excludeSemantics: true,
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '$score',
                          style: FinsightTypography.displaySb38.copyWith(
                            fontSize: 76,
                            height: 1.1,
                            color: FinsightColors.primary,
                          ),
                        ),
                        Text('/ 100', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  DiagnosisBadge(result['representativeType']),
                  const SizedBox(height: 10),
                  const Text('점수가 높을수록 금융 부담과 대응자원 부족이 커요.'),
                  if (result['formulaVersion'] case final String version)
                    Text('산식 버전 $version', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ),
          if (external != null || response != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '어디서 스트레스를 받고 있나요',
                  style: FinsightTypography.bodySb16,
                ),
                if (external != null)
                  _DiagnosisMeter(
                    label: '외부 금융 압박',
                    score: external,
                    color: const Color(0xFFFD69FD),
                  ),
                if (response != null)
                  _DiagnosisMeter(
                    label: '나의 금융 대응력',
                    score: response,
                    color: const Color(0xFFFD69FD),
                  ),
              ],
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('외부 금융 압박 TOP3', style: FinsightTypography.bodySb16),
              ..._areas(
                pressures.take(allLow ? 1 : 3),
                'pressure',
                FinsightColors.orange400,
              ),
              if (allLow)
                const Text('외부 부담 6개 영역이 모두 낮아요. 동점 기준으로 부채부담형을 표시해요.'),
            ],
          ),
          _DiagnosisPanel(
            children: [
              ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: true,
                title: const Text('외부 부담 6개 영역'),
                children: _areas(pressures, 'pressure', FinsightColors.primary),
              ),
            ],
          ),
          _DiagnosisPanel(
            children: [
              ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: true,
                title: const Text('개인 금융 대응자원'),
                subtitle: const Text('점수가 높을수록 대응자원이 충분해요.'),
                children: _areas(
                  resources,
                  'resource',
                  FinsightColors.green300,
                ),
              ),
            ],
          ),
          _DiagnosisMeter(
            label: '체감 금융 스트레스',
            score: _score(result['perceivedStress'] as Map<String, dynamic>),
            color: FinsightColors.red400,
          ),
          _DiagnosisPanel(
            children: [
              const Text(
                '전반적으로 느끼는 금융 스트레스',
                style: FinsightTypography.bodySb16,
              ),
              Text(
                '${result['overallStress']}',
                style: FinsightTypography.titleSb18,
              ),
              const Text('참고 응답 · YFSI 점수에는 포함되지 않아요.'),
            ],
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GuideScreen(
                  api: api,
                  badgeName: diagnosisBadgeName,
                  attemptId: attemptId,
                ),
              ),
            ),
            child: const Text('내 맞춤 가이드 보기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(backLabel),
          ),
        ],
      ),
    );
  }
}

class _DiagnosisMeter extends StatelessWidget {
  const _DiagnosisMeter({
    required this.label,
    required this.score,
    required this.color,
    this.inline = false,
  });
  final String label;
  final int score;
  final Color color;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final track = ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 400),
        tween: Tween(begin: 0, end: score / 100),
        builder: (_, value, _) => LinearProgressIndicator(
          value: value,
          color: color,
          backgroundColor: FinsightColors.gray750,
          minHeight: 5,
          borderRadius: BorderRadius.circular(5),
          trackGap: 0,
        ),
      ),
    );
    final name = Text(label, style: FinsightTypography.bodyR14);
    final value = Text(
      '$score점',
      style: FinsightTypography.bodySb14.copyWith(color: color),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final inlineTrack = inline && constraints.maxWidth >= 270 * scale;
          final labels = Row(
            children: [
              Expanded(child: name),
              const SizedBox(width: 8),
              if (inlineTrack) ...[
                Expanded(child: track),
                const SizedBox(width: 8),
              ],
              value,
            ],
          );
          if (inlineTrack) return labels;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [labels, const SizedBox(height: 5), track],
          );
        },
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.children,
    this.leading,
    this.titleWidget,
    this.actions,
    this.centerTitle,
    this.automaticallyImplyLeading = true,
    this.contentPadding = const EdgeInsets.all(24),
    this.scrolledUnderElevation,
    this.bottomNavigationBar,
    this.childSpacing = 16,
  });
  final Widget? titleWidget;
  final List<Widget>? actions;
  final bool? centerTitle;
  final bool automaticallyImplyLeading;
  final String title;
  final List<Widget> children;
  final Widget? leading;
  final EdgeInsets contentPadding;
  final double? scrolledUnderElevation;
  final Widget? bottomNavigationBar;
  final double childSpacing;

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: bottomNavigationBar,
    appBar: AppBar(
      title: titleWidget ?? Text(title),
      leading: leading,
      actions: actions,
      centerTitle: centerTitle,
      scrolledUnderElevation: scrolledUnderElevation,
      automaticallyImplyLeading: automaticallyImplyLeading,
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: contentPadding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in children)
                  Padding(
                    padding: EdgeInsets.only(bottom: childSpacing),
                    child: child,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

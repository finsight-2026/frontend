import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../account/app_api.dart';
import '../content/content_exposure.dart';
import '../design/content_skeleton.dart';
import '../design/status_message.dart';
import '../design/finsight_wordmark.dart';
import '../design/tokens.dart';
import '../shared/request_id.dart';
import 'news_article_image.dart';

const _path = '/api/v1/news';

class NewsScreen extends StatefulWidget {
  const NewsScreen({
    required this.api,
    this.edition,
    this.embedded = false,
    this.notification,
    this.detailNavigationBar,
    super.key,
  });
  final AppApi api;
  final String? edition;
  final bool embedded;
  final Widget? notification;
  final WidgetBuilder? detailNavigationBar;

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  late var _feed = _load();
  final _viewSession = newRequestId();

  late String? _edition = widget.edition;
  bool _missingEdition = false;

  Future<Response<Map<String, dynamic>>> _load() async {
    if (_edition case final edition?) {
      try {
        return await widget.api.request<Map<String, dynamic>>(
          'GET',
          Uri(path: _path, queryParameters: {'edition': edition}).toString(),
        );
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) rethrow;
        _edition = null;
        _missingEdition = true;
      }
    }
    return widget.api.request<Map<String, dynamic>>('GET', _path);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _feed = next;
    });
    try {
      await next;
    } on DioException {
      // FutureBuilder displays the failure with a retry action.
    }
  }

  Future<void> _openArticle(Map<String, dynamic> article) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NewsDetail(
          api: widget.api,
          id: article['id'] as String,
          edition: article['editionDate'] as String?,
          revision: article['revision'] as int?,
          fromFeed: true,
          navigationBar: widget.detailNavigationBar,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => _NewsPage(
    title: const FinsightWordmark(),
    centerTitle: false,
    automaticallyImplyLeading: !widget.embedded,
    actions: [?widget.notification],
    child: FutureBuilder(
      future: _feed,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const StatusMessage('뉴스를 불러오지 못했어요.'),
              TextButton(onPressed: _refresh, child: const Text('다시 시도')),
            ],
          );
        }
        if (!snapshot.hasData) {
          return const _NewsSkeleton();
        }
        final feed = snapshot.data!.data!;
        final articles = (feed['articles'] as List)
            .cast<Map<String, dynamic>>();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              const _NewsEyebrow('MORNING BRIEF · 오전 8시'),
              const SizedBox(height: 8),
              Semantics(
                header: true,
                label: '경제 뉴스',
                child: const Text(
                  '오늘의 경제,\n한 장으로 가볍게',
                  style: FinsightTypography.displaySb22,
                ),
              ),
              const SizedBox(height: 8),
              const Text('내 생활에 연결되는 경제 뉴스를 읽어보세요.', style: _supportingText),
              const SizedBox(height: 24),
              if (_edition case final date?) Text('$date 편성'),
              if (_missingEdition) const Text('알림에 연결된 뉴스가 비공개되었거나 삭제되었어요.'),
              if (feed['preparing'] == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: StatusMessage.notice(
                    articles.isEmpty
                        ? '오늘의 뉴스를 준비하고 있어요.'
                        : '오늘의 뉴스를 준비 중이에요. 이전 편성 기사를 볼 수 있어요.',
                  ),
                ),
              for (final (index, article) in articles.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ContentExposure(
                    key: ValueKey((article['id'], article['revision'])),
                    onVisible: () => _newsEvent(
                      widget.api,
                      article,
                      viewSession: _viewSession,
                    ),
                    child: _ArticleCard(
                      api: widget.api,
                      article: article,
                      featured: index == 0,
                      open: () => _openArticle(article),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class NewsDetail extends StatefulWidget {
  const NewsDetail({
    required this.api,
    required this.id,
    this.edition,
    this.revision,
    this.fromFeed = false,
    this.navigationBar,
    super.key,
  });
  final AppApi api;
  final String id;
  final String? edition;
  final int? revision;
  final bool fromFeed;
  final WidgetBuilder? navigationBar;

  @override
  State<NewsDetail> createState() => _NewsDetailState();
}

class _NewsDetailState extends State<NewsDetail> {
  late var _article = _load();
  String? _linkError;
  bool _opening = false;
  bool _unavailable = false;

  Future<Response<Map<String, dynamic>>> _load() =>
      widget.api.request<Map<String, dynamic>>(
        'GET',
        Uri(
          path: '$_path/${widget.id}',
          queryParameters: {
            'edition': ?widget.edition,
            'revision': ?widget.revision?.toString(),
          },
        ).toString(),
      );

  Future<void> _open() async {
    setState(() {
      _linkError = null;
      _opening = true;
    });
    try {
      final current = await _load();
      if (!mounted) return;
      final uri = Uri.tryParse(current.data!['sourceUrl'] as String);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'www.hankyung.com' ||
          !await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
            webOnlyWindowName: '_self',
          )) {
        _linkError = '원문을 열지 못했어요.';
      }
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 404) {
        _unavailable = true;
      } else {
        _linkError = '원문을 확인하지 못했어요. 다시 시도해주세요.';
      }
    } on Exception {
      _linkError = '원문을 열지 못했어요.';
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _reload() {
    final next = _load()..ignore();
    setState(() {
      _article = next;
    });
  }

  Widget _failure(bool missing) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(missing ? '현재 공개된 기사가 아니에요.' : '기사를 불러오지 못했어요.'),
      TextButton(
        onPressed: missing
            ? () {
                if (widget.fromFeed || widget.revision == null) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => NewsScreen(api: widget.api),
                    ),
                  );
                }
              }
            : _reload,
        child: Text(missing ? '목록으로 돌아가기' : '다시 시도'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => _NewsPage(
    title: const Text('경제 한 장'),
    bottomNavigationBar: widget.navigationBar?.call(context),
    child: _unavailable
        ? _failure(true)
        : FutureBuilder(
            future: _article,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _NewsSkeleton(detail: true);
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                return _failure(
                  error is DioException && error.response?.statusCode == 404,
                );
              }
              final article = snapshot.data!.data!;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  const _NewsEyebrow('경제 한 장 | 1분 금융 읽기'),
                  const SizedBox(height: 8),
                  Semantics(
                    header: true,
                    child: Text(
                      article['title'] as String,
                      style: FinsightTypography.displaySb22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(_byline(article), style: _supportingText),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Section(
                          '한눈에 보기',
                          article['summary'] as String,
                          accent: true,
                        ),
                        if (article['hasImage'] == true)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 304),
                              child: _NewsImage(
                                key: ValueKey((
                                  article['id'],
                                  article['editionDate'],
                                  article['revision'],
                                )),
                                api: widget.api,
                                article: article,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        ContentExposure(
                          key: ValueKey((article['id'], article['revision'])),
                          impression: false,
                          onVisible: () => _newsEvent(widget.api, article),
                          child: _Section(
                            '기사 요약',
                            article['body'] as String,
                            panel: true,
                            showHeading: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Section(
                    '나에게 연결되는 이유',
                    article['reason'] as String? ??
                        '기사 내용이 내 생활비와 금융 계획에 어떤 영향을 줄지 살펴보세요.',
                    artwork: 'assets/illustrations/news-connection.png',
                  ),
                  _Section(
                    '오늘의 작은 행동',
                    article['action'] as String,
                    artwork: 'assets/illustrations/news-small-action.png',
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: FinsightColors.gray800,
                      foregroundColor: FinsightColors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 12,
                      ),
                    ),
                    onPressed: _opening ? null : _open,
                    child: const Text('기사 원문 보기'),
                  ),
                  StatusMessage(_linkError, reservedLines: 3),
                ],
              );
            },
          ),
  );
}

class _NewsImage extends StatefulWidget {
  const _NewsImage({
    required this.api,
    required this.article,
    this.thumbnail = false,
    super.key,
  });

  final AppApi api;
  final Map<String, dynamic> article;
  final bool thumbnail;

  @override
  State<_NewsImage> createState() => _NewsImageState();
}

class _NewsImageState extends State<_NewsImage> {
  late final Future<Response<Uint8List>> _load = widget.api.request<Uint8List>(
    'GET',
    newsArticleImagePath(
      widget.article['id'] as String,
      widget.article['editionDate'] as String,
      widget.article['revision'] as int,
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Response<Uint8List>>(
    future: _load,
    builder: (context, snapshot) {
      final bytes = snapshot.data?.data;
      if (bytes == null) {
        return !widget.thumbnail &&
                snapshot.connectionState != ConnectionState.done
            ? const AspectRatio(aspectRatio: 304 / 205)
            : const SizedBox.shrink();
      }
      final picture = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          cacheWidth: widget.thumbnail ? 160 : 960,
          fit: BoxFit.cover,
          semanticLabel: '기사 이미지',
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
      return widget.thumbnail
          ? picture
          : AspectRatio(aspectRatio: 304 / 205, child: picture);
    },
  );
}

Future<void> _newsEvent(
  AppApi api,
  Map<String, dynamic> article, {
  String? viewSession,
}) async {
  final revision = article['revision'];
  final edition = article['editionDate'];
  if (revision is! int || edition is! String) return;
  await recordContentEvent(
    api,
    Uri(
      path: '$_path/${article['id']}/events',
      queryParameters: {'edition': edition},
    ).toString(),
    revision: revision,
    viewSessionId: viewSession,
  );
}

String _byline(Map<String, dynamic> article) {
  final date = DateTime.parse(
    article['articlePublishedAt'] as String,
  ).toUtc().add(const Duration(hours: 9));
  return '${article['source']} · ${date.toIso8601String().substring(0, 10)}';
}

const _supportingText = TextStyle(color: FinsightColors.gray400);

class _NewsEyebrow extends StatelessWidget {
  const _NewsEyebrow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: FinsightTypography.labelM12.copyWith(
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({
    required this.api,
    required this.article,
    required this.featured,
    required this.open,
  });

  final AppApi api;
  final Map<String, dynamic> article;
  final bool featured;
  final VoidCallback open;

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(20);
    return Material(
      color: FinsightColors.gray900,
      borderRadius: border,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: border,
          border: Border.all(color: FinsightColors.gray800),
          gradient: featured
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      FinsightColors.neonLime900.withValues(alpha: .3),
                      FinsightColors.gray900,
                    ),
                    FinsightColors.gray900,
                  ],
                )
              : null,
        ),
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: EdgeInsets.all(featured ? 20 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (article['hasImage'] == true) ...[
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _NewsImage(
                      api: api,
                      article: article,
                      thumbnail: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  article['title'] as String,
                  style: featured
                      ? FinsightTypography.displaySb22
                      : FinsightTypography.titleSb18,
                ),
                if (featured) ...[
                  const SizedBox(height: 8),
                  Text(article['summary'] as String, style: _supportingText),
                ],
                const SizedBox(height: 12),
                Text(_byline(article), style: _supportingText),
                if (featured) ...[
                  const SizedBox(height: 14),
                  const _NewsEyebrow('1분 요약 보기 →'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(
    this.title,
    this.body, {
    this.artwork,
    this.panel = false,
    this.accent = false,
    this.showHeading = true,
  });
  final String title;
  final String body;
  final String? artwork;
  final bool panel;
  final bool accent;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final bodyText = Text(
      body,
      style: accent ? FinsightTypography.titleM18 : _supportingText,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeading)
            Semantics(
              header: true,
              child: Text(
                title,
                style: FinsightTypography.bodySb16.copyWith(
                  color: accent ? color : null,
                ),
              ),
            ),
          if (showHeading) const SizedBox(height: 8),
          if (panel || artwork != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: FinsightColors.gray900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: EdgeInsets.all(artwork == null ? 12 : 8),
                child: Row(
                  children: [
                    if (artwork case final asset?) ...[
                      Image.asset(
                        asset,
                        width: 44,
                        height: 44,
                        excludeFromSemantics: true,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: bodyText),
                  ],
                ),
              ),
            )
          else
            bodyText,
        ],
      ),
    );
  }
}

class _NewsSkeleton extends StatelessWidget {
  const _NewsSkeleton({this.detail = false});

  final bool detail;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
    children: [
      ContentSkeleton(
        label: detail ? '기사 불러오는 중' : '뉴스 불러오는 중',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SkeletonLine(.37, fontSize: 12),
            const SizedBox(height: 12),
            const SkeletonLine(.84, fontSize: 22),
            const SizedBox(height: 7),
            const SkeletonLine(.61, fontSize: 22),
            const SizedBox(height: 12),
            const SkeletonLine(.52, fontSize: 12),
            const SizedBox(height: 24),
            if (detail) ...[
              const SkeletonLine(.31),
              const SizedBox(height: 8),
              const SkeletonLine(.86),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 304),
                  child: const AspectRatio(
                    aspectRatio: 304 / 205,
                    child: SkeletonBlock(height: 205, radius: 8),
                  ),
                ),
              ),
            ] else
              const SkeletonPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SkeletonLine(.35, fontSize: 12),
                    SizedBox(height: 14),
                    SkeletonLine(.93, fontSize: 22),
                    SizedBox(height: 8),
                    SkeletonLine(.64, fontSize: 22),
                    SizedBox(height: 16),
                    SkeletonLine(.82),
                    SizedBox(height: 28),
                    SkeletonLine(.44, fontSize: 12),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SkeletonRows(count: detail ? 2 : 1, showLeading: detail),
          ],
        ),
      ),
    ],
  );
}

class _NewsPage extends StatelessWidget {
  const _NewsPage({
    required this.title,
    required this.child,
    this.automaticallyImplyLeading = true,
    this.centerTitle = true,
    this.actions = const [],
    this.bottomNavigationBar,
  });
  final Widget title;
  final Widget child;
  final bool automaticallyImplyLeading;
  final bool centerTitle;
  final List<Widget> actions;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: title,
      centerTitle: centerTitle,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: automaticallyImplyLeading,
      actions: actions,
    ),
    bottomNavigationBar: bottomNavigationBar,
    body: SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: child,
        ),
      ),
    ),
  );
}

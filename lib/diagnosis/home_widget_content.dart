import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';

import '../account/app_api.dart';
import '../news/news_article_image.dart';

typedef WidgetAction = ({
  String? attemptId,
  String? id,
  int? revision,
  String? title,
  String state,
});

String widgetActionFallback(String? state) => switch (state) {
  'NO_DIAGNOSIS' => '나에게 맞는 행동을 찾아볼까요',
  'COMPLETE' => '이번 달 추천 행동을 모두 확인했어요',
  _ => '추천 행동을 준비하고 있어요',
};
typedef WidgetNews = ({
  String id,
  String edition,
  int revision,
  String title,
  String? publishedDate,
  String? endsAt,
  bool today,
  Uint8List? image,
});

class HomeWidgetContent {
  const HomeWidgetContent({this.action, this.news, this.keepNews = false});

  final WidgetAction? action;
  final WidgetNews? news;
  final bool keepNews;

  static Future<HomeWidgetContent> load(AppApi api) async {
    final (action, (news, keepNews)) = await (
      _optional(loadWidgetAction(api)),
      _newsForRefresh(api),
    ).wait;
    return HomeWidgetContent(action: action, news: news, keepNews: keepNews);
  }

  static Future<(WidgetNews?, bool)> _newsForRefresh(AppApi api) async {
    try {
      return (await loadWidgetNews(api), false);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      return (null, status == null || status >= 500);
    }
  }

  static Future<T?> _optional<T>(Future<T?> content) async {
    try {
      return await content;
    } on DioException {
      return null;
    }
  }

  Map<String, Object?> get nativeData => {
    'actionTitle': action?.title,
    'actionState': action?.state,
    'actionAttemptId': action?.attemptId,
    'actionId': action?.id,
    'actionRevision': action?.revision,
    'newsTitle': news?.title,
    'newsDate': news?.edition,
    'newsId': news?.id,
    'newsRevision': news?.revision,
    'newsPublishedDate': news?.publishedDate,
    'newsEndsAt': news?.endsAt,
    'newsImage': news?.image,
    'keepNews': keepNews,
  };
}

Future<WidgetAction> loadWidgetAction(AppApi api) async {
  final response = await api.request<Map<String, dynamic>>(
    'GET',
    '/api/v1/guides/widget',
  );
  final data = response.data!;
  return (
    attemptId: data['attemptId'] as String?,
    id: data['id'] as String?,
    revision: data['revision'] as int?,
    title: data['title'] as String?,
    state: data['state'] as String,
  );
}

Future<WidgetNews?> loadWidgetNews(AppApi api) async {
  final response = await api.request<Map<String, dynamic>>(
    'GET',
    '/api/v1/news',
  );
  final feed = response.data!;
  final article = (feed['articles'] as List)
      .cast<Map<String, dynamic>>()
      .firstOrNull;
  if (article == null) return null;
  final publishedDate = DateTime.tryParse(
    article['articlePublishedAt'] as String? ?? '',
  )?.toUtc().add(const Duration(hours: 9)).toIso8601String().split('T').first;
  final id = article['id'] as String;
  final edition = article['editionDate'] as String;
  final revision = article['revision'] as int;
  return (
    id: id,
    edition: edition,
    revision: revision,
    title: article['title'] as String,
    publishedDate: publishedDate,
    endsAt: article['endsAt'] as String?,
    today: (publishedDate ?? edition) == feed['today'],
    image: article['hasImage'] == true
        ? await _loadWidgetThumbnail(api, id, edition, revision)
        : null,
  );
}

Future<Uint8List?> _loadWidgetThumbnail(
  AppApi api,
  String id,
  String edition,
  int revision,
) async {
  try {
    final response = await api.request<Uint8List>(
      'GET',
      newsArticleImagePath(id, edition, revision),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) return null;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final scale = math.min(1.0, 288 / math.max(width, height));
        return ui.TargetImageSize(
          width: math.max(1, (width * scale).round()),
          height: math.max(1, (height * scale).round()),
        );
      },
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } on DioException catch (error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403 || status == 404) rethrow;
    return null;
  } on Exception {
    return null;
  }
}

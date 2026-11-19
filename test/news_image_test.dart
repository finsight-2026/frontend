import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/news/news_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('news fetches its selected edition image as bytes', (
    tester,
  ) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGOM2qfDwMDAxAAGAA+IAUiQgQ3tAAAAAElFTkSuQmCC',
    );
    final http = Dio(BaseOptions(baseUrl: apiUrl));
    final imagePaths = <Uri>[];
    final detailPaths = <Uri>[];
    var expired = false;
    const title = '이미지 기사에서 한 달 동안 반복되는 지출과 자동이체 내역을 다시 살펴볼 때';
    http.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.endsWith('/auth/login')) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'accessToken': 'access', 'refreshToken': 'refresh'},
              ),
            );
            return;
          }
          if (options.uri.path.endsWith('/image')) {
            expect(options.responseType, ResponseType.bytes);
            expect(options.headers['Authorization'], 'Bearer access');
            imagePaths.add(options.uri);
            handler.resolve(
              Response(requestOptions: options, data: png, statusCode: 200),
            );
            return;
          }
          final article = {
            'id': 'news-test',
            'title': title,
            'summary': '요약',
            'body': '본문',
            'source': '한국경제',
            'editionDate': '2026-11-11',
            'articlePublishedAt': '2026-11-11T01:00:00Z',
            'revision': 2,
            'action': '기록을 확인하세요',
            'hasImage': true,
          };
          if (options.uri.path == '/api/v1/news/news-test') {
            detailPaths.add(options.uri);
            if (expired) {
              handler.reject(
                DioException.badResponse(
                  statusCode: 404,
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 404),
                ),
              );
              return;
            }
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: switch (options.uri.path) {
                '/api/v1/news' => {
                  'today': '2026-11-11',
                  'articles': [if (!expired) article],
                  'preparing': expired,
                },
                '/api/v1/news/news-test' => article,
                _ => null,
              },
            ),
          );
        },
      ),
    );
    final api = AppApi(http: http);
    addTearDown(api.close);
    await tester.runAsync(
      () => api.login('fixture@example.test', 'FixturePassword'),
    );
    await tester.pumpWidget(MaterialApp(home: NewsScreen(api: api)));
    await tester.pumpAndSettle();
    final articleImage = find.byWidgetPredicate(
      (widget) => widget is Image && widget.semanticLabel == '기사 이미지',
    );
    expect(articleImage, findsOneWidget);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    expect(articleImage, findsOneWidget);
    expect(imagePaths, hasLength(2));
    expect(detailPaths.single.queryParameters, {
      'edition': '2026-11-11',
      'revision': '2',
    });
    for (final uri in imagePaths) {
      expect(uri.path, '/api/v1/news/news-test/image');
      expect(uri.queryParameters, {'edition': '2026-11-11', 'revision': '2'});
    }

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.text(title).hitTestable(), findsOneWidget);
    final originalLink = find.text('기사 원문 보기');
    await tester.scrollUntilVisible(originalLink, 160);
    for (final name in ['news-connection', 'news-small-action']) {
      final artwork = find.image(AssetImage('assets/illustrations/$name.png'));
      expect(tester.getSize(artwork), const Size.square(44));
    }
    await Scrollable.ensureVisible(tester.element(originalLink), alignment: .5);
    await tester.pumpAndSettle();
    expect(originalLink.hitTestable(), findsOneWidget);
    expired = true;
    await tester.tap(originalLink);
    await tester.pumpAndSettle();
    expect(find.text('현재 공개된 기사가 아니에요.'), findsOneWidget);
    expect(find.text(title), findsNothing);
    expect(detailPaths, hasLength(2));
    await tester.tap(find.text('목록으로 돌아가기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('오늘의 뉴스를 준비'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

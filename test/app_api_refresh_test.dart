import 'dart:async';

import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/content/content_exposure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'content retries retain the event epoch and learn the current epoch',
    () async {
      final http = Dio(BaseOptions(baseUrl: apiUrl));
      final submitted = <Map<String, dynamic>>[];
      http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            final refreshing = request.path.endsWith('/refresh');
            if (refreshing || request.path.endsWith('/login')) {
              return handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: request,
                  statusCode: 200,
                  data: {
                    'accessToken': refreshing ? 'new' : 'old',
                    'refreshToken': 'refresh',
                    'contentEventEpoch': refreshing ? 4 : 3,
                  },
                ),
              );
            }
            submitted.add(Map<String, dynamic>.from(request.data as Map));
            if (request.headers['Authorization'] == 'Bearer old') {
              return handler.reject(
                DioException.badResponse(
                  statusCode: 401,
                  requestOptions: request,
                  response: Response<void>(
                    requestOptions: request,
                    statusCode: 401,
                  ),
                ),
              );
            }
            handler.resolve(
              Response<void>(
                requestOptions: request,
                statusCode: 204,
                headers: Headers.fromMap({
                  'x-finsight-content-epoch': [
                    submitted.length == 2 ? '5' : '4',
                  ],
                }),
              ),
            );
          },
        ),
      );
      final api = AppApi(http: http);
      addTearDown(api.close);
      await api.login('person@example.test', 'Example123');
      const path = '/api/v1/news/article/events';
      await recordContentEvent(api, path, revision: 1);
      await recordContentEvent(api, path, revision: 1);
      expect(submitted.map((event) => event['contentEventEpoch']), [3, 3, 5]);
      expect(submitted[0]['eventId'], submitted[1]['eventId']);
      expect(api.contentEventEpoch, 5);
      api.clearSession();
      expect(api.contentEventEpoch, 0);
    },
  );

  test(
    'parallel 401 responses share one refresh and retry with the new token',
    () async {
      final http = Dio(BaseOptions(baseUrl: apiUrl));
      final receivedBoth = Completer<void>();
      var expiredRequests = 0;
      var refreshes = 0;
      http.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            Response<Map<String, String>> tokens(
              String access,
              String refresh,
            ) => Response(
              requestOptions: request,
              statusCode: 200,
              data: {'accessToken': access, 'refreshToken': refresh},
            );
            if (request.path.endsWith('/login')) {
              handler.resolve(tokens('old', 'refresh-old'));
            } else if (request.path.endsWith('/refresh')) {
              refreshes++;
              await receivedBoth.future;
              handler.resolve(tokens('new', 'refresh-new'));
            } else if (request.headers['Authorization'] == 'Bearer old') {
              if (++expiredRequests == 2) receivedBoth.complete();
              handler.reject(
                DioException.badResponse(
                  statusCode: 401,
                  requestOptions: request,
                  response: Response<void>(
                    requestOptions: request,
                    statusCode: 401,
                  ),
                ),
              );
            } else {
              expect(request.headers['Authorization'], 'Bearer new');
              handler.resolve(
                Response<void>(requestOptions: request, statusCode: 204),
              );
            }
          },
        ),
      );
      final api = AppApi(http: http);
      addTearDown(api.close);
      await api.login('person@example.test', 'Example123');
      await Future.wait([
        api.request<void>('POST', '/api/v1/account/activity'),
        api.request<void>('GET', '/api/v1/notifications'),
      ]);
      expect(expiredRequests, 2);
      expect(refreshes, 1);
    },
  );
}

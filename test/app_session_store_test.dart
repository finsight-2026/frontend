import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/account/app_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline logout queues only the proof across a restart', () async {
    String? persisted;
    var online = false;
    final delivered = <String>[];
    AppSessionStore makeStore() => AppSessionStore(
      () async => persisted,
      (value) async => persisted = value,
      (token) async {
        if (!online) throw Exception('offline');
        delivered.add(token);
      },
    );

    final store = makeStore();
    await store.save((refresh: 'first-refresh', revocation: 'first-proof'));
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          expect(request.path, '/api/v1/auth/refresh');
          expect(request.data, {'refreshToken': 'first-refresh'});
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: request,
              data: {
                'accessToken': 'access',
                'refreshToken': 'rotated-refresh',
              },
            ),
          );
        },
      ),
    );
    final api = AppApi(http: dio, sessionStore: store);
    addTearDown(api.close);
    expect(await api.restore(), SessionRestore.restored);
    expect(await store.read(), (
      refresh: 'rotated-refresh',
      revocation: 'first-proof',
    ));

    await api.logout();
    await store.flush();
    expect(await store.read(), isNull);
    expect(persisted, '{"pending":["first-proof"]}');
    expect(delivered, isEmpty);

    final restarted = makeStore();
    expect(await restarted.read(), isNull);
    const newSession = (refresh: 'second-refresh', revocation: 'second-proof');
    await restarted.save(newSession);
    online = true;
    await restarted.flush();
    expect(delivered, ['first-proof']);
    expect(await restarted.read(), newSession);
    await restarted.flush();
    expect(delivered, ['first-proof']);
  });
}

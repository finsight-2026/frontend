import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../notification/notification_device.dart';
import 'app_session_store.dart';

export 'app_session_store.dart' show apiUrl;

enum SessionRestore { absent, expired, restored }

class AppApi {
  AppApi({
    Dio? http,
    AppSessionStore? sessionStore,
    NotificationRegistrationSource? registrationSource,
  }) : _http =
           http ??
           Dio(
             BaseOptions(
               baseUrl: apiUrl,
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 10),
             ),
           ),
       _store = sessionStore,
       _registration =
           registrationSource ??
           (sessionStore == null ? null : notificationRegistration(apiUrl));

  final Dio _http;
  final AppSessionStore? _store;
  final NotificationRegistrationSource? _registration;
  Future<void>? _deviceSync;
  String? _access;
  String? _refresh;
  String? _revocation;
  Future<void>? _refreshing;
  int _sessionGeneration = 0;
  int _contentEventEpoch = 0;

  int get contentEventEpoch => _contentEventEpoch;

  Future<DateTime?> login(String email, String password) async {
    final response = await _http.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      data: {'email': email, 'password': password},
      options: Options(
        validateStatus: (status) => status == 200 || status == 409,
      ),
    );
    if (response.statusCode == 409) {
      await forgetSession();
      return DateTime.parse(response.data!['dueAt'] as String);
    }
    await acceptSession(response.data!);
    return null;
  }

  Future<void> acceptSession(Map<String, dynamic> tokens) async {
    clearSession();
    final revocation = tokens['revocationToken'] as String?;
    if (revocation != null) {
      await _store?.save((
        refresh: tokens['refreshToken'] as String,
        revocation: revocation,
      ));
    }
    _revocation = revocation;
    _setTokens(tokens);
  }

  Future<SessionRestore> restore() async {
    flushPendingRevocations();
    final saved = await _store?.read();
    if (saved == null) return SessionRestore.absent;
    _revocation = saved.revocation;
    try {
      await _rotate(saved.refresh, _sessionGeneration);
      return SessionRestore.restored;
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
      await forgetSession(revoke: true);
      return SessionRestore.expired;
    }
  }

  void flushPendingRevocations() {
    final store = _store;
    if (store != null) unawaited(store.flush());
  }

  void _setTokens(Map<String, dynamic> tokens) {
    _access = tokens['accessToken'] as String;
    _refresh = tokens['refreshToken'] as String;
    _acceptContentEventEpoch(tokens['contentEventEpoch'] as int?);
  }

  void _acceptContentEventEpoch(int? epoch) {
    if (epoch != null && epoch > _contentEventEpoch) _contentEventEpoch = epoch;
  }

  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    final access = _access;
    final generation = _sessionGeneration;
    Future<Response<T>> send() async {
      final response = await _http.request<T>(
        path,
        data: data,
        options: Options(
          method: method,
          responseType: T == Uint8List ? ResponseType.bytes : null,
          headers: {
            if (_access case final token?) 'Authorization': 'Bearer $token',
          },
        ),
      );
      if (generation == _sessionGeneration) {
        final epoch = response.headers.value('x-finsight-content-epoch');
        if (epoch != null) _acceptContentEventEpoch(int.tryParse(epoch));
      }
      return response;
    }

    try {
      return await send();
    } on DioException catch (error) {
      final refresh = _refresh;
      if (error.response?.statusCode != 401 ||
          refresh == null ||
          generation != _sessionGeneration) {
        rethrow;
      }
      if (_access == access) {
        final pending = _refreshing ??= _rotate(refresh, generation);
        try {
          await pending;
        } finally {
          if (identical(_refreshing, pending)) _refreshing = null;
        }
      }
      if (generation != _sessionGeneration) rethrow;
      return send();
    }
  }

  Future<void> _rotate(String refresh, int generation) async {
    final response = await _http.post<Map<String, dynamic>>(
      '/api/v1/auth/refresh',
      data: {'refreshToken': refresh},
    );
    if (generation != _sessionGeneration) return;
    final tokens = response.data!;
    if (_revocation case final revocation?) {
      await _store?.rotate(
        (refresh: refresh, revocation: revocation),
        (refresh: tokens['refreshToken'] as String, revocation: revocation),
      );
    }
    if (generation == _sessionGeneration) _setTokens(tokens);
  }

  Stream<void> get notificationRegistrationChanges =>
      _registration?.changes ?? const Stream.empty();

  Future<void> syncNotificationDevice() async {
    final source = _registration;
    if (source == null || _access == null) return;
    final generation = _sessionGeneration;
    final previous = _deviceSync ?? Future<void>.value();
    final next = previous.then((_) => _syncDevice(source, generation));
    _deviceSync = next;
    try {
      await next;
    } finally {
      if (identical(_deviceSync, next)) _deviceSync = null;
    }
  }

  Future<void> _syncDevice(
    NotificationRegistrationSource source,
    int generation,
  ) async {
    if (generation != _sessionGeneration) return;
    try {
      final permission = await NotificationDevice.permission();
      if (permission == DeviceNotificationPermission.unknown ||
          generation != _sessionGeneration) {
        return;
      }
      DeviceRegistration? registration;
      if (permission == DeviceNotificationPermission.allowed) {
        final preferences = await request<Map<String, dynamic>>(
          'GET',
          '/api/v1/notifications/preferences',
        );
        if (preferences.data?['enabled'] == true &&
            generation == _sessionGeneration) {
          registration = await source.registration();
        }
      }
      if (generation != _sessionGeneration) return;
      const path = '/api/v1/notifications/device';
      if (registration == null) {
        source.clear();
        await request<void>('DELETE', path);
      } else {
        await request<void>(
          'PUT',
          path,
          data: {
            'provider': registration.provider,
            'token': registration.token,
          },
        );
      }
    } on Exception {
      // Retry synchronization on the next resume or preference change.
    }
  }

  Future<void> logout() async {
    final store = _store;
    final revocation = _revocation;
    if (store != null && revocation != null) {
      await store.forget(revocation, revoke: true);
      clearSession();
      flushPendingRevocations();
      return;
    }
    await request<void>('POST', '/api/v1/auth/logout');
    clearSession();
  }

  Future<void> forgetSession({bool revoke = false}) async {
    final revocation = _revocation;
    if (revocation != null) await _store?.forget(revocation, revoke: revoke);
    clearSession();
    if (revoke) flushPendingRevocations();
  }

  Future<void> cancelWithdrawal(String email, String password) async {
    await _http.post<void>(
      '/api/v1/account/withdrawal/cancel',
      data: {'email': email, 'password': password, 'confirmed': true},
    );
  }

  void clearSession() {
    _sessionGeneration++;
    _registration?.clear();
    _refreshing = null;
    _contentEventEpoch = 0;
    _access = null;
    _refresh = null;
    _revocation = null;
  }

  void close() => _http.close(force: true);
}

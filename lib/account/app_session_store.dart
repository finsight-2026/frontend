import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const apiUrl = String.fromEnvironment(
  'FINSIGHT_API_URL',
  defaultValue: kReleaseMode
      ? 'https://api.finsight.life'
      : 'http://127.0.0.1:8080',
);

typedef StoredSession = ({String refresh, String revocation});

class AppSessionStore {
  AppSessionStore(this._read, this._write, this._revoke, [this._retryDelay]);

  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  final Future<void> Function(String) _revoke;
  final Duration? _retryDelay;
  Future<void>? _tail;
  Future<void>? _flushing;
  Timer? _retry;
  bool _loaded = false;
  StoredSession? _session;
  final _pending = <String>{};

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final task = (_tail ?? Future<void>.value()).then((_) async {
      if (!_loaded) {
        final raw = await _read();
        Object? decoded;
        if (raw != null) {
          try {
            decoded = jsonDecode(raw);
          } on FormatException {
            decoded = null;
          }
        }
        if (decoded case final Map<String, dynamic> values) {
          final refresh = values['refresh'];
          final revocation = values['revocation'];
          if (refresh is String && revocation is String) {
            _session = (refresh: refresh, revocation: revocation);
          }
          if (values['pending'] case final List<Object?> pending) {
            _pending.addAll(pending.whereType<String>());
          }
        }
        _loaded = true;
      }
      return action();
    });
    final tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tail = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tail, tail)) _tail = null;
      }),
    );
    return task;
  }

  Future<void> _save(StoredSession? next, Set<String> pending) async {
    await _write(
      jsonEncode({
        if (next != null) 'refresh': next.refresh,
        if (next != null) 'revocation': next.revocation,
        'pending': pending.toList(growable: false),
      }),
    );
    _session = next;
    _pending
      ..clear()
      ..addAll(pending);
  }

  Future<StoredSession?> read() => _exclusive(() async => _session);

  Future<void> save(StoredSession session) =>
      _exclusive(() => _save(session, {..._pending}));

  Future<void> rotate(StoredSession expected, StoredSession next) =>
      _exclusive(() async {
        if (_session == expected) await _save(next, {..._pending});
      });

  Future<void> forget(String revocation, {bool revoke = false}) =>
      _exclusive(() async {
        final next = _session?.revocation == revocation ? null : _session;
        final pending = {..._pending, if (revoke) revocation};
        if (next != _session || pending.length != _pending.length) {
          await _save(next, pending);
        }
      });

  Future<void> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);

  Future<void> _flush() async {
    _retry?.cancel();
    try {
      while (true) {
        final token = await _exclusive(() async => _pending.firstOrNull);
        if (token == null) return;
        await _revoke(token);
        await _exclusive(() => _save(_session, {..._pending}..remove(token)));
      }
    } on Exception {
      if (_retryDelay case final delay?) {
        _retry = Timer(delay, () => unawaited(flush()));
      }
    }
  }
}

AppSessionStore _createSessionStore() {
  const storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
  );
  const key = 'finsight.session.v1';
  String? memory;
  final dio = Dio(
    BaseOptions(
      baseUrl: apiUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
  return AppSessionStore(
    () async => kIsWeb ? memory : storage.read(key: key),
    (value) async {
      if (kIsWeb) {
        memory = value;
      } else {
        await storage.write(key: key, value: value);
      }
    },
    (token) async {
      await dio.post<void>(
        '/api/v1/auth/logout/revoke',
        data: {'revocationToken': token},
      );
    },
    const Duration(seconds: 30),
  );
}

final appSessionStore = _createSessionStore();

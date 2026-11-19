import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DeviceNotificationPermission { notDetermined, allowed, denied, unknown }

class NotificationDevice {
  static const _channel = MethodChannel('finsight/notification_permissions');

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<DeviceNotificationPermission> permission({
    bool request = false,
  }) async {
    final status = await _channel.invokeMethod<String>(
      request ? 'request' : 'status',
    );
    return DeviceNotificationPermission.values.asNameMap()[status] ??
        DeviceNotificationPermission.unknown;
  }

  static Future<bool> openSettings() async =>
      await _channel.invokeMethod<bool>('openSettings') == true;
}

typedef DeviceRegistration = ({String provider, String token});

abstract interface class NotificationRegistrationSource {
  Stream<void> get changes;
  Future<DeviceRegistration> registration();
  void clear();
}

NotificationRegistrationSource? notificationRegistration(String origin) {
  final local = localNotificationRegistration(origin);
  if (local != null) return local;
  const enabled = bool.fromEnvironment('FINSIGHT_FCM_CLIENT_ENABLED');
  return enabled && NotificationDevice.isIOS
      ? _FcmNotificationRegistration()
      : null;
}

NotificationRegistrationSource? localNotificationRegistration(String origin) {
  const requested = bool.fromEnvironment('FINSIGHT_LOCAL_PUSH_REGISTRATION');
  if (!kDebugMode || !requested || !NotificationDevice.isIOS) return null;
  final address = Uri.tryParse(origin);
  if (address == null ||
      !{'127.0.0.1', 'localhost', '::1'}.contains(address.host)) {
    return null;
  }
  return _LocalNotificationRegistration();
}

class _LocalNotificationRegistration implements NotificationRegistrationSource {
  String? _token;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<DeviceRegistration> registration() async {
    final random = Random.secure();
    final token = _token ??= base64UrlEncode(
      List.generate(32, (_) => random.nextInt(256)),
    );
    return (provider: 'LOCAL', token: token);
  }

  @override
  void clear() => _token = null;
}

class _FcmNotificationRegistration implements NotificationRegistrationSource {
  static const _channel = MethodChannel('finsight/fcm_registration');
  static final _changes = _listen();

  static StreamController<void> _listen() {
    final events = StreamController<void>.broadcast();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') events.add(null);
    });
    return events;
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<DeviceRegistration> registration() async {
    final token = await _channel.invokeMethod<String>('registrationId');
    if (token == null || token.isEmpty) {
      throw PlatformException(code: 'FCM_NOT_READY');
    }
    return (provider: 'FCM_FID', token: token);
  }

  @override
  void clear() => unawaited(_suspend());

  Future<void> _suspend() async {
    try {
      await _channel.invokeMethod<void>('suspend');
    } on PlatformException {
      // The server-side registration is removed independently of this call.
    } on MissingPluginException {
      // The local build can run without an FCM provider.
    }
  }
}

class NotificationOpens {
  NotificationOpens._() {
    if (NotificationDevice.isIOS) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'open') _opens.add(null);
      });
    }
  }

  static final instance = NotificationOpens._();
  static const _channel = MethodChannel('finsight/notification_opens');
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  final _opens = StreamController<void>.broadcast();
  Stream<void> get opens => _opens.stream;

  Future<T?> _invoke<T>(String method) async {
    if (!NotificationDevice.isIOS) return null;
    try {
      return await _channel.invokeMethod<T>(method);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> peek() async => await _invoke<bool>('peek') ?? false;

  Future<String?> take() async {
    final id = await _invoke<String>('take');
    return id != null && _uuid.hasMatch(id) ? id : null;
  }
}

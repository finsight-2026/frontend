import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef WidgetOptions = ({bool showScore, bool showType, bool showContent});

enum HomeWidgetDestination { diagnosis, standard, news, action }

typedef WidgetArticleTarget = ({String id, String edition, int revision});
typedef WidgetGuideTarget = ({String attemptId, String id, int revision});
typedef WidgetOpen = ({
  HomeWidgetDestination destination,
  WidgetArticleTarget? article,
  WidgetGuideTarget? guide,
});

class HomeWidgetPlatform {
  HomeWidgetPlatform._() {
    if (isNative) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'open') _opens.add(null);
      });
    }
  }

  static final instance = HomeWidgetPlatform._();
  static const _channel = MethodChannel('finsight/home_widget');
  static const hidden = (showScore: false, showType: false, showContent: false);

  final _opens = StreamController<void>.broadcast();
  Stream<void> get opens => _opens.stream;
  int _generation = 0;

  bool get isNative => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  int nextRefresh() => ++_generation;

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!isNative) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }

  Future<WidgetOptions?> options() async {
    final result = await _invoke<Map<Object?, Object?>>('options');
    return result == null
        ? null
        : (
            showScore: result['showScore'] == true,
            showType: result['showType'] == true,
            showContent: result['showContent'] == true,
          );
  }

  Future<void> configure(WidgetOptions options) {
    nextRefresh();
    return _invoke<void>('configure', {
      'showScore': options.showScore,
      'showType': options.showType,
      'showContent': options.showContent,
    });
  }

  Future<void> publish(int generation, Map<String, Object?> data) async {
    if (_generation == generation) await _invoke<void>('publish', data);
  }

  Future<void> clear({bool keepOptions = false}) async {
    nextRefresh();
    try {
      await _invoke<void>(keepOptions ? 'clearData' : 'clear');
    } on PlatformException {
      // The operating system can reject a widget refresh during app teardown.
    }
  }

  Future<void> clearIfCurrent(int generation) async {
    if (_generation == generation) await clear();
  }

  Future<bool> peekOpen() async => await _invoke<bool>('peekOpen') ?? false;
  Future<WidgetOpen?> consumeOpen() async {
    final raw = await _invoke<String>('consumeOpen');
    if (raw == null) return null;
    final target = Uri.tryParse(raw);
    final destination = switch (target?.path) {
      'diagnosis' => HomeWidgetDestination.diagnosis,
      'default' => HomeWidgetDestination.standard,
      'news' => HomeWidgetDestination.news,
      'action' => HomeWidgetDestination.action,
      _ => null,
    };
    if (destination == null) return null;
    WidgetArticleTarget? article;
    WidgetGuideTarget? guide;
    if (destination == HomeWidgetDestination.news) {
      final id = target!.queryParameters['id'] ?? '';
      final edition = target.queryParameters['edition'] ?? '';
      final revision = int.tryParse(target.queryParameters['revision'] ?? '');
      if (RegExp(
            r'^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$',
          ).hasMatch(id) &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(edition) &&
          revision != null &&
          revision > 0 &&
          revision <= 2147483647) {
        article = (id: id, edition: edition, revision: revision);
      }
    }
    if (destination == HomeWidgetDestination.action) {
      final params = target!.queryParametersAll;
      if (params.length == 3 &&
          params.values.every((values) => values.length == 1)) {
        final attemptId = target.queryParameters['attemptId'] ?? '';
        final id = target.queryParameters['id'] ?? '';
        final revision = int.tryParse(target.queryParameters['revision'] ?? '');
        if (RegExp(
              r'^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$',
            ).hasMatch(attemptId) &&
            RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id) &&
            revision != null &&
            revision > 0 &&
            revision <= 2147483647) {
          guide = (attemptId: attemptId, id: id, revision: revision);
        }
      }
    }
    return (destination: destination, article: article, guide: guide);
  }
}

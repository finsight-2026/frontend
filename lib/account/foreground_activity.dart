import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import 'app_api.dart';

class ForegroundActivity extends StatefulWidget {
  const ForegroundActivity({required this.api, required this.child, super.key});
  final AppApi api;
  final Widget child;

  @override
  State<ForegroundActivity> createState() => _ForegroundActivityState();
}

class _ForegroundActivityState extends State<ForegroundActivity>
    with WidgetsBindingObserver {
  String? _recordedDate;
  bool _inFlight = false;
  bool _expired = false;
  StreamSubscription<void>? _registrationChanges;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _registrationChanges = widget.api.notificationRegistrationChanges.listen(
      (_) => unawaited(widget.api.syncNotificationDevice()),
    );
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) _resume();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resume();
  }

  void _resume() {
    widget.api.flushPendingRevocations();
    unawaited(widget.api.syncNotificationDevice());
    unawaited(_record());
  }

  Future<void> _record() async {
    final kstDate = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 9))
        .toIso8601String()
        .substring(0, 10);
    if (_expired || _inFlight || _recordedDate == kstDate) return;
    _inFlight = true;
    try {
      final response = await widget.api.request<Map<String, dynamic>>(
        'POST',
        '/api/v1/account/activity',
      );
      _recordedDate = response.data?['date'] as String?;
    } on DioException catch (error) {
      _expired = error.response?.statusCode == 401;
    } finally {
      _inFlight = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_registrationChanges?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

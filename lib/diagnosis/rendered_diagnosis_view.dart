import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../account/app_api.dart';
import '../shared/request_id.dart';

class RenderedDiagnosisView extends StatefulWidget {
  const RenderedDiagnosisView({
    required this.api,
    required this.attemptId,
    required this.child,
    this.contentId,
    this.contentRevision,
    super.key,
  });

  final AppApi api;
  final String attemptId;
  final String? contentId;
  final int? contentRevision;
  final Widget child;

  @override
  State<RenderedDiagnosisView> createState() => _RenderedDiagnosisViewState();
}

class _RenderedDiagnosisViewState extends State<RenderedDiagnosisView>
    with WidgetsBindingObserver {
  final _eventId = newRequestId();
  String? _occurredAt;
  bool _reported = false;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _afterFrame();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _afterFrame();
  }

  void _afterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reported || _pending) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      if (ModalRoute.isCurrentOf(context) == false) return;
      unawaited(_record());
    });
  }

  Future<void> _record() async {
    _pending = true;
    _occurredAt ??= DateTime.now().toUtc().toIso8601String();
    try {
      await widget.api.request<void>(
        'POST',
        '/api/v1/diagnosis/attempts/${widget.attemptId}/views',
        data: {
          'eventId': _eventId,
          'contentId': ?widget.contentId,
          'contentRevision': ?widget.contentRevision,
          'occurredAt': _occurredAt,
        },
      );
      _reported = true;
    } on DioException {
      // Analytics availability must not prevent viewing or completing a guide.
    } finally {
      _pending = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

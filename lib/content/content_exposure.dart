import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../account/app_api.dart';
import '../shared/request_id.dart';

Future<void> recordContentEvent(
  AppApi api,
  String path, {
  required int revision,
  String? viewSessionId,
}) async {
  try {
    await api.request<void>(
      'POST',
      path,
      data: {
        'eventId': newRequestId(),
        'action': viewSessionId == null ? 'VIEWED' : 'IMPRESSION',
        'revision': revision,
        'contentEventEpoch': api.contentEventEpoch,
        'viewSessionId': ?viewSessionId,
        'occurredAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  } on DioException {
    // Telemetry must not interrupt access to published content.
  }
}

class ContentExposure extends StatefulWidget {
  const ContentExposure({
    required this.onVisible,
    required this.child,
    this.impression = true,
    super.key,
  });

  final Future<void> Function() onVisible;
  final Widget child;
  final bool impression;

  @override
  State<ContentExposure> createState() => _ContentExposureState();
}

class _ContentExposureState extends State<ContentExposure>
    with WidgetsBindingObserver {
  final _boxKey = GlobalKey();
  ScrollPosition? _position;
  Timer? _dwell;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sent) return;
    ModalRoute.isCurrentOf(context);
    final position = Scrollable.maybeOf(context)?.position;
    if (_position != position) {
      _position?.removeListener(_onScroll);
      _position = position;
      _position?.addListener(_onScroll);
    }
    _afterLayout();
  }

  @override
  void didUpdateWidget(covariant ContentExposure oldWidget) {
    super.didUpdateWidget(oldWidget);
    _afterLayout();
  }

  void _afterLayout() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());

  void _onScroll() {
    _check();
    _afterLayout();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _afterLayout();
    } else {
      _cancel();
    }
  }

  @override
  void didChangeMetrics() => _afterLayout();

  bool _visible() {
    if (!mounted || ModalRoute.isCurrentOf(context) == false) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    final box = _boxKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final bounds = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    if (bounds.isEmpty) return false;
    final viewport = RenderAbstractViewport.maybeOf(box);
    final viewportBox = viewport is RenderBox ? viewport as RenderBox : null;
    var clip = Offset.zero & MediaQuery.sizeOf(context);
    if (viewportBox != null && viewportBox.attached && viewportBox.hasSize) {
      clip = clip.intersect(
        MatrixUtils.transformRect(
          viewportBox.getTransformTo(null),
          Offset.zero & viewportBox.size,
        ),
      );
    }
    final visible = bounds.intersect(clip);
    return !visible.isEmpty &&
        (!widget.impression ||
            visible.width * visible.height >=
                bounds.width * bounds.height * 0.5);
  }

  void _check() {
    if (_sent || !mounted) return;
    if (!_visible()) {
      _cancel();
      return;
    }
    if (!widget.impression) {
      _send();
    } else {
      _dwell ??= Timer(const Duration(seconds: 1), () {
        _dwell = null;
        if (_visible()) _send();
      });
    }
  }

  void _send() {
    _sent = true;
    _position?.removeListener(_onScroll);
    _position = null;
    unawaited(widget.onVisible());
  }

  void _cancel() {
    _dwell?.cancel();
    _dwell = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _position?.removeListener(_onScroll);
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(key: _boxKey, child: widget.child);
}

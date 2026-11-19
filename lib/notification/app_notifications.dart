import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account/app_api.dart';
import '../design/content_skeleton.dart';
import '../design/status_message.dart';
import '../design/tokens.dart';
import 'notification_device.dart';

const _path = '/api/v1/notifications';
const _preferences = '$_path/preferences';
const _filters = {
  'ALL': '전체',
  'DIAGNOSIS': '진단',
  'GUIDE': '가이드',
  'ECONOMY': '경제 요약',
};
const _switches = {
  'ENABLED': ('enabled', '전체 푸시 알림', '모든 푸시를 한 번에 켜거나 끌 수 있어요.'),
  'PERIODIC': ('periodic', '정기 진단 리마인드', '마지막 진단 완료 30일 이후 첫 오후 8시'),
  'INCOMPLETE': ('incomplete', '미완료 진단 안내', '진단을 멈추고 24시간 이후 첫 오후 8시'),
  'GUIDE': ('guide', '맞춤 가이드 행동 알림', '미완료 가이드 첫 열람 3일 이후 첫 오후 8시'),
  'ECONOMY': ('economy', '아침 경제 요약', '새 기사가 게시된 날 오전 8시'),
};

Future<Response<Map<String, dynamic>>> _inbox(
  AppApi api,
  String filter, [
  String? before,
]) => api.request<Map<String, dynamic>>(
  'GET',
  Uri(
    path: _path,
    queryParameters: {'filter': filter, 'before': ?before},
  ).toString(),
);

class NotificationEntry extends StatefulWidget {
  const NotificationEntry({
    required this.api,
    required this.openTarget,
    this.compact = false,
    this.inboxNavigationBar,
    super.key,
  });
  final AppApi api;
  final Future<void> Function(BuildContext, Map<String, dynamic>) openTarget;
  final bool compact;
  final WidgetBuilder? inboxNavigationBar;

  static Future<void> openInbox(
    BuildContext context, {
    required AppApi api,
    required Future<void> Function(BuildContext, Map<String, dynamic>)
    openTarget,
    String? notificationId,
    WidgetBuilder? inboxNavigationBar,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _NotificationInbox(
        api: api,
        openTarget: openTarget,
        notificationId: notificationId,
        navigationBar: inboxNavigationBar,
      ),
    ),
  );

  @override
  State<NotificationEntry> createState() => _NotificationEntryState();
}

class _NotificationEntryState extends State<NotificationEntry> {
  late var _page = _inbox(widget.api, 'ALL');

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _page,
    builder: (context, snapshot) {
      final unread = snapshot.data?.data?['unread'] == true;
      final icon = Badge(
        backgroundColor: FinsightColors.primary,
        isLabelVisible: unread,
        child: const Icon(Icons.notifications_outlined),
      );
      final label = unread ? '알림 · 읽지 않은 항목 있음' : '알림';
      Future<void> open() async {
        await NotificationEntry.openInbox(
          context,
          api: widget.api,
          openTarget: widget.openTarget,
          inboxNavigationBar: widget.inboxNavigationBar,
        );
        if (mounted) {
          setState(() {
            _page = _inbox(widget.api, 'ALL');
          });
        }
      }

      return widget.compact
          ? IconButton(
              tooltip: label,
              icon: icon,
              color: Theme.of(context).colorScheme.primary,
              onPressed: open,
            )
          : TextButton.icon(icon: icon, label: Text(label), onPressed: open);
    },
  );
}

class _NotificationInbox extends StatefulWidget {
  const _NotificationInbox({
    required this.api,
    required this.openTarget,
    this.notificationId,
    this.navigationBar,
  });
  final String? notificationId;
  final WidgetBuilder? navigationBar;
  final AppApi api;
  final Future<void> Function(BuildContext, Map<String, dynamic>) openTarget;

  @override
  State<_NotificationInbox> createState() => _NotificationInboxState();
}

class _NotificationInboxState extends State<_NotificationInbox> {
  var _filter = 'ALL';
  late var _page = _inbox(widget.api, _filter);
  final _extra = <Map<String, dynamic>>[];
  final _read = <String>{};
  String? _next;
  bool _loadedMore = false;
  String? _error;
  bool _busy = false;
  String? _retryTarget;

  @override
  void initState() {
    super.initState();
    if (widget.notificationId case final id?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_open(id));
      });
    }
  }

  void _select(String filter) {
    setState(() {
      _filter = filter;
      _extra.clear();
      _next = null;
      _loadedMore = false;
      _error = null;
      _retryTarget = null;
      _page = _inbox(widget.api, filter);
    });
  }

  Future<void> _more(String before) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = (await _inbox(widget.api, _filter, before)).data!;
      if (!mounted) return;
      _extra.addAll((result['items'] as List).cast<Map<String, dynamic>>());
      _next = result['nextCursor'] as String?;
      _loadedMore = true;
    } on DioException {
      _error = '알림을 더 불러오지 못했어요. 다시 시도해주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String id) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _retryTarget = null;
    });
    try {
      await widget.api.request<void>('PUT', '$_path/$id/read');
      if (!mounted) return;
      _read.add(id);
      final target = await widget.api.request<Map<String, dynamic>>(
        'GET',
        '$_path/$id/target',
      );
      if (!mounted) return;
      final destination = target.data!;
      if (destination['kind'] == 'NOTICE') {
        await _openNotice(destination);
      } else {
        await widget.openTarget(context, destination);
      }
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 404) {
        _select(_filter);
        _error = '이미 삭제되었거나 보관 기간이 지난 알림이에요.';
      } else {
        _error = '알림을 열지 못했어요. 다시 시도해주세요.';
        _retryTarget = id;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openNotice(Map<String, dynamic> target) async {
    final notice = target['notice'];
    if (target['available'] != true || notice is! Map<String, dynamic>) {
      _error = switch (target['reason']) {
        'EXPIRED' => '게시 기간이 끝난 공지예요.',
        'UNPUBLISHED' => '현재 공개되지 않은 공지예요.',
        _ => '삭제되었거나 확인할 수 없는 공지예요.',
      };
      return;
    }
    final theme = Theme.of(context).textTheme;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: '공지 닫기',
                  onPressed: () => Navigator.of(sheet).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    Text(notice['title'] as String, style: theme.headlineSmall),
                    const SizedBox(height: 16),
                    Text(notice['summary'] as String, style: theme.titleMedium),
                    const SizedBox(height: 16),
                    Text(notice['body'] as String),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPreferences() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationPreferences(api: widget.api),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _page,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      final page = loading ? null : snapshot.data?.data;
      final items = [
        if (page != null)
          ...(page['items'] as List).cast<Map<String, dynamic>>(),
        ..._extra,
      ];
      final next = _loadedMore ? _next : page?['nextCursor'] as String?;
      final now = _koreanTime(DateTime.now());
      final today = <Map<String, dynamic>>[];
      final earlier = <Map<String, dynamic>>[];
      for (final item in items) {
        final created = _koreanTime(
          DateTime.parse(item['createdAt'] as String),
        );
        (DateUtils.isSameDay(now, created) ? today : earlier).add(item);
      }

      return _NotificationPage(
        title: '알림',
        navigationBar: items.isEmpty
            ? null
            : widget.navigationBar?.call(context),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: '알림 설정',
              icon: const Icon(Icons.settings_outlined),
              onPressed: _openPreferences,
            ),
        ],
        children: [
          const SizedBox(height: 12),
          const _PageHeading('놓치지 않도록 알려드릴게요', '나에게 필요한 순간만, 가볍게'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              for (final entry in _filters.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  labelStyle: FinsightTypography.bodyM14.copyWith(
                    color: _filter == entry.key
                        ? FinsightColors.gray1000
                        : FinsightColors.gray300,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                  showCheckmark: false,
                  selectedColor: FinsightColors.primary,
                  backgroundColor: FinsightColors.gray900,
                  selected: _filter == entry.key,
                  onSelected: _busy
                      ? null
                      : (selected) {
                          if (selected) _select(entry.key);
                        },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const ContentSkeleton(
              label: '알림 불러오는 중',
              child: SkeletonRows(showLeading: true),
            )
          else if (snapshot.hasError)
            TextButton(
              onPressed: () => _select(_filter),
              child: const Text('알림을 불러오지 못했어요. 다시 시도'),
            )
          else if (items.isEmpty) ...[
            const SizedBox(height: 34),
            ExcludeSemantics(
              child: Image.asset(
                'assets/illustrations/notification-empty.png',
                height: 124,
              ),
            ),
            const SizedBox(height: 34),
            const Text(
              '아직 알림이 없어요',
              textAlign: TextAlign.center,
              style: FinsightTypography.titleSb18,
            ),
            const SizedBox(height: 8),
            Text(
              '진단 일정·맞춤 가이드·경제 소식을\n확인할 수 있어요.',
              textAlign: TextAlign.center,
              style: FinsightTypography.bodyR14.copyWith(
                color: FinsightColors.gray400,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _openPreferences,
              child: const Text('알림 설정하기'),
            ),
          ] else ...[
            if (today.isNotEmpty) _group('오늘', today, now),
            if (earlier.isNotEmpty) _group('지난 알림', earlier, now),
            if (next != null)
              TextButton(
                onPressed: _busy ? null : () => _more(next),
                child: const Text('더 보기'),
              ),
          ],
          StatusMessage(_error),
          if (_retryTarget case final id?)
            TextButton(
              onPressed: _busy ? null : () => _open(id),
              child: const Text('다시 열기'),
            ),
        ],
      );
    },
  );

  Widget _group(String title, List<Map<String, dynamic>> items, DateTime now) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: FinsightTypography.bodySb16),
            const SizedBox(height: 10),
            _NotificationCard(
              children: [for (final item in items) _row(item, now)],
            ),
          ],
        ),
      );

  Widget _row(Map<String, dynamic> item, DateTime now) {
    final id = item['id'] as String;
    final unread = item['read'] != true && !_read.contains(id);
    final (icon, tint) = switch (item['kind']) {
      'PERIODIC' ||
      'INCOMPLETE' => (Icons.monitor_heart_outlined, FinsightColors.blue300),
      'GUIDE' => (Icons.auto_awesome_outlined, FinsightColors.orange300),
      'ECONOMY' => (Icons.light_mode_outlined, FinsightColors.primary),
      _ => (Icons.notifications_none, FinsightColors.gray300),
    };
    final date = _koreanTime(DateTime.parse(item['createdAt'] as String));
    final period = date.hour < 12 ? '오전' : '오후';
    final hour = (date.hour + 11) % 12 + 1;
    final minute = date.minute.toString().padLeft(2, '0');
    final year = date.year == now.year ? '' : '${date.year}년 ';
    final time = '$period $hour:$minute';
    final timestamp = DateUtils.isSameDay(now, date)
        ? time
        : '$year${date.month}월 ${date.day}일 · $time';
    return InkWell(
      onTap: _busy ? null : () => _open(id),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(icon, size: 16, color: tint),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] as String,
                    style: FinsightTypography.bodySb14,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['body'] as String,
                    style: FinsightTypography.bodyR14.copyWith(
                      color: FinsightColors.gray300,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timestamp,
                    style: FinsightTypography.labelR12.copyWith(
                      color: FinsightColors.gray500,
                    ),
                  ),
                ],
              ),
            ),
            if (unread)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 5),
                child: Semantics(
                  label: '읽지 않음',
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: FinsightColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(dimension: 6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NotificationPreferences extends StatefulWidget {
  const NotificationPreferences({required this.api, super.key});
  final AppApi api;

  @override
  State<NotificationPreferences> createState() =>
      _NotificationPreferencesState();
}

class _NotificationPreferencesState extends State<NotificationPreferences>
    with WidgetsBindingObserver {
  late var _result = _load();
  Map<String, dynamic>? _saved;
  DeviceNotificationPermission? _permission;
  int _permissionRequest = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (NotificationDevice.isIOS) {
      WidgetsBinding.instance.addObserver(this);
      _refreshPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final request = ++_permissionRequest;
    DeviceNotificationPermission result;
    try {
      result = await NotificationDevice.permission();
    } on PlatformException {
      result = DeviceNotificationPermission.unknown;
    } on MissingPluginException {
      result = DeviceNotificationPermission.unknown;
    }
    if (mounted && request == _permissionRequest) {
      setState(() => _permission = result);
    }
  }

  Future<void> _openSettings() async {
    try {
      if (await NotificationDevice.openSettings()) return;
    } on PlatformException {
      // Allow the user to retry opening Settings.
    }
    if (mounted) {
      setState(() => _error = '기기 설정을 열지 못했어요. 다시 시도해주세요.');
    }
  }

  Future<Response<Map<String, dynamic>>> _load() =>
      widget.api.request<Map<String, dynamic>>('GET', _preferences);

  Future<bool> _confirmPurpose() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('알림 수신 안내'),
          content: const Text('진단, 가이드 실천과 아침 경제 요약 알림을 받을 수 있어요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('계속'),
            ),
          ],
        ),
      ) ==
      true;

  Future<bool> _enableOnDevice() async {
    if (!NotificationDevice.isIOS) return true;
    var permission = await NotificationDevice.permission();
    if (!mounted) return false;
    if (permission == DeviceNotificationPermission.notDetermined) {
      if (!await _confirmPurpose() || !mounted) return false;
      permission = await NotificationDevice.permission(request: true);
    }
    if (!mounted) return false;
    _permissionRequest++;
    setState(() {
      _permission = permission;
      _error = switch (permission) {
        DeviceNotificationPermission.denied ||
        DeviceNotificationPermission.allowed => null,
        _ => '기기 알림 권한을 확인하지 못했어요. 다시 시도해주세요.',
      };
    });
    return permission == DeviceNotificationPermission.allowed;
  }

  Future<void> _save(String setting, bool enabled) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (setting == 'ENABLED' && enabled && !await _enableOnDevice()) return;
      if (!mounted) return;
      _saved = (await widget.api.request<Map<String, dynamic>>(
        'PUT',
        _preferences,
        data: {'setting': setting, 'enabled': enabled},
      )).data!;
      if (setting == 'ENABLED') unawaited(widget.api.syncNotificationDevice());
    } on DioException {
      _error = '알림 설정을 저장하지 못했어요. 다시 시도해주세요.';
    } on PlatformException {
      _error = '기기 알림 권한을 확인하지 못했어요. 다시 시도해주세요.';
    } on MissingPluginException {
      _error = '기기 알림 권한을 확인하지 못했어요. 다시 시도해주세요.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _permissionLabel => !NotificationDevice.isIOS
      ? '기기 알림 권한은 iOS 앱에서 확인할 수 있어요.'
      : switch (_permission) {
          DeviceNotificationPermission.allowed => '허용됨',
          DeviceNotificationPermission.denied => '차단됨',
          DeviceNotificationPermission.notDetermined => '아직 요청하지 않았어요.',
          DeviceNotificationPermission.unknown => '권한을 확인하지 못했어요.',
          null => '확인 중',
        };

  @override
  Widget build(BuildContext context) => _NotificationPage(
    title: '알림 설정',
    children: [
      const _PageHeading('알림 설정', '원할 때 언제든 변경할 수 있어요'),
      if (_permission == DeviceNotificationPermission.denied)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_permissionLabel),
          subtitle: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _openSettings,
              child: const Text('기기 설정 열기'),
            ),
          ),
        ),
      const SizedBox(height: 16),
      FutureBuilder(
        future: _result,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ContentSkeleton(
              label: '알림 설정 불러오는 중',
              child: SkeletonRows(count: 4, showSubtitle: false),
            );
          }
          if (snapshot.hasError) {
            return TextButton(
              onPressed: () => setState(() {
                _result = _load();
              }),
              child: const Text('알림 설정을 불러오지 못했어요. 다시 시도'),
            );
          }
          final preferences = _saved ?? snapshot.data!.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NotificationCard(children: [_switch('ENABLED', preferences)]),
              StatusMessage(_error, reservedLines: 3),
              const SizedBox(height: 20),
              const Text('진단 및 행동 알림', style: FinsightTypography.bodySb16),
              const SizedBox(height: 10),
              _NotificationCard(
                children: [
                  for (final setting in ['PERIODIC', 'INCOMPLETE', 'GUIDE'])
                    _switch(setting, preferences),
                ],
              ),
              const SizedBox(height: 20),
              const Text('콘텐츠 알림', style: FinsightTypography.bodySb16),
              const SizedBox(height: 10),
              _NotificationCard(children: [_switch('ECONOMY', preferences)]),
            ],
          );
        },
      ),
      const SizedBox(height: 16),
      if (_permission != DeviceNotificationPermission.denied)
        ListTile(
          title: const Text('기기 알림 권한'),
          subtitle: Text(_permissionLabel),
        ),
      if (_permission == DeviceNotificationPermission.unknown)
        TextButton(
          onPressed: _refreshPermission,
          child: const Text('권한 다시 확인'),
        ),
    ],
  );

  Widget _switch(String setting, Map<String, dynamic> preferences) {
    final (key, label, description) = _switches[setting]!;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      title: Text(label, style: FinsightTypography.bodyM14),
      subtitle: Text(
        description,
        style: FinsightTypography.labelR12.copyWith(
          color: FinsightColors.gray400,
        ),
      ),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return null;
        return states.contains(WidgetState.selected)
            ? FinsightColors.primary
            : FinsightColors.gray750;
      }),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? null
            : FinsightColors.gray1000,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      value: preferences[key] == true,
      onChanged: _busy ? null : (enabled) => _save(setting, enabled),
    );
  }
}

DateTime _koreanTime(DateTime date) =>
    date.toUtc().add(const Duration(hours: 9));

class _PageHeading extends StatelessWidget {
  const _PageHeading(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: FinsightTypography.displaySb28),
      const SizedBox(height: 5),
      Text(
        subtitle,
        style: FinsightTypography.bodyR14.copyWith(
          color: FinsightColors.gray400,
        ),
      ),
    ],
  );
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: FinsightColors.gray900,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (final (index, child) in children.indexed) ...[
          if (index > 0)
            const Divider(
              height: 1,
              indent: 12,
              endIndent: 12,
              color: FinsightColors.gray800,
            ),
          child,
        ],
      ],
    ),
  );
}

class _NotificationPage extends StatelessWidget {
  const _NotificationPage({
    required this.title,
    required this.children,
    this.actions,
    this.navigationBar,
  });
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? navigationBar;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      scrolledUnderElevation: 0,
      title: Text(title, style: FinsightTypography.bodySb16),
      actions: actions,
    ),
    bottomNavigationBar: navigationBar,
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: children,
          ),
        ),
      ),
    ),
  );
}

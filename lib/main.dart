import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'account/app_api.dart';
import 'account/app_login.dart' show AppLogin;
import 'account/app_session_store.dart';
import 'account/password_reset.dart';
import 'account/signup_consent.dart';
import 'account/signup_credentials.dart';
import 'account/signup_profile.dart';
import 'account/signup_verification.dart';
import 'account/social_login.dart';
import 'design/finsight_theme.dart';
import 'design/finsight_wordmark.dart';
import 'diagnosis/home_widget_platform.dart';
import 'notification/notification_device.dart';

void main() {
  runApp(const ProviderScope(child: FinsightApp()));
}

const _emailSignupEnabled = bool.fromEnvironment(
  'FINSIGHT_EMAIL_SIGNUP_ENABLED',
  defaultValue: !kReleaseMode,
);

final GoRouter _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const _LaunchScreen()),
    GoRoute(
      path: '/login',
      builder: (context, state) => AppLogin(
        initialLink: state.extra is PendingSocialLink
            ? state.extra as PendingSocialLink
            : null,
      ),
    ),
    GoRoute(
      path: '/password-reset/request',
      builder: (context, state) =>
          PasswordResetRequest(initialEmail: state.extra as String?),
    ),
    GoRoute(
      path: '/password-reset',
      builder: (context, state) {
        final native = state.extra is _NativeResetLink
            ? state.extra as _NativeResetLink
            : null;
        final tokens = state.uri.queryParametersAll['token'];
        return PasswordResetComplete(
          key: native == null ? null : ObjectKey(native),
          token: native?.token ?? (tokens?.length == 1 ? tokens!.single : null),
        );
      },
    ),
    GoRoute(
      path: '/password-reset/done',
      builder: (context, state) => const PasswordResetDone(),
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => SignupCredentials(
        onContinue: _emailSignupEnabled
            ? (email, password) =>
                  _continueEmailSignup(context, email, password)
            : null,
      ),
    ),
  ],
);

void _continueEmailSignup(BuildContext context, String email, String password) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => SignupProfile(
        onContinue: (profile) async {
          final consent = await showSignupConsent(context);
          if (consent == null || !context.mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => SignupVerification(
                email: email,
                password: password,
                profile: profile,
                consent: consent,
                onSessionEnded: () => _router.go('/'),
                onDone: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  _router.push('/login');
                },
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _NativeResetLink {
  const _NativeResetLink(this.token);

  final String token;
}

class FinsightApp extends StatefulWidget {
  const FinsightApp({super.key});

  @override
  State<FinsightApp> createState() => _FinsightAppState();
}

class _FinsightAppState extends State<FinsightApp> {
  static const _links = MethodChannel('finsight/password_reset_links');
  static final _token = RegExp(r'^[A-Za-z0-9_-]{43}$');

  @override
  void initState() {
    super.initState();
    if (HomeWidgetPlatform.instance.isNative) {
      _links.setMethodCallHandler((call) async {
        if (call.method == 'open') await _openResetLink();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _openResetLink());
    }
  }

  Future<void> _openResetLink() async {
    try {
      final token = await _links.invokeMethod<String>('take');
      if (mounted && token != null && _token.hasMatch(token)) {
        _router.go('/password-reset', extra: _NativeResetLink(token));
      }
    } on MissingPluginException {
      // The channel is available only in the iOS runner.
    }
  }

  @override
  void dispose() {
    if (HomeWidgetPlatform.instance.isNative) _links.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'FINSIGHT',
      debugShowCheckedModeBanner: false,
      theme: finsightTheme(),
      routerConfig: _router,
    );
  }
}

class _LaunchScreen extends StatefulWidget {
  const _LaunchScreen();

  @override
  State<_LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<_LaunchScreen>
    with WidgetsBindingObserver {
  final _api = AppApi(sessionStore: appSessionStore);
  bool _busy = true;
  bool _slow = false;
  bool _failed = false;
  bool _welcome = false;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _api.flushPendingRevocations();
  }

  Future<void> _restore() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _failed = false;
      _slow = false;
    });
    _delay = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _slow = true);
    });
    try {
      final outcome = await _api.restore();
      _delay?.cancel();
      if (!mounted) return;
      if (outcome == SessionRestore.expired) {
        unawaited(HomeWidgetPlatform.instance.clear());
        context.go('/login');
        return;
      }
      if (outcome == SessionRestore.restored) {
        await openAuthenticatedHome(context, _api);
      }
      if (mounted) setState(() => _welcome = true);
    } on Exception {
      if (mounted) setState(() => _failed = true);
    } finally {
      _delay?.cancel();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _delay?.cancel();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_welcome) return const WelcomeScreen();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Align(
          alignment: const Alignment(0, -0.09),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FinsightWordmark(width: 163),
                if (_busy && _slow) ...[
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  const Text('로그인 확인에 시간이 걸리고 있어요.'),
                ],
                if (_failed) ...[
                  const SizedBox(height: 20),
                  const Text(
                    '로그인 상태를 확인하지 못했어요. 인터넷 연결을 확인해주세요.',
                    textAlign: TextAlign.center,
                  ),
                  FilledButton(onPressed: _restore, child: const Text('다시 시도')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  StreamSubscription<void>? _widgetOpens;
  StreamSubscription<void>? _notificationOpens;
  bool _checkingExternalOpen = false;

  @override
  void initState() {
    super.initState();
    final platform = HomeWidgetPlatform.instance;
    if (!platform.isNative) return;
    _widgetOpens = platform.opens.listen((_) => _loginForExternalOpen());
    _notificationOpens = NotificationOpens.instance.opens.listen(
      (_) => _loginForExternalOpen(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loginForExternalOpen(),
    );
  }

  Future<void> _loginForExternalOpen() async {
    if (!mounted ||
        _checkingExternalOpen ||
        ModalRoute.isCurrentOf(context) != true) {
      return;
    }
    _checkingExternalOpen = true;
    try {
      final pending =
          await NotificationOpens.instance.peek() ||
          await HomeWidgetPlatform.instance.peekOpen();
      if (pending && mounted && ModalRoute.isCurrentOf(context) == true) {
        context.push('/login');
      }
    } finally {
      _checkingExternalOpen = false;
    }
  }

  @override
  void dispose() {
    _widgetOpens?.cancel();
    _notificationOpens?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typography = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const top = 24.0;
            final bottom = (constraints.maxHeight * .16).clamp(24.0, 122.0);
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, top, 24, bottom),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 440,
                    minHeight: (constraints.maxHeight - top - bottom).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FinsightWordmark(width: 163),
                          const SizedBox(height: 28),
                          Text(
                            '돈 걱정,\n얼마나 하고\n계신가요?',
                            style: typography.displayLarge,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '약 5분이면 충분해요.\n나의 금융 스트레스를 알아보세요.',
                            style: typography.bodyLarge,
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton(
                              onPressed: () => context.push('/signup'),
                              child: const Text('시작하기'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => context.push('/login'),
                              child: Text.rich(
                                TextSpan(
                                  text: '이미 계정이 있나요? ',
                                  style: typography.labelMedium?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '로그인하기',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

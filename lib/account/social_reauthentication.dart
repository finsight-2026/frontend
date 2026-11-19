import 'package:flutter/material.dart';

import 'app_api.dart';
import 'social_authentication.dart';

Future<bool> verifyWithSocialProvider(
  AppApi api,
  SocialProvider provider,
) async {
  final result = await SocialAuthentication(
    api,
  ).authenticate(provider, SocialPurpose.reauth);
  if (result == null || result['status'] == 'CANCELED') return false;
  if (result['status'] != 'REAUTHENTICATED') {
    throw StateError('The provider did not verify the signed-in account');
  }
  return true;
}

class SocialReauthOptions extends StatefulWidget {
  const SocialReauthOptions({
    required this.api,
    required this.onPressed,
    required this.enabled,
    super.key,
  });

  final AppApi api;
  final ValueChanged<SocialProvider> onPressed;
  final bool enabled;

  @override
  State<SocialReauthOptions> createState() => _SocialReauthOptionsState();
}

class _SocialReauthOptionsState extends State<SocialReauthOptions> {
  late final _providers = _load();

  Future<List<SocialProvider>> _load() async {
    final providers = await SocialAuthentication(widget.api).providers();
    if (providers.isEmpty) return [];
    final identity = (await widget.api.request<Map<String, dynamic>>(
      'GET',
      '/api/v1/account/settings',
    )).data!;
    final connected = identity['socialProviders'] as List<dynamic>? ?? [];
    return providers
        .where((provider) => connected.contains(provider.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _providers,
    builder: (context, snapshot) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final provider in snapshot.data ?? const <SocialProvider>[])
          TextButton(
            onPressed: widget.enabled ? () => widget.onPressed(provider) : null,
            child: Text('${provider.label}로 본인 확인'),
          ),
      ],
    ),
  );
}

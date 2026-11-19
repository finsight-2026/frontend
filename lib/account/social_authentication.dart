import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_api.dart';

enum SocialProvider {
  kakao('KAKAO', '카카오'),
  apple('APPLE', 'Apple');

  const SocialProvider(this.id, this.label);
  final String id;
  final String label;
}

enum SocialPurpose {
  login('LOGIN', false),
  link('LINK', true),
  reauth('REAUTH', true),
  cancelWithdrawal('CANCEL_WITHDRAWAL', false);

  const SocialPurpose(this.id, this.account);
  final String id;
  final bool account;
}

class SocialAuthentication {
  const SocialAuthentication(this.api);

  static const _channel = MethodChannel('finsight/social_authentication');
  static const _auth = '/api/v1/auth/social';
  static const _account = '/api/v1/account/social';

  final AppApi api;

  Future<List<SocialProvider>> providers() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return [];
    final response = await api.request<List<dynamic>>(
      'GET',
      '$_auth/providers',
    );
    return SocialProvider.values
        .where((provider) => response.data!.contains(provider.id))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> authenticate(
    SocialProvider provider,
    SocialPurpose purpose,
  ) async {
    final base = purpose.account ? _account : _auth;
    final started = (await api.request<Map<String, dynamic>>(
      'POST',
      '$base/start',
      data: {
        'provider': provider.id,
        'purpose': purpose.id,
        if (purpose == SocialPurpose.cancelWithdrawal) 'confirmed': true,
      },
    )).data!;
    final state = started['state'] as String;
    final raw = await _channel.invokeMethod<String>('authenticate', {
      'url': started['authorizationUrl'] as String,
      'reauthenticate':
          purpose == SocialPurpose.reauth ||
          purpose == SocialPurpose.cancelWithdrawal,
    });
    if (raw == null) return null;
    final callback = Uri.tryParse(raw);
    if (callback == null ||
        callback.scheme != 'finsight-social' ||
        callback.host != 'auth' ||
        callback.path != '/complete' ||
        callback.hasPort ||
        callback.userInfo.isNotEmpty ||
        callback.hasFragment ||
        callback.queryParametersAll.length != 1 ||
        !listEquals(callback.queryParametersAll['state'], [state])) {
      throw const FormatException('Unexpected social authentication callback');
    }
    return (await api.request<Map<String, dynamic>>(
      'POST',
      '$base/finish',
      data: {'state': state, 'verifier': started['verifier'] as String},
    )).data;
  }

  Future<Map<String, dynamic>> register({
    required String token,
    required String email,
    required Map<String, String> profile,
    required String version,
    required bool research,
  }) async => (await api.request<Map<String, dynamic>>(
    'POST',
    '$_auth/register',
    data: {
      'onboardingToken': token,
      'email': email,
      'profile': profile,
      'terms': true,
      'privacy': true,
      'research': research,
      'documentVersion': version,
    },
  )).data!;

  Future<String> linkMatchingEmail(String token) async =>
      (await api.request<Map<String, dynamic>>(
            'POST',
            '$_account/link',
            data: {'onboardingToken': token},
          )).data!['status']
          as String;

  Future<String> unlink(SocialProvider provider) async =>
      (await api.request<Map<String, dynamic>>(
            'DELETE',
            '$_account/${provider.id}',
          )).data!['status']
          as String;
}

import 'package:flutter/material.dart';

import '../design/finsight_wordmark.dart';
import '../design/status_message.dart';
import 'signup_consent.dart';
import 'signup_layout.dart';
import 'signup_profile.dart';
import 'social_authentication.dart';

class SocialSignupComplete extends StatelessWidget {
  const SocialSignupComplete({required this.email, super.key});

  final String email;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const FinsightWordmark(width: 98),
      centerTitle: true,
      scrolledUnderElevation: 0,
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SignupCompleteContent(email: email),
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(24, 8, 24, 50),
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('지금 시작하기'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<Map<String, dynamic>?> openSocialSignup(
  BuildContext context,
  SocialAuthentication social,
  String token,
  String verifiedEmail,
) => Navigator.of(context).push<Map<String, dynamic>>(
  MaterialPageRoute(
    builder: (profilePage) => SignupProfile(
      email: verifiedEmail,
      onContinue: (profile) async {
        final consent = await showSignupConsent(profilePage, api: social.api);
        if (consent == null || !profilePage.mounted) return;

        final result = await social.register(
          token: token,
          email: verifiedEmail,
          profile: profile,
          version: consent.version,
          research: consent.research,
        );
        if (!profilePage.mounted) return;
        switch (result['status']) {
          case 'CREATED':
          case 'EXISTING_ACCOUNT':
            Navigator.pop(profilePage, result);
          default:
            final message = switch (result['status']) {
              'POLICY_CHANGED' => '약관이 바뀌었어요. 다음을 눌러 최신 문서를 확인해주세요.',
              'EXPIRED' || 'IDENTITY_IN_USE' => '소셜 인증을 다시 시작해주세요.',
              _ => '가입 정보를 확인하고 다시 시도해주세요.',
            };
            ScaffoldMessenger.of(
              profilePage,
            ).showSnackBar(statusSnackBar(message, tone: StatusTone.warning));
        }
      },
    ),
  ),
);

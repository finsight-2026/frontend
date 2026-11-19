import 'package:flutter/material.dart';

import '../design/status_message.dart';
import '../design/tokens.dart';

const signupValidationSpace = StatusMessage(null, reservedLines: 2);

Widget signupValidationError(BuildContext context, String error) =>
    StatusMessage(error, reservedLines: 2);

class SignupProgress extends StatelessWidget {
  const SignupProgress(this.step, {super.key});

  final int step;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '가입 $step단계, 전체 3단계',
    child: Row(
      children: [
        for (var index = 1; index <= 3; index++) ...[
          if (index > 1) const SizedBox(width: 8),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: index <= step
                    ? Theme.of(context).colorScheme.primary
                    : FinsightColors.gray300,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const SizedBox(height: 4),
            ),
          ),
        ],
      ],
    ),
  );
}

InputDecoration signupInputDecoration(String label, {String? hint}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      filled: true,
      fillColor: FinsightColors.gray900,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: FinsightColors.gray900),
      ),
    );

class SignupCompleteContent extends StatelessWidget {
  const SignupCompleteContent({required this.email, super.key});

  final String email;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: (MediaQuery.sizeOf(context).height * .124).clamp(36.0, 108.0),
      ),
      Image.asset(
        'assets/illustrations/signup-complete.png',
        height: 124,
        excludeFromSemantics: true,
      ),
      const SizedBox(height: 28),
      Text('$email 님,', textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        'FINSIGHT 가입이 완료됐어요.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: 20),
      for (final benefit in const [
        '내 금융 스트레스를 살펴볼 수 있어요.',
        '진단 결과에 맞는 가이드를 확인할 수 있어요.',
        '아침 경제 소식을 확인할 수 있어요.',
      ])
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.check,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(benefit),
        ),
    ],
  );
}

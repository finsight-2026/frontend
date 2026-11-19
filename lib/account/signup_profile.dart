import 'dart:async';

import 'package:flutter/material.dart';

import '../design/status_message.dart';
import '../design/tokens.dart';
import 'signup_layout.dart';

const _age = [
  ('UNDER_19', '만 18세 이하'),
  ('19_22', '만 19세 ~ 22세'),
  ('23_25', '만 23세 ~ 25세'),
  ('26_29', '만 26세 ~ 29세'),
  ('30_PLUS', '만 30세 이상'),
];
const _situation = [
  ('COLLEGE_EARLY', '대학 1~2학년 재학 중'),
  ('COLLEGE_LATE', '대학 3~4학년 이상 재학 중'),
  ('JOB_SEEKER', '졸업 후 구직 중'),
  ('EMPLOYED', '직장인'),
  ('OTHER', '기타 (직접 입력)'),
];
const _gender = [('MALE', '남자'), ('FEMALE', '여자'), ('UNDISCLOSED', '응답하지 않음')];
const _housing = [
  ('WITH_FAMILY', '부모·가족과 함께 거주'),
  ('MONTHLY_RENT', '자취 - 월세'),
  ('JEONSE', '자취 - 전세'),
  ('OWNED', '자가'),
  ('DORMITORY', '기숙사'),
  ('OTHER', '기타 (직접 입력)'),
];
const _income = [
  ('REGULAR', '정기적인 근로소득이 있음'),
  ('IRREGULAR', '아르바이트·프리랜서 등 비정기적인 소득이 있음'),
  ('SUPPORT', '용돈·생활비 지원이 주된 소득원임'),
  ('NONE', '별도의 정기적 소득이 없음'),
  ('OTHER', '기타 (직접 입력)'),
];
const _debt = [
  ('YES', '있음'),
  ('NO', '없음'),
  ('UNKNOWN', '잘 모르겠음'),
  ('UNDISCLOSED', '응답하지 않음'),
  ('OTHER', '기타 (직접 입력)'),
];
const _debtType = [
  ('STUDENT', '학자금 대출'),
  ('CREDIT', '신용대출'),
  ('HOUSING', '전·월세 관련 대출'),
  ('CARD', '카드대금·카드론·현금서비스'),
  ('UNDISCLOSED', '응답하지 않음'),
  ('OTHER', '기타 (직접 입력)'),
];
const _expenses = [
  ('MOSTLY_SUPPORTED', '대부분 가족 등으로부터 지원받음'),
  ('PARTLY_SELF_PAID', '일부 지원받고 일부 본인이 부담함'),
  ('MOSTLY_SELF_PAID', '대부분 본인이 부담함'),
  ('FULLY_SELF_PAID', '전적으로 본인이 부담함'),
];

String profileSummary(Map<String, String> profile) {
  final labels = [
    for (final (value, label) in _age)
      if (profile['age'] == value) label,
    for (final (value, label) in _situation)
      if (profile['situation'] == value)
        value == 'OTHER' ? (profile['situationOther'] ?? '기타') : label,
  ];
  return labels.isEmpty ? '기본 정보가 없어요.' : labels.join(' · ');
}

class SignupProfile extends StatefulWidget {
  const SignupProfile({
    required this.onContinue,
    this.initialProfile,
    this.email,
    this.bottomNavigationBar,
    super.key,
  });

  final FutureOr<void> Function(Map<String, String>) onContinue;
  final Map<String, String>? initialProfile;
  final String? email;
  final Widget? bottomNavigationBar;

  @override
  State<SignupProfile> createState() => _SignupProfileState();
}

class _SignupProfileState extends State<SignupProfile> {
  final _form = GlobalKey<FormState>();
  late final _values = {...?widget.initialProfile};
  bool _saving = false;
  bool _failed = false;

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onContinue(Map.unmodifiable(_values));
    } on Exception {
      _failed = true;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, List<(String, String)> options) {
    final reservedLines = key == 'age' ? 2 : 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            itemHeight: null,
            initialValue: _values[key],
            decoration: signupInputDecoration(label, hint: '선택').copyWith(
              helper: StatusMessage(null, reservedLines: reservedLines),
            ),
            errorBuilder: (_, error) =>
                StatusMessage(error, reservedLines: reservedLines),
            items: [
              for (final (value, text) in options)
                DropdownMenuItem(value: value, child: Text(text)),
            ],
            selectedItemBuilder: (context) => [
              for (final (_, text) in options)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(text),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() {
                      _values[key] = value;
                      if (value != 'OTHER') _values.remove('${key}Other');
                      if (key == 'debt' && value != 'YES') {
                        _values.remove('debtType');
                        _values.remove('debtTypeOther');
                      }
                    });
                  },
            validator: (value) {
              if (value == null) return '항목을 선택해주세요.';
              if (value == 'UNDER_19') return '만 19세 이상부터 가입할 수 있어요.';
              return null;
            },
          ),
          if (_values[key] == 'OTHER')
            TextFormField(
              initialValue: _values['${key}Other'],
              enabled: !_saving,
              maxLength: 50,
              decoration: InputDecoration(
                labelText: '$label 기타 내용',
                helper: signupValidationSpace,
              ),
              errorBuilder: signupValidationError,
              onChanged: (value) => _values['${key}Other'] = value.trim(),
              validator: (value) => value == null || value.trim().isEmpty
                  ? '기타 내용을 입력해주세요.'
                  : null,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final signingUp = widget.initialProfile == null;
    return Scaffold(
      bottomNavigationBar: widget.bottomNavigationBar,
      appBar: AppBar(
        title: Text(signingUp ? '로그인/가입' : '내 정보 수정'),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(24, signingUp ? 8 : 24, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (signingUp) ...[
                      const SignupProgress(2),
                      const SizedBox(height: 44),
                    ],
                    Text(
                      signingUp ? '조금만 더 알려주세요' : '내 정보를 수정해요',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      signingUp
                          ? '정확한 분석을 위해 필요해요'
                          : '기본 정보는 필수이며, 부채가 있는 경우에만 종류를 선택해 주세요.',
                    ),
                    const SizedBox(height: 20),
                    if (widget.email case final email?) ...[
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: FinsightColors.primary,
                            foregroundColor: FinsightColors.gray1000,
                            child: Text(email.characters.first.toUpperCase()),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              email
                                  .replaceAll('@', '@\u200B')
                                  .replaceAll('.', '.\u200B'),
                              semanticsLabel: email,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: FinsightColors.gray800),
                      const SizedBox(height: 12),
                      Text('이메일', style: FinsightTypography.bodySb14),
                      const SizedBox(height: 6),
                      InputDecorator(
                        decoration: signupInputDecoration(''),
                        child: Text(
                          email
                              .replaceAll('@', '@\u200B')
                              .replaceAll('.', '.\u200B'),
                          semanticsLabel: email,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    _field('age', '연령대', _age),
                    _field('situation', '현재 상황', _situation),
                    _field('gender', '성별', _gender),
                    _field('housing', '현재 주거 형태', _housing),
                    _field('income', '주된 소득 상태', _income),
                    _field('debt', '부채 유무', _debt),
                    if (_values['debt'] == 'YES')
                      _field('debtType', '가장 큰 부채', _debtType),
                    _field('expenses', '생활비의 본인 부담 여부', _expenses),
                    StatusMessage(
                      _failed ? '정보를 저장하지 못했어요. 다시 시도해주세요.' : null,
                      reservedLines: 3,
                    ),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: Text(
                        widget.initialProfile == null ? '다음' : '저장하기',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

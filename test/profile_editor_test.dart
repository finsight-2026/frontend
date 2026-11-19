import 'package:finsight/account/signup_profile.dart';
import 'package:finsight/design/finsight_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'profile editor keeps a long email and validates conditional inputs',
    (tester) async {
      tester.view.physicalSize = const Size(320, 650);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewInsets);

      const email = 'an.older.profile.with.a.long.email@example.test';
      Map<String, String>? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: finsightTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.7)),
            child: child!,
          ),
          home: SignupProfile(
            email: email,
            initialProfile: const {
              'age': '19_22',
              'situation': 'EMPLOYED',
              'gender': 'UNDISCLOSED',
              'housing': 'WITH_FAMILY',
              'income': 'REGULAR',
              'debt': 'NO',
              'expenses': 'FULLY_SELF_PAID',
            },
            onContinue: (values) => saved = values,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.semanticsLabel == email,
        ),
        findsNWidgets(2),
      );
      final debt = find.byType(DropdownButtonFormField<String>).at(5);
      await tester.ensureVisible(debt);
      await tester.pumpAndSettle();
      await tester.tap(debt);
      await tester.pumpAndSettle();
      await tester.tap(find.text('있음').last);
      await tester.pumpAndSettle();

      final type = find.byType(DropdownButtonFormField<String>).at(6);
      await tester.ensureVisible(type);
      await tester.pumpAndSettle();
      await tester.tap(type);
      await tester.pumpAndSettle();
      await tester.tap(find.text('기타 (직접 입력)').last);
      await tester.pumpAndSettle();
      final field = find.byType(TextFormField);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.enterText(field, '기타 대출');
      final input = find.byType(EditableText);
      await tester.ensureVisible(input);
      await tester.pumpAndSettle();
      expect(input.hitTestable(), findsOneWidget);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      final submit = find.text('저장하기');
      await tester.ensureVisible(submit);
      await tester.pumpAndSettle();
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(saved, containsPair('debtTypeOther', '기타 대출'));
      expect(saved, isNot(contains('email')));
      expect(tester.takeException(), isNull);
    },
  );
}

import 'package:finsight/main.dart';
import 'package:finsight/account/app_login.dart';
import 'package:finsight/account/signup_credentials.dart';
import 'package:finsight/design/finsight_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FlutterSecureStorage.setMockInitialValues({});
  testWidgets('login moves focus to password with an inset keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44);
    tester.view.viewInsets = const FakeViewPadding(bottom: 270);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        theme: finsightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: const AppLogin(),
      ),
    );
    final fields = find.byType(TextField);
    await tester.enterText(
      fields.first,
      'person-with-a-long-address@example.test',
    );
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).last)
          .focusNode
          .hasFocus,
      isTrue,
    );
    final submit = find.widgetWithText(FilledButton, '로그인');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(submit).dy, lessThanOrEqualTo(568 - 270));
    final before = tester.getRect(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final message = find.text('이메일과 비밀번호를 입력해주세요.');
    expect(tester.widget<Text>(message).style?.color, const Color(0xFFFF484B));
    expect(tester.getRect(submit), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('social-only signup visibly disables email registration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: finsightTheme(), home: const SignupCredentials()),
    );
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(fields, hasLength(3));
    expect(fields.every((field) => !field.enabled), isTrue);
    expect(
      find.text('현재 이메일 기능이 테스트 중이에요.\n카카오 혹은 애플로 가입해주세요.'),
      findsOneWidget,
    );
    final submit = find.widgetWithText(FilledButton, '다음');
    await tester.ensureVisible(submit);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
  });

  testWidgets('signup validation keeps the next button in place', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: finsightTheme(),
        home: SignupCredentials(onContinue: (_, _) {}),
      ),
    );
    final submit = find.widgetWithText(FilledButton, '다음');
    await tester.ensureVisible(submit);
    final before = tester.getRect(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final message = find.text('이메일 주소를 확인해주세요.');
    expect(tester.widget<Text>(message).style?.color, const Color(0xFFFF484B));
    expect(tester.getRect(submit), before);
  });
  testWidgets('intro scrolls on a narrow screen with enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          padding: EdgeInsets.only(top: 44, bottom: 34),
          textScaler: TextScaler.linear(2),
        ),
        child: const FinsightApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('돈 걱정,\n얼마나 하고\n계신가요?'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('시작하기'), 150);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'signup moves through three inputs with the keyboard and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewInsets);
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.7)),
            child: child!,
          ),
          home: SignupCredentials(onContinue: (email, _) => submitted = email),
        ),
      );
      final fields = find.byType(EditableText);
      const email = 'long.test.address.using.multiple.parts@example.test';
      await tester.ensureVisible(fields.at(0));
      await tester.enterText(fields.at(0), email);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(fields.at(1)).focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(fields.at(1), 'Finsight1234');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(fields.at(2)).focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(fields.at(2), 'Finsight1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(submitted, email);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration keeps credential fields when returning from profile',
    (tester) async {
      await tester.pumpWidget(const FinsightApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('시작하기'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'qa@example.test');
      await tester.enterText(fields.at(1), 'Finsight1234');
      await tester.enterText(fields.at(2), 'Finsight1234');
      await tester.ensureVisible(find.text('다음'));
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('조금만 더 알려주세요'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('가입하기'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        'qa@example.test',
      );
    },
  );
}

import 'package:finsight/main.dart';
import 'package:finsight/account/password_reset.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reset validation keeps the submit button in place', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: PasswordResetComplete(token: 'A' * 43)),
    );
    final submit = find.widgetWithText(FilledButton, '비밀번호 변경하기');
    await tester.ensureVisible(submit);
    final before = tester.getRect(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final error = find.text('비밀번호 조건과 확인 입력을 확인해주세요.');
    expect(tester.widget<Text>(error).style?.color, const Color(0xFFFF484B));
    expect(tester.getRect(submit), before);
  });

  testWidgets(
    'reset confirmation stays reachable with the keyboard and enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.7)),
            child: child!,
          ),
          home: PasswordResetComplete(token: 'A' * 43),
        ),
      );
      final fields = find.byType(EditableText);
      await tester.ensureVisible(fields.first);
      await tester.enterText(
        fields.first,
        'LongLocalPasswordThatFitsCorrectly123',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 255);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(fields.last).focusNode.hasFocus,
        isTrue,
      );
      await tester.enterText(fields.last, 'DifferentPassword123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('비밀번호 조건과 확인 입력을 확인해주세요.'),
        80,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'iOS opens a pending reset and accepts a later valid link',
    (tester) async {
      const channel = MethodChannel('finsight/password_reset_links');
      final messenger = tester.binding.defaultBinaryMessenger;
      var pending = 'A' * 43;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'take') return null;
        final token = pending;
        pending = '';
        return token;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(const FinsightApp());
      await tester.pumpAndSettle();
      expect(find.text('새 비밀번호를\n설정해주세요.'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'LocalPass123');

      Future<void> open(String token) async {
        pending = token;
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('open')),
          (_) {},
        );
        await tester.pumpAndSettle();
      }

      await open('invalid');
      expect(tester.widget<TextField>(field).controller?.text, 'LocalPass123');
      await open('B' * 43);
      expect(find.text('새 비밀번호를\n설정해주세요.'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller?.text, isEmpty);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets('reset completion shows its artwork and fits enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: const PasswordResetDone(),
      ),
    );
    final artwork = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              'assets/illustrations/password-reset-unlocked.png',
    );
    expect(tester.getSize(artwork), const Size.square(124));
    expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
    final login = find.widgetWithText(FilledButton, '로그인하기');
    await tester.scrollUntilVisible(login, 80);
    expect(login.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

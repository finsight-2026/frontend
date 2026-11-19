import 'dart:ui' show CheckedState;

import 'package:dio/dio.dart';
import 'package:finsight/account/app_api.dart';
import 'package:finsight/account/signup_consent.dart';
import 'package:finsight/design/finsight_checkbox_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PoliciesApi extends AppApi {
  final paths = <String>[];
  bool detailAvailable = false;

  @override
  Future<Response<T>> request<T>(
    String method,
    String path, {
    Object? data,
  }) async {
    final options = RequestOptions(path: path);
    paths.add('$method $path');
    if (path == '/api/v1/policies') {
      return Response<T>(
        requestOptions: options,
        data:
            <String, dynamic>{
                  'activeVersion': 'release-2',
                  'documents': [
                    for (final (id, title) in [
                      ('terms', '서비스 이용약관'),
                      ('privacy-policy', '개인정보 처리방침'),
                      ('privacy-consent', '수집·이용 동의'),
                      ('research', '연구 활용 안내'),
                    ])
                      <String, dynamic>{
                        'id': id,
                        'title': title,
                        'version': 'release-2',
                        'status': 'CURRENT',
                        'effectiveDate': '2026-11-10',
                      },
                  ],
                }
                as T,
      );
    }
    if (!detailAvailable) throw DioException(requestOptions: options);
    return Response<T>(
      requestOptions: options,
      data:
          <String, dynamic>{
                'document': <String, dynamic>{
                  'id': 'terms',
                  'title': '서비스 이용약관',
                  'version': 'release-2',
                  'status': 'CURRENT',
                  'effectiveDate': '2026-11-10',
                },
                'body': '만 19세 이상',
              }
              as T,
    );
  }
}

void main() {
  testWidgets('required agreements are unchecked and research is optional', (
    tester,
  ) async {
    final api = _PoliciesApi();
    addTearDown(api.close);
    SignupConsent? consent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                consent = await showSignupConsent(context, api: api);
              },
              child: const Text('약관 열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('약관 열기'));
    await tester.pumpAndSettle();

    final next = find.widgetWithText(FilledButton, '동의하고 계속');
    final termsRow = find.widgetWithText(FinsightCheckboxTile, '(필수) 이용약관');
    final termsIcon = find.descendant(
      of: termsRow,
      matching: find.byType(Image),
    );
    final details = find.byTooltip('(필수) 이용약관 자세히 보기');
    String iconAsset() =>
        (tester.widget<Image>(termsIcon).image as AssetImage).assetName;

    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    expect(iconAsset(), 'assets/controls/checkbox-unchecked.png');
    final iconPosition = tester.getRect(termsIcon);
    final buttonPosition = tester.getRect(next);
    expect(iconPosition.size, const Size.square(24));
    expect(find.text('보기'), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_ios_rounded), findsNWidgets(3));
    final labelPosition = tester.getRect(find.text('(필수) 이용약관'));
    expect(iconPosition.right, lessThan(labelPosition.left));
    expect(
      tester.getRect(details).left,
      greaterThanOrEqualTo(labelPosition.right),
    );
    expect(
      tester.getSemantics(termsRow).flagsCollection.isChecked,
      CheckedState.isFalse,
    );
    await tester.tap(termsIcon);
    await tester.pumpAndSettle();
    expect(iconAsset(), 'assets/controls/checkbox-checked.png');
    expect(tester.getRect(termsIcon), iconPosition);
    expect(tester.getRect(next), buttonPosition);
    expect(
      tester.getSemantics(termsRow).flagsCollection.isChecked,
      CheckedState.isTrue,
    );
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text('서비스 이용약관'), findsOneWidget);
    expect(find.text('문서를 불러오지 못했어요.'), findsOneWidget);
    api.detailAvailable = true;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('release-2 · 2026-11-10 시행'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      contains('만 19세 이상'),
    );
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
    tester.platformDispatcher.textScaleFactorTestValue = 1.7;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, '확인했어요');
    expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(568 - 34));
    expect(confirm.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    expect(details.hitTestable(), findsOneWidget);
    expect(
      tester.getRect(termsIcon).right,
      lessThan(tester.getRect(details).left),
    );
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.tap(find.text('(필수) 개인정보 수집 및 이용'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);

    final all = find.text('모두 동의');
    final research = find.widgetWithText(
      FinsightCheckboxTile,
      '(선택) 연구데이터 활용 동의',
    );
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(research).flagsCollection.isChecked,
      CheckedState.isTrue,
    );
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(research).flagsCollection.isChecked,
      CheckedState.isFalse,
    );
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.tap(find.text('(필수) 이용약관'));
    await tester.tap(find.text('(필수) 개인정보 수집 및 이용'));
    await tester.pumpAndSettle();

    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(consent, (version: 'release-2', research: false));
    expect(api.paths, [
      'GET /api/v1/policies',
      'GET /api/v1/policies/terms/release-2',
      'GET /api/v1/policies/terms/release-2',
    ]);
  });
}

import 'package:finsight/content/content_exposure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('records only one uninterrupted second at half visibility', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    int impressions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 200,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    const SizedBox(height: 170),
                    ContentExposure(
                      onVisible: () async => impressions++,
                      child: const SizedBox(width: 300, height: 100),
                    ),
                    const SizedBox(height: 400),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(impressions, 0);
    scroll.jumpTo(30);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(impressions, 0);
    scroll.jumpTo(30);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 999));
    expect(impressions, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(impressions, 1);
    scroll.jumpTo(0);
    await tester.pump();
    scroll.jumpTo(30);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(impressions, 1);
  });
}

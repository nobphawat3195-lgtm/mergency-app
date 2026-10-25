import 'package:fixgo_core/fixgo_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Apple button shows only in the iPhone app', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(showAppleLogin, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(showAppleLogin, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Apple button ignores taps while signing in', (tester) async {
    var taps = 0;
    Future<void> pump(VoidCallback? onPressed) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: AppleLoginButton(onPressed: onPressed)),
          ),
        );

    await pump(() => taps++);
    await tester.tap(find.byType(AppleLoginButton));
    expect(taps, 1);

    await pump(null);
    await tester.tap(find.byType(AppleLoginButton), warnIfMissed: false);
    expect(taps, 1);
  });
}

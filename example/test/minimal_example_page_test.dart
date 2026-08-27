import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_native_web_view_browser/src/simple_native_web_view_browser_platform_interface.dart';

import 'package:simple_native_web_view_browser_example/browser_demo_screen.dart';
import 'package:simple_native_web_view_browser_example/minimal_example_page.dart';

void main() {
  testWidgets('минимальная страница: дефолтные значения и состояние',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MinimalExamplePage()),
    );

    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('minimalUrlField'))).controller!.text,
      'https://example.com',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('minimalStatusText'))).data,
      'Браузер не открыт',
    );
    final closeButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('minimalCloseButton')),
    );
    expect(closeButton.onPressed, isNull, reason: 'закрывать нечего');
  });

  testWidgets('минимальная страница: открытие и закрытие браузера',
      (tester) async {
    SimpleNativeWebViewBrowserPlatform.instance =
        MockSimpleNativeWebViewBrowserPlatform();

    await tester.pumpWidget(
      const MaterialApp(home: MinimalExamplePage()),
    );

    await tester.tap(find.byKey(const ValueKey('minimalOpenButton')));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('minimalStatusText'))).data,
      'Браузер открыт',
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('minimalCloseButton')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const ValueKey('minimalCloseButton')));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('minimalStatusText'))).data,
      'Браузер закрыт',
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('minimalCloseButton')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('из демо-экрана открывается минимальная страница', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: BrowserDemoScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('minimalExampleButton')));
    await tester.pumpAndSettle();

    expect(find.byType(MinimalExamplePage), findsOneWidget);
    expect(find.byKey(const ValueKey('minimalUrlField')), findsOneWidget);
  });
}

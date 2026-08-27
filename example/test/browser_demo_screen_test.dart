import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_native_web_view_browser/simple_native_web_view_browser.dart';

import 'package:simple_native_web_view_browser_example/browser_demo_screen.dart';
import 'package:simple_native_web_view_browser_example/main.dart';

void main() {
  testWidgets('экран показывает дефолтные значения формы', (tester) async {
    await tester.pumpWidget(const BrowserDemoApp());

    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('urlField'))).controller!.text,
      kDefaultUrl,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('userAgentField')))
          .controller!
          .text,
      kDefaultUserAgent,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('redirectPrefixField')))
          .controller!
          .text,
      kDefaultRedirectPrefix,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('persistentStoreSwitch')))
          .value,
      isTrue,
    );
  });

  testWidgets('переключение режима адресной строки работает', (tester) async {
    await tester.pumpWidget(const BrowserDemoApp());

    await tester.tap(find.byKey(const ValueKey('urlBarMode_readOnly')));
    await tester.pump();

    final group = tester.widget<RadioGroup<SimpleBrowserUrlBarMode>>(
      find.byType(RadioGroup<SimpleBrowserUrlBarMode>),
    );
    expect(group.groupValue, SimpleBrowserUrlBarMode.readOnly);
  });

  testWidgets('экран содержит журнал событий', (tester) async {
    await tester.pumpWidget(const BrowserDemoApp());

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('eventLog')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const ValueKey('eventLog')), findsOneWidget);
    expect(find.text('Журнал событий'), findsOneWidget);
  });
}
